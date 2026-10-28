import XCTest
@testable import LogicCheck

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

    func testErrorDescriptionUsesTheFriendlyMessage() {
        let error = APIError(
            status: 400,
            body: "{\"type\":\"error\",\"error\":{\"type\":\"MissingSessionID\",\"message\":\"No session.\"}}"
        )
        XCTAssertEqual(error.localizedDescription, "HTTP 400: MissingSessionID: No session.")
    }
}
