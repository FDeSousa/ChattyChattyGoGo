import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Regular width (iPad, landscape on large devices) shows a sidebar.
    @State private var selection: Conversation?
    /// Compact width pushes chats onto a navigation stack.
    @State private var path = NavigationPath()

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack(path: $path) {
                ChatListView(selection: nil, path: $path)
            }
        } else {
            NavigationSplitView {
                ChatListView(selection: $selection)
            } detail: {
                if let selection {
                    ChatView(conversation: selection)
                        .id(selection.id)
                } else {
                    EmptyStateView()
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }
}

// MARK: - Previews

#Preview("Content", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        ContentView()
            .environment(AppState(previewHasKey: true))
    }
}
