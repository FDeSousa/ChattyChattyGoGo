import Foundation

/// Client for the OpenCode Go gateway.
///
/// The gateway exposes several provider dialects (OpenAI chat completions, OpenAI responses,
/// Anthropic messages and Google Gemini). Requests are streamed over server-sent events.
struct OpenCodeService: @unchecked Sendable {
    enum Endpoint {
        static let host = "opencode.ai"

        static func openAIChat() -> URL {
            url(path: "/inference/go/openai/v1/chat/completions")
        }

        static func openAIResponses() -> URL {
            url(path: "/inference/go/openai/v1/responses")
        }

        static func anthropicMessages() -> URL {
            url(path: "/inference/go/anthropic/v1/messages")
        }

        static func googleStream(model: String) -> URL {
            url(
                path: "/inference/go/google/v1beta/models/\(model):streamGenerateContent",
                query: [URLQueryItem(name: "alt", value: "sse")]
            )
        }

        /// Pay-as-you-go (Console / Zen) endpoints serve the same dialects one
        /// level up, without the `/go` segment.
        static func zenOpenAIChat() -> URL {
            url(path: "/inference/openai/v1/chat/completions")
        }

        static func zenOpenAIResponses() -> URL {
            url(path: "/inference/openai/v1/responses")
        }

        static func zenAnthropicMessages() -> URL {
            url(path: "/inference/anthropic/v1/messages")
        }

        static func zenGoogleStream(model: String) -> URL {
            url(
                path: "/inference/google/v1beta/models/\(model):streamGenerateContent",
                query: [URLQueryItem(name: "alt", value: "sse")]
            )
        }

        /// Jev's System One endpoint. There is no Go variant: it always bills the
        /// pay-as-you-go side (or is free while the promotion lasts).
        static func systemOne() -> URL {
            url(path: "/inference/systemone/v1/systemone")
        }

        static func models() -> URL {
            url(path: "/inference/go/v1/models")
        }

        static func usage() -> [URL] {
            [
                url(path: "/inference/go/v1/usage"),
                url(path: "/zen/go/v1/usage")
            ]
        }

        static func url(path: String, query: [URLQueryItem] = []) -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path
            components.queryItems = query.isEmpty ? nil : query
            return components.url!
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Streaming

    /// Stream a completion.
    ///
    /// `families` is tried in order. If the first family is rejected because the model
    /// lives behind a different endpoint, the next one is tried automatically.
    func stream(
        _ request: ChatRequest,
        families: [APIFamily]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error = APIError.failed("No endpoint could serve this model.")
                for family in families {
                    do {
                        try await self.performWithRetries(request, family: family, continuation: continuation)
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch let failure as StreamFailure {
                        lastError = failure.underlying
                        // Text already streamed – never restart on another endpoint.
                        guard !failure.producedContent else {
                            continuation.finish(throwing: failure.underlying)
                            return
                        }
                        guard let apiError = failure.underlying as? APIError else { break }
                        // Authentication and quota problems will not be fixed by
                        // trying another endpoint.
                        if apiError.isAuthProblem || apiError.isRateLimit { break }
                        guard apiError.suggestsRoutingProblem else { break }
                    } catch {
                        lastError = error
                        break
                    }
                }
                continuation.finish(throwing: lastError)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Retries transient failures the way a coding agent would: a couple of attempts,
    /// waiting for `Retry-After` when the gateway asks for it.
    private func performWithRetries(
        _ request: ChatRequest,
        family: APIFamily,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await perform(request, family: family, continuation: continuation)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as StreamFailure {
                guard let apiError = failure.underlying as? APIError else { throw failure }
                guard failure.producedContent == false else { throw failure }
                guard apiError.isRetryable, attempt < 2 else { throw failure }
                lastError = failure
                let wait = apiError.retryAfterSeconds ?? Self.backoff(for: attempt)
                if wait > 0 { try await Task.sleep(for: .seconds(min(wait, 60))) }
            }
        }
        if let lastError {
            throw lastError
        }
    }

    private static func backoff(for attempt: Int) -> Int {
        [2, 5, 15][min(attempt, 2)]
    }

    /// Wraps an error with the knowledge of whether text was already streamed.
    private struct StreamFailure: Error {
        let underlying: Error
        let producedContent: Bool
    }

    private func perform(
        _ request: ChatRequest,
        family: APIFamily,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var attempts: [BodyOptions] = []
        attempts.append(BodyOptions(includeReasoning: request.reasoning != .off, includeStreamOptions: true))
        if request.reasoning != .off {
            attempts.append(BodyOptions(includeReasoning: false, includeStreamOptions: true))
        }
        attempts.append(BodyOptions(includeReasoning: false, includeStreamOptions: false))

        var lastError: Error = APIError.failed("The request could not be completed.")
        var producedContent = false

        for options in attempts {
            do {
                let produced = try await performOnce(
                    request,
                    family: family,
                    options: options,
                    continuation: continuation
                )
                producedContent = producedContent || produced
                return
            } catch let error as APIError where error.suggestsUnsupportedParameter {
                lastError = error
                continue
            } catch {
                throw StreamFailure(underlying: error, producedContent: producedContent)
            }
        }
        throw StreamFailure(underlying: lastError, producedContent: producedContent)
    }

    /// Runs a single HTTP attempt. Returns `true` when at least one chunk was produced.
    private func performOnce(
        _ request: ChatRequest,
        family: APIFamily,
        options: BodyOptions,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> Bool {
        let urlRequest = try makeURLRequest(request, family: family, options: options)

        let (bytes, response) = try await session.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                body += "\n"
                if body.count > 4000 { break }
            }
            throw APIError(
                status: http.statusCode,
                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                retryAfter: Self.retryAfter(from: http)
            )
        }

        var parser = SSEParser(family: family)
        var produced = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let event = parser.consume(line: line) {
                if case .content = event { produced = true }
                continuation.yield(event)
            }
            if parser.isFinished { break }
        }
        return produced
    }

    // MARK: - Request building

    /// Parses a `Retry-After` header, in seconds or as an HTTP date.
    private static func retryAfter(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Int(value) { return max(0, seconds) }
        if let date = Self.httpDateFormatter.date(from: value) {
            return max(0, Int(date.timeIntervalSinceNow.rounded()))
        }
        return nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private struct BodyOptions {
        var includeReasoning: Bool
        var includeStreamOptions: Bool
    }

    private func makeURLRequest(
        _ request: ChatRequest,
        family: APIFamily,
        options: BodyOptions
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: url(for: request.model, family: family))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        applySessionHeaders(to: &urlRequest, sessionID: request.sessionID)

        switch family {
        case .anthropic:
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-goog-api-key")
        default:
            break
        }

        let body = makeBody(request, family: family, options: options)
        urlRequest.httpBody = try JSONValue.encode(body)
        return urlRequest
    }

    /// The gateway routes a conversation by its session id and expects a client
    /// specific user agent. See https://opencode.ai/docs/go/#where-can-i-use-it
    private func applySessionHeaders(to urlRequest: inout URLRequest, sessionID: String) {
        let session = sessionID.isEmpty ? SessionIdentity.installSessionID : sessionID
        urlRequest.setValue(session, forHTTPHeaderField: "x-opencode-session")
        urlRequest.setValue(session, forHTTPHeaderField: "x-opencode-session-id")
        urlRequest.setValue(session, forHTTPHeaderField: "X-Session-Id")
        urlRequest.setValue(session, forHTTPHeaderField: "x-session-affinity")
        urlRequest.setValue(SessionIdentity.clientName, forHTTPHeaderField: "x-opencode-client")
        urlRequest.setValue(SessionIdentity.userAgent, forHTTPHeaderField: "User-Agent")
    }

    /// Routes a model to its endpoint. Go models live under `/inference/go`,
    /// pay-as-you-go models one level up, and Jev under System One.
    private func url(for model: ModelInfo, family: APIFamily) -> URL {
        switch (family, model.service) {
        case (.systemOne, _):
            Endpoint.systemOne()
        case (.openAIChat, .go), (.openAIChat, .retired):
            Endpoint.openAIChat()
        case (.openAIResponses, .go), (.openAIResponses, .retired):
            Endpoint.openAIResponses()
        case (.anthropic, .go), (.anthropic, .retired):
            Endpoint.anthropicMessages()
        case (.google, .go), (.google, .retired):
            Endpoint.googleStream(model: model.id)
        case (.openAIChat, .zen):
            Endpoint.zenOpenAIChat()
        case (.openAIResponses, .zen):
            Endpoint.zenOpenAIResponses()
        case (.anthropic, .zen):
            Endpoint.zenAnthropicMessages()
        case (.google, .zen):
            Endpoint.zenGoogleStream(model: model.id)
        }
    }

    private func makeBody(
        _ request: ChatRequest,
        family: APIFamily,
        options: BodyOptions
    ) -> JSONValue {
        switch family {
        case .openAIChat:
            return openAIChatBody(request, options: options)
        case .openAIResponses:
            return openAIResponsesBody(request, options: options)
        case .anthropic:
            return anthropicBody(request, options: options)
        case .google:
            return googleBody(request, options: options)
        case .systemOne:
            // Jev is never chatted with; the app blocks it before a chat request
            // is built (see ChatViewModel). This keeps the switch exhaustive.
            return .object(["model": .string(request.model.id)])
        }
    }

    private func openAIChatBody(_ request: ChatRequest, options: BodyOptions) -> JSONValue {
        var messages: [JSONValue] = []
        if let system = request.systemPrompt, !system.isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(system)]))
        }
        for message in request.messages {
            let content = openAIContent(for: message)
            messages.append(.object([
                "role": .string(message.role.rawValue),
                "content": content
            ]))
        }

        var body: [String: JSONValue] = [
            "model": .string(request.model.id),
            "messages": .array(messages),
            "stream": .bool(true)
        ]
        if options.includeStreamOptions {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        if options.includeReasoning, let effort = request.reasoning.effortValue {
            body["reasoning_effort"] = .string(effort)
        }
        if let temperature = request.temperature {
            body["temperature"] = .double(temperature)
        }
        return .object(body)
    }

    /// Chat completions use a plain string for text, and an array of parts when a
    /// message carries an image.
    private func openAIContent(for message: WireMessage) -> JSONValue {
        guard !message.attachments.isEmpty else {
            return .string(message.content)
        }
        var parts: [JSONValue] = [
            .object([
                "type": .string("text"),
                "text": .string(message.content)
            ])
        ]
        for attachment in message.attachments {
            switch attachment {
            case .image(let mimeType, let base64):
                parts.append(.object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("data:\(mimeType);base64,\(base64)")
                    ])
                ]))
            case .document(let text):
                parts.append(.object([
                    "type": .string("text"),
                    "text": .string(text)
                ]))
            }
        }
        return .array(parts)
    }

    private func openAIResponsesBody(_ request: ChatRequest, options: BodyOptions) -> JSONValue {
        var input: [JSONValue] = []
        for message in request.messages {
            var parts: [JSONValue] = [
                .object([
                    "type": .string("input_text"),
                    "text": .string(message.content)
                ])
            ]
            for attachment in message.attachments {
                switch attachment {
                case .image(let mimeType, let base64):
                    parts.append(.object([
                        "type": .string("input_image"),
                        "image_url": .string("data:\(mimeType);base64,\(base64)")
                    ]))
                case .document(let text):
                    parts.append(.object([
                        "type": .string("input_text"),
                        "text": .string(text)
                    ]))
                }
            }
            input.append(.object([
                "role": .string(message.role.rawValue),
                "content": .array(parts)
            ]))
        }

        var body: [String: JSONValue] = [
            "model": .string(request.model.id),
            "input": .array(input),
            "stream": .bool(true)
        ]
        if let system = request.systemPrompt, !system.isEmpty {
            body["instructions"] = .string(system)
        }
        if options.includeReasoning, let effort = request.reasoning.effortValue {
            body["reasoning"] = .object(["effort": .string(effort)])
        }
        if let temperature = request.temperature {
            body["temperature"] = .double(temperature)
        }
        return .object(body)
    }

    private func anthropicBody(_ request: ChatRequest, options: BodyOptions) -> JSONValue {
        var messages: [JSONValue] = []
        for message in request.messages where message.role != .system {
            var blocks: [JSONValue] = [
                .object([
                    "type": .string("text"),
                    "text": .string(message.content)
                ])
            ]
            for attachment in message.attachments {
                switch attachment {
                case .image(let mimeType, let base64):
                    blocks.append(.object([
                        "type": .string("image"),
                        "source": .object([
                            "type": .string("base64"),
                            "media_type": .string(mimeType),
                            "data": .string(base64)
                        ])
                    ]))
                case .document(let text):
                    blocks.append(.object([
                        "type": .string("text"),
                        "text": .string(text)
                    ]))
                }
            }
            messages.append(.object([
                "role": .string(message.role.rawValue),
                "content": .array(blocks)
            ]))
        }

        var body: [String: JSONValue] = [
            "model": .string(request.model.id),
            "max_tokens": .int(8192),
            "messages": .array(messages),
            "stream": .bool(true)
        ]
        if let system = request.systemPrompt, !system.isEmpty {
            body["system"] = .string(system)
        }
        if options.includeReasoning, let budget = request.reasoning.anthropicBudget {
            body["thinking"] = .object([
                "type": .string("enabled"),
                "budget_tokens": .int(budget)
            ])
        }
        if let temperature = request.temperature {
            body["temperature"] = .double(temperature)
        }
        return .object(body)
    }

    private func googleBody(_ request: ChatRequest, options: BodyOptions) -> JSONValue {
        var contents: [JSONValue] = []
        for message in request.messages where message.role != .system {
            let role = message.role == .assistant ? "model" : "user"
            var parts: [JSONValue] = [.object(["text": .string(message.content)])]
            for attachment in message.attachments {
                switch attachment {
                case .image(let mimeType, let base64):
                    parts.append(.object([
                        "inlineData": .object([
                            "mimeType": .string(mimeType),
                            "data": .string(base64)
                        ])
                    ]))
                case .document(let text):
                    parts.append(.object(["text": .string(text)]))
                }
            }
            contents.append(.object([
                "role": .string(role),
                "parts": .array(parts)
            ]))
        }

        var body: [String: JSONValue] = [
            "contents": .array(contents)
        ]
        if let system = request.systemPrompt, !system.isEmpty {
            body["systemInstruction"] = .object([
                "parts": .array([.object(["text": .string(system)])])
            ])
        }
        var generationConfig: [String: JSONValue] = [:]
        if let temperature = request.temperature {
            generationConfig["temperature"] = .double(temperature)
        }
        if options.includeReasoning, let budget = request.reasoning.geminiBudget {
            generationConfig["thinkingConfig"] = .object([
                "thinkingBudget": .int(budget)
            ])
        }
        if !generationConfig.isEmpty {
            body["generationConfig"] = .object(generationConfig)
        }
        return .object(body)
    }

    // MARK: - Non-streaming

    /// A single, non-streamed completion.
    ///
    /// Used for small side requests such as naming a conversation, where streaming
    /// would only complicate the caller.
    func complete(_ request: ChatRequest, family: APIFamily) async throws -> String {
        let body = makeBody(
            request,
            family: family,
            options: BodyOptions(includeReasoning: false, includeStreamOptions: false)
        )
        .with("stream", .bool(false))

        var urlRequest = URLRequest(url: url(for: request.model, family: family))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        switch family {
        case .anthropic:
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-goog-api-key")
        default:
            break
        }
        applySessionHeaders(to: &urlRequest, sessionID: request.sessionID)
        urlRequest.httpBody = try JSONValue.encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)

        return try Self.readText(from: data, family: family)
    }

    /// Pulls the text out of a non-streamed reply.
    private static func readText(from data: Data, family: APIFamily) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("The reply could not be read.")
        }
        switch family {
        case .openAIChat:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return (message?["content"] as? String) ?? ""
        case .openAIResponses:
            for item in (object["output"] as? [[String: Any]]) ?? []
            where (item["type"] as? String) == "message" {
                let content = item["content"] as? [[String: Any]] ?? []
                for part in content where (part["type"] as? String) == "output_text" {
                    return (part["text"] as? String) ?? ""
                }
            }
            return ""
        case .anthropic:
            for block in (object["content"] as? [[String: Any]]) ?? []
            where (block["type"] as? String) == "text" {
                return (block["text"] as? String) ?? ""
            }
            return "" 
        case .google:
            let candidates = object["candidates"] as? [[String: Any]]
            let parts = ((candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            return parts.compactMap { $0["text"] as? String }.joined()
        case .systemOne:
            return ""
        }
    }

    // MARK: - Simple endpoints

    /// Fetch the live list of model ids available to this key.
    func fetchModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: Endpoint.models())
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applySessionHeaders(to: &request, sessionID: "")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = payload["data"] as? [[String: Any]] else {
            throw APIError.decoding("The model list could not be read.")
        }
        return list.compactMap { $0["id"] as? String }
    }

    /// Fetch usage windows (rolling / weekly / monthly).
    func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        var lastError: Error = APIError.failed("Usage is unavailable right now.")
        for url in Endpoint.usage() {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            applySessionHeaders(to: &request, sessionID: "")

            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
                return try UsageSnapshot.decode(from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw APIError(
            status: http.statusCode,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            retryAfter: Self.retryAfter(from: http)
        )
    }

    // MARK: - System One (Jev)

    /// Evaluates typed questions against a state and returns structured answers.
    ///
    /// Jev does not stream or generate prose, so this is a plain POST that
    /// retries transient failures the way the streaming path does.
    func evaluate(
        _ state: String,
        questions: [JevQuestion],
        modelID: String,
        apiKey: String,
        sessionID: String
    ) async throws -> JevResponse {
        var questionEntries: [String: JSONValue] = [:]
        for question in questions {
            questionEntries[question.id.uuidString] = .object(question.wire)
        }
        let body: JSONValue = .object([
            "model": .string(modelID),
            "state": .string(state),
            "questions": .object(questionEntries)
        ])

        var urlRequest = URLRequest(url: Endpoint.systemOne())
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        applySessionHeaders(to: &urlRequest, sessionID: sessionID)
        urlRequest.httpBody = try JSONValue.encode(body)

        var lastError: Error = APIError.failed("Jev could not be reached.")
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: urlRequest)
                try validate(response: response, data: data)
                return try JevResponse.parse(from: data)
            } catch let apiError as APIError {
                guard apiError.isRetryable, attempt < 2 else { throw apiError }
                let wait = apiError.retryAfterSeconds ?? Self.backoff(for: attempt)
                if wait > 0 { try await Task.sleep(for: .seconds(min(wait, 60))) }
            } catch {
                guard attempt < 2 else { throw error }
                lastError = error
                try await Task.sleep(for: .seconds(Self.backoff(for: attempt)))
            }
        }
        throw lastError
    }
}

extension ReasoningLevel {
    /// Value used by the OpenAI style endpoints.
    var effortValue: String? {
        switch self {
        case .off: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }

    /// Thinking budget used by the Anthropic style endpoint.
    var anthropicBudget: Int? {
        switch self {
        case .off: nil
        case .low: 1024
        case .medium: 4096
        case .high: 16384
        }
    }

    /// Thinking budget used by the Gemini style endpoint.
    var geminiBudget: Int? {
        switch self {
        case .off: nil
        case .low: 1024
        case .medium: 8192
        case .high: 24576
        }
    }
}
