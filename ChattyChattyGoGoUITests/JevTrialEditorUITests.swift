import XCTest

/// Smoke tests for the trial editor: adding entries must not crash the editor
/// and the controls must remain usable. The data-level regression (entries
/// surviving an add) is covered exhaustively by the unit tests in JevTests.
final class JevTrialEditorUITests: XCTestCase {
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
    private func tap(_ element: XCUIElement, scrolls: Int = 8, timeout: TimeInterval = 10) {
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

    /// Gets through onboarding to the chat list, then opens a seeded trial editor.
    private func enterTrialEditor() {
        XCTAssertTrue(app.staticTexts["ChattyChatty GoGo"].waitForExistence(timeout: 10))
        tap(app.buttons["Get started"])
        tap(app.buttons["Skip"])
        tap(app.buttons["Start chatting"])
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 8), app.debugDescription)

        tap(app.buttons["Jev trials"])
        XCTAssertTrue(app.navigationBars["Jev trials"].waitForExistence(timeout: 5), app.debugDescription)
        tap(app.buttons["New trial"])
        XCTAssertTrue(app.buttons["Add option"].firstMatch.waitForExistence(timeout: 8),
                      "the seeded editor should be open - \(app.debugDescription)")
    }

    func testAddingRubricLevelsKeepsTheEditorUsable() {
        enterTrialEditor()

        let addLevel = app.buttons["Add level"].firstMatch
        tap(addLevel, scrolls: 10)
        // The add must not crash or remove the control.
        XCTAssertTrue(addLevel.waitForExistence(timeout: 5), "Add level should remain usable")
        tap(addLevel, scrolls: 4)
        XCTAssertTrue(addLevel.exists, "Add level should remain usable after a second add")
        shot("jev-editor-levels")
    }

    func testAddingOptionsKeepsTheEditorUsable() {
        enterTrialEditor()

        tap(app.buttons["Add option"].firstMatch, scrolls: 8)
        XCTAssertTrue(app.buttons["Add option"].firstMatch.exists, "Add option should remain usable")
        tap(app.buttons["Add option"].firstMatch, scrolls: 4)
        XCTAssertTrue(app.buttons["Add option"].firstMatch.exists, "Add option should remain usable after a second add")
        shot("jev-editor-options")
    }

    func testTypedOptionTextsSurviveAddingAnother() {
        enterTrialEditor()

        // The seeded choice question's first option is "returns".
        let returns = app.textFields.matching(
            NSPredicate(format: "value == %@", "returns")
        ).firstMatch
        XCTAssertTrue(returns.waitForExistence(timeout: 5), app.debugDescription)
        returns.clearAndEnterText("None")

        tap(app.buttons["Add option"].firstMatch, scrolls: 8)
        // The edited value must still be present.
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "None")).firstMatch
            .waitForExistence(timeout: 5), "the option edited earlier must keep its text")
        shot("jev-editor-rename-survived")
    }
}

/// Types over the whole content of a text field.
private extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        tap()
        guard let value = self.value as? String else {
            typeText(text)
            return
        }
        var deleteString = ""
        for _ in 0..<value.count {
            deleteString += XCUIKeyboardKey.delete.rawValue
        }
        typeText(deleteString)
        typeText(text)
    }
}
