import Foundation
import SwiftUI

/// App-wide state: does an API key exist, is the app locked, which theme to use.
///
/// Everything the UI needs to react to is stored here (not read straight from
/// `Preferences`), so SwiftUI's observation actually fires when a value changes.
@MainActor
@Observable
final class AppState {
    private(set) var hasAPIKey: Bool = false
    private(set) var isLocked: Bool = false
    private(set) var hasCompletedOnboarding: Bool = false
    private(set) var defaultModelID: String = ""
    private(set) var theme: ThemeMode = .system
    private(set) var biometricEnabled: Bool = false
    /// Model ids the account may actually use. Empty means "not known yet".
    private(set) var enabledModelIDs: Set<String> = []
    /// True once the model list has been fetched at least once.
    private(set) var hasModelList = false
    private(set) var modelListError: String?
    private(set) var isLoadingModels = false
    /// When the model list was last refreshed.
    private(set) var modelListUpdatedAt: Date?
    /// Models the gateway has refused in practice, even when the list says otherwise.
    private(set) var refusedModelIDs: Set<String> = []
    /// What the gateway said when it refused each model, keyed by model id.
    private(set) var refusedReasons: [String: String] = [:]

    let biometrics = BiometricService()

    init(previewHasKey: Bool? = nil) {
        if UITestSupport.isUITesting {
            Preferences.resetAll()
            KeychainService.delete()
        }
        // Everything stored is loaded either way, so a preview sees the same
        // preferences the real app does.
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding
        defaultModelID = Preferences.defaultModelID
        theme = Preferences.theme
        biometricEnabled = Preferences.biometricEnabled
        enabledModelIDs = Set(Preferences.enabledModelIDs)
        hasModelList = !enabledModelIDs.isEmpty
        modelListUpdatedAt = Preferences.modelListUpdatedAt
        refusedModelIDs = Set(Preferences.refusedModelIDs)
        refusedReasons = Preferences.refusedReasons

        if let previewHasKey {
            hasAPIKey = previewHasKey
            isLocked = false
        } else {
            hasAPIKey = !(KeychainService.read()?.isEmpty ?? true)
            isLocked = biometricEnabled && hasAPIKey
        }
    }

    func refresh() {
        hasCompletedOnboarding = Preferences.hasCompletedOnboarding
        defaultModelID = Preferences.defaultModelID
        theme = Preferences.theme
        biometricEnabled = Preferences.biometricEnabled
        hasAPIKey = !(KeychainService.read()?.isEmpty ?? true)
        isLocked = biometricEnabled && hasAPIKey
        enabledModelIDs = Set(Preferences.enabledModelIDs)
        hasModelList = !enabledModelIDs.isEmpty
        modelListUpdatedAt = Preferences.modelListUpdatedAt
        refusedModelIDs = Set(Preferences.refusedModelIDs)
        refusedReasons = Preferences.refusedReasons
    }

    /// Asks the gateway which models this account may use.
    ///
    /// The list depends on the account: models can be switched off by the workspace
    /// or blocked by the account's privacy settings, and those requests fail.
    func refreshModels() async {
        guard let key = KeychainService.read(), !key.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await OpenCodeService().fetchModels(apiKey: key)
            setEnabledModels(models)
            modelListError = nil
        } catch {
            modelListError = error.localizedDescription
        }
    }

    /// Stores the account's model list.
    func setEnabledModels(_ models: [String]) {
        enabledModelIDs = Set(models)
        hasModelList = true
        modelListError = nil
        modelListUpdatedAt = .now
        Preferences.enabledModelIDs = models
        Preferences.modelListUpdatedAt = .now
    }

    /// True when the account is known to allow this model.
    func isModelEnabled(_ modelID: String) -> Bool {
        if refusedModelIDs.contains(modelID) { return false }
        guard hasModelList, !enabledModelIDs.isEmpty else { return true }
        return enabledModelIDs.contains(modelID)
    }

    /// Remembers that the gateway refused this model, and what it said about it.
    func markRefused(_ modelID: String, reason: String? = nil) {
        var refused = Preferences.refusedModelIDs
        if !refused.contains(modelID) {
            refused.append(modelID)
            Preferences.refusedModelIDs = refused
            refusedModelIDs = Set(refused)
        }
        if let reason, !reason.isEmpty {
            var reasons = Preferences.refusedReasons
            reasons[modelID] = reason
            Preferences.refusedReasons = reasons
            refusedReasons = reasons
        }
    }

    /// The gateway's own words for why this model was refused.
    func refusedReason(for modelID: String) -> String? {
        refusedReasons[modelID]
    }

    /// Why a model cannot be used on this account, for the picker to explain.
    ///
    /// Best available answer wins: the server's own reason, then what the model's
    /// billing or tier usually means, then the plain fact.
    func unavailableReason(for modelID: String) -> String? {
        if let learned = refusedReasons[modelID], !learned.isEmpty {
            return "OpenCode refused it: \(learned)"
        }
        guard let model = ModelCatalog.model(withID: modelID) else {
            return "Switched off for your OpenCode account."
        }
        switch model.service {
        case .retired:
            return "Removed from the OpenCode lineup in October 2026. Neither Go nor the pay-as-you-go console offers it any more."
        case .zen:
            return "Not in the Go subscription: its requests bill the pay-as-you-go balance instead. Turning on Extra Usage in the console lets Go fall back to that balance when limits run out."
        case .go:
            break
        }
        if model.family == .systemOne {
            return "Jev answers typed questions, not chats. Try it from Settings → Jev trials."
        }
        if model.id.contains("free") {
            return "Free models may train on request data, so they need free endpoints allowed in the workspace's Privacy settings."
        }
        if model.privacyNote != nil {
            return "Contributor tier: the workspace has to allow data sharing for this model to answer."
        }
        return "Switched off for your OpenCode account."
    }

    /// Forgets the locally learned refusals, for when the account settings change.
    func forgetRefusals() {
        Preferences.refusedModelIDs = []
        Preferences.refusedReasons = [:]
        refusedModelIDs = []
        refusedReasons = [:]
    }

    /// Today's automatic pick, restricted to models this account may use.
    func autoModel(for date: Date = .now) -> ModelInfo? {
        let pool = ModelCatalog.autoPool.compactMap { id -> ModelInfo? in
            guard let model = ModelCatalog.model(withID: id) else { return nil }
            return isModelEnabled(id) ? model : nil
        }
        guard !pool.isEmpty else {
            return ModelCatalog.autoModel(for: date)
        }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[abs(day) % pool.count]
    }

    /// The curated catalogue filtered down to the models this account may use.
    ///
    /// Models the account has that the catalogue does not describe yet are kept and
    /// shown with a plain entry: they still work, they just have no write-up.
    var availableModels: [ModelInfo] {
        guard hasModelList, !enabledModelIDs.isEmpty else { return ModelCatalog.all }
        var result = ModelCatalog.all.filter { enabledModelIDs.contains($0.id) }
        let known = Set(ModelCatalog.all.map(\.id))
        for id in enabledModelIDs.subtracting(known).sorted() {
            result.append(ModelInfo(
                id: id,
                displayName: id,
                family: .openAIChat,
                summary: "Not described yet. The app works out which endpoint it needs.",
                bestFor: []
            ))
        }
        return result
    }

    /// Called when the onboarding flow finishes.
    func completeOnboarding(modelID: String) {
        Preferences.defaultModelID = modelID
        Preferences.hasCompletedOnboarding = true
        defaultModelID = modelID
        hasCompletedOnboarding = true
    }

    func setDefaultModel(_ id: String) {
        Preferences.defaultModelID = id
        defaultModelID = id
    }

    func setTheme(_ mode: ThemeMode) {
        Preferences.theme = mode
        theme = mode
    }

    func setBiometricEnabled(_ enabled: Bool) {
        Preferences.biometricEnabled = enabled
        biometricEnabled = enabled
        if !enabled { isLocked = false }
    }

    func unlock() async {
        guard biometricEnabled else {
            isLocked = false
            return
        }
        guard case .available = biometrics.availability else {
            // Nothing to authenticate with – do not trap the user in the lock screen.
            isLocked = false
            return
        }
        let ok = await biometrics.authenticate(reason: "Unlock your conversations")
        if ok { isLocked = false }
    }

    func lock() {
        guard biometricEnabled else { return }
        isLocked = true
    }
}
