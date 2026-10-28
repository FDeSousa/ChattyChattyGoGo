import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var showingAPIKey = false
    @State private var showingModelPicker = false
    @State private var showingInstructions = false
    @State private var showingUsage = false
    @State private var showingDeleteAll = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isImporting = false
    @State private var importSummary: ImportSummary?
    @State private var importError: String?
    @State private var pendingImport: Backup.Payload?
    @State private var pendingImportCount = 0

    struct ImportSummary: Identifiable {
        let chats: Int
        let messages: Int
        var id: String { "\(chats)-\(messages)" }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                modelSection
                assistantSection
                usageSection
                privacySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAPIKey) {
                APIKeyView()
            }
            .sheet(isPresented: $showingModelPicker) {
                ModelPickerView(
                    selection: Binding(
                        get: { appState.defaultModelID },
                        set: { appState.setDefaultModel($0) }
                    ),
                    title: "Default model"
                )
            }
            .sheet(isPresented: $showingInstructions) {
                GlobalInstructionsView()
            }
            .sheet(isPresented: $showingUsage) {
                UsageView()
            }
            .alert("Delete every chat?", isPresented: $showingDeleteAll) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    for conversation in conversations {
                        modelContext.delete(conversation)
                    }
                    try? modelContext.save()
                }
            } message: {
                Text("This removes all conversations and messages from this device. It cannot be undone.")
            }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    openBackup(url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Add \(pendingImportCount) chats?",
                isPresented: Binding(
                    get: { pendingImport != nil },
                    set: { if !$0 { pendingImport = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(BackupService.ImportMode.merge.title) { runImport(.merge) }
                Button(BackupService.ImportMode.replace.title, role: .destructive) { runImport(.replace) }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("Adding replaces nothing. Replacing removes the chats already on this device first.")
            }
            .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("Imported", isPresented: Binding(
                get: { importSummary != nil },
                set: { if !$0 { importSummary = nil } }
            )) {
                Button("OK", role: .cancel) { importSummary = nil }
            } message: {
                importedSummaryText
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            Button {
                showingAPIKey = true
            } label: {
                HStack {
                    Label("API key", systemImage: "key")
                    Spacer()
                    Text(appState.hasAPIKey ? "Configured" : "Not set")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Link(destination: URL(string: "https://opencode.ai/auth")!) {
                Label("Get a key in the OpenCode console", systemImage: "arrow.up.right.square")
            }

            Button {
                Task { await appState.refreshModels() }
            } label: {
                HStack {
                    Label("Refresh model list", systemImage: "arrow.clockwise")
                    Spacer()
                    if appState.isLoadingModels {
                        ProgressView().controlSize(.small)
                    } else if let updated = appState.modelListUpdatedAt {
                        Text(updated.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if let error = appState.modelListError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("OpenCode Go")
        } footer: {
            if appState.hasModelList {
                Text("\(appState.enabledModelIDs.count) models are enabled for your account. Models that are switched off are hidden from the picker.")
            } else {
                Text("Your key is stored in the iOS keychain and is only sent to opencode.ai when you ask a question.")
            }
        }
    }

    private var modelSection: some View {
        Section {
            Button {
                showingModelPicker = true
            } label: {
                HStack {
                    Label("Default model", systemImage: "cpu")
                    Spacer()
                    Text(defaultModelName)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Picker(selection: Binding(
                get: { Preferences.defaultReasoning },
                set: { Preferences.defaultReasoning = $0 }
            )) {
                ForEach(ReasoningLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            } label: {
                Label("Default thinking", systemImage: "brain.head.profile")
            }

            NavigationLink {
                TemperatureSettingsView()
            } label: {
                Label("Temperature", systemImage: "thermometer.medium")
            }

            NavigationLink {
                JevTrialsListView()
            } label: {
                Label("Jev trials", systemImage: "questionmark.diamond")
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Thinking only applies to models that support a reasoning budget. Jev answers typed questions rather than chatting - trials live here.")
        }
    }

    private var assistantSection: some View {
        Section {
            Button {
                showingInstructions = true
            } label: {
                HStack {
                    Label("Global instructions", systemImage: "text.bubble")
                    Spacer()
                    Text(Preferences.systemPrompt.isEmpty ? "None" : "Set")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Picker(selection: Binding(
                get: { appState.theme },
                set: { appState.setTheme($0) }
            )) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }
        } header: {
            Text("Assistant")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.biometricEnabled },
                set: { appState.setBiometricEnabled($0) }
            )) {
                Label("Lock with \(biometricName)", systemImage: "faceid")
            }
            .disabled(!biometricsAvailable)
        } header: {
            Text("Privacy")
        } footer: {
            Text(biometricsAvailable
                 ? "The app locks itself when you leave it."
                 : "Biometrics are not available on this device.")
        }
    }

    private var usageSection: some View {
        Section {
            LabeledContent("Allowance used", value: totalCost.usdFormatted)
            LabeledContent("Replies", value: "\(answerCount)")
            LabeledContent("Input tokens", value: totalInput.formatted())
            LabeledContent("Output tokens", value: totalOutput.formatted())

            NavigationLink {
                UsageView()
            } label: {
                Label("Plan allowance", systemImage: "gauge.with.dots.needle.50percent")
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Go is a flat subscription. The amount above is what your chats consumed of the monthly allowance, not a bill.")
        }
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share exported chats", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    exportChats()
                } label: {
                    Label("Export all chats", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                isImporting = true
            } label: {
                Label("Import chats", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showingDeleteAll = true
            } label: {
                Label("Delete all chats", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Chats live only on this device. Export regularly if you want a copy, and import the file to restore it.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionString)
            LabeledContent("Chats stored", value: "\(conversations.count)")
            Link(destination: URL(string: "https://opencode.ai/go")!) {
                Label("About OpenCode Go", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var defaultModelName: String {
        ModelCatalog.resolve(appState.defaultModelID, globalDefault: "")?.displayName ?? "Auto"
    }

    private var biometricsAvailable: Bool {
        if case .available = appState.biometrics.availability { return true }
        return false
    }

    private var biometricName: String {
        if case .available(let name) = appState.biometrics.availability { return name }
        return "Face ID"
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var answers: [Message] {
        conversations
            .flatMap(\.messages)
            .filter { $0.role == .assistant && $0.hasUsage }
    }

    private var totalCost: Double {
        answers.reduce(0) { $0 + $1.costUSD }
    }

    private var totalInput: Int {
        answers.reduce(0) { $0 + $1.totalInputTokens }
    }

    private var totalOutput: Int {
        answers.reduce(0) { $0 + $1.outputTokens }
    }

    private var answerCount: Int {
        answers.count
    }

    private var importedSummaryText: Text {
        let chats = importSummary?.chats ?? 0
        let messages = importSummary?.messages ?? 0
        return Text(String(chats) + " chats with " + String(messages) + " messages were added.")
    }

    private func openBackup(_ url: URL) {
        do {
            let (payload, summary) = try BackupService.read(from: url)
            pendingImportCount = summary.chats
            pendingImport = payload
        } catch {
            importError = "That file is not a chat export.\n\(error.localizedDescription)"
        }
    }

    private func runImport(_ mode: BackupService.ImportMode) {
        guard let payload = pendingImport else { return }
        pendingImport = nil
        do {
            let summary = try BackupService.import(payload, into: modelContext, mode: mode)
            importSummary = ImportSummary(chats: summary.chats, messages: summary.messages)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportChats() {
        do {
            exportURL = try BackupService.export(conversations: conversations)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Optional sampling temperature. Left unset means the provider default is used.
struct TemperatureSettingsView: View {
    @State private var value: Double = Preferences.temperature ?? 1.0
    @State private var enabled: Bool = Preferences.temperature != nil

    var body: some View {
        Form {
            Section {
                Toggle("Override temperature", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        Preferences.temperature = newValue ? value : nil
                    }

                Slider(value: $value, in: 0...2, step: 0.1) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Text("Precise").font(.caption2)
                } maximumValueLabel: {
                    Text("Creative").font(.caption2)
                }
                .disabled(!enabled)
                .onChange(of: value) { _, newValue in
                    if enabled { Preferences.temperature = newValue }
                }

                LabeledContent("Value", value: String(format: "%.1f", value))
            } footer: {
                Text("Lower values are more focused, higher values more varied. Many models ignore this.")
            }
        }
        .navigationTitle("Temperature")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Global system prompt.
struct GlobalInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("These instructions are sent with every new chat. Individual chats can override them.")
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
            .navigationTitle("Global instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Preferences.systemPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { text = Preferences.systemPrompt }
        }
    }
}

// MARK: - Previews

#Preview("Settings", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        SettingsView()
            .environment(AppState(previewHasKey: true))
    }
}
