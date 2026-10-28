import SwiftData
import XCTest
@testable import ChattyChattyGoGo

@MainActor
final class PersistenceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Conversation.self, Message.self, configurations: configuration)
    }

    func testMessagesAreStoredOnTheConversation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let conversation = Conversation(title: "Trip ideas")
        context.insert(conversation)

        let question = Message(role: .user, content: "Where should I go?", conversation: conversation)
        let answer = Message(role: .assistant, content: "Lisbon.", conversation: conversation)
        context.insert(question)
        context.insert(answer)
        try context.save()

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.sortedMessages.first?.content, "Where should I go?")
        XCTAssertEqual(conversation.sortedMessages.last?.role, .assistant)
        XCTAssertEqual(conversation.lastMessage?.content, "Lisbon.")
    }

    func testDeletingAConversationRemovesItsMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let conversation = Conversation(title: "Doomed")
        context.insert(conversation)
        context.insert(Message(role: .user, content: "Hello", conversation: conversation))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Message>()).count, 1)

        context.delete(conversation)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Message>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Conversation>()).count, 0)
    }

    func testRoleRoundTripsThroughStorage() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let message = Message(role: .assistant, content: "Hi")
        context.insert(message)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<Message>()).first)
        XCTAssertEqual(fetched.role, .assistant)
        XCTAssertEqual(fetched.roleRaw, "assistant")
    }

    func testConversationDisplayTitleFallsBackToNewChat() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        XCTAssertEqual(conversation.displayTitle, "New Chat")
    }
}
