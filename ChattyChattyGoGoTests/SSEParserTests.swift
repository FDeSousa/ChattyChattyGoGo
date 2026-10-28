import XCTest
@testable import ChattyChattyGoGo

final class SSEParserTests: XCTestCase {
    func testOpenAIChatDelta() {
        var parser = SSEParser(family: .openAIChat)
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
        guard case .content(let text)? = parser.consume(line: line) else {
            return XCTFail("expected content chunk")
        }
        XCTAssertEqual(text, "Hello")
    }

    func testOpenAIChatDoneMarker() {
        var parser = SSEParser(family: .openAIChat)
        XCTAssertNil(parser.consume(line: "data: [DONE]"))
        XCTAssertTrue(parser.isFinished)
    }

    func testOpenAIChatReasoningIsSeparated() {
        var parser = SSEParser(family: .openAIChat)
        let line = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"thinking\"}}]}"
        guard case .reasoning(let text)? = parser.consume(line: line) else {
            return XCTFail("expected reasoning chunk")
        }
        XCTAssertEqual(text, "thinking")
    }

    func testOpenAIResponsesDelta() {
        var parser = SSEParser(family: .openAIResponses)
        XCTAssertNil(parser.consume(line: "event: response.output_text.delta"))
        let line = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}"
        guard case .content(let text)? = parser.consume(line: line) else {
            return XCTFail("expected content chunk")
        }
        XCTAssertEqual(text, "Hi")
    }

    func testAnthropicContentBlockDelta() {
        var parser = SSEParser(family: .anthropic)
        let line = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Bonjour\"}}"
        guard case .content(let text)? = parser.consume(line: line) else {
            return XCTFail("expected content chunk")
        }
        XCTAssertEqual(text, "Bonjour")
    }

    func testAnthropicThinkingDelta() {
        var parser = SSEParser(family: .anthropic)
        let line = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"hmm\"}}"
        guard case .reasoning(let text)? = parser.consume(line: line) else {
            return XCTFail("expected reasoning chunk")
        }
        XCTAssertEqual(text, "hmm")
    }

    func testAnthropicMessageStop() {
        var parser = SSEParser(family: .anthropic)
        XCTAssertNil(parser.consume(line: "data: {\"type\":\"message_stop\"}"))
        XCTAssertTrue(parser.isFinished)
    }

    func testGoogleCandidateText() {
        var parser = SSEParser(family: .google)
        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Ciao\"}]}}]}"
        guard case .content(let text)? = parser.consume(line: line) else {
            return XCTFail("expected content chunk")
        }
        XCTAssertEqual(text, "Ciao")
    }

    func testGoogleThoughtPartIsReasoning() {
        var parser = SSEParser(family: .google)
        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"pondering\",\"thought\":true}]}}]}"
        guard case .reasoning(let text)? = parser.consume(line: line) else {
            return XCTFail("expected reasoning chunk")
        }
        XCTAssertEqual(text, "pondering")
    }

    func testCommentsAndUnknownFieldsAreIgnored() {
        var parser = SSEParser(family: .openAIChat)
        XCTAssertNil(parser.consume(line: ": keep-alive"))
        XCTAssertNil(parser.consume(line: "id: 42"))
        XCTAssertNil(parser.consume(line: ""))
    }

    func testMalformedPayloadIsIgnored() {
        var parser = SSEParser(family: .openAIChat)
        XCTAssertNil(parser.consume(line: "data: {not json"))
    }
}
