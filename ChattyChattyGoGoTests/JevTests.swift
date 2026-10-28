import SwiftData
import XCTest
@testable import ChattyChattyGoGo

/// The Jev decision model: wire encoding, response parsing and the trial store.
final class JevTests: XCTestCase {

    // MARK: - Wire encoding

    func testABooleanQuestionEncodesTypeAndInstructions() throws {
        let question = JevQuestion(type: .boolean, instructions: "Is this urgent?")
        let wire = toPlainJSON(question.wire)

        XCTAssertEqual(wire["type"] as? String, "noul")
        XCTAssertEqual(wire["instructions"] as? String, "Is this urgent?")
        XCTAssertNil(wire["criteria"])
    }

    func testAChoiceQuestionEncodesCriteriaWithDescriptions() throws {
        let question = JevQuestion(
            type: .choice,
            instructions: "Which team?",
            options: [
                JevOption(name: "billing", description: "Charges and invoices"),
                JevOption(name: "shipping", description: "Delivery problems")
            ]
        )
        let wire = toPlainJSON(question.wire)
        let criteria = try XCTUnwrap(wire["criteria"] as? [String: Any])
        XCTAssertEqual(criteria["billing"] as? String, "Charges and invoices")
        XCTAssertEqual(criteria["shipping"] as? String, "Delivery problems")
    }

    func testAScoreQuestionEncodesTheRubricInOrder() throws {
        let question = JevQuestion(
            type: .score,
            instructions: "How annoyed?",
            rubric: ["Calm", "Frustrated"]
        )
        let wire = toPlainJSON(question.wire)
        XCTAssertEqual(wire["criteria"] as? [String], ["Calm", "Frustrated"])
    }

    func testBlankOptionNamesFallBackToPositionalKeys() throws {
        let question = JevQuestion(
            type: .choice,
            instructions: "Pick one",
            options: [
                JevOption(name: "", description: "First"),
                JevOption(name: "second", description: "Second")
            ]
        )
        let wire = toPlainJSON(question.wire)
        let criteria = try XCTUnwrap(wire["criteria"] as? [String: Any])
        XCTAssertTrue(criteria["option1"] != nil || criteria["0"] != nil, "Blank names need a stable key")
        XCTAssertEqual(criteria["second"] as? String, "Second")
    }

    func testAScoreQuestionKnowsItsHighestLevel() {
        let question = JevQuestion(type: .score, instructions: "Score", rubric: ["A", "B", "C"])
        XCTAssertEqual(question.scoreMaximum, 2)
    }

    // MARK: - Response parsing

    func testAFullReplyIsParsed() throws {
        let payload = """
        {
          "model": "jev-1.13.0",
          "answers": {
            "\(UUID().uuidString)": {
              "type": "noul", "noul": 0.93
            },
            "\(UUID().uuidString)": {
              "type": "choice", "choice": "billing", "confidence": 0.94,
              "probabilities": {"billing": 0.94, "returns": 0.05, "shipping": 0.01}
            },
            "\(UUID().uuidString)": {
              "type": "score", "score": 1.38, "confidence": 0.88,
              "legend": {"0": "Calm", "1": "Frustrated", "2": "Very angry"},
              "probabilities": {"0": 0.04, "1": 0.46, "2": 0.50}
            }
          },
          "usage": {
            "input_tokens": 1140,
            "output_tokens": 11,
            "cost": 0.00004788,
            "opencode": {"billing_source": "balance"}
          }
        }
        """.data(using: .utf8)!

        let response = try JevResponse.parse(from: payload)

        XCTAssertEqual(response.model, "jev-1.13.0")
        XCTAssertEqual(response.answers.count, 3)
        XCTAssertEqual(response.usage.inputTokens, 1140)
        XCTAssertEqual(response.usage.outputTokens, 11)
        XCTAssertEqual(try XCTUnwrap(response.costUSD), 0.00004788, accuracy: 0.0000001)
        XCTAssertEqual(response.billingSource, "balance")

        let types = Set(response.answers.map(\.type))
        XCTAssertEqual(types, [.boolean, .choice, .score])

        let score = try XCTUnwrap(response.answers.first { $0.type == .score })
        XCTAssertEqual(try XCTUnwrap(score.score), 1.38, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(score.confidence), 0.88, accuracy: 0.0001)
        XCTAssertEqual(score.legend["1"], "Frustrated")

        // A boolean answer has no confidence field: the noul value is the confidence.
        let boolean = try XCTUnwrap(response.answers.first { $0.type == .boolean })
        XCTAssertNil(boolean.confidence)
        XCTAssertEqual(try XCTUnwrap(boolean.noul), 0.93, accuracy: 0.0001)
        XCTAssertEqual(boolean.summary, "Yes (0.93)")
    }

    func testASparseReplyStillParses() throws {
        let payload = """
        {"model": "jev-1.13.0", "answers": {}, "usage": {}}
        """.data(using: .utf8)!

        let response = try JevResponse.parse(from: payload)
        XCTAssertTrue(response.answers.isEmpty)
        XCTAssertEqual(response.usage.inputTokens, 0)
        XCTAssertNil(response.costUSD)
        XCTAssertNil(response.billingSource)
    }

    func testGarbageIsRejectedAsDecoding() {
        XCTAssertThrowsError(try JevResponse.parse(from: Data("<html>".utf8))) { error in
            guard let apiError = error as? APIError, case .decoding = apiError else {
                return XCTFail("expected a decoding error, got \(error)")
            }
        }
    }

    func testTheDefaultQuestionSetCoversAllTypes() {
        let set = JevQuestionSet.defaultSet
        XCTAssertEqual(set.map(\.type), [.boolean, .choice, .score])
    }

    // MARK: - Catalogue

    func testJevRunsOnTheConsoleNotTheGoSubscription() {
        for model in JevModels.all {
            XCTAssertEqual(model.family, .systemOne)
            XCTAssertEqual(model.service, .zen)
        }
        XCTAssertEqual(ModelCatalog.model(withID: JevModels.paidID)?.displayName, "Jev 1.13")
        XCTAssertNotNil(ModelPrices.pricing(for: JevModels.paidID))
        XCTAssertNotNil(ModelPrices.pricing(for: JevModels.freeID))
    }

    // MARK: - Trial store

    @MainActor
    func testATrialRoundTripsItsQuestionsThroughStorage() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let trial = JevTrialFactory.make(in: context)
        XCTAssertEqual(trial.title, "Support triage")
        XCTAssertEqual(trial.questions.count, 3)
        XCTAssertFalse(trial.state.isEmpty)

        // Re-read from the store (forcing the JSON decode path) and compare.
        let key = trial.id
        try context.save()
        context.autosaveEnabled = false
        let refetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<JevTrial>()).first { $0.id == key }
        )
        XCTAssertEqual(refetched.questions.count, 3)
        XCTAssertEqual(refetched.questions.map(\.type), trial.questions.map(\.type))
        XCTAssertEqual(refetched.questions[1].options.map(\.name), trial.questions[1].options.map(\.name))
    }

    @MainActor
    func testARunKeepsAnswersProbabilitiesAndMeasurements() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let trial = JevTrialFactory.make(in: context)
        let question = try XCTUnwrap(trial.questions.first)

        let run = JevRun()
        run.modelID = trial.modelID
        run.durationMS = 842
        run.inputTokens = 1_140
        run.outputTokens = 11
        run.costUSD = 0.00004788
        run.billingSource = "balance"
        run.questionSnapshot = trial.questions
        context.insert(run)
        run.trial = trial

        let answer = JevRunAnswer()
        answer.questionID = question.id
        answer.questionType = question.type.rawValue
        answer.instructions = question.instructions
        answer.noulValue = 0.93
        answer.probabilities = ["true": 0.93, "false": 0.07]
        context.insert(answer)
        answer.run = run
        try context.save()

        XCTAssertEqual(trial.runs.count, 1)
        XCTAssertEqual(run.answers.first?.summary, "Yes (0.93)")
        let falseProbability = try XCTUnwrap(run.answers.first?.probabilities["false"])
        XCTAssertEqual(falseProbability, 0.07, accuracy: 0.0001)
        XCTAssertEqual(run.durationMS, 842)
        XCTAssertEqual(run.billingSource, "balance")
    }

    @MainActor
    func testDeletingATrialRemovesItsRunsAndAnswers() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let trial = JevTrialFactory.make(in: context)
        let run = JevRun()
        run.questionSnapshot = trial.questions
        context.insert(run)
        run.trial = trial
        let answer = JevRunAnswer()
        context.insert(answer)
        answer.run = run
        try context.save()

        context.delete(trial)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<JevRun>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JevRunAnswer>()).count, 0)
    }

    // MARK: - Editing through the trial view model

    /// Each test's container is kept here. When a container deinitializes its
    /// contexts are reset and the trial's backing data dies with it - the next
    /// access then crashes with "model instance was destroyed by calling
    /// ModelContext.reset". XCTestCase's per-method lifetime gives the container
    /// exactly the right scope, and how long it survives is no longer up to ARC.
    private var editorContainer: ModelContainer?

    @MainActor
    private func makeEditor() throws -> (JevTrial, JevTrialViewModel) {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let trial = JevTrial()
        trial.title = "Edit tests"
        container.mainContext.insert(trial)
        editorContainer = container
        return (trial, JevTrialViewModel(trial: trial))
    }

    /// The flow from the field report: type None / Low / Medium into a choice
    /// question, then add a fourth entry. Nothing may be lost.
    @MainActor
    func testAddingAnOptionAfterRenamesKeepsEveryEarlierOne() throws {
        let (trial, viewModel) = try makeEditor()
        viewModel.addQuestion(type: .choice)
        let id = try XCTUnwrap(trial.questions.first?.id)
        XCTAssertEqual(viewModel.question(withID: id)?.options.map(\.name), ["first", "second"])

        // Rename the two seeded options, as the editor's text fields would.
        viewModel.mutate(id) { row in
            row.options[0] = JevOption(name: "None", description: row.options[0].description)
        }
        viewModel.mutate(id) { row in
            row.options[1] = JevOption(name: "Low", description: row.options[1].description)
        }

        // Add two more, renaming the first addition.
        viewModel.addOption(toQuestionWithID: id)
        viewModel.mutate(id) { row in
            row.options[2] = JevOption(name: "Medium", description: "")
        }
        viewModel.addOption(toQuestionWithID: id)

        let row = try XCTUnwrap(viewModel.question(withID: id))
        XCTAssertEqual(row.options.map(\.name), ["None", "Low", "Medium", "option4"])
        XCTAssertEqual(row.options[0].description, "What the first option covers")
    }

    /// Edits that interleave with additions, as taps race against typing, all land.
    @MainActor
    func testInterleavedEditsAllLand() throws {
        let (trial, viewModel) = try makeEditor()
        viewModel.addQuestion(type: .choice)
        let id = try XCTUnwrap(trial.questions.first?.id)

        viewModel.addOption(toQuestionWithID: id)                   // three options
        viewModel.mutate(id) { row in                               // rename the first
            row.options[0] = JevOption(name: "None", description: row.options[0].description)
        }
        viewModel.addOption(toQuestionWithID: id)                   // four options
        viewModel.mutate(id) { row in                               // rename the third
            row.options[2] = JevOption(name: "High", description: row.options[2].description)
        }
        viewModel.deleteOption(at: 1, fromQuestionWithID: id)       // drop the second

        let row = try XCTUnwrap(viewModel.question(withID: id))
        XCTAssertEqual(row.options.map(\.name), ["None", "High", "option4"])
    }

    @MainActor
    func testRubricLevelsGrowAndShrinkWithoutCollateral() throws {
        let (trial, viewModel) = try makeEditor()
        viewModel.addQuestion(type: .score)
        let id = try XCTUnwrap(trial.questions.first?.id)
        XCTAssertEqual(viewModel.question(withID: id)?.rubric, ["Low", "Likely", "High"])

        viewModel.addRubricLevel(toQuestionWithID: id)
        viewModel.addRubricLevel(toQuestionWithID: id)
        viewModel.mutate(id) { row in row.rubric[1] = "Median" }
        viewModel.deleteRubricLevel(0, fromQuestionWithID: id)

        XCTAssertEqual(viewModel.question(withID: id)?.rubric, ["Median", "High", "More 3", "More 4"])
    }

    @MainActor
    func testDeletingAQuestionByItsId() throws {
        let (trial, viewModel) = try makeEditor()
        viewModel.addQuestion(type: .boolean)
        viewModel.addQuestion(type: .boolean)
        XCTAssertEqual(trial.questions.count, 2)

        let secondID = try XCTUnwrap(trial.questions.last?.id)
        viewModel.deleteQuestion(withID: secondID)
        XCTAssertEqual(trial.questions.count, 1)
        XCTAssertNil(viewModel.question(withID: secondID))
    }
}

// MARK: - Wire flattening

extension XCTestCase {
    /// Flattens the request wire format into plain JSON, so payloads can be
    /// compared against hand-written strings.
    func toPlainJSON(_ value: [String: JSONValue]) -> [String: Any] {
        func convert(_ value: JSONValue) -> Any {
            switch value {
            case .string(let string): string
            case .int(let integer): integer
            case .double(let number): number
            case .bool(let boolean): boolean
            case .null: NSNull()
            case .array(let items): items.map(convert)
            case .object(let object): object.reduce(into: [String: Any]()) { $0[$1.key] = convert($1.value) }
            }
        }
        return value.reduce(into: [String: Any]()) { $0[$1.key] = convert($1.value) }
    }
}
