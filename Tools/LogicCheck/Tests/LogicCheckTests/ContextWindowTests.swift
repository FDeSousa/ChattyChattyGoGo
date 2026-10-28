import Foundation
import XCTest
@testable import LogicCheck

final class ContextWindowTests: XCTestCase {
    private func message(_ role: WireMessage.Role, _ text: String) -> WireMessage {
        WireMessage(role: role, content: text)
    }

    func testShortConversationsAreSentInFull() {
        let messages = [
            message(.user, "First"),
            message(.assistant, "Second"),
            message(.user, "Third")
        ]
        let result = ContextWindow.fit(messages, systemPrompt: nil, modelID: "kimi-k3")
        XCTAssertEqual(result.kept.count, 3)
        XCTAssertEqual(result.trimmed, 0)
    }

    func testOldMessagesAreDroppedFirst() {
        // 5,000 tokens per message against a 100,000 token window forces trimming.
        var messages: [WireMessage] = []
        for index in 0..<40 {
            let filler = String(repeating: "x", count: 20_000)
            messages.append(message(index % 2 == 0 ? .user : .assistant, filler + " #\(index)"))
        }

        let result = ContextWindow.fit(messages, systemPrompt: "system", modelID: "claude-haiku-5-5")
        XCTAssertLessThan(result.kept.count, messages.count)
        XCTAssertGreaterThan(result.trimmed, 0)

        // The newest message is always kept.
        XCTAssertEqual(result.kept.last?.content, messages.last?.content)
        // And the oldest kept message is not the first one.
        XCTAssertNotEqual(result.kept.first?.content, messages.first?.content)
    }

    func testNeverTrimsBelowTheMinimumKeptMessages() {
        var messages: [WireMessage] = []
        for _ in 0..<6 {
            messages.append(message(.user, String(repeating: "y", count: 20_000)))
        }
        let result = ContextWindow.fit(messages, systemPrompt: nil, modelID: "claude-haiku-5-5")
        XCTAssertGreaterThanOrEqual(result.kept.count, ContextWindow.minimumKeptMessages)
    }

    func testEstimatesUseFourCharactersPerToken() {
        XCTAssertEqual(ModelInfo.estimateTokens(in: String(repeating: "a", count: 400)), 100)
        XCTAssertEqual(ModelInfo.estimateTokens(in: ""), 0)
    }

    func testContextLimitsComeFromThePublishedFigures() {
        XCTAssertEqual(ModelCatalog.contextLimit(for: "grok-4.7"), 200_000)
        XCTAssertEqual(ModelCatalog.contextLimit(for: "claude-haiku-5-5"), 100_000)
        XCTAssertEqual(ModelCatalog.contextLimit(for: "not-a-model"), ModelCatalog.defaultContextLimit)
    }

    func testSystemPromptCountsTowardTheBudget() {
        let messages = [message(.user, "Hello"), message(.assistant, "Hi")]
        let without = ContextWindow.fit(messages, systemPrompt: nil, modelID: "kimi-k3")
        let with = ContextWindow.fit(messages, systemPrompt: String(repeating: "s", count: 800), modelID: "kimi-k3")
        XCTAssertGreaterThan(with.estimatedTokens, without.estimatedTokens)
        XCTAssertEqual(with.kept.count, without.kept.count)
    }
}

@MainActor
final class AllowanceTests: XCTestCase {
    private func answer(modelID: String, cost: Double, at date: Date) -> Message {
        let message = Message(role: .assistant, content: "Answer", createdAt: date)
        message.modelIDUsed = modelID
        message.costUSD = cost
        return message
    }

    private var startOfThisMonth: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
    }

    func testWindowsSplitByAge() {
        let now = Date.now
        let messages = [
            answer(modelID: "kimi-k3", cost: 0.10, at: now.addingTimeInterval(-600)),   // rolling, week, month
            answer(modelID: "kimi-k3", cost: 0.20, at: now.addingTimeInterval(-48 * 3600)), // week, month
            answer(modelID: "kimi-k3", cost: 0.40, at: startOfThisMonth.addingTimeInterval(3600)) // month only
        ]

        let allowance = try? XCTUnwrap(AllowanceTracker.allowances(from: messages).first)
        XCTAssertEqual(allowance?.modelID, "kimi-k3")
        XCTAssertEqual(allowance?.rolling5h ?? 0, 0.10, accuracy: 0.0001)
        XCTAssertEqual(allowance?.weekly ?? 0, 0.30, accuracy: 0.0001)
        XCTAssertEqual(allowance?.monthly ?? 0, 0.70, accuracy: 0.0001)
    }

    func testLastMonthsUsageDoesNotCountTowardThisMonth() {
        let lastMonth = startOfThisMonth.addingTimeInterval(-24 * 3600)
        let message = answer(modelID: "kimi-k3", cost: 0.50, at: lastMonth)

        let allowance = try? XCTUnwrap(AllowanceTracker.allowances(from: [message]).first)
        XCTAssertEqual(allowance?.monthly ?? 0, 0, accuracy: 0.0001)
        XCTAssertEqual(allowance?.weekly ?? 0, 0, accuracy: 0.0001)
    }

    func testPercentagesUseTwentyPercentForTheRollingWindow() {
        let now = Date.now
        // Kimi K3 has a $15 monthly limit: 5h window is $3, week is $7.50.
        let message = answer(modelID: "kimi-k3", cost: 1.50, at: now)
        let allowance = try? XCTUnwrap(AllowanceTracker.allowances(from: [message]).first)

        XCTAssertEqual(allowance?.rollingPercent ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(allowance?.weeklyPercent ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(allowance?.monthlyPercent ?? 0, 10, accuracy: 0.01)
    }

    func testOverrunIsClampedForDisplay() {
        let now = Date.now
        // Spend the whole month in one go: the 5h window is overrun five times over.
        let message = answer(modelID: "kimi-k3", cost: 15, at: now)
        let allowance = try? XCTUnwrap(AllowanceTracker.allowances(from: [message]).first)

        XCTAssertEqual(allowance?.rollingPercent, 100)
        XCTAssertEqual(allowance?.weeklyPercent, 100)
        XCTAssertEqual(allowance?.monthlyPercent, 100)
    }

    func testMessagesWithoutACostAreIgnored() {
        let message = Message(role: .assistant, content: "No usage recorded")
        message.modelIDUsed = "kimi-k3"
        XCTAssertEqual(AllowanceTracker.allowances(from: [message]).count, 0)
    }

    func testUserMessagesAreNotCounted() {
        let message = Message(role: .user, content: "Question")
        message.modelIDUsed = "kimi-k3"
        message.costUSD = 1
        XCTAssertEqual(AllowanceTracker.allowances(from: [message]).count, 0)
    }

    func testUnknownModelsGetNoLimit() {
        let message = answer(modelID: "not-a-model", cost: 1, at: .now)
        let allowance = try? XCTUnwrap(AllowanceTracker.allowances(from: [message]).first)
        XCTAssertEqual(allowance?.monthlyLimit, 0)
        XCTAssertTrue(allowance?.isUnlimited ?? false)
    }

    func testPublishedLimitsMatchThePriceList() {
        XCTAssertEqual(ModelPrices.monthlyLimits["kimi-k3"], 15)
        XCTAssertEqual(ModelPrices.monthlyLimits["deepseek-v4.1-flash"], 80)
        XCTAssertEqual(ModelPrices.monthlyLimits["beam-free"], 0)
    }
}
