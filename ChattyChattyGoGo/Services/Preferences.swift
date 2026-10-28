import Foundation
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Small, non-secret app settings. The API key is *not* stored here.
@MainActor
enum Preferences {
    private enum Key {
        static let defaultModelID = "defaultModelID"
        static let defaultReasoning = "defaultReasoning"
        static let systemPrompt = "systemPrompt"
        static let theme = "theme"
        static let biometricEnabled = "biometricEnabled"
        static let completedOnboarding = "completedOnboarding"
        static let familyOverrides = "familyOverrides"
        static let temperature = "temperature"
        static let enabledModelIDs = "enabledModelIDs"
        static let refusedModelIDs = "refusedModelIDs"
        static let refusedReasons = "refusedReasons"
        static let modelListUpdatedAt = "modelListUpdatedAt"
    }

    private static let defaults = UserDefaults.standard

    static var defaultModelID: String {
        get { defaults.string(forKey: Key.defaultModelID) ?? "" }
        set { defaults.set(newValue, forKey: Key.defaultModelID) }
    }

    static var defaultReasoning: ReasoningLevel {
        get {
            guard let raw = defaults.string(forKey: Key.defaultReasoning),
                  let level = ReasoningLevel(rawValue: raw) else { return .off }
            return level
        }
        set { defaults.set(newValue.rawValue, forKey: Key.defaultReasoning) }
    }

    static var systemPrompt: String {
        get { defaults.string(forKey: Key.systemPrompt) ?? "" }
        set { defaults.set(newValue, forKey: Key.systemPrompt) }
    }

    static var temperature: Double? {
        get {
            guard defaults.object(forKey: Key.temperature) != nil else { return nil }
            return defaults.double(forKey: Key.temperature)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.temperature)
            } else {
                defaults.removeObject(forKey: Key.temperature)
            }
        }
    }

    static var theme: ThemeMode {
        get {
            guard let raw = defaults.string(forKey: Key.theme), let mode = ThemeMode(rawValue: raw) else { return .system }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    static var biometricEnabled: Bool {
        get { defaults.bool(forKey: Key.biometricEnabled) }
        set { defaults.set(newValue, forKey: Key.biometricEnabled) }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.completedOnboarding) }
        set { defaults.set(newValue, forKey: Key.completedOnboarding) }
    }

    /// The model ids the account is allowed to use, as reported by the gateway.
    static var enabledModelIDs: [String] {
        get { defaults.stringArray(forKey: Key.enabledModelIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.enabledModelIDs) }
    }

    /// When the model list was last fetched.
    static var modelListUpdatedAt: Date? {
        get { defaults.object(forKey: Key.modelListUpdatedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.modelListUpdatedAt) }
    }

    /// Models the gateway has actually refused, learned the hard way.
    static var refusedModelIDs: [String] {
        get { defaults.stringArray(forKey: Key.refusedModelIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.refusedModelIDs) }
    }

    /// What the gateway said when it refused each model, keyed by model id.
    static var refusedReasons: [String: String] {
        get { (defaults.dictionary(forKey: Key.refusedReasons) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.refusedReasons) }
    }

    /// Manual API-family overrides, used when the gateway serves a model through an
    /// endpoint our catalogue does not know about.
    static var familyOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.familyOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.familyOverrides) }
    }

    /// Wipes every stored preference. Used when the app is launched by a UI test.
    static func resetAll() {
        for key in [
            Key.defaultModelID,
            Key.defaultReasoning,
            Key.systemPrompt,
            Key.theme,
            Key.biometricEnabled,
            Key.completedOnboarding,
            Key.familyOverrides,
            Key.temperature,
            Key.enabledModelIDs,
            Key.modelListUpdatedAt,
            Key.refusedModelIDs,
            Key.refusedReasons
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
