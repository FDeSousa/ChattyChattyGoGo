import SwiftUI

/// Reusable model chooser. Shows every model in the Go lineup with a short
/// description of what it is good at.
///
/// The gateway is asked which models the account may actually use, so models that are
/// switched off in the OpenCode console are not offered.
struct ModelPickerView: View {
    @Binding var selection: String
    var title: String = "Model"

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var familyTarget: ModelInfo?
    @State private var showUnavailable = false

    /// Everything worth showing: the curated catalogue plus any model the account
    /// has that the catalogue does not describe yet.
    private var selectable: [ModelInfo] {
        let curated = ModelCatalog.all
        let extra = appState.availableModels.filter { model in !curated.contains(model) }
        return curated + extra
    }

    private var filtered: [ModelInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return selectable }
        return selectable.filter { model in
            model.id.lowercased().contains(query) ||
            model.displayName.lowercased().contains(query) ||
            model.summary.lowercased().contains(query) ||
            model.bestFor.contains { $0.lowercased().contains(query) }
        }
    }

    private func isEnabled(_ model: ModelInfo) -> Bool {
        appState.isModelEnabled(model.id)
    }

    /// Chat models: everything except Jev, which never takes part in conversations.
    private var chatModels: [ModelInfo] {
        filtered.filter { $0.family != .systemOne }
    }

    /// The Jev decision models, which run from the trials rather than a chat.
    private var systemOneModels: [ModelInfo] {
        filtered.filter { $0.family == .systemOne }
    }

    private var enabledModels: [ModelInfo] {
        chatModels.filter { isEnabled($0) }
    }

    /// Models this account cannot use, each with the app's best explanation why.
    private var unavailableModels: [ModelInfo] {
        chatModels.filter { !isEnabled($0) }
    }

    /// The model that is currently picked, even when the account may not use it.
    private var selectedModel: ModelInfo? {
        ModelCatalog.model(withID: selection)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = ModelCatalog.autoModelID
                        dismiss()
                    } label: {
                        ModelRow(
                            model: ModelInfo(
                                id: ModelCatalog.autoModelID,
                                displayName: "Auto",
                                family: .openAIChat,
                                summary: "Uses today's pick from a rotating set of strong general models.",
                                bestFor: ["Hands-off answers"]
                            ),
                            isSelected: selection == ModelCatalog.autoModelID,
                            badge: "Auto"
                        )
                    }
                    .buttonStyle(.plain)

                    if selection.isEmpty {
                        Button {
                            selection = ""
                            dismiss()
                        } label: {
                            HStack {
                                Label("Use the global default", systemImage: "checkmark")
                                Spacer()
                                Text(ModelCatalog.resolve("", globalDefault: Preferences.defaultModelID)?.displayName ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            selection = ""
                            dismiss()
                        } label: {
                            HStack {
                                Label("Use the global default", systemImage: "arrow.uturn.backward")
                                Spacer()
                                Text(ModelCatalog.resolve("", globalDefault: Preferences.defaultModelID)?.displayName ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Special")
                } footer: {
                    if let auto = appState.autoModel() {
                        Text("Today's Auto pick is \(auto.displayName) — \(auto.summary)")
                    }
                }

                Section("All models") {
                    ForEach(enabledModels) { model in
                        Button {
                            selection = model.id
                            dismiss()
                        } label: {
                            ModelRow(model: model, isSelected: selection == model.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                familyTarget = model
                            } label: {
                                Label("API style…", systemImage: "wrench.and.screwdriver")
                            }
                        }
                    }
                }

                if !systemOneModels.isEmpty {
                    Section {
                        ForEach(systemOneModels) { model in
                            // Not tappable: Jev answers typed questions, not chats,
                            // so it is never picked as a conversation model.
                            ModelRow(
                                model: model,
                                isUnavailable: true,
                                refusalReason: "Jev does not hold conversations. Try it from Settings \u{2192} Jev trials, which record answers, probabilities, timing and cost."
                            )
                            .disabled(true)
                        }
                    } header: {
                        Text("Decision models")
                    } footer: {
                        Text("Jev bills the pay-as-you-go balance (or nothing), not the Go subscription. The trial harness in Settings runs it.")
                    }
                }

                if !appState.refusedModelIDs.isEmpty {
                    Section {
                        Button {
                            appState.forgetRefusals()
                        } label: {
                            Label("Refresh models", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } footer: {
                        Text("Models listed are those OpenCode has enabled for your account. If you have changed your OpenCode settings, check again.")
                    }
                }

                if !unavailableModels.isEmpty {
                    Section {
                        Toggle("Show models not enabled for this account", isOn: $showUnavailable)

                        if showUnavailable {
                            ForEach(unavailableModels) { model in
                                // Greyed out and not tappable: the gateway rejects
                                // requests to it, so selecting it would only mislead.
                                ModelRow(
                                    model: model,
                                    isSelected: selection == model.id,
                                    isUnavailable: true,
                                    refusalReason: appState.unavailableReason(for: model.id)
                                )
                                .opacity(0.55)
                                .disabled(true)
                            }
                        }
                    } header: {
                        Text("Not enabled")
                    } footer: {
                        Text("Requests to these models are turned away on this OpenCode account. Each one says why.")
                    }
                }

                if let selectedModel, !isEnabled(selectedModel) {
                    let reason = appState.unavailableReason(for: selectedModel.id) ??
                        "It cannot answer on this account."
                    Section {
                        Label(
                            "\(selectedModel.displayName): \(reason)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        familyTarget = ModelInfo(
                            id: selection,
                            displayName: selection,
                            family: .openAIChat,
                            summary: "",
                            bestFor: []
                        )
                    } label: {
                        Label("Set API style for the selected model", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(selection.isEmpty || selection == ModelCatalog.autoModelID)
                } footer: {
                    Text("Only change this if a model fails to answer. The app tries the correct endpoint automatically and remembers what worked.")
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $familyTarget) { model in
                FamilyOverrideView(modelID: model.id)
            }
        }
    }
}

/// Colour of the billing badge shown on a model row. Go models get none, so
/// only the pay-as-you-go and retired cases matter in practice.
enum ModelServiceBadge {
    static func color(_ service: ModelService) -> Color {
        switch service {
        case .go: .accentColor
        case .zen: .indigo
        case .retired: .gray
        }
    }
}

/// One model in the list.
struct ModelRow: View {
    let model: ModelInfo
    var isSelected: Bool = false
    var badge: String?
    var isUnavailable: Bool = false
    /// Why the account cannot use it, shown when set.
    var refusalReason: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.headline)

                    // Where the model bills: Go models carry no badge, the rest say so.
                    if model.service != .go {
                        Text(model.service.badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ModelServiceBadge.color(model.service).opacity(0.18), in: Capsule())
                            .foregroundStyle(ModelServiceBadge.color(model.service))
                    }

                    if let badge {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if model.supportsReasoning {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Supports thinking")
                    }
                    if model.supportsImages {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Can read images")
                    }
                    if isUnavailable {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Not enabled for this account")
                    }
                }

                Text(model.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.bestFor.isEmpty {
                    Text(model.bestFor.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let refusalReason {
                    Label(refusalReason, systemImage: "exclamationmark.bubble")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let privacyNote = model.privacyNote {
                    Label(privacyNote, systemImage: "hand.raised")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let retention = model.retention {
                    Label(retention, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Requests are not kept by the provider", systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Lets the user pin the API family for a model when the automatic detection is wrong.
struct FamilyOverrideView: View {
    let modelID: String

    @Environment(\.dismiss) private var dismiss
    @State private var family: APIFamily = .openAIChat

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("API style", selection: $family) {
                        ForEach(APIFamily.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("API style for \(modelID)")
                } footer: {
                    Text("The OpenCode Go gateway exposes each model through one provider dialect. If a model refuses to answer, try the next style.")
                }
            }
            .navigationTitle("API style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var overrides = Preferences.familyOverrides
                        overrides[modelID] = family.rawValue
                        Preferences.familyOverrides = overrides
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let raw = Preferences.familyOverrides[modelID], let saved = APIFamily(rawValue: raw) {
                    family = saved
                } else {
                    family = ModelCatalog.model(withID: modelID)?.family ?? .openAIChat
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Model picker", traits: .fixedLayout(width: 440, height: 956)) {
    @Previewable @State var selection = "kimi-k3"
    ModelPickerView(selection: $selection, title: "Model for this chat")
        .environment(AppState(previewHasKey: true))
}

#Preview("Model row", traits: .fixedLayout(width: 440, height: 200)) {
    List {
        ModelRow(model: ModelCatalog.model(withID: "gemini-4-argon-contributor")!)
        ModelRow(model: ModelCatalog.model(withID: "kimi-k3")!, isSelected: true)
    }
    .listStyle(.plain)
}

#Preview("API style", traits: .fixedLayout(width: 440, height: 600)) {
    FamilyOverrideView(modelID: "kimi-k3")
}
