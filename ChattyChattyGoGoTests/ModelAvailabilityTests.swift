import XCTest
@testable import ChattyChattyGoGo

/// What the app knows about which models the account may use.
@MainActor
final class ModelAvailabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Tests share the device's defaults, so each one starts from a clean slate.
        // setUp runs on the main thread, so isolation is assumed here safely.
        MainActor.assumeIsolated { Preferences.resetAll() }
    }

    func testWithoutAListEveryModelIsAllowed() {
        let state = AppState(previewHasKey: true)
        XCTAssertTrue(state.isModelEnabled("kimi-k3"))
        XCTAssertTrue(state.isModelEnabled("anything-else"))
        XCTAssertTrue(state.availableModels.contains { $0.id == "kimi-k3" })
    }

    func testDisabledModelsAreFilteredAndUnknownOnesAreKept() {
        let state = AppState(previewHasKey: true)
        state.setEnabledModels(["kimi-k3", "brand-new-model"])

        // The curated models the account does not have are gone.
        XCTAssertFalse(state.availableModels.contains { $0.id == "claude-haiku-5-5" })
        XCTAssertTrue(state.availableModels.contains { $0.id == "kimi-k3" })

        // A model the catalogue does not describe is still offered.
        let unknown = state.availableModels.first { $0.id == "brand-new-model" }
        XCTAssertNotNil(unknown)
        XCTAssertEqual(unknown?.displayName, "brand-new-model")
        XCTAssertFalse(unknown?.summary.isEmpty ?? true)
    }

    func testIsModelEnabledConsultsTheAccountList() {
        let state = AppState(previewHasKey: true)
        state.setEnabledModels(["kimi-k3"])
        XCTAssertTrue(state.isModelEnabled("kimi-k3"))
        XCTAssertFalse(state.isModelEnabled("beam-free"))
    }

    func testARefusedModelIsRemembered() {
        let state = AppState(previewHasKey: true)
        state.setEnabledModels(["kimi-k3", "beam-free"])

        XCTAssertTrue(state.isModelEnabled("beam-free"))
        state.markRefused("beam-free")
        XCTAssertFalse(state.isModelEnabled("beam-free"))

        // Other models are unaffected.
        XCTAssertTrue(state.isModelEnabled("kimi-k3"))

        // And the memory can be cleared.
        state.forgetRefusals()
        XCTAssertTrue(state.isModelEnabled("beam-free"))
    }

    func testARefusalRemembersWhyTheGatewaySaidNo() {
        let state = AppState(previewHasKey: true)
        state.markRefused(
            "nemotron-3-ultra-free",
            reason: "Free models may train on request data. Allow free endpoints in your workspace's Privacy settings to use them."
        )

        XCTAssertTrue(
            state.refusedReason(for: "nemotron-3-ultra-free")?
                .contains("Privacy settings") ?? false
        )

        // The reason survives a fresh app state, like the refusal itself.
        let second = AppState(previewHasKey: true)
        XCTAssertTrue(
            second.refusedReason(for: "nemotron-3-ultra-free")?
                .contains("Privacy settings") ?? false
        )

        state.forgetRefusals()
        XCTAssertNil(state.refusedReason(for: "nemotron-3-ultra-free"))
    }

    func testUnavailableReasonExplainsEachTier() {
        let state = AppState(previewHasKey: true)

        // A free model gets the privacy explanation.
        let free = state.unavailableReason(for: "beam-free")
        XCTAssertTrue(free?.contains("Privacy settings") ?? false)

        // A contributor model gets the data-sharing explanation.
        let contributor = state.unavailableReason(for: "muse-spark-1.3-contributor")
        XCTAssertTrue(contributor?.contains("data sharing") ?? false)

        // A model that moved to the pay-as-you-go console says so.
        let zen = state.unavailableReason(for: "nemotron-3-ultra-free")
        XCTAssertTrue(zen?.contains("pay-as-you-go") ?? false)

        // A model dropped from both line-ups is dated instead.
        let retired = state.unavailableReason(for: "gemini-4-argon-contributor")
        XCTAssertTrue(retired?.contains("Removed from the OpenCode lineup") ?? false)

        // Anything else is plain about it.
        XCTAssertEqual(
            state.unavailableReason(for: "claude-haiku-5-5"),
            "Switched off for your OpenCode account."
        )

        // A refused model shows the gateway's own words first.
        state.markRefused("claude-haiku-5-5", reason: "region blocked")
        XCTAssertTrue(state.unavailableReason(for: "claude-haiku-5-5")?.contains("region blocked") ?? false)
        state.forgetRefusals()
    }

    func testRefusingWithoutAReasonStillBlocksTheModel() {
        let state = AppState(previewHasKey: true)
        state.markRefused("kimi-k3")
        XCTAssertFalse(state.isModelEnabled("kimi-k3"))
        XCTAssertNil(state.refusedReason(for: "kimi-k3"))
        XCTAssertEqual(
            state.unavailableReason(for: "kimi-k3"),
            "Switched off for your OpenCode account."
        )
    }

    func testMarkingARefusalPersistsIt() {
        let first = AppState(previewHasKey: true)
        first.setEnabledModels(["kimi-k3"])
        first.markRefused("kimi-k3")

        // A fresh app state reads the same refusal from storage.
        let second = AppState(previewHasKey: true)
        second.setEnabledModels(["kimi-k3"])
        XCTAssertFalse(second.isModelEnabled("kimi-k3"))
        second.forgetRefusals()
        XCTAssertTrue(second.isModelEnabled("kimi-k3"))
    }

    func testTheAutomaticPickOnlyUsesEnabledModels() {
        let state = AppState(previewHasKey: true)
        // Leave only two of the auto pool enabled.
        state.setEnabledModels(["kimi-k3", "glm-5.3"])

        // Whichever day it is, the pick must come from the enabled half of the pool.
        let allowed: Set<String> = ["kimi-k3", "glm-5.3"]
        for dayOffset in 0..<10 {
            let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now)!
            let pick = state.autoModel(for: date)
            XCTAssertTrue(allowed.contains(pick?.id ?? ""), "day \(dayOffset) picked \(pick?.id ?? "nothing")")
        }
    }

    func testTheAutomaticPickFallsBackWhenThePoolIsEmpty() {
        let state = AppState(previewHasKey: true)
        state.setEnabledModels(["beam-free"]) // not in the auto pool
        XCTAssertNotNil(state.autoModel())
    }

    func testGatewayErrorShapesThatMeanUnavailable() {
        XCTAssertTrue(APIError(status: 400, body: "{\"error\":{\"message\":\"model beam-free is not available for your account\"}}").suggestsModelUnavailable)
        XCTAssertTrue(APIError(status: 403, body: "{\"error\":{\"message\":\"this model is disabled by your data sharing settings\"}}").suggestsModelUnavailable)
        XCTAssertTrue(APIError(status: 403, body: "model not available in your region").suggestsModelUnavailable)

        // A 404 is a wrong endpoint family, not a missing model.
        XCTAssertFalse(APIError(status: 404, body: "model not found").suggestsModelUnavailable)
        // And an unrelated 400 is neither.
        XCTAssertFalse(APIError(status: 400, body: "invalid request body").suggestsModelUnavailable)
    }
}
