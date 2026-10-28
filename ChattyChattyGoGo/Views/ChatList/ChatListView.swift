import SwiftData
import SwiftUI

struct ChatListView: View {
    /// Drives the split-view detail column. `nil` means "push a chat onto the stack".
    var selection: Binding<Conversation?>? = nil
    /// Navigation path of the enclosing stack, used to push a freshly created chat.
    var path: Binding<NavigationPath>? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var viewModel = ChatListViewModel()
    @State private var showingSettings = false
    @State private var showingJevTrials = false
    @State private var renameTarget: Conversation?
    @State private var renameText: String = ""

    /// Compact width pushes a chat onto the stack, regular width fills the detail column.
    private var usesPushNavigation: Bool {
        selection == nil
    }

    var body: some View {
        List(selection: selection) {
            if !appState.hasAPIKey {
                Section {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Add your OpenCode Go key", systemImage: "key.fill")
                    }
                } footer: {
                    Text("A key is needed before you can ask anything. It is stored in the iOS keychain.")
                }
            }

            if isSearchingResults {
                searchResults
            } else {
                conversationSections
            }
        }
        .navigationTitle("Chats")
        .navigationDestination(for: Conversation.self) { conversation in
            ChatView(conversation: conversation)
        }
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search every chat")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingJevTrials = true
                } label: {
                    Label("Jev trials", systemImage: "questionmark.diamond")
                }

                Button {
                    newChat()
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationDestination(isPresented: $showingJevTrials) {
            JevTrialsListView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Rename chat", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    target.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    target.titleIsAutomatic = false
                    target.updatedAt = .now
                    save()
                }
                renameTarget = nil
            }
        }
        .task(id: viewModel.searchText) {
            viewModel.search(query: viewModel.searchText, in: modelContext)
        }
    }

    private var isSearchingResults: Bool {
        viewModel.searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    // MARK: - Sections

    @ViewBuilder
    private var conversationSections: some View {
        if conversations.isEmpty {
            ContentUnavailableView(
                "No chats yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Start a conversation and it will be saved on this device.")
            )
        } else {
            ForEach(viewModel.sections(for: conversations)) { section in
                Section(section.group.title) {
                    ForEach(section.conversations) { conversation in
                        row(for: conversation)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    renameText = conversation.displayTitle
                                    renameTarget = conversation
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    delete(conversation)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.searchResults.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Section("Results") {
                ForEach(viewModel.searchResults) { result in
                    row(for: result.conversation, subtitle: result.snippet)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(result.conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for conversation: Conversation, subtitle: String? = nil) -> some View {
        let content = ChatRowView(conversation: conversation, subtitle: subtitle)
        if usesPushNavigation {
            NavigationLink(value: conversation) { content }
        } else {
            content.tag(conversation)
        }
    }

    // MARK: - Actions

    private func newChat() {
        let conversation = Conversation(modelID: "")
        modelContext.insert(conversation)
        save()
        if usesPushNavigation {
            path?.wrappedValue.append(conversation)
        } else {
            selection?.wrappedValue = conversation
        }
    }

    private func delete(_ conversation: Conversation) {
        modelContext.delete(conversation)
        if selection?.wrappedValue?.id == conversation.id {
            selection?.wrappedValue = nil
        }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Could not save: \(error)")
        }
    }
}

// MARK: - Previews

#Preview("Chat list", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        NavigationStack {
            ChatListView(selection: nil)
        }
        .environment(AppState(previewHasKey: true))
    }
}

#Preview("Chat list — no key", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        NavigationStack {
            ChatListView(selection: nil)
        }
        .environment(AppState(previewHasKey: false))
    }
}
