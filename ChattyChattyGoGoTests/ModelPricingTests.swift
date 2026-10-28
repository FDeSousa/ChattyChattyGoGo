import XCTest
@testable import ChattyChattyGoGo

final class ModelPricingTests: XCTestCase {
    func testCostUsesTheCachedRateForCachedInput() {
        let pricing = ModelPricing(input: 3.00, output: 15.00, cachedRead: 0.30, cachedWrite: nil)
        let usage = TokenUsage(inputTokens: 1_000, outputTokens: 300, cachedInputTokens: 700)
        // 300 fresh input at $3/1M, 700 cached at $0.30/1M, 300 output at $15/1M.
        let expected = 300.0 / 1_000_000 * 3.00
            + 700.0 / 1_000_000 * 0.30
            + 300.0 / 1_000_000 * 15.00
        XCTAssertEqual(pricing.cost(for: usage), expected, accuracy: 0.0000001)
    }

    func testFreeModelsCostNothing() {
        let usage = TokenUsage(inputTokens: 10_000, outputTokens: 5_000, cachedInputTokens: 0)
        XCTAssertEqual(ModelPricing.free.cost(for: usage), 0)
    }

    func testPublishedPricesArePresentForTheMainModels() {
        XCTAssertNotNil(ModelPrices.pricing(for: "kimi-k3"))
        XCTAssertNotNil(ModelPrices.pricing(for: "claude-haiku-5-5"))
        XCTAssertNotNil(ModelPrices.pricing(for: "grok-4.7"))
        XCTAssertNotNil(ModelPrices.pricing(for: "gemini-4-argon-contributor"))
    }

    func testTypicalRequestCostsArePlausible() {
        let kimi = try? XCTUnwrap(ModelPrices.typicalCost(for: "kimi-k3"))
        XCTAssertNotNil(kimi)
        XCTAssertGreaterThan(kimi ?? 0, 0)
        XCTAssertLessThan(kimi ?? 999, 1)

        // A free model is free.
        XCTAssertEqual(ModelPrices.typicalCost(for: "beam-free") ?? 0, 0)
    }

    func testUnknownModelHasNoPrice() {
        XCTAssertNil(ModelPrices.pricing(for: "not-a-model"))
    }

    func testUsageMergingKeepsTheLargestCounts() {
        let first = TokenUsage(inputTokens: 800, outputTokens: 0, cachedInputTokens: 600)
        let second = TokenUsage(inputTokens: 0, outputTokens: 120, cachedInputTokens: 0)
        let merged = first.merged(with: second)
        XCTAssertEqual(merged.inputTokens, 800)
        XCTAssertEqual(merged.outputTokens, 120)
        XCTAssertEqual(merged.cachedInputTokens, 600)
    }
}
