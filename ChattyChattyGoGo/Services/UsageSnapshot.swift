import Foundation

/// Usage windows reported by the OpenCode Go account endpoint.
struct UsageSnapshot: Sendable {
    struct Window: Sendable, Identifiable {
        let id: String
        let status: String
        /// Percentage of the allowance already used (0...100).
        let percent: Double
        let resetsAt: Date?

        var isHealthy: Bool {
            percent < 80
        }
    }

    let rolling: Window
    let weekly: Window
    let monthly: Window

    /// The pay-as-you-go balance, when the endpoint reports one.
    ///
    /// OpenCode does not document a balance field on the usage endpoint, so this
    /// is read opportunistically from any plausibly-dollar `balance`/`credits`
    /// field in the payload. The interface shows it as it arrives - simply not at
    /// all when the endpoint does not say.
    let balanceUSD: Double?

    var windows: [Window] { [rolling, weekly, monthly] }

    static func decode(from data: Data) throws -> UsageSnapshot {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = payload["usage"] as? [String: Any] else {
            throw APIError.decoding("Usage information could not be read.")
        }

        func window(_ key: String) -> Window {
            let value = usage[key] as? [String: Any] ?? [:]
            let percent = (value["percent"] as? NSNumber)?.doubleValue ?? 0
            let resetsAt = (value["resetsAt"] as? String).flatMap { UsageSnapshot.parseDate($0) }
            return Window(
                id: key,
                status: value["status"] as? String ?? "unknown",
                percent: percent,
                resetsAt: resetsAt
            )
        }

        func number(_ any: Any?) -> Double? {
            switch any {
            case let number as NSNumber:
                let value = number.doubleValue
                // Anything outside dollar range is more likely a token or cent
                // count than a balance, and a wrong number would mislead.
                return value.isFinite && value >= 0 && value < 1_000_000 ? value : nil
            case let string as String:
                guard let value = Double(string), value.isFinite, value >= 0, value < 1_000_000 else { return nil }
                return value
            default:
                return nil
            }
        }

        let balanceUSD = number(usage["balance"])
            ?? number(usage["credits"])
            ?? number(usage["credit"])
            ?? number(payload["balance"])
            ?? number(payload["credits"])

        return UsageSnapshot(
            rolling: window("rolling"),
            weekly: window("weekly"),
            monthly: window("monthly"),
            balanceUSD: balanceUSD
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
