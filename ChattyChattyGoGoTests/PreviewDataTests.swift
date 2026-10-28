import SwiftData
import XCTest
@testable import ChattyChattyGoGo

@MainActor
final class PreviewDataTests: XCTestCase {
    func testConversationWithPrePopulatedMessagesCanBeStored() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Conversation.self, Message.self, configurations: configuration)
        let context = container.mainContext

        let conversation = Conversation(title: "Trip to Lisbon", modelID: "kimi-k3")
        conversation.messages = [
            Message(role: .user, content: "Plan my trip"),
            Message(role: .assistant, content: "Here is a plan")
        ]
        context.insert(conversation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].messages.count, 2)
        XCTAssertEqual(fetched[0].displayTitle, "Trip to Lisbon")
        XCTAssertEqual(fetched[0].lastMessage?.role, .assistant)
    }

    func testMessageSearchIndexIsPersisted() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Conversation.self, Message.self, configurations: configuration)
        let context = container.mainContext

        let conversation = Conversation(title: "Shopping")
        let message = Message(role: .user, content: "Buy MILK")
        message.refreshSearchText()
        context.insert(conversation)
        context.insert(message)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Message>()).first
        XCTAssertEqual(stored?.searchText, "buy milk")
    }
}
