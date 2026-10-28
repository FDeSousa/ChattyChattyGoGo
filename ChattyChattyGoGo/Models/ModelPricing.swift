import Foundation

/// Price of a model, in US dollars per million tokens.
///
/// Go is a flat subscription, so this is not what you are billed – it is how much of
/// your monthly allowance a request consumed.
struct ModelPricing: Sendable, Hashable {
    let input: Double
    let output: Double
    let cachedRead: Double
    let cachedWrite: Double?

    static let free = ModelPricing(input: 0, output: 0, cachedRead: 0, cachedWrite: nil)

    /// The cost of one request, in US dollars.
    func cost(for usage: TokenUsage) -> Double {
        let freshInput = Double(usage.billedInputTokens) / 1_000_000 * input
        let cached = Double(usage.cachedInputTokens) / 1_000_000 * cachedRead
        let generated = Double(usage.outputTokens) / 1_000_000 * output
        return freshInput + cached + generated
    }

    /// Rough cost of an average request, used to show what a model typically costs.
    func typicalCost(inputTokens: Int, cachedTokens: Int, outputTokens: Int) -> Double {
        cost(for: TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedTokens
        ))
    }
}

enum ModelPrices {
    /// Prices from the OpenCode Go price list, in dollars per million tokens.
    ///
    /// DeepSeek is listed at the off-peak rate; its peak rate is up to double.
    /// Models that are not listed have no published price, so their cost is unknown.
    static let table: [String: ModelPricing] = [
        "glm-5.3-flash": .init(input: 0.15, output: 0.50, cachedRead: 0.03, cachedWrite: nil),
        "glm-5.3": .init(input: 1.40, output: 4.40, cachedRead: 0.26, cachedWrite: nil),
        "glm-5.2": .init(input: 1.40, output: 4.40, cachedRead: 0.26, cachedWrite: nil),
        "kimi-k3": .init(input: 3.00, output: 15.00, cachedRead: 0.30, cachedWrite: 3.00),
        "kimi-k2.7-code": .init(input: 0.95, output: 4.00, cachedRead: 0.19, cachedWrite: nil),
        "longcat-2.0": .init(input: 0.30, output: 1.20, cachedRead: 0.006, cachedWrite: nil),
        "longcat-2.5-preview-free": .free,
        "step-5-preview": .init(input: 1.00, output: 2.70, cachedRead: 0.10, cachedWrite: nil),
        "beam-free": .free,
        "mimo-v2.6-flash": .init(input: 0.14, output: 0.28, cachedRead: 0.0028, cachedWrite: nil),
        "mimo-v2.6-pro": .init(input: 0.435, output: 0.87, cachedRead: 0.003625, cachedWrite: nil),
        "mimo-v2.5": .init(input: 0.14, output: 0.28, cachedRead: 0.0028, cachedWrite: nil),
        "mimo-v2.5-pro": .init(input: 0.435, output: 0.87, cachedRead: 0.003625, cachedWrite: nil),
        "minimax-m3": .init(input: 0.30, output: 1.20, cachedRead: 0.06, cachedWrite: nil),
        "minimax-m3.1-flash-free": .free,
        "muse-spark-1.3-contributor": .init(input: 0.10, output: 0.20, cachedRead: 0.002, cachedWrite: nil),
        "muse-spark-1.2-contributor": .init(input: 0.10, output: 0.20, cachedRead: 0.002, cachedWrite: nil),
        "qwen3.8-max": .init(input: 2.00, output: 6.00, cachedRead: 0.25, cachedWrite: 2.50),
        "qwen3.8-flash": .init(input: 0.15, output: 0.47, cachedRead: 0.016, cachedWrite: 0.20),
        "qwen3.7-plus": .init(input: 0.40, output: 1.60, cachedRead: 0.04, cachedWrite: 0.50),
        "deepseek-v4.1-flash": .init(input: 0.15, output: 0.60, cachedRead: 0.003, cachedWrite: nil),
        "deepseek-v4-pro": .init(input: 0.66, output: 1.98, cachedRead: 0.022, cachedWrite: nil),
        "hy4-preview": .init(input: 0.834, output: 2.501, cachedRead: 0.042, cachedWrite: nil),
        "hy3": .init(input: 0.14, output: 0.58, cachedRead: 0.035, cachedWrite: nil),
        "grok-4.7": .init(input: 2.00, output: 6.00, cachedRead: 0.50, cachedWrite: nil),  // doubles past 200K tokens
        "gpt-6-luna": .init(input: 0.10, output: 0.50, cachedRead: 0.01, cachedWrite: 0.125),
        "gpt-5.6-luna": .init(input: 0.20, output: 1.20, cachedRead: 0.02, cachedWrite: 0.25),
        "claude-haiku-5-5": .init(input: 0.10, output: 0.50, cachedRead: 0.01, cachedWrite: 0.125),
        "gemini-4-argon-contributor": .init(input: 4.00, output: 20.00, cachedRead: 0.20, cachedWrite: nil),
        "kimi-k3.1-pro": .init(input: 2.00, output: 10.00, cachedRead: 0.20, cachedWrite: 2.00),
        "minimax-m3.1-flash": .init(input: 0.15, output: 0.60, cachedRead: 0.015, cachedWrite: nil),
        "gemini-4-argon": .init(input: 2.00, output: 10.00, cachedRead: 0.10, cachedWrite: nil),  // half price through Nov 30, 2026
        "iceman-contributor-free": .free,
        "jev-1.13": .init(input: 0.042, output: 0, cachedRead: 0, cachedWrite: nil),  // pay-as-you-go; output is free
        "jev-1.13-free": .free
    ]

    /// Monthly dollar limit per model, from the Go price list.
    ///
    /// Go splits each model's monthly limit into windows: a rolling five hour window at
    /// 20% of it, a week at 50%, and the month itself at 100%. Zero means the model has
    /// no published limit (the free previews are unlimited).
    static let monthlyLimits: [String: Double] = [
        "glm-5.3-flash": 60,
        "glm-5.3": 15,
        "glm-5.2": 60,
        "kimi-k3": 15,
        "kimi-k2.7-code": 60,
        "longcat-2.0": 60,
        "longcat-2.5-preview-free": 0,
        "step-5-preview": 15,
        "beam-free": 0,
        "mimo-v2.6-flash": 60,
        "mimo-v2.6-pro": 15,
        "mimo-v2.5": 60,
        "mimo-v2.5-pro": 15,
        "minimax-m3": 60,
        "minimax-m3.1-flash-free": 0,
        "minimax-m3.1-flash": 20,
        "muse-spark-1.3-contributor": 60,
        "muse-spark-1.2-contributor": 60,
        "qwen3.8-max": 15,
        "qwen3.8-flash": 30,
        "qwen3.7-plus": 60,
        "deepseek-v4.1-flash": 80,
        "deepseek-v4-pro": 15,
        "hy4-preview": 30,
        "hy3": 60,
        "grok-4.7": 15,
        "gpt-6-luna": 15,
        "gpt-5.6-luna": 15,
        "claude-haiku-5-5": 15,
        "gemini-4-argon-contributor": 60,
        "kimi-k3.1-pro": 15,
        "gemini-4-argon": 30,
        "iceman-contributor-free": 0
    ]

    /// Typical request sizes, from the OpenCode usage estimates.
    static let typicalRequests: [String: (input: Int, cached: Int, output: Int)] = [
        "grok-4.7": (390, 32_500, 120),
        "glm-5.3-flash": (1_000, 55_000, 200),
        "glm-5.3": (700, 52_000, 150),
        "glm-5.2": (700, 52_000, 150),
        "gpt-6-luna": (1_000, 50_000, 220),
        "gpt-5.6-luna": (1_000, 50_000, 220),
        "claude-haiku-5-5": (1_100, 55_000, 240),
        "kimi-k3": (1_050, 76_500, 300),
        "kimi-k2.7-code": (870, 55_000, 200),
        "longcat-2.0": (920, 88_900, 200),
        "step-5-preview": (1_000, 55_000, 200),
        "deepseek-v4.1-flash": (410, 71_300, 310),
        "deepseek-v4-pro": (750, 82_000, 290),
        "minimax-m3": (510, 56_000, 190),
        "muse-spark-1.3-contributor": (620, 71_400, 300),
        "muse-spark-1.2-contributor": (620, 71_400, 300),
        "mimo-v2.6-flash": (830, 71_500, 295),
        "mimo-v2.6-pro": (790, 86_000, 305),
        "mimo-v2.5": (830, 71_500, 295),
        "mimo-v2.5-pro": (790, 86_000, 305),
        "qwen3.8-max": (420, 66_000, 200),
        "qwen3.8-flash": (600, 58_000, 200),
        "qwen3.7-plus": (500, 57_000, 190),
        "hy4-preview": (830, 71_500, 295),
        "hy3": (830, 71_500, 295),
        "kimi-k3.1-pro": (1_050, 76_500, 300),
        "minimax-m3.1-flash": (500, 49_400, 360)
    ]

    static func pricing(for modelID: String) -> ModelPricing? {
        table[modelID]
    }

    /// What one average request with this model costs, in US dollars.
    static func typicalCost(for modelID: String) -> Double? {
        guard let pricing = table[modelID], let typical = typicalRequests[modelID] else { return nil }
        return pricing.typicalCost(
            inputTokens: typical.input,
            cachedTokens: typical.cached,
            outputTokens: typical.output
        )
    }
}

extension Double {
    /// Formats a dollar amount the way the usage screens show it.
    var usdFormatted: String {
        if self == 0 { return "$0.00" }
        if self < 0.01 { return String(format: "$%.4f", self) }
        if self < 1 { return String(format: "$%.3f", self) }
        return String(format: "$%.2f", self)
    }
}
