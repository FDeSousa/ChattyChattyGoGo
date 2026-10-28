import Foundation
import SwiftData

/// A Jev trial session: a subject (the "state") plus a set of typed questions.
///
/// Each run asks Jev to evaluate the questions against the state and is recorded
/// in full - answers, probabilities, timing, tokens and cost - so the model's
/// behaviour can be compared across ids, question wordings and states.
@Model
final class JevTrial {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    /// A short name for what is being judged, e.g. "Support triage".
    var title: String
    /// The subject text sent as the `state`.
    var state: String
    /// `jev-1.13` or `jev-1.13-free`.
    var modelID: String
    /// A stable session id so re-runs ride the same upstream caches.
    var sessionID: String
    /// The questions as currently edited, JSON-encoded.
    private var questionSetData: Data

    @Relationship(deleteRule: .cascade, inverse: \JevRun.trial)
    var runs: [JevRun] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String = "",
        state: String = "",
        modelID: String = JevModels.freeID,
        sessionID: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.state = state
        self.modelID = modelID
        self.sessionID = sessionID
        self.questionSetData = Data()
    }

    var questions: [JevQuestion] {
        get {
            guard !questionSetData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([JevQuestion].self, from: questionSetData)) ?? []
        }
        set {
            questionSetData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

/// One evaluation round: a whole request, including every answer it produced.
@Model
final class JevRun {
    var id: UUID
    var createdAt: Date
    var modelID: String
    var durationMS: Int
    var inputTokens: Int
    var outputTokens: Int
    /// What OpenCode charged, when the gateway reported it.
    var costUSD: Double?
    /// `balance`, `free`, ... - how the request was billed.
    var billingSource: String?
    var isFailed: Bool
    var errorDetail: String
    /// The questions as they were asked in this run, JSON-encoded.
    private var questionSnapshotData: Data

    @Relationship(deleteRule: .cascade, inverse: \JevRunAnswer.run)
    var answers: [JevRunAnswer] = []

    var trial: JevTrial?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        modelID: String = "",
        durationMS: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double? = nil,
        billingSource: String? = nil,
        isFailed: Bool = false,
        errorDetail: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modelID = modelID
        self.durationMS = durationMS
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.billingSource = billingSource
        self.isFailed = isFailed
        self.errorDetail = errorDetail
        self.questionSnapshotData = Data()
    }

    var questionSnapshot: [JevQuestion] {
        get {
            guard !questionSnapshotData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([JevQuestion].self, from: questionSnapshotData)) ?? []
        }
        set {
            questionSnapshotData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

/// A single answer inside a run.
@Model
final class JevRunAnswer {
    var id: UUID
    var questionID: UUID
    var questionType: String
    var instructions: String
    /// Noul: probability the statement is true (0–1).
    var noulValue: Double?
    /// Choice: the option key the model picked.
    var choiceValue: String?
    /// Score: the position on the rubric (0-based, may be fractional).
    var scoreValue: Double?
    /// How sure the model was (0–1); noul answers leave this nil.
    var confidence: Double?
    /// The full distribution, JSON-encoded as `[name: probability]`.
    private var probabilitiesData: Data

    var run: JevRun?

    init(
        id: UUID = UUID(),
        questionID: UUID = UUID(),
        questionType: String = "",
        instructions: String = "",
        noulValue: Double? = nil,
        choiceValue: String? = nil,
        scoreValue: Double? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.questionID = questionID
        self.questionType = questionType
        self.instructions = instructions
        self.noulValue = noulValue
        self.choiceValue = choiceValue
        self.scoreValue = scoreValue
        self.confidence = confidence
        self.probabilitiesData = Data()
    }

    var probabilities: [String: Double] {
        get {
            guard !probabilitiesData.isEmpty else { return [:] }
            return (try? JSONDecoder().decode([String: Double].self, from: probabilitiesData)) ?? [:]
        }
        set {
            probabilitiesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var questionTypeValue: JevQuestionType? {
        JevQuestionType(rawValue: questionType)
    }

    /// A presentation-friendly copy of the answer's meaning.
    var summary: String {
        switch questionTypeValue {
        case .boolean:
            guard let noulValue else { return "—" }
            return noulValue >= 0.5 ? "Yes (\(String(format: "%.2f", noulValue)))" : "No (\(String(format: "%.2f", noulValue)))"
        case .choice:
            guard let choiceValue else { return "—" }
            let probability = probabilities[choiceValue] ?? 0
            return "\(choiceValue) · \(String(format: "%.2f", probability))"
        case .score:
            guard let scoreValue else { return "—" }
            return String(format: "%.2f", scoreValue)
        case nil:
            return "—"
        }
    }
}
