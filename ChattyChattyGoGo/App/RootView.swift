import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else if appState.isLocked {
                LockView()
            } else {
                ContentView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isLocked)
        .task {
            appState.refresh()
            await appState.refreshModels()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appState.lock()
            } else if phase == .active {
                appState.refresh()
            }
        }
    }
}
