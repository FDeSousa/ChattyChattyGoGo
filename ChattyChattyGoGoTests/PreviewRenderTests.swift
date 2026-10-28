import SwiftData
import SwiftUI
import XCTest
@testable import ChattyChattyGoGo

/// Mounts every previewed view in a real window and captures it.
///
/// The helper is asynchronous on purpose: `await Task.sleep` yields the main actor, which
/// is what lets SwiftUI commit state changes (such as the syntax highlighter's result)
/// before the capture. Blocking waits cannot do that, so the code would always be
/// captured plain.
@MainActor
final class PreviewRenderTests: XCTestCase {
    /// Kept nonisolated so `tearDown` can release it; test-only, single threaded use.
    nonisolated(unsafe) private var window: UIWindow?

    override func tearDown() {
        // Handing the window back is enough; it has no scene, so it just
        // deallocates. Touching its UIKit properties from here would need
        // main-actor isolation that `tearDown` cannot override with.
        window = nil
        super.tearDown()
    }

    private func snapshot(
        _ view: some View,
        size: CGSize = CGSize(width: 440, height: 956),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> UIImage? {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // Yields the main actor, so SwiftUI can finish laying out and any
        // asynchronous work can land before the capture.
        try? await Task.sleep(for: .milliseconds(1_100))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            window.layer.render(in: context.cgContext)
        }
        XCTAssertGreaterThan(
            image.size.width, 0,
            "render produced an empty image",
            file: file, line: line
        )
        return image
    }

    func testChatListRenders() async throws {
        let container = PreviewData.container()
        let image = await snapshot(
            NavigationStack { ChatListView(selection: nil) }
                .environment(AppState(previewHasKey: true))
                .modelContainer(container)
        )
        XCTAssertNotNil(image)
    }

    func testChatRenders() async throws {
        let container = PreviewData.container()
        let conversation = try XCTUnwrap(
            (try? container.mainContext.fetch(FetchDescriptor<Conversation>()))?.first
        )
        let image = await snapshot(
            NavigationStack { ChatView(conversation: conversation) }
                .environment(AppState(previewHasKey: true))
                .modelContainer(container)
        )
        XCTAssertNotNil(image)
    }

    func testEmptyChatRenders() async throws {
        let container = PreviewData.container()
        let conversations = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Conversation>()))
        let empty = try XCTUnwrap(conversations.last)
        let image = await snapshot(
            NavigationStack { ChatView(conversation: empty) }
                .environment(AppState(previewHasKey: true))
                .modelContainer(container)
        )
        XCTAssertNotNil(image)
    }

    func testMessageBubblesRender() async {
        let image = await snapshot(
            VStack(alignment: .leading, spacing: 16) {
                MessageBubble(message: PreviewData.message(.user, "What is an actor?"))
                MessageBubble(
                    message: PreviewData.message(.assistant, "A reference type that owns its state."),
                    modelName: "Kimi K3"
                )
                MessageBubble(
                    message: PreviewData.message(.assistant, "", failed: true, errorDetail: "HTTP 401")
                )
            }
            .padding(),
            size: CGSize(width: 440, height: 520)
        )
        XCTAssertNotNil(image)
    }

    func testMarkdownRenders() async {
        let image = await snapshot(
            ScrollView {
                MarkdownText(text: """
                ### Heading

                **Bold**, *italic* and `code`.

                - One
                - Two

                ```swift
                let x = 1
                ```
                """)
                .padding()
            },
            size: CGSize(width: 440, height: 520)
        )
        XCTAssertNotNil(image)
    }

    func testComposerRenders() async {
        let image = await snapshot(
            ComposerBar(text: .constant("Hello"), isStreaming: false, onSend: {}, onStop: {}),
            size: CGSize(width: 440, height: 120)
        )
        XCTAssertNotNil(image)
    }

    func testSettingsRenders() async throws {
        let container = PreviewData.container()
        let image = await snapshot(
            SettingsView()
                .environment(AppState(previewHasKey: true))
                .modelContainer(container)
        )
        XCTAssertNotNil(image)
    }

    func testModelPickerRenders() async {
        let image = await snapshot(
            ModelPickerView(selection: .constant("kimi-k3"))
                .environment(AppState(previewHasKey: true))
        )
        XCTAssertNotNil(image)
    }

    func testOnboardingAndLockRender() async {
        let onboarding = await snapshot(OnboardingView().environment(AppState(previewHasKey: true)))
        XCTAssertNotNil(onboarding)

        let locked = await snapshot(LockView().environment(AppState(previewHasKey: true)))
        XCTAssertNotNil(locked)
    }

    func testUsageRowRenders() async {
        let window = UsageSnapshot.Window(id: "rolling", status: "ok", percent: 42, resetsAt: .now)
        let image = await snapshot(List { UsageWindowRow(window: window) }, size: CGSize(width: 440, height: 200))
        XCTAssertNotNil(image)
    }

    func testContentRenders() async throws {
        let container = PreviewData.container()
        let image = await snapshot(
            ContentView()
                .environment(AppState(previewHasKey: true))
                .modelContainer(container)
        )
        XCTAssertNotNil(image)
    }
}
