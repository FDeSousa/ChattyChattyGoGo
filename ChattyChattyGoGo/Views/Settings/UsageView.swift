import SwiftData
import SwiftUI

/// Live tracker for the OpenCode Go allowance.
///
/// Shows the three windows the gateway reports (rolling 5 hours, week, month) and what
/// this app has used per model. It refreshes itself so it can be left open while the
/// subscription is being used elsewhere.
struct UsageView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var snapshot: UsageSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var lastUpdated: Date?
    @State private var autoRefresh = true
    @State private var allowances: [ModelAllowance] = []

    var body: some View {
        List {
            accountSection
            if !allowances.isEmpty {
                modelSection
            }
            if let snapshot {
                Section {
                    if let balance = snapshot.balanceUSD {
                        LabeledContent("Pay-as-you-go balance", value: balance.usdFormatted)
                    }
                    ForEach(snapshot.windows) { window in
                        UsageWindowRow(window: window)
                    }
                } header: {
                    Text("Allowance used")
                } footer: {
                    Text("These percentages come from the OpenCode account API and cover your whole plan, wherever you use it. The balance line is shown only when the endpoint reports one, and it is what Jev and pay-as-you-go models draw on.")
                }
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh usage")
            }
        }
        .task {
            load()
            loadAllowances()
            await autoRefreshLoop()
        }
        .refreshable {
            load()
            loadAllowances()
        }
        .onChange(of: autoRefresh) { _, _ in
            load()
        }
        .overlay(alignment: .bottom) {
            if let lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            Toggle("Refresh every 30 seconds", isOn: $autoRefresh)
        } footer: {
            Text("Leave this open to watch the allowance while using OpenCode Go elsewhere.")
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(allowances) { allowance in
                ModelAllowanceRow(allowance: allowance)
            }
        } header: {
            Text("Per model, as used by this app")
        } footer: {
            Text("Each model gets a rolling five hour window at 20% of its monthly limit, a week at 50%, and the month at 100%. Counted from the replies recorded on this device only.")
        }
    }

    // MARK: - Loading

    private func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            guard let key = KeychainService.read(), !key.isEmpty else {
                errorMessage = "Add your API key first."
                return
            }
            do {
                snapshot = try await OpenCodeService().fetchUsage(apiKey: key)
                errorMessage = nil
                lastUpdated = .now
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadAllowances() {
        let messages = (try? modelContext.fetch(FetchDescriptor<Message>())) ?? []
        allowances = AllowanceTracker.allowances(from: messages)
    }

    /// Refreshes every 30 seconds while the view is open, without blocking anything.
    private func autoRefreshLoop() async {
        guard autoRefresh else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            load()
            loadAllowances()
        }
    }
}

/// One window of the account allowance.
struct UsageWindowRow: View {
    let window: UsageSnapshot.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.id.capitalized)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(window.percent))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(window.percent, 0), 100), total: 100)
                .tint(window.isHealthy ? .accentColor : .orange)
            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What this app has consumed of one model's allowance.
struct ModelAllowanceRow: View {
    let allowance: ModelAllowance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(allowance.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(allowance.isUnlimited ? "Unlimited" : allowance.monthlyLimit.formatted(.currency(code: "USD")))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            window(label: "5 hours", used: allowance.rolling5h, percent: allowance.rollingPercent, limit: allowance.monthlyLimit * 0.2)
            window(label: "Week", used: allowance.weekly, percent: allowance.weeklyPercent, limit: allowance.monthlyLimit * 0.5)
            window(label: "Month", used: allowance.monthly, percent: allowance.monthlyPercent, limit: allowance.monthlyLimit)
        }
        .padding(.vertical, 2)
    }

    private func window(label: String, used: Double, percent: Double, limit: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            ProgressView(value: percent, total: 100)
                .tint(percent >= 90 ? .orange : .accentColor)

            Text(used.usdFormatted)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\\(label): \\(used.usdFormatted) of \\(limit.usdFormatted)")
    }
}
