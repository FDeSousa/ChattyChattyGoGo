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

    func testOpenAIChatParsesStreamedFunctionCallArguments() {
        var parser = SSEParser(family: .openAIChat)
        let first = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"calculator","arguments":"{\"expression\":\"2"}}]}}]}"#
        let second = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"*3\"}"}}]},"finish_reason":"tool_calls"}]}"#
        XCTAssertNil(parser.consume(line: first))
        guard case .toolCalls(let calls, _)? = parser.consume(line: second) else {
            return XCTFail("expected completed function call")
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].id, "call-1")
        XCTAssertEqual(calls[0].name, "calculator")
        XCTAssertEqual(calls[0].arguments, #"{"expression":"2*3"}"#)
        XCTAssertFalse(parser.isFinished, "the stream may still report token usage before [DONE]")
        XCTAssertNil(parser.consume(line: "data: [DONE]"))
        XCTAssertTrue(parser.isFinished)
    }

    func testOpenAIResponsesExtractsFunctionCallsAndUsage() {
        var parser = SSEParser(family: .openAIResponses)
        let line = #"data: {"type":"response.completed","response":{"output":[{"type":"function_call","call_id":"call-2","name":"calculator","arguments":"{\"expression\":\"4+5\"}"}],"usage":{"input_tokens":12,"output_tokens":3}}}"#
        guard case .toolCalls(let calls, let usage)? = parser.consume(line: line) else {
            return XCTFail("expected Responses function call")
        }
        XCTAssertEqual(calls.first?.id, "call-2")
        XCTAssertEqual(calls.first?.name, "calculator")
        XCTAssertEqual(calls.first?.arguments, #"{"expression":"4+5"}"#)
        XCTAssertEqual(usage?.inputTokens, 12)
        XCTAssertTrue(parser.isFinished)
    }

    func testGoogleParsesFunctionCallParts() {
        var parser = SSEParser(family: .google)
        let line = #"data: {"usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":2},"candidates":[{"content":{"parts":[{"functionCall":{"name":"calculator","args":{"expression":"6*7"}}}]},"finishReason":"STOP"}]}"#
        guard case .toolCalls(let calls, let usage)? = parser.consume(line: line) else {
            return XCTFail("expected Gemini function call")
        }
        XCTAssertEqual(calls.first?.name, "calculator")
        XCTAssertEqual(calls.first?.arguments, #"{"expression":"6*7"}"#)
        XCTAssertEqual(usage?.inputTokens, 8)
        XCTAssertTrue(parser.isFinished)
    }
}
