import SwiftData
import XCTest
@testable import LogicCheck

@MainActor
final class ChatSearchTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Conversation.self, Message.self, configurations: configuration)
    }

    func testSearchFindsMessagesByContent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let trip = Conversation(title: "Trip to Lisbon")
        context.insert(trip)
        let tripMessage = Message(role: .user, content: "Where should I eat in Lisbon?", conversation: trip)
        tripMessage.refreshSearchText()
        context.insert(tripMessage)

        let code = Conversation(title: "Swift helpers")
        context.insert(code)
        let codeMessage = Message(role: .user, content: "Write a debounce function", conversation: code)
        codeMessage.refreshSearchText()
        context.insert(codeMessage)
        try context.save()

        let results = ChatListViewModel.runSearch(query: "lisbon", in: context)

        XCTAssertTrue(results.contains { $0.conversation.id == trip.id })
        XCTAssertFalse(results.contains { $0.conversation.id == code.id })
    }

    func testSearchIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let chat = Conversation(title: "Shopping")
        context.insert(chat)
        let message = Message(role: .user, content: "Buy MILK and eggs", conversation: chat)
        message.refreshSearchText()
        context.insert(message)
        try context.save()

        let results = ChatListViewModel.runSearch(query: "milk", in: context)
        XCTAssertEqual(results.count, 1)
    }

    func testAccentInsensitiveSearch() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let chat = Conversation(title: "Café")
        context.insert(chat)
        let message = Message(role: .user, content: "Zürich or Málaga?", conversation: chat)
        message.refreshSearchText()
        context.insert(message)
        try context.save()

        XCTAssertEqual(ChatListViewModel.runSearch(query: "zurich", in: context).count, 1)
        XCTAssertEqual(ChatListViewModel.runSearch(query: "malaga", in: context).count, 1)
        XCTAssertEqual(ChatListViewModel.runSearch(query: "café", in: context).count, 1)
    }

    func testShortQueriesReturnNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let chat = Conversation(title: "Anything")
        context.insert(chat)
        try context.save()

        let results = ChatListViewModel.runSearch(query: "a", in: context)
        XCTAssertTrue(results.isEmpty)
    }
}
