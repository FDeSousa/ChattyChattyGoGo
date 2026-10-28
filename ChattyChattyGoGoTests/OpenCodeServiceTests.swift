import Foundation
import XCTest
@testable import ChattyChattyGoGo

/// Records requests and replies with canned responses.
final class MockURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body: String = ""
    }

    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    static func reset() {
        replies = []
        requests = []
        bodies = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.bodyData(for: request))

        let reply = Self.replies.isEmpty ? Reply() : Self.replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession hands the body to the protocol as a stream.
    private static func bodyData(for request: URLRequest) -> Data {
        if let body = request.httpBody, !body.isEmpty { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func stopLoading() { }
}

final class OpenCodeServiceTests: XCTestCase {
    private func model(_ id: String = "kimi-k3", family: APIFamily = .openAIChat) -> ModelInfo {
        ModelInfo(id: id, displayName: id, family: family, summary: "", bestFor: [])
    }

    private func request(_ model: ModelInfo, reasoning: ReasoningLevel = .off) -> ChatRequest {
        ChatRequest(
            model: model,
            messages: [WireMessage(role: .user, content: "Hi")],
            systemPrompt: "Be brief",
            reasoning: reasoning,
            apiKey: "sk-test",
            sessionID: "ses_" + String(repeating: "a", count: 64)
        )
    }

    func testRequestCarriesSessionAndClientHeaders() async throws {
        MockURLProtocol.replies = [MockURLProtocol.Reply(body: "data: [DONE]\n")]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        _ = try await collect(service.stream(request(model()), families: [.openAIChat]))

        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        let session = "ses_" + String(repeating: "a", count: 64)

        // The gateway refuses requests without a session id.
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-opencode-session"), session)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-opencode-session-id"), session)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Session-Id"), session)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-session-affinity"), session)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-opencode-client"), SessionIdentity.clientName)

        // …and it wants a client specific user agent, not an SDK name.
        let userAgent = try XCTUnwrap(sent.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(userAgent.hasPrefix(SessionIdentity.clientName + "/"), userAgent)
    }

    func testAnthropicRequestCarriesSessionHeader() async throws {
        MockURLProtocol.replies = [MockURLProtocol.Reply(body: "data: {\"type\":\"message_stop\"}\n")]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        _ = try await collect(service.stream(request(model("claude-haiku-5-5", family: .anthropic)), families: [.anthropic]))

        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertNotNil(sent.value(forHTTPHeaderField: "x-opencode-session"))
    }

    func testModelListCarriesSessionHeader() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: "{\"object\":\"list\",\"data\":[{\"id\":\"kimi-k3\"}]}")
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        _ = try await service.fetchModels(apiKey: "sk-test")

        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        let session = try XCTUnwrap(sent.value(forHTTPHeaderField: "x-opencode-session"))
        XCTAssertTrue(session.hasPrefix("ses_"), session)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> String {
        var text = ""
        for try await event in stream {
            if case .content(let value) = event { text += value }
        }
        return text
    }

    private func collectUsage(_ stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> TokenUsage {
        var usage = TokenUsage()
        for try await event in stream {
            if case .usage(let reported) = event { usage = usage.merged(with: reported) }
        }
        return usage
    }

    func testOpenAIChatRequestAndStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: [DONE]

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model()), families: [.openAIChat]))

        XCTAssertEqual(text, "Hello world")
        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://opencode.ai/inference/go/openai/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "kimi-k3")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["content"] as? String, "Hi")
    }

    func testOpenAIResponsesRequestAndStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"Hi"}

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model("grok-4.7", family: .openAIResponses)), families: [.openAIResponses]))

        XCTAssertEqual(text, "Hi")
        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://opencode.ai/inference/go/openai/v1/responses")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        XCTAssertEqual(body["instructions"] as? String, "Be brief")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
    }

    func testAnthropicRequestAndStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Bonjour"}}

            data: {"type":"message_stop"}

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model("claude-haiku-5-5", family: .anthropic)), families: [.anthropic]))

        XCTAssertEqual(text, "Bonjour")
        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://opencode.ai/inference/go/anthropic/v1/messages")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "Be brief")
        XCTAssertEqual(body["max_tokens"] as? Int, 8192)
    }

    func testGoogleRequestAndStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            data: {"candidates":[{"content":{"parts":[{"text":"Ciao"}]}}]}

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model("gemini-4-argon-contributor", family: .google)), families: [.google]))

        XCTAssertEqual(text, "Ciao")
        let sent = try XCTUnwrap(MockURLProtocol.requests.first)
        let url = try XCTUnwrap(sent.url)
        XCTAssertTrue(url.absoluteString.contains("/inference/go/google/v1beta/models/gemini-4-argon-contributor:streamGenerateContent"))
        XCTAssertTrue(url.absoluteString.contains("alt=sse"))
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-goog-api-key"), "sk-test")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        XCTAssertNotNil(body["systemInstruction"])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents[0]["role"] as? String, "user")
    }

    func testWrongFamilyFallsBackToTheNextEndpoint() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(status: 404, body: "model not found on this endpoint"),
            MockURLProtocol.Reply(body: """
            data: {"type":"response.output_text.delta","delta":"Recovered"}

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model()), families: [.openAIChat, .openAIResponses]))

        XCTAssertEqual(text, "Recovered")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertTrue(try XCTUnwrap(MockURLProtocol.requests.last?.url?.absoluteString).contains("/responses"))
    }

    func testNonRoutingErrorIsNotRetried() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(status: 401, body: "invalid api key")
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        do {
            _ = try await collect(service.stream(request(model()), families: [.openAIChat, .openAIResponses]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(MockURLProtocol.requests.count, 1)
        }
    }

    func testUnsupportedReasoningParameterIsRetriedWithoutIt() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(status: 400, body: "unknown field: reasoning_effort"),
            MockURLProtocol.Reply(body: """
            data: {"choices":[{"delta":{"content":"Fine"}}]}

            data: [DONE]

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let text = try await collect(service.stream(request(model(), reasoning: .high), families: [.openAIChat]))

        XCTAssertEqual(text, "Fine")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)

        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[0]) as? [String: Any])
        XCTAssertEqual(first["reasoning_effort"] as? String, "high")

        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: MockURLProtocol.bodies[1]) as? [String: Any])
        XCTAssertNil(second["reasoning_effort"])
    }

    func testUsageIsParsedFromTheOpenAIStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            data: {"choices":[{"delta":{"content":"Hi"}}]}

            data: {"choices":[],"usage":{"prompt_tokens":1200,"completion_tokens":340,"prompt_tokens_details":{"cached_tokens":900}}}

            data: [DONE]

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let usage = try await collectUsage(service.stream(request(model()), families: [.openAIChat]))

        XCTAssertEqual(usage.inputTokens, 1200)
        XCTAssertEqual(usage.outputTokens, 340)
        XCTAssertEqual(usage.cachedInputTokens, 900)
        XCTAssertEqual(usage.billedInputTokens, 300)
    }

    func testUsageIsParsedFromTheAnthropicStream() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: """
            data: {"type":"message_start","message":{"usage":{"input_tokens":800,"cache_read_input_tokens":600}}}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

            data: {"type":"message_delta","usage":{"output_tokens":120}}

            data: {"type":"message_stop"}

            """)
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let usage = try await collectUsage(
            service.stream(request(model("claude-haiku-5-5", family: .anthropic)), families: [.anthropic])
        )

        XCTAssertEqual(usage.inputTokens, 800)
        XCTAssertEqual(usage.cachedInputTokens, 600)
        XCTAssertEqual(usage.outputTokens, 120)
    }

    func testFetchModelsParsesIdentifiers() async throws {
        MockURLProtocol.replies = [
            MockURLProtocol.Reply(body: "{\"object\":\"list\",\"data\":[{\"id\":\"kimi-k3\"},{\"id\":\"glm-5.3\"}]}")
        ]
        let service = OpenCodeService(session: MockURLProtocol.makeSession())
        let models = try await service.fetchModels(apiKey: "sk-test")
        XCTAssertEqual(models, ["kimi-k3", "glm-5.3"])
        XCTAssertEqual(
            try XCTUnwrap(MockURLProtocol.requests.first?.url?.absoluteString),
            "https://opencode.ai/inference/go/v1/models"
        )
    }

    func testUsageDecoding() throws {
        let json = """
        {"usage":{"rolling":{"status":"ok","percent":11,"resetsAt":"2026-08-17T17:10:09.580Z"},
        "weekly":{"status":"ok","percent":4,"resetsAt":"2026-08-24T00:00:00.580Z"},
        "monthly":{"status":"ok","percent":2,"resetsAt":"2026-09-13T04:26:00.580Z"}}}
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.rolling.percent, 11)
        XCTAssertEqual(snapshot.weekly.percent, 4)
        XCTAssertEqual(snapshot.monthly.percent, 2)
        XCTAssertNotNil(snapshot.rolling.resetsAt)
    }
}
