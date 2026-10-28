import Foundation
import SwiftData

/// One Jev trial: edits the subject and questions, runs evaluations, records everything.
///
/// The work is deliberately synchronous-with-await: Jev answers in one shot, so a
/// run is a single request whose results land in SwiftData as they are parsed.
@MainActor
@Observable
final class JevTrialViewModel: Identifiable {
    let trial: JevTrial
    var isRunning = false
    var runError: String?
    /// The evaluation from the most recent run, for instant display before the run list refreshes.
    private(set) var latestRun: JevRun?

    @ObservationIgnored private let service = OpenCodeService()

    init(trial: JevTrial) {
        self.trial = trial
    }

    var model: ModelInfo? {
        ModelCatalog.model(withID: trial.modelID)
    }

    // MARK: - Editing

    /// A question straight from the trial, looked up by id.
    ///
    /// The editor reads rows through this, never from held copies, so what a row
    /// shows is always what the trial stores.
    func question(withID id: UUID) -> JevQuestion? {
        trial.questions.first { $0.id == id }
    }

    /// The only write path for a question's contents.
    ///
    /// The change is applied to the row **as stored right now**, resolved by id at
    /// call time. Views necessarily hold copies of a row while the user is editing
    /// elsewhere in the form, so a naive "replace the row with my copy" would
    /// resurrect stale data - that is how adding a third option used to wipe the
    /// first two. Field-sized changes here keep every concurrent edit.
    func mutate(_ id: UUID, _ change: (inout JevQuestion) -> Void) {
        var questions = trial.questions
        guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
        var row = questions[index]
        change(&row)
        questions[index] = row
        trial.questions = questions
    }

    func addQuestion(type: JevQuestionType) {
        var questions = trial.questions
        switch type {
        case .boolean:
            questions.append(JevQuestion(type: .boolean, instructions: ""))
        case .choice:
            questions.append(JevQuestion(
                type: .choice,
                instructions: "",
                options: [
                    JevOption(name: "first", description: "What the first option covers"),
                    JevOption(name: "second", description: "What the second option covers")
                ]
            ))
        case .score:
            questions.append(JevQuestion(
                type: .score,
                instructions: "",
                rubric: ["Low", "Likely", "High"]
            ))
        }
        trial.questions = questions
    }

    func deleteQuestion(withID id: UUID) {
        trial.questions = trial.questions.filter { $0.id != id }
    }

    func addOption(toQuestionWithID id: UUID) {
        mutate(id) { question in
            var updated = question
            var seed = updated.options.count + 1
            var name = "option\(seed)"
            while updated.options.contains(where: { $0.name == name }) {
                seed += 1
                name = "option\(seed)"
            }
            updated.options.append(JevOption(name: name, description: ""))
            question = updated
        }
    }

    /// Deletes the option at `index` - the row that shows it knows its own offset.
    func deleteOption(at index: Int, fromQuestionWithID id: UUID) {
        mutate(id) { question in
            guard index < question.options.count else { return }
            question.options.remove(at: index)
        }
    }

    func addRubricLevel(toQuestionWithID id: UUID) {
        mutate(id) { question in
            var updated = question
            updated.rubric.append("More \(updated.rubric.count)")
            question = updated
        }
    }

    func deleteRubricLevel(_ index: Int, fromQuestionWithID id: UUID) {
        mutate(id) { question in
            guard index < question.rubric.count else { return }
            question.rubric.remove(at: index)
        }
    }

    // MARK: - Running

    /// Evaluates the current questions against the state and records the result.
    ///
    /// Records the runified truth even on failure: a failed round is a data point too.
    func run(context: ModelContext) async {
        guard !isRunning, !trial.questions.isEmpty else { return }
        let apiKey = KeychainService.read() ?? ""
        guard !apiKey.isEmpty else {
            runError = APIError.missingAPIKey.localizedDescription
            return
        }

        if trial.sessionID.isEmpty {
            trial.sessionID = SessionIdentity.makeSessionID()
        }

        isRunning = true
        runError = nil

        let started = ContinuousClock.now
        do {
            let response = try await service.evaluate(
                trial.state,
                questions: trial.questions,
                modelID: trial.modelID,
                apiKey: apiKey,
                sessionID: trial.sessionID
            )
            let duration = started.duration(to: .now)
            let run = record(response: response, duration: duration, context: context)
            latestRun = run
        } catch is CancellationError {
            // Nothing to record: the run was cancelled before it finished.
        } catch let apiError as APIError {
            // The free Jev id may be limited to OpenCode's own clients, which
            // turns a trial into an HTTP 403. Point at the paid id.
            if case .http(let status, _, _) = apiError, status == 403 {
                runError = "\(apiError.localizedDescription) Third-party clients may be turned away on the free id - try Jev 1.13 in the trial's model picker."
            } else if apiError.isQuotaExhausted {
                // The account's free Jev budget is spent; waiting changes nothing.
                runError = "\(apiError.localizedDescription) The free id's budget for this account is spent - switch to Jev 1.13 (not the Free one) in the trial's model picker."
            } else {
                runError = apiError.localizedDescription
            }
            recordFailure(apiError, duration: started.duration(to: .now), context: context)
        } catch {
            runError = error.localizedDescription
            recordFailure(error, duration: started.duration(to: .now), context: context)
        }

        isRunning = false
    }

    private func record(response: JevResponse, duration: Duration, context: ModelContext) -> JevRun {
        let run = JevRun()
        run.createdAt = .now
        run.modelID = trial.modelID
        run.durationMS = Int(duration.components.seconds) * 1000
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        run.inputTokens = response.usage.inputTokens
        run.outputTokens = response.usage.outputTokens
        run.billingSource = response.billingSource
        run.costUSD = response.costUSD ?? estimatedCost(usage: response.usage)
        run.questionSnapshot = trial.questions
        context.insert(run)
        run.trial = trial

        for question in trial.questions {
            guard let answer = response.answers.first(where: { $0.questionID == question.id.uuidString }) else { continue }
            let stored = JevRunAnswer()
            stored.questionID = question.id
            stored.questionType = question.type.rawValue
            stored.instructions = question.instructions
            stored.noulValue = answer.noul
            stored.choiceValue = answer.choice
            stored.scoreValue = answer.score
            stored.confidence = answer.confidence
            stored.probabilities = answer.probabilities
            context.insert(stored)
            stored.run = run
        }

        trial.updatedAt = .now
        try? context.save()
        return run
    }

    private func recordFailure(_ error: Error, duration: Duration, context: ModelContext) {
        let run = JevRun()
        run.createdAt = .now
        run.modelID = trial.modelID
        run.durationMS = Int(duration.components.seconds) * 1000
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        run.isFailed = true
        run.errorDetail = error.localizedDescription
        run.questionSnapshot = trial.questions
        context.insert(run)
        run.trial = trial
        trial.updatedAt = .now
        try? context.save()
        latestRun = run
    }

    /// When the gateway does not report a charge, fall back to the published rate.
    private func estimatedCost(usage: JevUsage) -> Double {
        guard let pricing = ModelPrices.pricing(for: trial.modelID) else { return 0 }
        return pricing.cost(for: TokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cachedInputTokens: 0
        ))
    }
}

/// A starting trial, used by the New button and previews.
enum JevTrialFactory {
    static func make(in context: ModelContext) -> JevTrial {
        let trial = JevTrial()
        trial.title = "Support triage"
        trial.state = JevQuestionSet.defaultState
        trial.questions = JevQuestionSet.defaultSet
        context.insert(trial)
        try? context.save()
        return trial
    }
}
