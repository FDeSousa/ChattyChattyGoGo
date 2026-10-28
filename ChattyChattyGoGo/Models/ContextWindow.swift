import Foundation

extension ModelInfo {
    /// Roughly how many tokens a string takes, using the usual characters-per-token rule.
    static func estimateTokens(in text: String) -> Int {
        Int((Double(text.count) / 4).rounded(.up))
    }
}

extension ModelCatalog {
    /// Context window of each model, in tokens, where OpenCode publishes one.
    ///
    /// Models without a published figure get `defaultLimit`, which is deliberately low:
    /// an over-long request is trimmed, an over-limit one is rejected by the provider.
    static let contextLimits: [String: Int] = [
        "grok-4.7": 200_000,
        "gpt-6-luna": 272_000,
        "gpt-5.6-luna": 272_000,
        "claude-haiku-5-5": 100_000,
        "qwen3.7-plus": 256_000,
        "gemini-4-argon-contributor": 1_000_000
    ]

    /// Assumed context window when the model has no published figure.
    static let defaultContextLimit = 64_000

    /// The context window to assume for a model.
    static func contextLimit(for modelID: String) -> Int {
        contextLimits[modelID] ?? defaultContextLimit
    }
}

/// Decides which part of a conversation is sent to the model.
enum ContextWindow {
    /// Tokens reserved for the answer, so the request does not fill the window.
    static let outputReserve = 4_096
    /// Never trim below this many messages, even if the window is full.
    static let minimumKeptMessages = 4

    struct Result: Sendable, Equatable {
        let kept: [WireMessage]
        let trimmed: Int
        /// Rough token count of the request that would actually be sent.
        let estimatedTokens: Int
    }

    /// Keeps the newest messages that fit the model's context window.
    ///
    /// The system prompt is not part of the list; the caller sends it separately and it
    /// is accounted for here.
    static func fit(
        _ messages: [WireMessage],
        systemPrompt: String?,
        modelID: String
    ) -> Result {
        let budget = max(1_000, ModelCatalog.contextLimit(for: modelID) - outputReserve)
        var used = ModelInfo.estimateTokens(in: systemPrompt ?? "")

        var kept: [WireMessage] = []
        var index = messages.count - 1
        while index >= 0 {
            let message = messages[index]
            let cost = ModelInfo.estimateTokens(in: message.content) + 8
            if used + cost > budget, kept.count >= minimumKeptMessages {
                break
            }
            kept.append(message)
            used += cost
            index -= 1
        }
        kept.reverse()

        return Result(
            kept: kept,
            trimmed: index + 1,
            estimatedTokens: used
        )
    }
}
