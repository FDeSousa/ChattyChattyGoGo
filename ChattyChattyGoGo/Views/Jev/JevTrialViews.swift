import SwiftData
import SwiftUI

/// The list of Jev trials, newest first.
///
/// A trial pairs a subject (the "state" Jev judges) with a set of typed questions.
/// Each run is recorded in full so the model's behaviour can be compared.
struct JevTrialsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JevTrial.updatedAt, order: .reverse) private var trials: [JevTrial]

    @State private var newTrial: JevTrial?

    var body: some View {
        List {
            if trials.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No trials yet", systemImage: "questionmark.diamond")
                    } description: {
                        Text("A trial asks Jev typed questions about a subject you choose - yes/no, pick-one or rubric score - and records every answer, probability, timing and cost. Use the + button to start one.")
                    }
                    .textSelection(.enabled)
                }
            }

            ForEach(trials) { trial in
                NavigationLink {
                    JevTrialEditorView(trial: trial)
                } label: {
                    JevTrialRow(trial: trial)
                }
            }
        }
        .navigationTitle("Jev trials")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newTrial = JevTrialFactory.make(in: modelContext)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New trial")
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { newTrial != nil },
            set: { if !$0 { newTrial = nil } }
        )) {
            if let newTrial {
                JevTrialEditorView(trial: newTrial)
            }
        }
    }
}

/// One trial in the list: what it judges and how it last went.
private struct JevTrialRow: View {
    let trial: JevTrial

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(trial.title.isEmpty ? "Untitled trial" : trial.title)
                .font(.headline)
                .lineLimit(1)

            Text(trial.state)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(trial.modelID)
                    .font(.caption2.monospacedDigit())
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(trial.questions.count) question\(trial.questions.count == 1 ? "" : "s")")
                    .font(.caption2)
                Spacer()
                if let last = trial.runs.max(by: { $0.createdAt < $1.createdAt }) {
                    Text(last.isFailed ? "Last run failed" : "Last run \(last.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(last.isFailed ? Color.orange : Color.gray)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Edits one trial: the subject, the questions, and the Jev id to ask.
struct JevTrialEditorView: View {
    @Bindable var trial: JevTrial
    @State private var viewModel: JevTrialViewModel

    init(trial: JevTrial) {
        self.trial = trial
        _viewModel = State(wrappedValue: JevTrialViewModel(trial: trial))
    }

    var body: some View {
        Form {
            subjectSection
            questionsSection
            modelSection
        }
        .navigationTitle(trial.title.isEmpty ? "Trial" : trial.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    JevTrialRunView(trial: trial)
                } label: {
                    Text("Run")
                }
                .disabled(trial.questions.isEmpty || trial.state.isEmpty)
            }
        }
    }

    // MARK: - Sections

    private var subjectSection: some View {
        Section {
            TextField("Name, e.g. Support triage", text: $trial.title)
            VStack(alignment: .leading, spacing: 4) {
                Text("Subject")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $trial.state)
                    .font(.body)
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
            }
        } header: {
            Text("Subject")
        } footer: {
            Text("The state Jev judges. Questions are asked about this text.")
        }
    }

    private var questionsSection: some View {
        Section {
            ForEach(trial.questions) { question in
                JevQuestionEditor(
                    questionID: question.id,
                    viewModel: viewModel
                )
            }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) where index < trial.questions.count {
                    viewModel.deleteQuestion(withID: trial.questions[index].id)
                }
            }

            Menu {
                ForEach(JevQuestionType.allCases, id: \.self) { type in
                    Button(type.title) {
                        viewModel.addQuestion(type: type)
                    }
                }
            } label: {
                Label("Add question", systemImage: "plus")
            }
        } header: {
            Text("Questions")
        } footer: {
            Text(trial.questions.isEmpty
                 ? "Add at least one question. Each type answers differently: true/false probability, one option from a set, or a place on a rubric."
                 : "Swipe left to delete a question, or edit any part of it.")
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Jev model", selection: $trial.modelID) {
                ForEach(JevModels.all) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        } footer: {
            Text("Both bill the pay-as-you-go balance (or nothing), not the Go subscription. The free id is usable at no charge; the paid id is charged at $0.042 per million input tokens.")
        }
    }
}

/// One question, editable.
///
/// All writes go through the view model's `mutate`, which resolves the row **by id
/// at write time** and touches only the field being edited. Holding a copy of the
/// row across re-renders and writing it back would resurrect stale data - the
/// bound copy predates field work happening elsewhere in the same form.
private struct JevQuestionEditor: View {
    let questionID: UUID
    let viewModel: JevTrialViewModel

    /// The row's current state, read from the trial by id.
    private var question: JevQuestion {
        viewModel.question(withID: questionID)
            ?? JevQuestion(type: .boolean, instructions: "")
    }

    private func mutate(_ change: (inout JevQuestion) -> Void) {
        viewModel.mutate(questionID, change)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Type", selection: typeBinding) {
                ForEach(JevQuestionType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextField("What should Jev answer?", text: instructionsBinding)

            switch question.type {
            case .boolean:
                Text(JevQuestionType.boolean.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .choice:
                optionsEditor(question: question)
            case .score:
                rubricEditor(question: question)
            }
        }
        .padding(.vertical, 2)
    }

    private var typeBinding: Binding<JevQuestionType> {
        Binding(
            get: { question.type },
            set: { type in mutate { row in row.type = type } }
        )
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { question.instructions },
            set: { text in mutate { row in row.instructions = text } }
        )
    }

    private func optionsEditor(question: JevQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Option key", text: optionNameBinding(index))
                        .font(.subheadline.weight(.medium))
                    TextField("What it covers", text: optionDescriptionBinding(index))
                        .font(.caption)
                }
                .padding(.vertical, 2)
                .overlay(alignment: .trailing) {
                    Button {
                        viewModel.deleteOption(at: index, fromQuestionWithID: questionID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(question.options.count < 3)
                }
            }

            Button {
                viewModel.addOption(toQuestionWithID: questionID)
            } label: {
                Label("Add option", systemImage: "plus.circle")
            }
        }
    }

    private func rubricEditor(question: JevQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(question.rubric.enumerated()), id: \.offset) { index, _ in
                HStack {
                    Text("\(index)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .leading)
                    TextField("Describe level \(index)", text: rubricBinding(index))
                }
                .padding(.vertical, 2)
                .overlay(alignment: .trailing) {
                    Button {
                        viewModel.deleteRubricLevel(index, fromQuestionWithID: questionID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(question.rubric.count < 3)
                }
            }

            Button {
                viewModel.addRubricLevel(toQuestionWithID: questionID)
            } label: {
                Label("Add level", systemImage: "plus.circle")
            }
        }
    }

    private func optionNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let row = question
                return index < row.options.count ? row.options[index].name : ""
            },
            set: { text in
                mutate { row in
                    guard index < row.options.count else { return }
                    let current = row.options[index]
                    row.options[index] = JevOption(name: text, description: current.description)
                }
            }
        )
    }

    private func optionDescriptionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let row = question
                return index < row.options.count ? row.options[index].description : ""
            },
            set: { text in
                mutate { row in
                    guard index < row.options.count else { return }
                    let current = row.options[index]
                    row.options[index] = JevOption(name: current.name, description: text)
                }
            }
        )
    }

    private func rubricBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let row = question
                return index < row.rubric.count ? row.rubric[index] : ""
            },
            set: { text in
                mutate { row in
                    guard index < row.rubric.count else { return }
                    row.rubric[index] = text
                }
            }
        )
    }
}

/// Runs one evaluation and shows the answers, probabilities, timing and cost.
struct JevTrialRunView: View {
    let trial: JevTrial

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: JevTrialViewModel

    init(trial: JevTrial) {
        self.trial = trial
        _viewModel = State(wrappedValue: JevTrialViewModel(trial: trial))
    }

    var body: some View {
        List {
            subjectSection
            if !trial.questions.isEmpty {
                questionsSection
            }
            if let error = viewModel.runError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            runsSection
        }
        .navigationTitle(trial.title.isEmpty ? "Run" : trial.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.run(context: modelContext) }
                } label: {
                    if viewModel.isRunning {
                        ProgressView()
                    } else {
                        Text("Run")
                    }
                }
                .disabled(viewModel.isRunning || trial.questions.isEmpty)
            }
        }
    }

    /// The thing being judged, alone in its own section so the questions that
    /// follow read as separate rows rather than a wall of text.
    private var subjectSection: some View {
        Section {
            Text(trial.modelID)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(trial.state)
                .font(.body)
        } header: {
            Text("Subject")
        } footer: {
            Text("Questions are asked about this text.")
        }
    }

    private var questionsSection: some View {
        Section {
            ForEach(Array(trial.questions.enumerated()), id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(question.instructions.isEmpty ? "(unwritten question)" : question.instructions)
                            .font(.body.weight(.medium))
                    }
                    Text(question.type.title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Questions")
        }
    }

    private var runs: [JevRun] {
        trial.runs.sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private var runsSection: some View {
        if runs.isEmpty {
            Section {
                Text("Press Run to ask Jev. Results, probabilities, timing and cost will be listed here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                JevRunDetailRow(run: runs[0])
                    .font(.footnote)
            } header: {
                Text("Latest run")
            }

            if runs.count > 1 {
                Section {
                    ForEach(runs.dropFirst()) { run in
                        DisclosureGroup {
                            JevRunDetailRow(run: run)
                                .font(.footnote)
                        } label: {
                            JevRunSummaryRow(run: run)
                        }
                    }
                } header: {
                    Text("Earlier runs")
                } footer: {
                    Text("Each run keeps the question wording it used, so results stay comparable after edits.")
                }
            }
        }
    }
}

/// Compact one-line history entry.
private struct JevRunSummaryRow: View {
    let run: JevRun

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(timeString)
                    .font(.subheadline)
                Text("\(run.answers.count) answer\(run.answers.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if run.isFailed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Failed")
            } else if run.costUSD != nil {
                Text(run.costUSD!.usdFormatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(durationString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timeString: String {
        run.createdAt.formatted(date: .omitted, time: .shortened)
    }

    private var durationString: String {
        run.isFailed ? "—" : JevFormatting.duration(run.durationMS)
    }
}

/// Every answer of one run, plus the measurements.
private struct JevRunDetailRow: View {
    let run: JevRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if run.isFailed {
                Label(run.errorDetail.isEmpty ? "The request failed." : run.errorDetail,
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            ForEach(run.answers) { answer in
                JevAnswerRow(answer: answer)
            }

            if !run.isFailed {
                Divider()
                JevMetricsRow(run: run)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One answer: meaning, confidence and the full distribution.
private struct JevAnswerRow: View {
    let answer: JevRunAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(answer.instructions.isEmpty ? "(unwritten question)" : answer.instructions)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(answer.summary)
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let confidence = answer.confidence {
                Text("Confidence \(String(format: "%.2f", confidence))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let distribution = answer.probabilities.sorted { $0.value > $1.value }
            if distribution.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(distribution, id: \.key) { key, value in
                        HStack(spacing: 6) {
                            Text(key)
                                .font(.caption2)
                                .frame(width: 90, alignment: .leading)
                                .lineLimit(1)
                            ProgressView(value: min(max(value, 0), 1), total: 1)
                                .tint(value == distribution.first!.value ? .accentColor : .gray.opacity(0.6))
                            Text(String(format: "%.2f", value))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Duration, tokens, charge and how the run was billed.
private struct JevMetricsRow: View {
    let run: JevRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Took", value: JevFormatting.duration(run.durationMS))
            LabeledContent("Input tokens", value: run.inputTokens.formatted())
            LabeledContent("Output tokens", value: run.outputTokens.formatted())
            if let cost = run.costUSD {
                LabeledContent("Charged", value: cost.usdFormatted)
            }
            if let source = run.billingSource {
                LabeledContent("Billed as", value: source)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// Small formatting helpers for the trial views.
enum JevFormatting {
    /// Milliseconds as "1,240 ms" under ten seconds, else "10.4 s".
    static func duration(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "—" }
        if milliseconds < 10_000 {
            return milliseconds.formatted() + " ms"
        }
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
    }
}

// MARK: - Previews

#Preview("Jev trials", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        JevTrialsListView()
    }
}

#Preview("Jev editor", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        NavigationStack {
            JevTrialEditorView(trial: PreviewData.jevSeed())
        }
    }
}

#Preview("Jev run", traits: .fixedLayout(width: 440, height: 956)) {
    PreviewScene {
        NavigationStack {
            JevTrialRunView(trial: PreviewData.jevSeed())
        }
    }
}
