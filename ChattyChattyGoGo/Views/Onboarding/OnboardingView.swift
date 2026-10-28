import SwiftUI

/// First-run flow: welcome, key, model.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var step: Step = .welcome
    @State private var key: String = ""
    @State private var keyState: KeyState = .idle
    @State private var selectedModel: String = ModelCatalog.autoModelID
    @State private var modelCount: Int?

    private enum Step: Int {
        case welcome
        case key
        case model
    }

    private enum KeyState: Equatable {
        case idle
        case working
        case saved
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .welcome:
                    welcomeStep
                case .key:
                    keyStep
                case .model:
                    modelStep
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step != .welcome {
                        Button("Skip") {
                            skip()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Color.accentColor)
                    Text("ChattyChatty GoGo")
                        .font(.largeTitle.bold())
                    Text("A private assistant that uses your own OpenCode Go subscription. No third-party servers, no account, no tracking.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    bullet(
                        icon: "iphone",
                        title: "On-device history",
                        detail: "Every conversation is stored locally and can be searched at any time."
                    )
                    bullet(
                        icon: "key.fill",
                        title: "Your key stays in the keychain",
                        detail: "It is only sent to opencode.ai when you ask a question."
                    )
                    bullet(
                        icon: "lock.shield",
                        title: "Face ID lock",
                        detail: "Lock the app so nobody else can read your chats."
                    )
                    bullet(
                        icon: "cpu",
                        title: "Every Go model",
                        detail: "Pick from the full model lineup, with notes on what each one is good at."
                    )
                }

                Button {
                    step = .key
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private func bullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - API key

    private var keyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your OpenCode Go key")
                        .font(.title2.bold())
                    Text("Copy it from the OpenCode console, then paste it here. It is saved in the iOS keychain.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SecureField("sk-…", text: $key)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(Color.chatSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        if let clipboard = Clipboard.paste() {
                            key = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test", systemImage: "network")
                            if keyState == .working {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || keyState == .working)
                }

                switch keyState {
                case .saved:
                    Label("Key works. \(modelCount ?? 0) models available.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                case .idle, .working:
                    EmptyView()
                }

                Link("Open the OpenCode console", destination: URL(string: "https://opencode.ai/auth")!)
                    .font(.footnote)

                Spacer(minLength: 12)

                Button {
                    step = .model
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isKeyValid)
            }
            .padding(24)
        }
    }

    private var isKeyValid: Bool {
        if case .saved = keyState { return true }
        return false
    }

    private func testConnection() {
        keyState = .working
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try KeychainService.save(trimmed)
                let models = try await OpenCodeService().fetchModels(apiKey: trimmed)
                modelCount = models.count
                appState.setEnabledModels(models)
                keyState = .saved
                appState.refresh()
            } catch {
                keyState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Model

    /// The models offered here are the ones this account may actually use.
    private var pickableModels: [ModelInfo] {
        let available = appState.availableModels
        guard !available.isEmpty else { return Array(ModelCatalog.all.prefix(8)) }
        return Array(available.prefix(8))
    }

    private var modelStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick a model")
                        .font(.title2.bold())
                    Text("You can change this later, and every chat can use its own model.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(pickableModels) { model in
                        Button {
                            selectedModel = model.id
                            appState.setDefaultModel(model.id)
                        } label: {
                            ModelRow(model: model, isSelected: selectedModel == model.id)
                                .padding(12)
                                .background(
                                    selectedModel == model.id ? Color.accentColor.opacity(0.12) : Color.chatSecondaryBackground,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        selectedModel = ModelCatalog.autoModelID
                        appState.setDefaultModel(ModelCatalog.autoModelID)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto").font(.headline)
                                Text("Rotates through a set of strong models once a day, using only the ones your account may use.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedModel == ModelCatalog.autoModelID {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(12)
                        .background(
                            selectedModel == ModelCatalog.autoModelID ? Color.accentColor.opacity(0.12) : Color.chatSecondaryBackground,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    finish()
                } label: {
                    Text("Start chatting")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    /// Skipping the key step moves on to the model picker; skipping that one finishes.
    private func skip() {
        switch step {
        case .welcome:
            step = .key
        case .key:
            step = .model
        case .model:
            finish()
        }
    }

    private func finish() {
        let model = selectedModel.isEmpty ? ModelCatalog.autoModelID : selectedModel
        appState.completeOnboarding(modelID: model)
    }
}

// MARK: - Previews

#Preview("Onboarding", traits: .fixedLayout(width: 440, height: 956)) {
    OnboardingView()
        .environment(AppState(previewHasKey: true))
}
