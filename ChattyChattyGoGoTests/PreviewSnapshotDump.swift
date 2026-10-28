import SwiftData
import SwiftUI
import XCTest
@testable import ChattyChattyGoGo

/// Writes PNG snapshots of the previewed screens to the temporary directory so they can
/// be inspected outside the test run.
///
/// The helper is asynchronous: `await Task.sleep` yields the main actor, which lets
/// SwiftUI commit its state (and the syntax highlighter finish) before the capture.
@MainActor
final class PreviewSnapshotExporter: XCTestCase {
    /// Kept nonisolated so `tearDown` can release it; test-only, single threaded use.
    nonisolated(unsafe) private var window: UIWindow?

    override func tearDown() {
        // Handing the window back is enough; it has no scene, so it just
        // deallocates. Touching its UIKit properties from here would need
        // main-actor isolation that `tearDown` cannot override with.
        window = nil
        super.tearDown()
    }

    private func dump(
        _ name: String,
        _ view: some View,
        size: CGSize = CGSize(width: 440, height: 956)
    ) async {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(1_100))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            window.layer.render(in: context.cgContext)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-preview-\(name).png")
        try? image.pngData()?.write(to: url)
        print("SNAPSHOT: \(url.path)")
    }

    func testDumpAll() async throws {
        let container = PreviewData.container()
        let conversations = try container.mainContext.fetch(FetchDescriptor<Conversation>())

        await dump("chatlist", NavigationStack { ChatListView(selection: nil) }
            .environment(AppState(previewHasKey: true))
            .modelContainer(container))

        await dump("chat", NavigationStack { ChatView(conversation: conversations[0]) }
            .environment(AppState(previewHasKey: true))
            .modelContainer(container))

        await dump("emptychat", NavigationStack { ChatView(conversation: conversations[2]) }
            .environment(AppState(previewHasKey: true))
            .modelContainer(container))

        await dump("settings", SettingsView()
            .environment(AppState(previewHasKey: true))
            .modelContainer(container))

        await dump("modelpicker", ModelPickerView(selection: .constant("kimi-k3"))
            .environment(AppState(previewHasKey: true)))

        await dump("onboarding", OnboardingView().environment(AppState(previewHasKey: true)))

        await dump("lock", LockView().environment(AppState(previewHasKey: true)))

        await dump("bubbles", VStack(alignment: .leading, spacing: 16) {
            MessageBubble(message: PreviewData.message(.user, "What is an actor in Swift?"))
            MessageBubble(
                message: PreviewData.message(
                    .assistant,
                    """
                    An **actor** is a reference type that protects its own mutable state. Only one task can touch it at a time.

                    ```swift
                    actor Counter {
                        private var value = 0
                        func increment() { value += 1 }
                    }
                    ```

                    - No locks needed
                    - Hop with `await`
                    """,
                    reasoning: "Actors serialise access, which removes data races without locks."
                ),
                modelName: "Kimi K3"
            )
        }.padding(), size: CGSize(width: 440, height: 620))
    }

    /// Dumps the newer screens: the usage tracker with allowances, the chat stats, and
    /// highlighted code blocks.
    func testDumpNewScreens() async throws {
        let container = PreviewData.container()
        let conversations = try container.mainContext.fetch(FetchDescriptor<Conversation>())

        // A conversation with usage recorded, so the stats and allowances have content.
        let conversation = conversations[0]
        let answer = Message(role: .assistant, content: "Here is a plan for Lisbon.")
        answer.modelIDUsed = "kimi-k3"
        answer.costUSD = 0.0321
        answer.durationMS = 2_400
        answer.firstTokenMS = 620
        answer.billedInputTokens = 900
        answer.cachedInputTokens = 12_000
        answer.outputTokens = 640
        conversation.messages.append(answer)

        await dump("stats", ChatStatsView(conversation: conversation))
        await dump("usage", UsageView()
            .environment(AppState(previewHasKey: true))
            .modelContainer(container))

        await dump("code", ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CodeBlockView(
                    code: """
                    struct Conversation: Identifiable {
                        let id = UUID()
                        var messages: [Message] = []
                    }
                    """,
                    language: "swift"
                )
                CodeBlockView(
                    code: "def walk(city): return [stop for stop in city if stop.coffee]",
                    language: "python"
                )
            }
            .padding()
        }, size: CGSize(width: 440, height: 480))
    }
}
