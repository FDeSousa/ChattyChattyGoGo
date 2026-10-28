import Foundation

/// Small helper so UI tests can start from a clean slate.
enum UITestSupport {
    static let resetArgument = "-uiTestResetState"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(resetArgument)
    }
}
