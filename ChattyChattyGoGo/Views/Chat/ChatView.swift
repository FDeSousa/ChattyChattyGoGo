import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var viewModel = ChatViewModel()
    @State private var showingStats = false
    @State private var showingSettings = false
    @State private var editingMessageID: UUID?
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile = false
    @State private var attachmentError: String?
    @State private var showingModelPicker = false
    @State private var showingSystemPrompt = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var bottomOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var messages: [Message] {
        conversation.sortedMessages
    }

    /// Changes whenever the streamed answer grows, so the view can follow along.
    private var streamSignature: String {
        guard let last = messages.last else { return "empty" }
        return "\(last.id.uuidString)-\(last.content.count)-\(last.reasoning.count)-\(last.isFailed)"
    }

    private var isAtBottom: Bool {
        guard viewportHeight > 0 else { return true }
        return bottomOffset <= viewportHeight + 60
    }

    var body: some View {
        ScrollViewReader { proxy in
            messageList
                .coordinateSpace(name: "chatScroll")
            .scrollDismissesKeyboard(.interactively)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: ViewportHeightKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(BottomOffsetKey.self) { bottomOffset = $0 }
            .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
            .onChange(of: streamSignature) { _, _ in
                if viewModel.isStreaming || isAtBottom {
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onChange(of: messages.count) { _, _ in
                if viewModel.isStreaming || isAtBottom {
                    scrollToBottom(proxy, animated: true)
                }
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if viewModel.supportsReasoning {
                        Menu {
                            ForEach(ReasoningLevel.allCases) { level in
                                Button {
                                    viewModel.reasoningLevel = level
                                } label: {
                                    if viewModel.reasoningLevel == level {
                                        Label(level.title, systemImage: "checkmark")
                                    } else {
                                        Text(level.title)
                                    }
                                }
                            }
                        } label: {
                            Label("Thinking: \(viewModel.reasoningLevel.title)", systemImage: viewModel.reasoningLevel.symbol)
                        }
                    }

                    Button {
                        renameText = conversation.displayTitle
                        showingRenameAlert = true
                    } label: {
                        Label("Rename chat", systemImage: "pencil")
                    }

                    Button {
                        showingSystemPrompt = true
                    } label: {
                        Label("Chat instructions", systemImage: "text.bubble")
                    }

                    Divider()

                    Button(role: .destructive) {
                        modelContext.delete(conversation)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Delete chat", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingModelPicker = true
                    } label: {
                        Label("Model", systemImage: "cpu")
                    }
                    Button {
                        showingStats = true
                    } label: {
                        Label("Usage & cost", systemImage: "chart.bar")
                    }
                    Button {
                        showingSystemPrompt = true
                    } label: {
                        Label("Chat instructions", systemImage: "text.bubble")
                    }
                } label: {
                    Label(viewModel.model?.displayName ?? "Model", systemImage: "cpu")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if viewModel.modelUnavailable, let model = viewModel.model {
                    unavailableBanner(model)
                } else if viewModel.lastErrorWasAuthProblem {
                    authBar
                } else if let error = viewModel.errorBanner {
                    errorBar(error)
                }
                ComposerBar(
                    text: $viewModel.draft,
                    attachments: pendingAttachments,
                    isStreaming: viewModel.isStreaming,
                    onSend: {
                        viewModel.send(attachments: pendingAttachments)
                        pendingAttachments = []
                        attachmentError = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    },
                    onStop: {
                        viewModel.stop()
                    },
                    onRemoveAttachment: { attachment in
                        pendingAttachments.removeAll { $0.id == attachment.id }
                    },
                    onAttachPhoto: {
                        photoItem = nil
                    },
                    onAttachFile: {
                        isImportingFile = true
                    },
                    attachmentWarning: attachmentWarning
                )
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(
                selection: Binding(
                    get: { conversation.modelID },
                    set: { newValue in
                        conversation.modelID = newValue
                        viewModel.clearModelState()
                        try? modelContext.save()
                    }
                ),
                title: "Model for this chat"
            )
        }
        .sheet(isPresented: $showingSystemPrompt) {
            ChatInstructionsView(conversation: conversation)
        }
        .sheet(isPresented: $showingStats) {
            ChatStatsView(conversation: conversation)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .modifier(AttachmentPickers(
            photoItem: $photoItem,
            isImportingFile: $isImportingFile,
            onImage: { item in await addImage(from: item) },
            onDocument: { addDocument($0) },
            onError: { attachmentError = $0 }
        ))
        .alert("Rename chat", isPresented: $showingRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                conversation.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                conversation.titleIsAutomatic = false
                conversation.updatedAt = .now
                try? modelContext.save()
            }
        }
        .task {
            viewModel.configure(conversation: conversation, context: modelContext, appState: appState)
        }
    }

    // MARK: - Pieces

    /// The scrolling list of messages, split out to keep the type checker happy.
    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if messages.isEmpty {
                    starter
                }

                if viewModel.trimmedMessageCount > 0 {
                    Label(
                        "The oldest \(viewModel.trimmedMessageCount) messages are not being sent, to stay inside \(viewModel.model?.displayName ?? "the model")'s context window.",
                        systemImage: "scissors"
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                ForEach(messages) { message in
                    MessageBubble(
                        message: message,
                        modelName: ModelCatalog.model(withID: message.modelIDUsed)?.displayName ?? "",
                        isStreaming: viewModel.isStreaming && message.id == messages.last?.id,
                        onCopy: {
                            Clipboard.copy(message.content)
                        },
                        onRegenerate: message.role == .assistant && !viewModel.isStreaming ? { viewModel.regenerate() } : nil,
                        onDelete: {
                            viewModel.deleteMessage(message)
                        },
                        onEdit: editingMessageID == message.id ? { editingMessageID = nil } : (viewModel.isStreaming ? nil : { editingMessageID = message.id }),
                        onSendEdit: editingMessageID == message.id ? { text in
                            editingMessageID = nil
                            viewModel.edit(message, to: text)
                        } : nil
                    )
                    .id(message.id)
                }

                GeometryReader { geo in
                    Color.clear.preference(
                        key: BottomOffsetKey.self,
                        value: geo.frame(in: .named("chatScroll")).maxY
                    )
                }
                .frame(height: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask anything")
                    .font(.title2.bold())
                Text("This chat is answered by \(viewModel.model?.displayName ?? "your chosen model"). Nothing leaves the device except the conversation itself.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.starters, id: \.self) { starter in
                    Button {
                        viewModel.draft = starter
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkle")
                                .foregroundStyle(Color.accentColor)
                            Text(starter)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.chatSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
    }

    /// Shown when the key was rejected, with a shortcut to fix it.
    private var authBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your API key was rejected")
                    .font(.caption.weight(.semibold))
                Text("The key may have expired or been revoked. Check it in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    showingSettings = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private func unavailableBanner(_ model: ModelInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.displayName) is not enabled for your account")
                    .font(.caption.weight(.semibold))
                Text("Requests to it are rejected by OpenCode. Pick a model that is enabled for you.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Choose another model") {
                    showingModelPicker = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Attachments

    /// A warning to show above the composer, if there is anything worth saying.
    private var attachmentWarning: String? {
        if let attachmentError { return attachmentError }
        if pendingAttachments.contains(where: { $0.kind == .image }),
           let model = viewModel.model,
           !model.supportsImages {
            return "\(model.displayName) may not understand images. The text is still sent."
        }
        return nil
    }

    private func addImage(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                attachmentError = "That image could not be loaded."
                return
            }
            let prepared = try AttachmentBuilder.image(from: data, name: "Photo")
            pendingAttachments.append(PendingAttachment(
                kind: .image,
                name: "Photo.jpg",
                mimeType: prepared.mimeType,
                data: prepared.data,
                text: ""
            ))
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func addDocument(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let document = try AttachmentBuilder.document(from: url)
            pendingAttachments.append(PendingAttachment(
                kind: .document,
                name: url.lastPathComponent,
                mimeType: document.mimeType,
                data: nil,
                text: document.text
            ))
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private static let starters = [
        "Explain quantum computing like I am five",
        "Help me plan a weekend trip to Lisbon",
        "Write a Swift function that debounces a callback",
        "Compare the trade-offs of renting versus buying"
    ]
}

/// Photo and file pickers, kept in a modifier so the chat body stays simple.
private struct AttachmentPickers: ViewModifier {
    @Binding var photoItem: PhotosPickerItem?
    @Binding var isImportingFile: Bool
    var onImage: (PhotosPickerItem) async -> Void
    var onDocument: (URL) -> Void
    var onError: (String) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: Binding(
                    get: { photoItem != nil },
                    set: { if !$0 { photoItem = nil } }
                ),
                selection: $photoItem,
                matching: .images
            )
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await onImage(item) }
                photoItem = nil
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [
                    .pdf, .plainText, .text, .json, .sourceCode, .xml, .yaml, .data, .spreadsheet
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    onDocument(url)
                case .failure(let error):
                    onError(error.localizedDescription)
                }
            }
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Per-chat instructions that replace the global system prompt.
struct ChatInstructionsView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("These instructions replace your global ones for this chat only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .scrollContentBackground(.hidden)
            }
            .navigationTitle("Chat instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        conversation.systemPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        conversation.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear { text = conversation.systemPrompt }
        }
    }
}

// MARK: - Previews

/// A chat preview needs a store, because the conversation must be inserted into it.
@MainActor
private struct ChatScenePreview: View {
    private let container: ModelContainer
    private let conversation: Conversation

    init(empty: Bool = false) {
        let container = PreviewData.container()
        self.container = container
        let all = (try? container.mainContext.fetch(FetchDescriptor<Conversation>())) ?? []
        if empty {
            self.conversation = all.last ?? Conversation()
        } else {
            self.conversation = all.first ?? Conversation()
        }
    }

    var body: some View {
        NavigationStack {
            ChatView(conversation: conversation)
        }
        .environment(AppState(previewHasKey: true))
        .modelContainer(container)
    }
}

#Preview("Chat", traits: .fixedLayout(width: 440, height: 956)) {
    ChatScenePreview()
}

#Preview("Chat — empty", traits: .fixedLayout(width: 440, height: 956)) {
    ChatScenePreview(empty: true)
}

#Preview("Chat instructions", traits: .fixedLayout(width: 440, height: 700)) {
    ChatInstructionsPreview()
}

@MainActor
private struct ChatInstructionsPreview: View {
    private let container: ModelContainer
    private let conversation: Conversation

    init() {
        let container = PreviewData.container()
        self.container = container
        self.conversation = (try? container.mainContext.fetch(FetchDescriptor<Conversation>()))?.first ?? Conversation()
    }

    var body: some View {
        ChatInstructionsView(conversation: conversation)
            .environment(AppState(previewHasKey: true))
            .modelContainer(container)
    }
}
