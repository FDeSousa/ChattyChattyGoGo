import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("ChattyChatty GoGo", systemImage: "bubble.left.and.bubble.right.fill")
        } description: {
            Text("Pick a conversation on the left, or start a new one. Everything stays on this device.")
        }
    }
}

// MARK: - Previews

#Preview("Empty state", traits: .fixedLayout(width: 440, height: 500)) {
    EmptyStateView()
}
