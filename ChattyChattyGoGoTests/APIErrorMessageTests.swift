import XCTest
@testable import ChattyChattyGoGo

/// The gateway's error bodies are JSON; the app should show the human readable part.
final class APIErrorMessageTests: XCTestCase {
    func testExtractsMessageFromGatewayErrorShape() {
        let body = """
        {"type":"error","error":{"type":"MissingSessionID","message":"Request is missing x-opencode-session and cannot be routed efficiently."}}
        """
        let message = APIError.friendlyMessage(from: body)
        XCTAssertEqual(
            message,
            "MissingSessionID: Request is missing x-opencode-session and cannot be routed efficiently."
        )
    }

    func testExtractsPlainMessage() {
        XCTAssertEqual(
            APIError.friendlyMessage(from: "{\"message\":\"Rate limit reached\"}"),
            "Rate limit reached"
        )
    }

    func testFallsBackToTheRawBody() {
        XCTAssertNil(APIError.friendlyMessage(from: "not json"))
    }

    /// The exact reply the gateway sent when a free model was blocked by the
    /// workspace's Privacy settings.
    static let privacyBody = """
        {"error":{"message":"Free models may train on request data. Allow free endpoints in your workspace's Privacy settings to use them."}}
        """

    func testPrivacyRejectionCountsAsModelUnavailable() {
        for status in [400, 403] {
            let error = APIError(status: status, body: Self.privacyBody)
            XCTAssertTrue(error.suggestsModelUnavailable, "HTTP \(status) privacy rejection should read as unavailable")
            XCTAssertFalse(error.isAuthProblem, "HTTP \(status) privacy rejection is not an auth problem: the key is fine")
            XCTAssertFalse(error.isRetryable)
        }
    }

    func testServerReasonKeepsTheGatewayOwnWords() {
        let error = APIError(status: 403, body: Self.privacyBody)
        XCTAssertEqual(
            error.serverReason,
            "Free models may train on request data. Allow free endpoints in your workspace's Privacy settings to use them."
        )
    }

    func testServerReasonOfABodylessErrorIsNothing() {
        XCTAssertNil(APIError.transport("no route").serverReason)
        XCTAssertNil(APIError(status: 403, body: "").serverReason)
    }

    func testServerReasonIsTruncated() {
        let long = String(repeating: "words ", count: 300)
        let body = "{\"message\":\"\(long)\"}"
        let reason = APIError(status: 400, body: body).serverReason
        XCTAssertTrue(reason?.hasSuffix("…") ?? false)
        XCTAssertLessThanOrEqual(reason?.count ?? 0, 301)
    }

    func testPlainBodyIsUsedVerbatimAsTheReason() {
        XCTAssertEqual(
            APIError(status: 403, body: "model nemotron-3-ultra-free is not enabled.").serverReason,
            "model nemotron-3-ultra-free is not enabled."
        )
    }

    func testErrorDescriptionUsesTheFriendlyMessage() {
        let error = APIError(
            status: 400,
            body: "{\"type\":\"error\",\"error\":{\"type\":\"MissingSessionID\",\"message\":\"No session.\"}}"
        )
        XCTAssertEqual(error.localizedDescription, "HTTP 400: MissingSessionID: No session.")
    }

    /// The exact reply the gateway sent when an account's free Jev budget was
    /// spent. Retrying this with backoff is what made a trial run stretch on
    /// before the same answer finally landed.
    static let freeUsageLimitBody = """
        {"error":{"type":"FreeUsageLimitError","message":"Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go to keep going: https://opencode.ai/go"}}
        """

    func testQuotaExhaustedFourTwentyNineIsFinal() {
        let error = APIError(status: 429, body: Self.freeUsageLimitBody)
        XCTAssertTrue(error.isQuotaExhausted)
        XCTAssertFalse(error.isRetryable, "the budget is spent; waiting changes nothing")
        XCTAssertFalse(error.isAuthProblem, "the key is fine; only the free budget is spent")
    }

    func testQuotaExhaustionIsReadStraightOffTheMessageToo() {
        let error = APIError(status: 429, body: "Free usage limit reached - subscribe to OpenCode Go to keep going.")
        XCTAssertTrue(error.isQuotaExhausted)
        XCTAssertFalse(error.isRetryable)
    }

    func testPlainRateLimitFourTwentyNineStaysRetryable() {
        let error = APIError(status: 429, body: "{\"message\":\"Rate limit exceeded, slow down.\"}")
        XCTAssertFalse(error.isQuotaExhausted)
        XCTAssertTrue(error.isRetryable)
    }
}
