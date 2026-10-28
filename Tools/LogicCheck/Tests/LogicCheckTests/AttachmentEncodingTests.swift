import Foundation
import XCTest
@testable import LogicCheck

/// How attachments are encoded for each provider dialect.
final class AttachmentEncodingTests: XCTestCase {
    private func body(_ model: ModelInfo, family: APIFamily, attachment: WireAttachment) throws -> [String: Any] {
        MockURLProtocol.reset()
        MockURLProtocol.replies = [MockURLProtocol.Reply(body: "data: [DONE]\n")]

        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let request = ChatRequest(
            model: model,
            messages: [
                WireMessage(role: .user, content: "What is this?", attachments: [attachment])
            ],
            apiKey: "sk-test",
            sessionID: "ses_" + String(repeating: "b", count: 64)
        )

        let expectation = expectation(description: "stream")
        Task {
            for try await _ in service.stream(request, families: [family]) { }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let data = try XCTUnwrap(MockURLProtocol.bodies.first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let image = WireAttachment.image(mimeType: "image/jpeg", base64: "QUJD")

    func testOpenAIChatSendsImageURLParts() throws {
        let model = ModelInfo(id: "kimi-k3", displayName: "Kimi", family: .openAIChat, summary: "", bestFor: [])
        let body = try body(model, family: .openAIChat, attachment: image)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let url = try XCTUnwrap((content[1]["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertEqual(url, "data:image/jpeg;base64,QUJD")
    }

    func testOpenAIResponsesSendsInputImageParts() throws {
        let model = ModelInfo(id: "grok-4.7", displayName: "Grok", family: .openAIResponses, summary: "", bestFor: [])
        let body = try body(model, family: .openAIResponses, attachment: image)

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,QUJD")
    }

    func testAnthropicSendsBase64ImageBlocks() throws {
        let model = ModelInfo(id: "claude-haiku-5-5", displayName: "Claude", family: .anthropic, summary: "", bestFor: [])
        let body = try body(model, family: .anthropic, attachment: image)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[1]["type"] as? String, "image")
        let source = try XCTUnwrap(content[1]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "QUJD")
    }

    func testGeminiSendsInlineData() throws {
        let model = ModelInfo(id: "gemini-4-argon-contributor", displayName: "Gemini", family: .google, summary: "", bestFor: [])
        let body = try body(model, family: .google, attachment: image)

        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(inline["data"] as? String, "QUJD")
    }

    func testDocumentsAreSentAsTextForEveryFamily() throws {
        let document = WireAttachment.document(text: "The quick brown fox.")

        let chatModel = ModelInfo(id: "kimi-k3", displayName: "Kimi", family: .openAIChat, summary: "", bestFor: [])
        let chatBody = try body(chatModel, family: .openAIChat, attachment: document)
        let chatMessages = try XCTUnwrap(chatBody["messages"] as? [[String: Any]])
        let chatContent = try XCTUnwrap(chatMessages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(chatContent[1]["text"] as? String, "The quick brown fox.")

        let geminiModel = ModelInfo(id: "gemini-4-argon-contributor", displayName: "Gemini", family: .google, summary: "", bestFor: [])
        let geminiBody = try body(geminiModel, family: .google, attachment: document)
        let contents = try XCTUnwrap(geminiBody["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts[1]["text"] as? String, "The quick brown fox.")
    }

    func testPlainTextMessagesStaySimple() throws {
        MockURLProtocol.reset()
        MockURLProtocol.replies = [MockURLProtocol.Reply(body: "data: [DONE]\n")]

        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let model = ModelInfo(id: "kimi-k3", displayName: "Kimi", family: .openAIChat, summary: "", bestFor: [])
        let request = ChatRequest(
            model: model,
            messages: [WireMessage(role: .user, content: "Hello")],
            apiKey: "sk-test"
        )
        let expectation = expectation(description: "stream")
        Task {
            for try await _ in service.stream(request, families: [.openAIChat]) { }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let data = try XCTUnwrap(MockURLProtocol.bodies.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, "Hello")
    }
}
