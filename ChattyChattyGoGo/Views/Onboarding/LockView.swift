import SwiftUI

/// Shown when the app is locked with Face ID.
struct LockView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("ChattyChatty GoGo is locked")
                    .font(.title3.bold())
                Text("Your conversations are hidden until you unlock the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await appState.unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
        }
        .padding()
        .task {
            await appState.unlock()
        }
    }
}

// MARK: - Previews

#Preview("Locked", traits: .fixedLayout(width: 440, height: 956)) {
    LockView()
        .environment(AppState(previewHasKey: true))
}
