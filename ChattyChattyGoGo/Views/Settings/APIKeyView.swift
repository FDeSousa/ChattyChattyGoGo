import SwiftUI

/// Screen for entering and testing the OpenCode Go API key.
struct APIKeyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var status: Status = .idle
    @State private var modelCount: Int?

    private enum Status: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("OpenCode Go API key", text: $key)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let saved = KeychainService.read(), !saved.isEmpty {
                        Button {
                            key = saved
                            status = .idle
                        } label: {
                            Label("Show saved key", systemImage: "eye")
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("API key")
                } footer: {
                    Text("Find your key in the OpenCode console. It is stored in the iOS keychain, never in app data or backups of your chats.")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Label("Save key", systemImage: "checkmark.circle")
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test connection", systemImage: "network")
                            if status == .working {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .working)

                    switch status {
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    case .idle, .working:
                        EmptyView()
                    }
                }
            }
            .navigationTitle("OpenCode Go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        do {
            try KeychainService.save(key)
            appState.refresh()
            status = .success("Key saved to the keychain.")
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func testConnection() {
        save()
        status = .working
        let key = KeychainService.read() ?? ""
        Task {
            do {
                let models = try await OpenCodeService().fetchModels(apiKey: key)
                modelCount = models.count
                status = .success("Connected. \(models.count) models are available on your plan.")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func pasteFromClipboard() {
        if let clipboard = Clipboard.paste(), !clipboard.isEmpty {
            key = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            status = .idle
        }
    }
}

extension String {
    var isNilOrEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Previews

#Preview("API key", traits: .fixedLayout(width: 440, height: 956)) {
    APIKeyView()
        .environment(AppState(previewHasKey: true))
}
