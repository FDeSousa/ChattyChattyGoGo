import Foundation
import Security

/// Identity of this client towards the OpenCode Go gateway.
///
/// The gateway asks third-party clients to
///
/// 1. identify themselves with their own user agent,
/// 2. send a stable session id per conversation in `x-opencode-session`,
///
/// so it can route a conversation to the same upstream and keep the prompt cache warm.
enum SessionIdentity {
    /// The app's bundle identifier — the definitive identity of this build, used
    /// as the client name reported to the OpenCode Go gateway instead of a
    /// hardcoded string, so it stays correct if the bundle id ever changes.
    ///
    /// Falls back to a stable name if the bundle id is unavailable (for example
    /// when running in a context without a bundle).
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "pt.com.desousa.filipe.ChattyChattyGoGo"
    }

    /// The user agent the gateway should see.
    static var userAgent: String {
        "\(bundleIdentifier)/1.0 (iOS)"
    }

    /// The client name reported in `x-opencode-client`.
    static var clientName: String {
        bundleIdentifier
    }

    /// A fresh session id in OpenCode's own format: `ses_` plus 64 hex characters.
    static func makeSessionID() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // Not fatal – a UUID based id is still stable and unique.
            return "ses_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "ses_" + hex
    }

    /// A stable id for this install, used for requests that are not tied to a
    /// conversation (model list, usage).
    ///
    /// Kept out of `Preferences` so the networking layer can read it without
    /// hopping to the main actor.
    nonisolated static var installSessionID: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: installIDKey), !existing.isEmpty {
                return existing
            }
            let fresh = makeSessionID()
            UserDefaults.standard.set(fresh, forKey: installIDKey)
            return fresh
        }
        set {
            UserDefaults.standard.set(newValue, forKey: installIDKey)
        }
    }

    private nonisolated static let installIDKey = "opencodeInstallSessionID"
}
