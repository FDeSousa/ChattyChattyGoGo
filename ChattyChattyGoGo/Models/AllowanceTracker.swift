import Foundation

/// How much of a model's allowance this app has used, per window.
///
/// OpenCode Go gives each model a monthly dollar limit, and splits it into windows:
/// a rolling 5-hour window at 20% of the monthly limit, a week at 50%, and the month
/// itself at 100%. Those windows are counted from the replies recorded on this device,
/// so they cover only what this app has used.
struct ModelAllowance: Sendable, Identifiable, Hashable {
    let modelID: String
    /// Dollar limit for one month, from the published price list.
    let monthlyLimit: Double
    /// Dollars used in each window.
    let rolling5h: Double
    let weekly: Double
    let monthly: Double

    var id: String { modelID }

    var displayName: String {
        ModelCatalog.model(withID: modelID)?.displayName ?? modelID
    }

    /// Percentage of each window already used.
    var rollingPercent: Double { percent(rolling5h, of: monthlyLimit * 0.2) }
    var weeklyPercent: Double { percent(weekly, of: monthlyLimit * 0.5) }
    var monthlyPercent: Double { percent(monthly, of: monthlyLimit) }

    var isUnlimited: Bool { monthlyLimit <= 0 }

    private func percent(_ used: Double, of limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(100, used / limit * 100)
    }
}

enum AllowanceTracker {
    /// The models this app has used, with their usage per window.
    static func allowances(from messages: [Message]) -> [ModelAllowance] {
        let now = Date.now
        var buckets: [String: (rolling: Double, week: Double, month: Double)] = [:]

        for message in messages {
            guard message.role == .assistant, !message.modelIDUsed.isEmpty else { continue }
            let cost = message.costUSD
            guard cost > 0 else { continue }
            var entry = buckets[message.modelIDUsed] ?? (0, 0, 0)
            if message.createdAt > now.addingTimeInterval(-5 * 3600) {
                entry.rolling += cost
            }
            if message.createdAt > now.addingTimeInterval(-7 * 24 * 3600) {
                entry.week += cost
            }
            if message.createdAt > startOfMonth(now) {
                entry.month += cost
            }
            buckets[message.modelIDUsed] = entry
        }

        return buckets.map { modelID, entry in
            let limit = ModelPrices.monthlyLimits[modelID] ?? 0
            return ModelAllowance(
                modelID: modelID,
                monthlyLimit: limit,
                rolling5h: entry.rolling,
                weekly: entry.week,
                monthly: entry.month
            )
        }
        .sorted { $0.rollingPercent > $1.rollingPercent }
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
