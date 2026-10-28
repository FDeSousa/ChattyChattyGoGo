import Foundation

/// Reasoning / thinking budget requested from the model.
enum ReasoningLevel: String, CaseIterable, Identifiable, Sendable {
    case off
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Balanced"
        case .high: "Deep"
        }
    }

    var symbol: String {
        switch self {
        case .off: "bolt.slash"
        case .low: "hare"
        case .medium: "gauge.with.dots.needle.33percent"
        case .high: "brain.head.profile"
        }
    }

    var explanation: String {
        switch self {
        case .off: "No extra thinking time. Fastest and cheapest."
        case .low: "A little extra reasoning for straightforward questions."
        case .medium: "Balanced thinking time for most questions."
        case .high: "Maximum reasoning budget. Slower, best for hard problems."
        }
    }
}

/// A file that travels with a user message.
enum WireAttachment: Sendable, Hashable {
    case image(mimeType: String, base64: String)
    case document(text: String)

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// A message in the wire format used by the providers.
struct WireMessage: Sendable, Hashable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    let role: Role
    let content: String
    /// Images and document text that belong to this message.
    var attachments: [WireAttachment] = []
}

/// Token counts reported by the provider for one request.
struct TokenUsage: Sendable, Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    /// Part of the input that was served from the provider's prompt cache.
    var cachedInputTokens: Int = 0

    var isEmpty: Bool { inputTokens == 0 && outputTokens == 0 }

    /// Input tokens that were not cached and are billed at the full rate.
    var billedInputTokens: Int { max(0, inputTokens - cachedInputTokens) }

    /// Providers report usage in pieces (Anthropic sends the input count first and the
    /// output count later), so the pieces are merged rather than replaced.
    func merged(with other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(inputTokens, other.inputTokens),
            outputTokens: max(outputTokens, other.outputTokens),
            cachedInputTokens: max(cachedInputTokens, other.cachedInputTokens)
        )
    }
}

/// One piece of streamed output.
enum StreamEvent: Sendable {
    case content(String)
    case reasoning(String)
    case usage(TokenUsage)
}

/// Everything needed to perform one completion.
struct ChatRequest: Sendable {
    let model: ModelInfo
    let messages: [WireMessage]
    let systemPrompt: String?
    let reasoning: ReasoningLevel
    let apiKey: String
    let temperature: Double?
    /// Stable per-conversation id, sent as `x-opencode-session`.
    let sessionID: String

    init(
        model: ModelInfo,
        messages: [WireMessage],
        systemPrompt: String? = nil,
        reasoning: ReasoningLevel = .off,
        apiKey: String,
        temperature: Double? = nil,
        sessionID: String = ""
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.reasoning = reasoning
        self.apiKey = apiKey
        self.temperature = temperature
        self.sessionID = sessionID
    }
}

/// Minimal, `Sendable` JSON tree so request bodies never cross actor boundaries with `Any`.
enum JSONValue: Sendable, Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    static func encode(_ value: JSONValue) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Returns a copy of an object with one key replaced or added.
    func with(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(let existing) = self else { return self }
        var object = existing
        object[key] = value
        return .object(object)
    }
}

/// Errors surfaced to the UI.
enum APIError: LocalizedError, Sendable {
    case missingAPIKey
    case http(status: Int, body: String, retryAfter: Int?)
    case transport(String)
    case decoding(String)
    case failed(String)

    init(status: Int, body: String, retryAfter: Int? = nil) {
        self = .http(status: status, body: body, retryAfter: retryAfter)
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key yet. Add your OpenCode Go key in Settings."
        case .http(let status, let body, _):
            body.isEmpty ? "The server returned HTTP \(status)." : "HTTP \(status): \(Self.friendlyMessage(from: body) ?? body)"
        case .transport(let message):
            message
        case .decoding(let message):
            message
        case .failed(let message):
            message
        }
    }

    /// Pulls the human readable part out of a JSON error body, for example
    /// `{"type":"error","error":{"type":"MissingSessionID","message":"…"}}`.
    static func friendlyMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any] {
            let type = error["type"] as? String
            let message = error["message"] as? String
            switch (type, message) {
            case let (type?, message?):
                return "\(type): \(message)"
            case let (type?, nil):
                return type
            case let (nil, message?):
                return message
            default:
                break
            }
        }
        if let message = object["message"] as? String {
            return message
        }
        if let detail = object["detail"] as? String {
            return detail
        }
        return nil
    }

    /// The key was rejected.
    ///
    /// A 403 that is really about a model the account may not use (privacy
    /// restrictions, region blocks) is not an auth problem: the key itself is fine.
    var isAuthProblem: Bool {
        if case .http(let status, let body, _) = self {
            if status == 401 { return true }
            if status == 403 {
                return !body.lowercased().contains("model") && !suggestsModelUnavailable
            }
        }
        return false
    }

    /// The server's own words for an HTTP rejection, without the type prefix.
    ///
    /// Kept verbatim so the app can explain *why* a model was refused, in the
    /// gateway's phrasing.
    var serverReason: String? {
        guard case .http(_, let body, _) = self, !body.isEmpty else { return nil }
        var message: String?
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let text = error["message"] as? String {
                message = text
            } else if let text = object["message"] as? String {
                message = text
            } else if let text = object["detail"] as? String {
                message = text
            }
        }
        if message == nil { message = Self.friendlyMessage(from: body) }
        if message == nil { message = body }
        guard var text = message, !text.isEmpty else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 300 { text = String(text.prefix(300)) + "…" }
        return text
    }

    /// The gateway asked us to slow down.
    var isRateLimit: Bool {
        if case .http(let status, _, _) = self, status == 429 { return true }
        return false
    }

    /// Seconds to wait before trying again, from the response header.
    var retryAfterSeconds: Int? {
        if case .http(_, _, let seconds) = self { return seconds }
        return nil
    }

    /// The account's allowance is spent, not merely busy.
    ///
    /// A 429 whose body says the usage limit is reached is final: waiting and
    /// retrying only delays the same verdict (that is how a trial run used to
    /// stretch "surprisingly long"). A plain rate-limit 429 - "slow down" - is
    /// different and stays retryable.
    var isQuotaExhausted: Bool {
        if case .http(let status, let body, _) = self, status == 429 {
            let lowered = body.lowercased()
            return lowered.contains("freeusagelimiterror")
                || lowered.contains("usage limit reached")
                || lowered.contains("subscribe to opencode")
        }
        return false
    }

    /// Whether another attempt is worth making automatically.
    var isRetryable: Bool {
        if isQuotaExhausted { return false }
        switch self {
        case .http(let status, _, _):
            return status == 429 || status == 408 || (500..<600).contains(status)
        case .transport:
            return true
        default:
            return false
        }
    }

    /// True when the failure suggests we are talking to the wrong endpoint family
    /// for this model, so trying another family is worth it.
    var suggestsRoutingProblem: Bool {
        switch self {
        case .http(let status, let body, _):
            if status == 404 || status == 405 { return true }
            let lowered = body.lowercased()
            return status == 400 && (
                lowered.contains("model") ||
                lowered.contains("not found") ||
                lowered.contains("does not exist") ||
                lowered.contains("unsupported")
            )
        default:
            return false
        }
    }

    /// True when the failure is about an optional parameter we can safely drop.
    var suggestsUnsupportedParameter: Bool {
        if case .http(let status, let body, _) = self, status == 400 {
            let lowered = body.lowercased()
            return lowered.contains("reasoning") ||
                lowered.contains("thinking") ||
                lowered.contains("stream_options") ||
                lowered.contains("unknown field") ||
                lowered.contains("unrecognized")
        }
        return false
    }

    /// True when the gateway refused because this model is not enabled for the account.
    ///
    /// The gateway turns models off per account, and some are blocked by region or by
    /// the account's privacy and data-sharing settings, so the wording varies. Free
    /// endpoints are the clearest example: OpenCode rejects them with a message about
    /// the workspace's Privacy settings. A 404 is *not* included here: that is how a
    /// wrong endpoint family answers, and it is worth trying another one.
    var suggestsModelUnavailable: Bool {
        guard case .http(let status, let body, _) = self else { return false }
        guard status == 400 || status == 403 else { return false }
        let lowered = body.lowercased()
        if lowered.contains("privacy") ||
            lowered.contains("train on request data") ||
            lowered.contains("free endpoints") ||
            lowered.contains("data sharing") {
            return true
        }
        if lowered.contains("model") {
            return lowered.contains("not found") ||
                lowered.contains("not available") ||
                lowered.contains("not enabled") ||
                lowered.contains("disabled") ||
                lowered.contains("does not exist") ||
                lowered.contains("unavailable")
        }
        return lowered.contains("not available") ||
            lowered.contains("not enabled") ||
            lowered.contains("disabled") ||
            lowered.contains("blocked") ||
            lowered.contains("not permitted") ||
            lowered.contains("not allowed") ||
            lowered.contains("denied") ||
            lowered.contains("restricted") ||
            lowered.contains("region") ||
            lowered.contains("unavailable")
    }
}
