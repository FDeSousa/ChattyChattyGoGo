import SwiftUI

/// Cost and timing for one conversation.
struct ChatStatsView: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss

    private var answers: [Message] {
        conversation.sortedMessages.filter { $0.role == .assistant && $0.hasUsage }
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

    private var totalCached: Int {
        answers.reduce(0) { $0 + $1.cachedInputTokens }
    }

    private var totalDurationMS: Int {
        answers.reduce(0) { $0 + $1.durationMS }
    }

    private var averageDurationMS: Int {
        guard !answers.isEmpty else { return 0 }
        return totalDurationMS / answers.count
    }

    /// Cost per model, for the breakdown.
    private var byModel: [(model: String, cost: Double, count: Int)] {
        var buckets: [String: (Double, Int)] = [:]
        for message in answers {
            let name = ModelCatalog.model(withID: message.modelIDUsed)?.displayName ?? message.modelIDUsed
            let current = buckets[name] ?? (0, 0)
            buckets[name] = (current.0 + message.costUSD, current.1 + 1)
        }
        return buckets
            .map { (model: $0.key, cost: $0.value.0, count: $0.value.1) }
            .sorted { $0.cost > $1.cost }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Allowance used", value: totalCost.usdFormatted)
                    LabeledContent("Messages", value: "\(answers.count)")
                    LabeledContent("Input tokens", value: totalInput.formatted())
                    LabeledContent("Cached input", value: totalCached.formatted())
                    LabeledContent("Output tokens", value: totalOutput.formatted())
                    LabeledContent("Total time", value: formatDuration(totalDurationMS))
                    LabeledContent("Average reply", value: formatDuration(averageDurationMS))
                } header: {
                    Text("This chat")
                } footer: {
                    Text("Go is a flat subscription, so the amount shown is what this chat consumed of your monthly allowance, not a bill.")
                }

                if !byModel.isEmpty {
                    Section("By model") {
                        ForEach(byModel, id: \.model) { entry in
                            HStack {
                                Text(entry.model)
                                Spacer()
                                Text(entry.cost.usdFormatted)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("Replies") {
                    ForEach(answers) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(message.costUSD.usdFormatted)
                                    .font(.caption.monospacedDigit())
                            }
                            if let summary = message.usageSummary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "—" }
        if milliseconds < 1000 { return "\(milliseconds) ms" }
        return String(format: "%.1f s", Double(milliseconds) / 1000)
    }
}
