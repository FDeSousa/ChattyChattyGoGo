import SwiftData
import XCTest
@testable import LogicCheck

/// Export and import round trip.
@MainActor
final class BackupTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Conversation.self, Message.self, configurations: configuration)
    }

    private func seed(_ context: ModelContext) throws -> Conversation {
        let conversation = Conversation(title: "Trip to Lisbon", modelID: "kimi-k3")
        let question = Message(role: .user, content: "Where should I eat?", conversation: conversation)
        let answer = Message(role: .assistant, content: "Try Alfama.", conversation: conversation)
        answer.createdAt = question.createdAt.addingTimeInterval(0.001)
        answer.modelIDUsed = "kimi-k3"
        context.insert(conversation)
        context.insert(question)
        context.insert(answer)
        try context.save()
        return conversation
    }

    func testExportThenImportRestoresTheSameChats() throws {
        let source = try makeContainer()
        let conversation = try seed(source.mainContext)

        let url = try BackupService.export(conversations: [conversation])
        let (payload, summary) = try BackupService.read(from: url)

        XCTAssertEqual(summary.chats, 1)
        XCTAssertEqual(summary.messages, 2)
        XCTAssertEqual(payload.chats.first?.title, "Trip to Lisbon")

        // Import into a fresh store.
        let target = try makeContainer()
        let imported = try BackupService.import(payload, into: target.mainContext, mode: .merge)

        XCTAssertEqual(imported.chats, 1)
        XCTAssertEqual(imported.messages, 2)

        let fetched = try target.mainContext.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.first?.displayTitle, "Trip to Lisbon")
        XCTAssertEqual(fetched.first?.messages.count, 2)
        XCTAssertEqual(fetched.first?.sortedMessages.first?.content, "Where should I eat?")
    }

    func testImportedMessagesAreSearchable() throws {
        let source = try makeContainer()
        let conversation = try seed(source.mainContext)
        let url = try BackupService.export(conversations: [conversation])
        let (payload, _) = try BackupService.read(from: url)

        let target = try makeContainer()
        _ = try BackupService.import(payload, into: target.mainContext, mode: .merge)

        // The searchable copy must be rebuilt, or the import would be invisible to search.
        let results = ChatListViewModel.runSearch(query: "alfama", in: target.mainContext)
        XCTAssertFalse(results.isEmpty)
    }

    func testMergeSkipsChatsAlreadyInTheStore() throws {
        let source = try makeContainer()
        let conversation = try seed(source.mainContext)
        let url = try BackupService.export(conversations: [conversation])
        let (payload, _) = try BackupService.read(from: url)

        // Import twice into the same store.
        _ = try BackupService.import(payload, into: source.mainContext, mode: .merge)
        let second = try BackupService.import(payload, into: source.mainContext, mode: .merge)

        XCTAssertEqual(second.chats, 0, "a chat that already exists must not be added again")
        let count = try source.mainContext.fetch(FetchDescriptor<Conversation>()).count
        XCTAssertEqual(count, 1)
    }

    func testReplaceEmptiesTheStoreFirst() throws {
        let source = try makeContainer()
        try seed(source.mainContext)

        let other = Conversation(title: "Only this one should survive")
        let message = Message(role: .user, content: "Hello", conversation: other)
        source.mainContext.insert(other)
        source.mainContext.insert(message)
        try source.mainContext.save()

        let url = try BackupService.export(conversations: [other])
        let (payload, _) = try BackupService.read(from: url)

        _ = try BackupService.import(payload, into: source.mainContext, mode: .replace)

        let conversations = try source.mainContext.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.displayTitle, "Only this one should survive")
    }

    func testForeignFilesAreRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-backup-\(UUID().uuidString).json")
        try Data("{\"hello\":\"world\"}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try BackupService.read(from: url)
            XCTFail("a file without chats should not be accepted")
        } catch {
            // expected
        }
    }

    func testImportedChatsGetTheirOwnSessionID() throws {
        let source = try makeContainer()
        let conversation = try seed(source.mainContext)
        let url = try BackupService.export(conversations: [conversation])
        let (payload, _) = try BackupService.read(from: url)

        let target = try makeContainer()
        _ = try BackupService.import(payload, into: target.mainContext, mode: .merge)

        let fetched = try target.mainContext.fetch(FetchDescriptor<Conversation>())
        XCTAssertTrue(fetched.first?.sessionID.hasPrefix("ses_") ?? false)
    }
}
