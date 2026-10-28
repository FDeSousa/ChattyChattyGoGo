import SwiftData
import SwiftUI

@main
struct ChattyChattyGoGoApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .modelContainer(Persistence.makeContainer())
    }
}
