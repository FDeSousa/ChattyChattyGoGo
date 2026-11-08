import XCTest
import SwiftData
@testable import ChattyChattyGoGo

final class AppToolRegistryTests: XCTestCase {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    func testCalculatorEvaluatesArithmeticWithoutSendingItToAModel() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = await AppToolRegistry.execute(
            FunctionToolCall(id: "call-1", name: "calculator", arguments: #"{"expression":"(12 + 8) * 3 / 2"}"#),
            context: context,
            attachments: []
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let value = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(value["value"] as? NSNumber).doubleValue, 30, accuracy: 0.0001)
    }

    @MainActor
    func testUnitConversionHandlesTemperatureOffsets() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let result = await AppToolRegistry.execute(
            FunctionToolCall(id: "call-2", name: "convert_units", arguments: #"{"value":0,"from":"C","to":"F"}"#),
            context: context,
            attachments: []
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let value = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(value["value"] as? NSNumber).doubleValue, 32, accuracy: 0.0001)
    }

    @MainActor
    func testPrivateDataAndWriteToolsRequirePerCallApproval() throws {
        let cases: [(String, String, String)] = [
            ("search_chats", #"{"query":"project"}"#, "Search saved chats?"),
            ("lookup_contacts", #"{"name":"Ada"}"#, "Search contacts?"),
            ("create_reminder", #"{"title":"Call dentist"}"#, "Create reminder?"),
            ("create_calendar_event", #"{"title":"Review","start":"2026-11-08T10:00:00Z","end":"2026-11-08T10:30:00Z"}"#, "Create calendar event?")
        ]
        for (name, arguments, title) in cases {
            let call = FunctionToolCall(id: name, name: name, arguments: arguments)
            XCTAssertEqual(AppToolRegistry.approval(for: call)?.title, title)
        }
        XCTAssertNil(AppToolRegistry.approval(for: FunctionToolCall(id: "calc", name: "calculator", arguments: #"{"expression":"1+1"}"#)))
    }
}
