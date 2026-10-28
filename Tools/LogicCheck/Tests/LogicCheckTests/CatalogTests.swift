import XCTest
@testable import LogicCheck

final class ModelCatalogTests: XCTestCase {
    func testEveryCatalogueModelHasADescription() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.summary.isEmpty, "\(model.id) has no summary")
            XCTAssertFalse(model.bestFor.isEmpty, "\(model.id) has no best-for list")
            XCTAssertFalse(model.displayName.isEmpty, "\(model.id) has no display name")
        }
    }

    func testCatalogueIdsAreUnique() {
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testResolveFindsKnownModel() {
        let model = ModelCatalog.resolve("kimi-k3", globalDefault: "")
        XCTAssertEqual(model?.id, "kimi-k3")
        XCTAssertEqual(model?.family, .openAIChat)
    }

    func testResolveFallsBackToGlobalDefault() {
        let model = ModelCatalog.resolve("", globalDefault: "claude-haiku-5-5")
        XCTAssertEqual(model?.id, "claude-haiku-5-5")
    }

    func testResolveAutoUsesTheDailyPick() {
        let model = ModelCatalog.resolve(ModelCatalog.autoModelID, globalDefault: "")
        XCTAssertNotNil(model)
        XCTAssertTrue(ModelCatalog.autoPool.contains(model?.id ?? ""))
    }

    func testResolveWithNoDefaultsDoesNotRecurseForever() {
        let model = ModelCatalog.resolve("", globalDefault: "")
        XCTAssertNotNil(model)
    }

    func testUnknownModelGetsAFallbackFamily() {
        let model = ModelCatalog.resolve("some-new-model", globalDefault: "")
        XCTAssertEqual(model?.id, "some-new-model")
        XCTAssertEqual(model?.family, .openAIChat)
    }

    func testAutoPickIsStableWithinADayAndRotatesOverTime() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        XCTAssertEqual(ModelCatalog.autoModel(for: day1)?.id, ModelCatalog.autoModel(for: day1)?.id)
        let pool = Set(ModelCatalog.autoPool)
        XCTAssertTrue(pool.contains(ModelCatalog.autoModel(for: day1)?.id ?? ""))
        XCTAssertTrue(pool.contains(ModelCatalog.autoModel(for: day2)?.id ?? ""))
    }

    func testAutoPoolExcludesContributorTierModels() {
        for id in ModelCatalog.autoPool {
            let model = ModelCatalog.model(withID: id)
            XCTAssertNil(model?.privacyNote, "\(id) should not be a contributor-tier model")
        }
    }
}

final class ChatTitleTests: XCTestCase {
    func testShortTitleIsUsedVerbatim() {
        XCTAssertEqual(ChatTitle.make(from: "What is Swift?"), "What is Swift?")
    }

    func testLongTitleIsTruncatedOnAWordBoundary() {
        let title = ChatTitle.make(from: "Please explain how Swift concurrency works with actors in detail please")
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertLessThan(title.count, 50)
    }

    func testNewlinesBecomeSpaces() {
        XCTAssertEqual(ChatTitle.make(from: "first line\nsecond line"), "first line second line")
    }

    func testEmptyTextFallsBack() {
        XCTAssertEqual(ChatTitle.make(from: "   "), "New Chat")
    }
}

final class MarkdownParserTests: XCTestCase {
    func testProseAndCodeAreSeparated() {
        let text = "Here you go:\n\n```swift\nlet x = 1\n```\n\nDone."
        let blocks = MarkdownParser.blocks(from: text)
        XCTAssertEqual(blocks.count, 3)
        if case .prose(let value) = blocks[0].kind {
            XCTAssertEqual(value, "Here you go:")
        } else {
            XCTFail("expected prose")
        }
        if case .code(let code, let language) = blocks[1].kind {
            XCTAssertEqual(code, "let x = 1")
            XCTAssertEqual(language, "swift")
        } else {
            XCTFail("expected code")
        }
    }

    func testUnterminatedFenceIsTreatedAsCode() {
        let blocks = MarkdownParser.blocks(from: "text\n```\ncode\n")
        XCTAssertEqual(blocks.count, 2)
        if case .code(let code, _) = blocks[1].kind {
            XCTAssertEqual(code, "code\n")
        } else {
            XCTFail("expected code")
        }
    }

    func testPlainTextProducesOneProseBlock() {
        let blocks = MarkdownParser.blocks(from: "just words")
        XCTAssertEqual(blocks.count, 1)
    }
}
