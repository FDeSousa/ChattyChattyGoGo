import Foundation

/// Incremental parser for the server-sent-event streams returned by the OpenCode Go gateway.
///
/// The gateway exposes four provider dialects; each one frames its deltas and its token
/// usage differently, so the parser is aware of which family the stream belongs to.
struct SSEParser {
    let family: APIFamily
    private var eventName: String?
    private(set) var isFinished = false

    init(family: APIFamily) {
        self.family = family
    }

    /// Feed one raw line of the event stream. Returns an event when the line carried
    /// new text or token counts.
    mutating func consume(line: String) -> StreamEvent? {
        if line.isEmpty {
            eventName = nil
            return nil
        }
        if line.hasPrefix(":") { return nil } // comment / keep-alive

        guard let separator = line.firstIndex(of: ":") else { return nil }
        let field = String(line[line.startIndex..<separator])
        var value = String(line[line.index(after: separator)...])
        if value.hasPrefix(" ") { value.removeFirst() }

        switch field {
        case "event":
            eventName = value
            return nil
        case "data":
            return handle(data: value)
        default:
            return nil
        }
    }

    private mutating func handle(data payload: String) -> StreamEvent? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed == "[DONE]" {
            isFinished = true
            return nil
        }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch family {
        case .openAIChat:
            return openAIChatEvent(object)
        case .openAIResponses:
            return openAIResponsesEvent(object)
        case .anthropic:
            return anthropicEvent(object)
        case .google:
            return googleEvent(object)
        case .systemOne:
            // Jev never streams; the chat path never reaches this parser.
            return nil
        }
    }

    // MARK: - OpenAI chat completions

    private mutating func openAIChatEvent(_ object: [String: Any]) -> StreamEvent? {
        // The usage block arrives in its own chunk, with no choices.
        if let usage = openAIUsage(object["usage"] as? [String: Any]) {
            return .usage(usage)
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            return .reasoning(reasoning)
        }
        if let text = delta["content"] as? String, !text.isEmpty {
            return .content(text)
        }
        if let parts = delta["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return .content(text) }
        }
        return nil
    }

    private func openAIUsage(_ usage: [String: Any]?) -> TokenUsage? {
        guard let usage else { return nil }
        let input = (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
        let cached = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? NSNumber
        return TokenUsage(inputTokens: input, outputTokens: output, cachedInputTokens: cached?.intValue ?? 0)
    }

    // MARK: - OpenAI responses

    private mutating func openAIResponsesEvent(_ object: [String: Any]) -> StreamEvent? {
        let type = object["type"] as? String ?? eventName ?? ""
        switch type {
        case "response.output_text.delta":
            let text = object["delta"] as? String ?? ""
            return text.isEmpty ? nil : .content(text)
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            let text = object["delta"] as? String ?? ""
            return text.isEmpty ? nil : .reasoning(text)
        case "response.completed", "response.incomplete", "response.failed":
            isFinished = true
            if let response = object["response"] as? [String: Any],
               let usage = response["usage"] as? [String: Any] {
                let input = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
                let output = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
                let cached = (usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? NSNumber
                return .usage(TokenUsage(inputTokens: input, outputTokens: output, cachedInputTokens: cached?.intValue ?? 0))
            }
            return nil
        default:
            // Be forgiving: some gateways stream the payload without an explicit type.
            if let text = object["delta"] as? String, !text.isEmpty {
                return .content(text)
            }
            return nil
        }
    }

    // MARK: - Anthropic messages

    private mutating func anthropicEvent(_ object: [String: Any]) -> StreamEvent? {
        let type = object["type"] as? String ?? eventName ?? ""
        switch type {
        case "message_start":
            let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any]
            let input = (usage?["input_tokens"] as? NSNumber)?.intValue ?? 0
            let cached = (usage?["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
            return .usage(TokenUsage(inputTokens: input, outputTokens: 0, cachedInputTokens: cached))
        case "content_block_delta":
            guard let delta = object["delta"] as? [String: Any] else { return nil }
            let deltaType = delta["type"] as? String ?? ""
            if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                return .reasoning(thinking)
            }
            if deltaType == "signature_delta" { return nil }
            if let text = delta["text"] as? String, !text.isEmpty {
                return .content(text)
            }
            return nil
        case "message_delta":
            let usage = object["usage"] as? [String: Any]
            let output = (usage?["output_tokens"] as? NSNumber)?.intValue ?? 0
            return .usage(TokenUsage(inputTokens: 0, outputTokens: output, cachedInputTokens: 0))
        case "message_stop":
            isFinished = true
            return nil
        default:
            return nil
        }
    }

    // MARK: - Google Gemini

    private mutating func googleEvent(_ object: [String: Any]) -> StreamEvent? {
        if let metadata = object["usageMetadata"] as? [String: Any] {
            let input = (metadata["promptTokenCount"] as? NSNumber)?.intValue ?? 0
            let output = (metadata["candidatesTokenCount"] as? NSNumber)?.intValue ?? 0
            let cached = (metadata["cachedContentTokenCount"] as? NSNumber)?.intValue ?? 0
            return .usage(TokenUsage(inputTokens: input, outputTokens: output, cachedInputTokens: cached))
        }
        guard let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }
        var text = ""
        var thought = ""
        for part in parts {
            guard let value = part["text"] as? String, !value.isEmpty else { continue }
            if (part["thought"] as? Bool) == true {
                thought += value
            } else {
                text += value
            }
        }
        if !thought.isEmpty { return .reasoning(thought) }
        if !text.isEmpty { return .content(text) }
        return nil
    }
}
