import Foundation

/// The wire format family a model is served through by the OpenCode Go gateway.
enum APIFamily: String, Codable, CaseIterable, Sendable, Hashable {
    case openAIChat
    case openAIResponses
    case anthropic
    case google
    case systemOne

    var title: String {
        switch self {
        case .openAIChat: "OpenAI Chat Completions"
        case .openAIResponses: "OpenAI Responses"
        case .anthropic: "Anthropic Messages"
        case .google: "Google Gemini"
        case .systemOne: "System One (Jev)"
        }
    }

    var shortTitle: String {
        switch self {
        case .openAIChat: "Chat"
        case .openAIResponses: "Responses"
        case .anthropic: "Anthropic"
        case .google: "Gemini"
        case .systemOne: "Jev"
        }
    }

    /// Order in which we try families when the model has no known mapping.
    static let fallbackOrder: [APIFamily] = [.openAIChat, .openAIResponses, .anthropic, .google]
}

/// Where a model can be reached: the flat Go subscription, or the pay-as-you-go
/// balance on the Console (historically called Zen).
enum ModelService: String, Sendable, Hashable, CaseIterable {
    /// Included in the Go / Go Plus subscription allowance.
    case go
    /// Bills the Console pay-as-you-go balance instead of the subscription.
    case zen
    /// Dropped from the lineup: neither on Go's list nor in the Console catalogue.
    case retired

    var title: String {
        switch self {
        case .go: "Go"
        case .zen: "Pay-as-you-go"
        case .retired: "Retired"
        }
    }

    var badge: String {
        switch self {
        case .go: "GO"
        case .zen: "ZEN"
        case .retired: "RETIRED"
        }
    }
}

/// A model exposed by OpenCode Go, with hand-written guidance about what it is good at.
struct ModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    var family: APIFamily
    /// Which billing covers this model.
    var service: ModelService
    /// One-line description.
    var summary: String
    /// What this model is best used for.
    var bestFor: [String]
    /// Whether the model exposes a reasoning / thinking budget control.
    var supportsReasoning: Bool
    /// Whether the model can look at images that are sent with a message.
    var supportsImages: Bool
    /// Set when the provider may use your prompts for training (cheaper tiers).
    var privacyNote: String?
    /// How long the provider keeps the request, from OpenCode's privacy tables.
    var retention: String? { ModelCatalog.retention(for: id) }

    init(
        id: String,
        displayName: String,
        family: APIFamily,
        service: ModelService = .go,
        summary: String,
        bestFor: [String],
        supportsReasoning: Bool = false,
        supportsImages: Bool = false,
        privacyNote: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.service = service
        self.summary = summary
        self.bestFor = bestFor
        self.supportsReasoning = supportsReasoning
        self.supportsImages = supportsImages
        self.privacyNote = privacyNote
    }
}

/// The curated catalogue of every model reachable through an OpenCode Go subscription.
enum ModelCatalog {
    /// Sentinel used when the user lets the app pick today's model.
    static let autoModelID = "auto"

    /// Data retention per model, from OpenCode Go and Console privacy tables.
    /// A model that matches nothing here has its requests discarded by the provider.
    ///
    /// Keys may end in `*` to cover a family, for example `kimi-*`.
    static let retentionByModelID: [String: String] = [
        "grok-4.7": "Kept 30 days",
        "grok-4.6": "Kept 30 days",
        "gpt-6-luna": "Kept 30 days",
        "gpt-5.6-luna": "Kept 30 days",
        "claude-haiku-5-5": "Kept 30 days",
        "beam-free": "Kept 30 days",
        "flint-40b-free": "Kept 30 days",
        "iceman-contributor-free": "Kept, and may be used for training",
        "muse-spark-1.3-contributor": "Kept, may be used for training",
        "muse-spark-1.2-contributor": "Kept, may be used for training",
        "mimo-*": "Not kept",
        "minimax-*": "Not kept",
        "kimi-*": "Not kept",
        "longcat-2.0": "Not kept",
        "step-5-preview": "Not kept",
        "qwen-*": "Not kept",
        "deepseek-v4-pro": "Not kept*",
        "deepseek-v4.1-flash": "Not kept*",
        "glm-*": "Not kept"
    ]

    /// The write-ups the app ships with, plus the Jev decision models.
    ///
    /// Jev answers typed questions (yes/no, choice, rubric) instead of prose, so
    /// the app routes it to the trial harness rather than the chat.
    static let all: [ModelInfo] = curated + JevModels.all

    /// The retention note for a model, falling back to its family prefix.
    static func retention(for modelID: String) -> String? {
        if let exact = retentionByModelID[modelID] { return exact }
        for (key, note) in retentionByModelID where key.hasSuffix("*") {
            let prefix = String(key.dropLast())
            if modelID.hasPrefix(prefix) { return note }
        }
        return nil
    }

    /// The curated write-up for every chat model in the Go and pay-as-you-go lineups.
    static let curated: [ModelInfo] = [
        ModelInfo(
            id: "kimi-k3",
            displayName: "Kimi K3",
            family: .openAIChat,
            summary: "Moonshot's current flagship. Long context, sharp on both everyday questions and technical ones.",
            bestFor: ["General assistance", "Long documents", "Everyday Q&A"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "kimi-k3.1-pro",
            displayName: "Kimi K3.1 Pro",
            family: .openAIChat,
            summary: "Moonshot's step-up tier over K3: stronger reasoning on hard problems, at a lower per-token price.",
            bestFor: ["Hard analysis", "Long sessions", "Coding help"],
            supportsReasoning: true,
            privacyNote: nil
        ),
        ModelInfo(
            id: "kimi-k2.7-code",
            displayName: "Kimi K2.7 Code",
            family: .openAIChat,
            summary: "Kimi tuned specifically for writing, reading and debugging code.",
            bestFor: ["Code review", "Debugging", "Refactoring"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "kimi-k2.6",
            displayName: "Kimi K2.6",
            family: .openAIChat,
            service: .zen,
            summary: "Previous Kimi flagship. A dependable generalist with strong instruction following.",
            bestFor: ["General assistance", "Summarising"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            family: .openAIChat,
            summary: "DeepSeek's most capable model. Strongest at multi-step reasoning, maths and hard problems.",
            bestFor: ["Hard analysis", "Maths & logic", "Hard problems"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "deepseek-v4.1-flash",
            displayName: "DeepSeek V4.1 Flash",
            family: .openAIChat,
            summary: "A faster DeepSeek that keeps most of the reasoning quality for quick answers.",
            bestFor: ["Quick questions", "Summaries", "Everyday help"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "glm-5.3",
            displayName: "GLM-5.3",
            family: .openAIChat,
            summary: "Zhipu's flagship. Strong reasoning and coding with a wide multilingual range.",
            bestFor: ["General assistance", "Coding help", "Chinese & English"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "glm-5.2",
            displayName: "GLM-5.2",
            family: .openAIChat,
            summary: "Previous GLM flagship. Fast, stable and good across the board.",
            bestFor: ["General Q&A", "Coding help"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "glm-5.3-flash",
            displayName: "GLM-5.3 Flash",
            family: .openAIChat,
            summary: "Flash-sized GLM 5.3, built for instant answers.",
            bestFor: ["Quick answers", "Simple tasks"]
        ),
        ModelInfo(
            id: "glm-5.1",
            displayName: "GLM-5.1",
            family: .openAIChat,
            service: .zen,
            summary: "Solid everyday GLM with tidy instruction following.",
            bestFor: ["Everyday Q&A", "Rewriting"]
        ),
        ModelInfo(
            id: "grok-4.7",
            displayName: "Grok 4.7",
            family: .openAIResponses,
            summary: "xAI's newest flagship. Sharp at hard questions, code and mixed reasoning.",
            bestFor: ["Hard questions", "Code", "Reasoning"],
            supportsReasoning: true,
            supportsImages: true
        ),
        ModelInfo(
            id: "grok-4.6",
            displayName: "Grok 4.6",
            family: .openAIResponses,
            service: .zen,
            summary: "Previous Grok flagship. Punchy, quick and comfortable with long context.",
            bestFor: ["General assistance", "Long context"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "gpt-6-luna",
            displayName: "GPT-6 Luna",
            family: .openAIResponses,
            summary: "OpenAI's strongest reasoning model in the Go lineup. Careful, structured answers.",
            bestFor: ["Careful reasoning", "Structured answers", "Hard problems"],
            supportsReasoning: true,
            supportsImages: true
        ),
        ModelInfo(
            id: "gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            family: .openAIResponses,
            summary: "Previous OpenAI flagship in Go. A good balance of quality and speed.",
            bestFor: ["General assistance", "Writing"],
            supportsReasoning: true,
            supportsImages: true
        ),
        ModelInfo(
            id: "claude-haiku-5-5",
            displayName: "Claude Haiku 5.5",
            family: .anthropic,
            summary: "Anthropic's fast tier. Crisp, well-structured answers with excellent tone.",
            bestFor: ["Quick answers", "Writing", "Everyday help"],
            supportsReasoning: true,
            supportsImages: true
        ),
        ModelInfo(
            id: "qwen3.8-max",
            displayName: "Qwen3.8 Max",
            family: .anthropic,
            summary: "Alibaba's largest Qwen. Deep reasoning and a very large context window.",
            bestFor: ["Long documents", "Deep reasoning", "Multilingual"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "qwen3.8-flash",
            displayName: "Qwen3.8 Flash",
            family: .anthropic,
            summary: "Qwen tuned for speed while keeping answer quality high.",
            bestFor: ["Quick answers", "Everyday help"]
        ),
        ModelInfo(
            id: "qwen3.7-plus",
            displayName: "Qwen3.7 Plus",
            family: .anthropic,
            summary: "Qwen's balanced tier. A reliable all-rounder with a generous context window.",
            bestFor: ["General assistance", "Long documents"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "qwen3.7-max",
            displayName: "Qwen3.7 Max",
            family: .anthropic,
            service: .retired,
            summary: "Qwen's reasoning-first flagship tier.",
            bestFor: ["Reasoning", "Hard problems"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "qwen3.6-plus",
            displayName: "Qwen3.6 Plus",
            family: .anthropic,
            service: .zen,
            summary: "Previous Qwen plus tier. Still a capable generalist.",
            bestFor: ["General assistance"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "minimax-m3",
            displayName: "MiniMax M3",
            family: .anthropic,
            summary: "MiniMax's flagship. Strong reasoning plus a knack for long, structured outputs.",
            bestFor: ["Long-form writing", "Planning", "Reasoning"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "minimax-m2.7",
            displayName: "MiniMax M2.7",
            family: .anthropic,
            service: .zen,
            summary: "Previous MiniMax flagship. Solid across reasoning and writing.",
            bestFor: ["General assistance", "Writing"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "minimax-m2.5",
            displayName: "MiniMax M2.5",
            family: .anthropic,
            service: .retired,
            summary: "Older MiniMax tier. Lightweight and quick.",
            bestFor: ["Quick answers"]
        ),
        ModelInfo(
            id: "minimax-m3.1-flash",
            displayName: "MiniMax M3.1 Flash",
            family: .openAIChat,
            summary: "The paid MiniMax M3.1 Flash tier: the same quick model with steadier limits than the free previews.",
            bestFor: ["Quick answers", "Drafting"]
        ),
        ModelInfo(
            id: "minimax-m3.1-flash-free",

            displayName: "MiniMax M3.1 Flash (Free)",
            family: .openAIChat,
            service: .retired,
            summary: "Free tier of MiniMax M3.1. No subscription cost, but lower priority and smaller limits.",
            bestFor: ["Casual questions", "Drafting"],
            privacyNote: "Free tier: OpenCode may train on request data unless free endpoints are allowed in the workspace's Privacy settings."
        ),
        ModelInfo(
            id: "nemotron-3-ultra-free",
            displayName: "Nemotron 3 Ultra (Free)",
            family: .openAIChat,
            service: .zen,
            summary: "NVIDIA's biggest Nemotron on the free tier. Capable reasoning at no extra cost, but low priority.",
            bestFor: ["Casual questions", "Reasoning for free"],
            privacyNote: "Free tier: OpenCode may train on request data unless free endpoints are allowed in the workspace's Privacy settings."
        ),
        ModelInfo(
            id: "mimo-v2.6-pro",
            displayName: "MiMo-V2.6 Pro",
            family: .openAIChat,
            summary: "Xiaomi MiMo's strongest tier. A balanced mix of reasoning quality and speed.",
            bestFor: ["General assistance", "Coding help"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "mimo-v2.6-flash",
            displayName: "MiMo-V2.6 Flash",
            family: .openAIChat,
            summary: "MiMo built for low latency.",
            bestFor: ["Quick answers", "Autocomplete-style help"]
        ),
        ModelInfo(
            id: "mimo-v2.5-pro",
            displayName: "MiMo-V2.5 Pro",
            family: .openAIChat,
            summary: "Previous MiMo pro tier. Reliable for multi-step questions.",
            bestFor: ["General assistance"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "mimo-v2.5",
            displayName: "MiMo-V2.5",
            family: .openAIChat,
            summary: "Previous MiMo tier, tuned for quick answers.",
            bestFor: ["Quick answers", "Summaries"]
        ),
        ModelInfo(
            id: "longcat-2.0",
            displayName: "LongCat-2.0",
            family: .openAIChat,
            summary: "Meituan's open model. Notably strong at coding and mathematical reasoning.",
            bestFor: ["Coding help", "Maths & logic"],
            supportsReasoning: true
        ),
        ModelInfo(
            id: "longcat-2.5-preview-free",
            displayName: "LongCat 2.5 Preview (Free)",
            family: .openAIChat,
            service: .retired,
            summary: "Free preview build of LongCat 2.5.",
            bestFor: ["Casual questions", "Drafting"],
            privacyNote: "Free tier: OpenCode may train on request data unless free endpoints are allowed in the workspace's Privacy settings."
        ),
        ModelInfo(
            id: "step-5-preview",
            displayName: "Step 5 Preview",
            family: .openAIChat,
            summary: "StepFun's preview build. A quick, friendly generalist.",
            bestFor: ["Everyday help", "Quick answers"]
        ),
        ModelInfo(
            id: "beam-free",
            displayName: "Beam (Free)",
            family: .openAIChat,
            summary: "A free general chat model. Nothing fancy, but it costs nothing extra.",
            bestFor: ["Casual questions"],
            privacyNote: "Free tier: OpenCode may train on request data unless free endpoints are allowed in the workspace's Privacy settings. Replies are kept 30 days."
        ),
        ModelInfo(
            id: "iceman-contributor-free",
            displayName: "Iceman Contributor Free",
            family: .openAIChat,
            summary: "Free for a limited time on the contributor tier: it answers at no cost because prompts may improve the model.",
            bestFor: ["Experimentation"],
            privacyNote: "Free period: your prompts may be used to improve the model, and the workspace's Privacy settings must allow free endpoints for it to answer."
        ),
        ModelInfo(
            id: "hy3",

            displayName: "HY3",
            family: .openAIChat,
            summary: "HY3 general-purpose assistant with a plain, quick style.",
            bestFor: ["Everyday Q&A"]
        ),
        ModelInfo(
            id: "hy4-preview",
            displayName: "HY4 Preview",
            family: .openAIChat,
            summary: "Preview build of HY4. Expect rough edges while it matures.",
            bestFor: ["Experimentation"]
        ),
        ModelInfo(
            id: "omen-alpha",
            displayName: "Omen Alpha",
            family: .openAIChat,
            summary: "An experimental alpha model. Interesting to try, but expect inconsistency.",
            bestFor: ["Experimentation"]
        ),
        ModelInfo(
            id: "gemini-4-argon",
            displayName: "Gemini 4 Argon",
            family: .google,
            summary: "Google's Gemini 4, currently half price through OpenCode. Very large context and strong general reasoning.",
            bestFor: ["Very long documents", "General assistance", "Images"],
            supportsReasoning: true,
            supportsImages: true
        ),
        ModelInfo(
            id: "gemini-4-argon-contributor",

            displayName: "Gemini 4 Argon (Contributor)",
            family: .google,
            service: .retired,
            summary: "Google's Gemini 4 on the contributor tier. Very large context and strong general reasoning.",
            bestFor: ["Very long documents", "General assistance"],
            supportsReasoning: true,
            supportsImages: true,
            privacyNote: "Contributor tier: your prompts may be used to improve Meta/Google models."
        ),
        ModelInfo(
            id: "muse-spark-1.3-contributor",
            displayName: "Muse Spark 1.3 (Contributor)",
            family: .openAIResponses,
            summary: "Meta's Muse Spark 1.3 on the discounted contributor tier.",
            bestFor: ["General assistance", "Drafting"],
            supportsReasoning: true,
            privacyNote: "Contributor tier: your prompts may be used to train future Meta models."
        ),
        ModelInfo(
            id: "muse-spark-1.2-contributor",
            displayName: "Muse Spark 1.2 (Contributor)",
            family: .openAIResponses,
            summary: "Previous Muse Spark on the discounted contributor tier.",
            bestFor: ["Drafting", "Summarising"],
            privacyNote: "Contributor tier: your prompts may be used to train future Meta models."
        )
    ]

    /// Models that make good automatic picks (no contributor-tier data sharing).
    static let autoPool: [String] = [
        "kimi-k3",
        "deepseek-v4-pro",
        "claude-haiku-5-5",
        "qwen3.8-max",
        "glm-5.3",
        "grok-4.7",
        "minimax-m3",
        "mimo-v2.6-pro"
    ]

    static func model(withID id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }

    /// Today's automatic pick. Stable for the whole day, rotates through the pool.
    static func autoModel(for date: Date = .now, calendar: Calendar = .current) -> ModelInfo? {
        let pool = autoPool.compactMap { model(withID: $0) }
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[abs(day) % pool.count]
    }

    /// Resolve a stored model id into something we can call.
    /// - "" means the global default, "auto" means today's pick, anything else is a model id.
    static func resolve(
        _ storedID: String,
        globalDefault: String,
        date: Date = .now
    ) -> ModelInfo? {
        let trimmed = storedID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let fallback = globalDefault.trimmingCharacters(in: .whitespacesAndNewlines)
            if fallback.isEmpty { return autoModel(for: date) }
            return resolve(fallback, globalDefault: "", date: date)
        }
        if trimmed == autoModelID {
            return autoModel(for: date)
        }
        if let known = model(withID: trimmed) { return known }
        // Unknown id (new model, or typed by hand) – assume the most common family.
        return ModelInfo(
            id: trimmed,
            displayName: trimmed,
            family: .openAIChat,
            summary: "Not in the curated list yet. You can pick the API style manually in Settings.",
            bestFor: []
        )
    }
}
