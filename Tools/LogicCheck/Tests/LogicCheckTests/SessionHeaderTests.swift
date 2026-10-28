import Foundation
import XCTest
@testable import LogicCheck

/// The Go gateway requires a stable session id and a client specific user agent.
final class SessionHeaderTests: XCTestCase {
    func testSessionIDHasOpenCodeFormat() {
        let id = SessionIdentity.makeSessionID()
        XCTAssertTrue(id.hasPrefix("ses_"), id)
        XCTAssertEqual(id.count, 68, id) // "ses_" + 64 hex characters
        let hex = String(id.dropFirst(4))
        XCTAssertNotNil(hex.range(of: "^[0-9a-f]{64}$", options: .regularExpression), hex)
    }

    func testSessionIDsAreUnique() {
        let ids = (0..<50).map { _ in SessionIdentity.makeSessionID() }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testInstallSessionIDIsStable() {
        let first = SessionIdentity.installSessionID
        let second = SessionIdentity.installSessionID
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("ses_"))
    }

    func testUserAgentIdentifiesTheClient() {
        XCTAssertTrue(SessionIdentity.userAgent.hasPrefix(SessionIdentity.clientName + "/"))
        XCTAssertFalse(SessionIdentity.userAgent.lowercased().contains("cfnetwork"))
        XCTAssertFalse(SessionIdentity.userAgent.lowercased().contains("darwin"))
    }
}
