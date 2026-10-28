import Foundation
import SwiftData
import SwiftUI

/// Sample content used by the Xcode previews.
///
/// Everything lives in an in-memory store, so opening a preview never touches the
/// conversations or the keychain of the real app.
@MainActor
enum PreviewData {
    /// iPhone 17 Pro Max logical size, so previews match the target device.
    static let proMaxSize = CGSize(width: 440, height: 956)

    /// A store with a few conversations, for list and chat previews.
    static func container() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Persistence.schema,
            configurations: configuration
        )
        let context = container.mainContext
        for conversation in conversations() {
            context.insert(conversation)
        }
        context.insert(jevSeed())
        try? context.save()
        return container
    }

    static func conversations() -> [Conversation] {
        let lisbon = Conversation(title: "Trip to Lisbon", modelID: "kimi-k3")
        lisbon.updatedAt = Date.now.addingTimeInterval(-600)
        lisbon.messages = [
            message(.user, "I have four days in Lisbon in October. What should I plan?"),
            message(
                .assistant,
                """
                October is a great time to visit — the crowds thin out after the first week and the light is lovely.

                ### A loose plan

                - **Day 1** — Alfama and the cathedral, starting early while it is quiet.
                - **Day 2** — Belém and the pasteis de nata.
                - **Day 3** — A day trip to Sintra; leave by 8:30 to beat the buses.
                - **Day 4** — LX Factory and a slow evening in Bairro Alto.

                For the weather, this is usually a good rule of thumb:

                ```swift
                let octoberAverage = (high: 23, low: 16) // °C
                ```

                Want me to turn this into a booked itinerary with times and prices?
                """
            )
        ]

        let concurrency = Conversation(title: "Swift concurrency help", modelID: "claude-haiku-5-5")
        concurrency.updatedAt = Date.now.addingTimeInterval(-3600 * 5)
        concurrency.messages = [
            message(.user, "Why does my @MainActor function warn about capturing self in a Task?"),
            message(
                .assistant,
                "Because the closure would otherwise run on a background executor while `self` is main-actor isolated. `Task { @MainActor in … }` keeps the hop explicit, and `MainActor.assumeIsolated` is the escape hatch when you already know you are on the main actor.",
                reasoning: "The warning is about actor isolation, not memory safety. Two fixes: mark the Task closure as @MainActor, or make the method nonisolated."
            )
        ]

        let empty = Conversation(title: "", modelID: "")
        empty.updatedAt = .now

        let older = Conversation(title: "Gift ideas for Dad", modelID: "deepseek-v4-pro")
        older.updatedAt = Date.now.addingTimeInterval(-3600 * 24 * 6)
        older.messages = [
            message(.user, "Something under 50 euros for a 70 year old who likes gardening and bad puns."),
            message(.assistant, "A set of heirloom tomato seeds and a tasteful bee-motif tea towel. Add a card with one truly awful pun.")
        ]

        return [lisbon, concurrency, empty, older]
    }

    static func message(
        _ role: MessageRole,
        _ content: String,
        reasoning: String = "",
        failed: Bool = false,
        errorDetail: String = ""
    ) -> Message {
        let message = Message(
            role: role,
            content: content,
            isFailed: failed,
            errorDetail: errorDetail,
            reasoning: reasoning
        )
        message.refreshSearchText()
        return message
    }

    /// A conversation with a single exchange, for the chat preview.
    static func chatPreviewConversation() -> Conversation {
        conversations()[0]
    }

    /// A trial with one recorded run, for the Jev previews.
    static func jevSeed() -> JevTrial {
        let trial = JevTrial()
        trial.title = "Support triage"
        trial.state = "A damaged order and an impatient customer."
        trial.modelID = JevModels.paidID
        trial.questions = JevQuestionSet.defaultSet
        trial.sessionID = SessionIdentity.makeSessionID()

        let run = JevRun()
        run.modelID = trial.modelID
        run.inputTokens = 1_142
        run.outputTokens = 12
        run.durationMS = 843
        run.costUSD = 0.000048
        run.billingSource = "balance"
        run.questionSnapshot = trial.questions
        for question in trial.questions {
            let answer = JevRunAnswer()
            answer.questionID = question.id
            answer.questionType = question.type.rawValue
            answer.instructions = question.instructions
            switch question.type {
            case .boolean:
                answer.noulValue = 0.93
                answer.confidence = nil
                answer.probabilities = ["true": 0.93, "false": 0.07]
            case .choice:
                answer.choiceValue = "billing"
                answer.confidence = 0.91
                answer.probabilities = ["billing": 0.91, "returns": 0.06, "shipping": 0.03]
            case .score:
                answer.scoreValue = 1.4
                answer.confidence = 0.87
                answer.probabilities = ["0": 0.05, "1": 0.41, "2": 0.54]
            }
            run.answers.append(answer)
        }
        run.createdAt = .now

        let earlier = JevRun()
        earlier.modelID = trial.modelID
        earlier.inputTokens = 1_102
        earlier.outputTokens = 12
        earlier.durationMS = 926
        earlier.costUSD = 0.000052
        earlier.billingSource = "balance"
        earlier.questionSnapshot = trial.questions
        earlier.createdAt = .now.addingTimeInterval(-3_600)
        let earlierAnswer = JevRunAnswer()
        earlierAnswer.questionID = trial.questions[0].id
        earlierAnswer.questionType = "noul"
        earlierAnswer.instructions = trial.questions[0].instructions
        earlierAnswer.noulValue = 0.86
        earlierAnswer.probabilities = ["true": 0.86, "false": 0.14]
        earlier.answers = [earlierAnswer]

        trial.runs = [run, earlier]
        return trial
    }
}

/// Wraps preview content in an in-memory store that survives re-renders.
@MainActor
struct PreviewScene<Content: View>: View {
    private let container: ModelContainer
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.container = PreviewData.container()
        self.content = content()
    }

    var body: some View {
        content
            .modelContainer(container)
    }
}
