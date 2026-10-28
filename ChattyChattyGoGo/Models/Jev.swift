import Foundation

/// Question types Jev answers, as they appear on the wire.
///
/// The yes/no type is called `noul` on the API – Jev's word for a calibrated
/// probability that a statement is true, not a plain boolean.
enum JevQuestionType: String, Codable, Sendable, CaseIterable, Hashable {
    case boolean = "noul"
    case choice
    case score

    var title: String {
        switch self {
        case .boolean: "Yes / No"
        case .choice: "Pick one"
        case .score: "Rubric score"
        }
    }

    var summary: String {
        switch self {
        case .boolean: "Answers how likely the statement is true, 0–1."
        case .choice: "Picks an option and shows each option's probability."
        case .score: "Places the subject on a rubric, lowest level is 0."
        }
    }
}

/// One option of a choice question: a short key and what it covers.
struct JevOption: Hashable, Sendable, Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String

    init(name: String, description: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.description = description
    }

    // Migration: older stored trials have no "id" key for their options.
    enum CodingKeys: String, CodingKey { case id, name, description }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    }
}

/// One level of a score rubric.
struct JevRubricLevel: Hashable, Sendable, Codable, Identifiable {
    let id: UUID
    var text: String

    init(text: String, id: UUID = UUID()) {
        self.id = id
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case id, text }

    // Migration: older stored trials keep the rubric as plain strings.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let str = try? single.decode(String.self) {
            self.id = UUID()
            self.text = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
    }
}

/// One typed question to evaluate against a state.
struct JevQuestion: Identifiable, Hashable, Sendable, Codable {
    /// The user-chosen key the answer comes back under. Never shown to the model.
    let id: UUID
    var type: JevQuestionType
    /// The question the model answers.
    var instructions: String
    /// For choice: the options. For score: the rubric, lowest first. For boolean: empty.
    var options: [JevOption]
    /// For score: descriptions of each rubric level, lowest first.
    var rubric: [JevRubricLevel]

    init(
        id: UUID = UUID(),
        type: JevQuestionType,
        instructions: String,
        options: [JevOption] = [],
        rubric: [JevRubricLevel] = []
    ) {
        self.id = id
        self.type = type
        self.instructions = instructions
        self.options = options
        self.rubric = rubric
    }

    enum CodingKeys: String, CodingKey { case id, type, instructions, options, rubric }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(JevQuestionType.self, forKey: .type)
        self.instructions = try container.decode(String.self, forKey: .instructions)
        self.options = (try? container.decode([JevOption].self, forKey: .options)) ?? []
        // Migration: older stored trials keep the rubric as plain strings.
        if let levels = try? container.decode([JevRubricLevel].self, forKey: .rubric) {
            self.rubric = levels
        } else if let strings = try? container.decode([String].self, forKey: .rubric) {
            self.rubric = strings.map { JevRubricLevel(text: $0) }
        } else {
            self.rubric = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(options, forKey: .options)
        try container.encode(rubric, forKey: .rubric)
    }

    // MARK: Wire shapes, from the OpenCode and TypeSafe API references.

    var wire: [String: JSONValue] {
        var question: [String: JSONValue] = [
            "type": .string(type.rawValue),
            "instructions": .string(instructions)
        ]
        switch type {
        case .boolean:
            break
        case .choice:
            // Blank names fall back to positional keys, and duplicates are deduped,
            // because criteria is a JSON object the server reads one key per option.
            var entries: [(String, JSONValue)] = []
            for (index, option) in options.enumerated() {
                let key = option.name.isEmpty ? "option\(index + 1)" : option.name
                entries.append((key, .string(option.description)))
            }
            question["criteria"] = .object(Dictionary(entries, uniquingKeysWith: { first, _ in first }))
        case .score:
            question["criteria"] = .array(rubric.map { .string($0.text) })
        }
        return question
    }

    /// The highest score a rubric question can return (a 0-based index).
    var scoreMaximum: Double {
        Double(max(rubric.count, options.count, 1) - 1)
    }
}

/// One answer from Jev, matched to its question.
struct JevAnswer: Identifiable, Hashable, Sendable {
    let questionID: String
    let type: JevQuestionType
    /// Boolean questions: probability the statement is true (0–1).
    var noul: Double?
    /// Choice questions: the selected option key.
    var choice: String?
    /// Score questions: the position on the rubric, 0-based (can be fractional).
    var score: Double?
    /// How sure the model is about the answer (0–1). Noul questions omit it –
    /// the noul value *is* the confidence.
    var confidence: Double?
    /// Full probability distribution over the options or rubric levels.
    var probabilities: [String: Double]
    /// For score questions: the rubric text by index.
    var legend: [String: String]

    var id: String { questionID }

    /// A human readable summary: "true · 0.99", "technical · 1.00", "1.5 of 2".
    var summary: String {
        switch type {
        case .boolean:
            guard let noul else { return "—" }
            return noul >= 0.5 ? "Yes (\(String(format: "%.2f", noul)))" : "No (\(String(format: "%.2f", noul)))"
        case .choice:
            guard let choice else { return "—" }
            let probability = probabilities[choice] ?? 0
            return "\(choice) · \(String(format: "%.2f", probability))"
        case .score:
            guard let score else { return "—" }
            let level = Int(score.rounded(.down))
            let label = legend["\(level)"] ?? ""
            return "\(String(format: "%.2f", score)) · \(label)"
        }
    }
}

/// Tokens the request used.
struct JevUsage: Hashable, Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
}

/// The full reply from a System One evaluation.
struct JevResponse: Sendable, Hashable {
    let model: String
    var answers: [JevAnswer]
    var usage: JevUsage
    /// What OpenCode charged, when the gateway reports it.
    var costUSD: Double?
    /// How the request was billed, when known: `balance`, `free`, ...
    var billingSource: String?

    /// Parses the gateway's response with the fields the API documents,
    /// and keeps anything extra OpenCode adds (cost, billing source).
    static func parse(from data: Data) throws -> JevResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("Jev's reply could not be read.")
        }

        let usageObject = object["usage"] as? [String: Any] ?? [:]
        let opencodeUsage = usageObject["opencode"] as? [String: Any] ?? [:]

        var answers: [JevAnswer] = []
        let answersObject = object["answers"] as? [String: Any] ?? [:]
        for (questionID, raw) in answersObject {
            guard let answer = raw as? [String: Any] else { continue }
            let type = JevQuestionType(rawValue: answer["type"] as? String ?? "") ?? .boolean
            var probabilities: [String: Double] = [:]
            if let distribution = answer["probabilities"] as? [String: Any] {
                for (key, value) in distribution {
                    if let number = value as? NSNumber { probabilities[key] = number.doubleValue }
                }
            }
            var legend: [String: String] = [:]
            if let rubric = answer["legend"] as? [String: Any] {
                for (key, value) in rubric where value is String {
                    legend[key] = value as? String
                }
            }
            answers.append(JevAnswer(
                questionID: questionID,
                type: type,
                noul: (answer["noul"] as? NSNumber)?.doubleValue,
                choice: answer["choice"] as? String,
                score: (answer["score"] as? NSNumber)?.doubleValue,
                confidence: (answer["confidence"] as? NSNumber)?.doubleValue,
                probabilities: probabilities,
                legend: legend
            ))
        }

        func numberValue(_ dictionary: [String: Any], _ keys: [String]) -> Double? {
            for key in keys {
                if let number = dictionary[key] as? NSNumber { return number.doubleValue }
            }
            return nil
        }

        return JevResponse(
            model: object["model"] as? String ?? "jev",
            answers: answers,
            usage: JevUsage(
                inputTokens: (usageObject["input_tokens"] as? NSNumber)?.intValue
                    ?? numberValue(opencodeUsage, ["input"]) .map { Int($0) } ?? 0,
                outputTokens: (usageObject["output_tokens"] as? NSNumber)?.intValue
                    ?? numberValue(opencodeUsage, ["output"]) .map { Int($0) } ?? 0
            ),
            costUSD: numberValue(usageObject, ["cost"]),
            billingSource: opencodeUsage["billing_source"] as? String
        )
    }
}

/// The question sets shipped with the app, so the first run has something to try.
enum JevQuestionSet {
    /// The example from OpenCode's own Jev documentation: triage a support request.
    static let defaultSet: [JevQuestion] = [
        JevQuestion(
            type: .boolean,
            instructions: "Does this request require urgent attention?"
        ),
        JevQuestion(
            type: .choice,
            instructions: "Which team should handle this request?",
            options: [
                JevOption(name: "returns", description: "Refunds, exchanges, or damaged items"),
                JevOption(name: "shipping", description: "Delivery delays or lost packages"),
                JevOption(name: "billing", description: "Charges, invoices, or payment problems")
            ]
        ),
        JevQuestion(
            type: .score,
            instructions: "How frustrated is the customer?",
            rubric: [JevRubricLevel(text: "Calm"), JevRubricLevel(text: "Frustrated"), JevRubricLevel(text: "Very angry")]
        )
    ]

    /// A made-up default state matching the question set, so "New trial" is useful at once.
    static let defaultState = """
    My order arrived late and the item is damaged. I want a refund. This is the third time
    this month something has gone wrong, and I am seriously considering taking my business
    elsewhere.
    """
}

/// The two Jev ids OpenCode serves, as ModelCatalog entries the UI can resolve.
enum JevModels {
    static let freeID = "jev-1.13-free"
    static let paidID = "jev-1.13"

    static let all: [ModelInfo] = [
        ModelInfo(
            id: freeID,
            displayName: "Jev 1.13 Free",
            family: .systemOne,
            service: .zen,
            summary: "TypeSafe's decision model, free for a limited time. Answers typed questions with values and probabilities, no prose.",
            bestFor: ["Yes/No checks", "Routing", "Scoring"]
        ),
        ModelInfo(
            id: paidID,
            displayName: "Jev 1.13",
            family: .systemOne,
            service: .zen,
            summary: "TypeSafe's decision model on the pay-as-you-go balance. $0.042 per million input tokens, output is free.",
            bestFor: ["Yes/No checks", "Routing", "Scoring"]
        )
    ]
}
