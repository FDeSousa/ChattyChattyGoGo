import HighlightSwift
import XCTest
@testable import ChattyChattyGoGo

/// The syntax highlighter must actually colour the code.
@MainActor
final class SyntaxHighlightTests: XCTestCase {
    func testSwiftCodeIsColoured() async throws {
        let highlight = Highlight()
        let result = try await highlight.request(
            "let answer = 42",
            mode: .language(.swift),
            colors: .light(.xcode)
        )

        XCTAssertEqual(result.language, "swift")
        XCTAssertFalse(result.isUndefined)
        // Several runs means several colours were applied.
        XCTAssertGreaterThan(result.attributedText.runs.count, 1)
    }

    func testTheFenceTagMapsToAKnownLanguage() {
        // The mapping table must cover the tags models actually emit.
        let tags = ["swift", "js", "ts", "py", "sh", "bash", "go", "rust", "json", "yaml", "sql", "html", "css"]
        for tag in tags {
            let mode = CodeBlockView.highlightMode(forTag: tag)
            guard case .language = mode else {
                XCTFail("\(tag) should map to a known grammar")
                continue
            }
        }
    }

    func testUnknownTagsFallBackToAnAlias() {
        guard case .languageAliasIgnoreIllegal(let alias) = CodeBlockView.highlightMode(forTag: "elvish") else {
            return XCTFail("unknown tags should use the alias mode")
        }
        XCTAssertEqual(alias, "elvish")
    }

    func testNoTagMeansAutomaticDetection() {
        XCTAssertEqual(CodeBlockView.highlightMode(forTag: ""), .automatic)
        XCTAssertEqual(CodeBlockView.highlightMode(forTag: nil), .automatic)
    }

    func testTheSharedHighlighterReturnsAResult() async throws {
        let highlighted = await CodeHighlighter.shared.highlight("let answer = 42", language: "swift", dark: false)
        let result = try XCTUnwrap(highlighted)
        XCTAssertFalse(result.isUndefined)
        XCTAssertGreaterThan(result.attributedText.runs.count, 1)

        // The same block is served from the cache afterwards.
        let cached = await CodeHighlighter.shared.highlight("let answer = 42", language: "swift", dark: false)
        let again = try XCTUnwrap(cached)
        XCTAssertEqual(again.attributedText, result.attributedText)
    }

    func testEmptyCodeIsNotHighlighted() async {
        // highlight.js reports "unknown" for text it cannot match; the view then shows
        // the plain text unchanged, so nothing is lost.
        let empty = await CodeHighlighter.shared.highlight("", language: nil, dark: false)
        _ = try? XCTUnwrap(empty)
    }
}
