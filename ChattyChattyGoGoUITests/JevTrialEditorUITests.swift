import XCTest

/// End-to-end checks for adding, renaming, and removing choice and rubric entries.
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

    private func assertEventuallyRemoved(_ element: XCUIElement, timeout: TimeInterval = 5,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && element.exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(element.exists, "The option should be removed", file: file, line: line)
    }

    private func scrollTo(_ element: XCUIElement, scrolls: Int = 10, timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        var remainingScrolls = scrolls
        while Date() < deadline {
            if element.exists && element.isHittable { return }
            if remainingScrolls > 0 {
                app.swipeUp()
                remainingScrolls -= 1
            } else {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTFail("Could not scroll \(element) into view")
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

    func testOptionRemovalWorksFromThreeOptionsDownToZeroAndAfterAdding() {
        enterTrialEditor()

        // The sample starts with three options. Deletion must remain enabled
        // after each removal, including when only one option remains.
        let removeReturns = app.buttons["Remove option returns"]
        tap(removeReturns, scrolls: 10)
        assertEventuallyRemoved(removeReturns)
        XCTAssertTrue(app.buttons["Remove option shipping"].waitForExistence(timeout: 5),
                      "removing returns must preserve shipping")

        let removeShipping = app.buttons["Remove option shipping"]
        tap(removeShipping, scrolls: 10)
        assertEventuallyRemoved(removeShipping)
        XCTAssertTrue(app.buttons["Remove option billing"].waitForExistence(timeout: 5),
                      "removing shipping must preserve billing")

        let removeBilling = app.buttons["Remove option billing"]
        tap(removeBilling, scrolls: 10)
        assertEventuallyRemoved(removeBilling)

        // From zero, add one, then remove it. This covers the reported case
        // where deletion used to be disabled below three entries.
        tap(app.buttons["Add option"].firstMatch, scrolls: 6)
        let removeFirst = app.buttons["Remove option option1"]
        XCTAssertTrue(removeFirst.waitForExistence(timeout: 5), "the first new option should be present")
        tap(removeFirst, scrolls: 4)
        assertEventuallyRemoved(removeFirst)

        // At two options, removing one must remove only that row.
        tap(app.buttons["Add option"].firstMatch, scrolls: 4)
        tap(app.buttons["Add option"].firstMatch, scrolls: 4)
        let removeOption1 = app.buttons["Remove option option1"]
        let removeOption2 = app.buttons["Remove option option2"]
        XCTAssertTrue(removeOption1.exists)
        XCTAssertTrue(removeOption2.exists)
        tap(removeOption2, scrolls: 4)
        XCTAssertTrue(removeOption1.exists, "removing option2 must preserve option1")
        assertEventuallyRemoved(removeOption2)
    }

    func testTypedOptionTextsSurviveAddingAnother() {
        enterTrialEditor()

        // The seeded choice question's first option is "returns".
        let removeReturns = app.buttons["Remove option returns"]
        scrollTo(removeReturns)
        let optionID = String(removeReturns.identifier.dropFirst("jev.option.remove.".count))
        let returns = app.textFields["jev.option.name.\(optionID)"]
        XCTAssertTrue(returns.exists, app.debugDescription)
        returns.clearAndEnterText("None")

        tap(app.buttons["Add option"].firstMatch, scrolls: 8)
        // The edited value must still be present.
        XCTAssertEqual(returns.value as? String, "None", "the option edited earlier must keep its text")
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
