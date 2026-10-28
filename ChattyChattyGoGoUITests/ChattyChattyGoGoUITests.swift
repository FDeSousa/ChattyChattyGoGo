import XCTest

/// Drives the app through its main flows and captures a screenshot of every screen.
/// The screenshots are written to the test runner's temporary directory.
final class ChattyChattyGoGoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestResetState"]
        app.launch()
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        print("UITEST-SNAPSHOT: \(url.path)")
    }

    /// Scrolls until the element can be tapped, then taps it.
    private func tap(_ element: XCUIElement, scrolls: Int = 4, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        var remainingScrolls = scrolls
        while Date() < deadline {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            if remainingScrolls > 0 {
                app.swipeUp()
                remainingScrolls -= 1
            } else {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTFail("Could not tap \(element)")
    }

    func testWalkthrough() {
        // 1. Onboarding
        XCTAssertTrue(app.staticTexts["ChattyChatty GoGo"].waitForExistence(timeout: 10))
        shot("01-onboarding")

        // 2. API key step
        tap(app.buttons["Get started"])
        XCTAssertTrue(app.staticTexts["Your OpenCode Go key"].waitForExistence(timeout: 5))
        shot("02-apikey")

        // 3. Skip the key, land on the model picker
        tap(app.buttons["Skip"])
        XCTAssertTrue(app.staticTexts["Pick a model"].waitForExistence(timeout: 5))
        shot("03-models")

        // 4. Into the app
        Thread.sleep(forTimeInterval: 1)
        tap(app.buttons["Start chatting"])
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 8), app.debugDescription)
        shot("04-chatlist-empty")

        // 5. Open settings from the sidebar
        tap(app.buttons["Settings"].firstMatch)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("05-settings")

        // 6. The model picker from settings
        tap(app.buttons.containing(.staticText, identifier: "Default model").firstMatch)
        XCTAssertTrue(app.navigationBars["Default model"].waitForExistence(timeout: 5))
        shot("06-modelpicker")
        tap(app.navigationBars["Default model"].buttons["Done"])

        tap(app.navigationBars["Settings"].buttons["Done"])

        // 7. Create a chat
        tap(app.buttons["New chat"].firstMatch)
        XCTAssertTrue(app.textFields["Ask anything…"].waitForExistence(timeout: 5), app.debugDescription)
        shot("07-newchat")

        // 8. Type a question – without a key the app shows a clear error.
        let field = app.textFields["Ask anything…"]
        field.tap()
        field.typeText("Hello there")
        shot("08-typed")
    }
}
