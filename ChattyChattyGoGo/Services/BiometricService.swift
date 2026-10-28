import Foundation
import LocalAuthentication

/// Face ID / Touch ID gate that keeps conversations private when the app is opened.
@MainActor
@Observable
final class BiometricService {
    enum Availability {
        case available(name: String)
        case unavailable(reason: String)
    }

    private(set) var availability: Availability = .unavailable(reason: "Checking…")

    init() {
        refresh()
    }

    func refresh() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if canEvaluate {
            switch context.biometryType {
            case .faceID:
                availability = .available(name: "Face ID")
            case .touchID:
                availability = .available(name: "Touch ID")
            case .opticID:
                availability = .available(name: "Optic ID")
            default:
                availability = .unavailable(reason: "No biometric authentication is enrolled on this device.")
            }
        } else {
            availability = .unavailable(reason: error?.localizedDescription ?? "Biometrics are not available.")
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            // Fall back to the device passcode so the user is never locked out.
            do {
                return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } catch {
                return false
            }
        }
    }
}
