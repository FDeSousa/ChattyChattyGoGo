import XCTest
final class DebugJevUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestResetState"]
        app.launch()
    }
    private func tap(_ e: XCUIElement, scrolls: Int = 8) {
        var r = scrolls
        let dl = Date().addingTimeInterval(10)
        while Date() < dl {
            if e.exists && e.isHittable { e.tap(); return }
            if r > 0 { app.swipeUp(); r -= 1 } else { Thread.sleep(forTimeInterval: 0.3) }
        }
        XCTFail("could not tap \(e)")
    }
    func testDebugAddOption() {
        XCTAssertTrue(app.staticTexts["ChattyChatty GoGo"].waitForExistence(timeout: 10))
        tap(app.buttons["Get started"]); tap(app.buttons["Skip"]); tap(app.buttons["Start chatting"])
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 8))
        tap(app.buttons["Jev trials"])
        XCTAssertTrue(app.navigationBars["Jev trials"].waitForExistence(timeout: 5))
        tap(app.buttons["New trial"])
        // count option-key fields before
        let q = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Option key"))
        XCTAssertTrue(q.firstMatch.waitForExistence(timeout: 8))
        print("BEFORE_COUNT=\(q.count)")
        // tap Add option
        tap(app.buttons["Add option"].firstMatch, scrolls: 4)
        Thread.sleep(forTimeInterval: 2)
        print("AFTER_COUNT=\(q.count)")
        print("VALUES=" + q.allElementsBoundByIndex.map { ($0.value as? String) ?? "?" }.joined(separator: ","))
        // dump
        print("TREE=\(app.debugDescription)")
        XCTAssertTrue(false, "debug")
    }
}
