import Foundation
import SwiftData

/// Drives one conversation: streaming replies, editing, retries.
@MainActor
@Observable
final class ChatViewModel {
    private(set) var conversation: Conversation?
    private var context: ModelContext?

    var draft: String = ""
    private(set) var isStreaming = false
    private(set) var errorBanner: String?
    /// How many older messages were left out of the last request to fit the context window.
    private(set) var trimmedMessageCount = 0
    var reasoningLevel: ReasoningLevel = Preferences.defaultReasoning
    /// Set when the user asks to jump to a particular message (opened from search).
    var pendingScrollTarget: UUID?

    private let service = OpenCodeService()
    private var streamTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var appState: AppState?
    /// Set when the chosen model is not enabled for the account.
    private(set) var modelUnavailable = false
    /// Set when the last failure was the key being rejected.
    private(set) var lastErrorWasAuthProblem = false

    // MARK: - Setup

    func configure(conversation: Conversation, context: ModelContext, appState: AppState? = nil) {
        self.conversation = conversation
        self.context = context
        self.appState = appState
        if conversation.modelID.isEmpty {
            conversation.modelID = ""
        }
        // Give the chat its gateway session id up front, so every turn of this
        // conversation is routed to the same upstream.
        if conversation.sessionID.isEmpty {
            _ = conversation.resolvedSessionID()
            save()
        }
        reasoningLevel = Preferences.defaultReasoning
    }

    // MARK: - Derived state

    var model: ModelInfo? {
        guard let conversation else { return nil }
        let stored = conversation.modelID
        let globalDefault = appState?.defaultModelID ?? Preferences.defaultModelID
        if stored == ModelCatalog.autoModelID || (stored.isEmpty && globalDefault == ModelCatalog.autoModelID) {
            return appState?.autoModel() ?? ModelCatalog.autoModel()
        }
        return ModelCatalog.resolve(stored, globalDefault: globalDefault)
    }

    var isAutoModel: Bool {
        let stored = conversation?.modelID ?? ""
        let effective = stored.isEmpty ? Preferences.defaultModelID : stored
        return effective == ModelCatalog.autoModelID
    }

    var systemPrompt: String {
        if let conversation, !conversation.systemPrompt.isEmpty {
            return conversation.systemPrompt
        }
        return Preferences.systemPrompt
    }

    var supportsReasoning: Bool {
        model?.supportsReasoning ?? false
    }

    /// False when the account has told us this model may not be used.
    var isModelEnabled: Bool {
        guard let model else { return true }
        return appState?.isModelEnabled(model.id) ?? true
    }

    // MARK: - Actions

    func send(attachments: [PendingAttachment] = []) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !attachments.isEmpty), !isStreaming, let conversation, let context else { return }

        errorBanner = nil

        // Catch a model the account has disabled before the request is made.
        if let model, !isModelEnabled {
            modelUnavailable = true
            errorBanner = "\(model.displayName) is not enabled for your OpenCode account. Pick another model to continue."
            return
        }

        // Jev answers typed questions, not conversations. Route it to the trials.
        if let model, model.family == .systemOne {
            errorBanner = "\(model.displayName) does not chat - it answers typed questions with values and probabilities. Try it from Settings → Jev trials."
            return
        }

        draft = ""

        let userMessage = Message(role: .user, content: text, conversation: conversation)
        userMessage.refreshSearchText()
        context.insert(userMessage)

        for attachment in attachments {
            let stored = Attachment(
                kind: attachment.kind,
                name: attachment.name,
                mimeType: attachment.mimeType,
                data: attachment.data,
                extractedText: attachment.text
            )
            stored.message = userMessage
            context.insert(stored)
        }
        if conversation.title.isEmpty {
            conversation.title = ChatTitle.make(from: text)
        }
        conversation.updatedAt = .now

        let assistantMessage = Message(role: .assistant, content: "", conversation: conversation)
        assistantMessage.createdAt = userMessage.createdAt.addingTimeInterval(0.001)
        context.insert(assistantMessage)
        save()

        run(assistant: assistantMessage, conversation: conversation, context: context)
    }

    /// Replaces the text of a sent message and regenerates everything after it.
    ///
    /// Editing a question re-asks it; editing an answer just saves the new text.
    func edit(_ message: Message, to newText: String) {
        guard !isStreaming, let conversation, let context else { return }
        let cleaned = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        errorBanner = nil

        let trail = conversation.sortedMessages
        guard let index = trail.firstIndex(where: { $0.id == message.id }) else { return }
        let later = trail[(index + 1)...]

        message.content = cleaned
        message.refreshSearchText()
        message.isFailed = false
        message.errorDetail = ""

        // Everything after the edit belongs to the old version of the thread.
        for laterMessage in later {
            context.delete(laterMessage)
        }
        save()

        if message.role == .user {
            let assistantMessage = Message(role: .assistant, content: "", conversation: conversation)
            assistantMessage.createdAt = message.createdAt.addingTimeInterval(0.002)
            context.insert(assistantMessage)
            conversation.updatedAt = .now
            save()
            run(assistant: assistantMessage, conversation: conversation, context: context)
        } else {
            conversation.updatedAt = .now
            save()
        }
    }

    /// Re-asks the last question, replacing the previous answer.
    func regenerate() {
        guard !isStreaming, let conversation, let context else { return }
        let messages = conversation.sortedMessages
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        guard messages.contains(where: { $0.role == .user }) else { return }

        errorBanner = nil
        context.delete(lastAssistant)
        save()

        let assistantMessage = Message(role: .assistant, content: "", conversation: conversation)
        assistantMessage.createdAt = Date.now.addingTimeInterval(0.001)
        context.insert(assistantMessage)
        conversation.updatedAt = .now
        save()

        run(assistant: assistantMessage, conversation: conversation, context: context)
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        save()
    }

    func clearError() {
        errorBanner = nil
    }

    /// Called after the model changes, so a stale "not enabled" banner goes away.
    func clearModelState() {
        modelUnavailable = false
        errorBanner = nil
        lastErrorWasAuthProblem = false
    }

    func deleteMessage(_ message: Message) {
        guard let context else { return }
        context.delete(message)
        save()
    }

    // MARK: - Streaming

    private func run(
        assistant: Message,
        conversation: Conversation,
        context: ModelContext
    ) {
        guard let model = model else {
            assistant.isFailed = true
            assistant.errorDetail = "No model is available. Pick one in Settings."
            errorBanner = assistant.errorDetail
            save()
            return
        }
        guard let apiKey = KeychainService.read(), !apiKey.isEmpty else {
            assistant.isFailed = true
            assistant.errorDetail = APIError.missingAPIKey.localizedDescription
            errorBanner = APIError.missingAPIKey.localizedDescription
            save()
            return
        }

        let all = conversation.sortedMessages
            .filter { $0.role != .system && !$0.isFailed && (!$0.content.isEmpty || !$0.attachments.isEmpty) }
            .map { message in
                WireMessage(
                    role: message.role == .assistant ? .assistant : .user,
                    content: message.content,
                    attachments: message.attachments.map(\.wire)
                )
            }

        // Keep the request inside the model's context window.
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fit = ContextWindow.fit(all, systemPrompt: prompt.isEmpty ? nil : prompt, modelID: model.id)
        let messages = fit.kept
        trimmedMessageCount = fit.trimmed

        let request = ChatRequest(
            model: model,
            messages: messages,
            systemPrompt: prompt.isEmpty ? nil : prompt,
            reasoning: supportsReasoning ? reasoningLevel : .off,
            apiKey: apiKey,
            temperature: Preferences.temperature,
            sessionID: conversation.resolvedSessionID()
        )

        isStreaming = true
        lastSave = .distantPast
        modelUnavailable = false
        lastErrorWasAuthProblem = false
        assistant.modelIDUsed = model.id

        let families = candidateFamilies(for: model)
        let started = ContinuousClock.now
        let hadImage = messages.contains { message in
            message.attachments.contains { $0.isImage }
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            var usage = TokenUsage()
            var firstToken: Duration?
            do {
                for try await event in self.service.stream(request, families: families) {
                    switch event {
                    case .content(let text):
                        if firstToken == nil { firstToken = started.duration(to: .now) }
                        assistant.content += text
                    case .reasoning(let text):
                        if firstToken == nil { firstToken = started.duration(to: .now) }
                        assistant.reasoning += text
                    case .usage(let reported):
                        usage = usage.merged(with: reported)
                    }
                    conversation.updatedAt = .now
                    self.saveIfNeeded()
                }
                assistant.isFailed = false
                assistant.errorDetail = ""
                assistant.refreshSearchText()
                await self.generateTitleIfNeeded(for: conversation)
                self.recordUsage(
                    usage,
                    on: assistant,
                    model: model,
                    elapsed: started.duration(to: .now),
                    firstToken: firstToken
                )
                self.isStreaming = false
                self.save()
            } catch is CancellationError {
                assistant.refreshSearchText()
                self.recordUsage(
                    usage,
                    on: assistant,
                    model: model,
                    elapsed: started.duration(to: .now),
                    firstToken: firstToken
                )
                self.isStreaming = false
                self.save()
            } catch {
                assistant.isFailed = true
                assistant.errorDetail = error.localizedDescription
                assistant.refreshSearchText()
                lastErrorWasAuthProblem = (error as? APIError)?.isAuthProblem == true
                if (error as? APIError)?.suggestsModelUnavailable == true {
                    let reason = (error as? APIError)?.serverReason
                    self.appState?.markRefused(model.id, reason: reason)
                    self.modelUnavailable = true
                    if let reason, !reason.isEmpty {
                        self.errorBanner = "OpenCode refused \(model.displayName): \(reason)"
                    } else {
                        self.errorBanner = "That model is not available on your OpenCode plan. Pick another one to continue."
                    }
                } else if !model.supportsImages, hadImage {
                    self.errorBanner = "\(model.displayName) refused the image. Most Go models are text only - try one marked with a photo icon."
                } else {
                    self.errorBanner = error.localizedDescription
                }
                self.isStreaming = false
                self.save()
            }
        }
    }

    // MARK: - Title

    /// Asks the chat's own model for a short title, once, after the first answer.
    ///
    /// The current model is used on purpose: the user already chose it, so no extra
    /// model is silently pulled in.
    private func generateTitleIfNeeded(for conversation: Conversation) async {
        guard conversation.titleIsAutomatic else { return }
        guard let apiKey = KeychainService.read(), !apiKey.isEmpty else { return }
        guard let model = model, !isStreaming else { return }

        let firstQuestion = conversation.sortedMessages.first { $0.role == .user }?.content ?? ""
        let firstAnswer = conversation.sortedMessages.last { $0.role == .assistant }?.content ?? ""
        guard !firstQuestion.isEmpty else { return }

        let request = ChatRequest(
            model: model,
            messages: [WireMessage(role: .user, content: titlePrompt(question: firstQuestion, answer: firstAnswer))],
            reasoning: .off,
            apiKey: apiKey,
            sessionID: conversation.resolvedSessionID()
        )

        do {
            let title = try await service.complete(request, family: model.family)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, conversation.titleIsAutomatic else { return }
            var cleaned = title.replacingOccurrences(of: "\u{22}", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 60 { cleaned = ChatTitle.make(from: cleaned) }
            if !cleaned.isEmpty {
                conversation.title = cleaned
                save()
            }
        } catch {
            // A failed title is not worth interrupting the user for.
        }
    }

    private func titlePrompt(question: String, answer: String) -> String {
        let opening = "Name this conversation in three to six words."
        let rule = "Reply with the title only, without quotes or a full stop."
        let lines = [
            opening,
            rule,
            "",
            "Question: " + String(question.prefix(600)),
            "",
            "Answer: " + String(answer.prefix(600))
        ]
        return lines.joined(separator: "\n")
    }

    /// Stores how long the request took and what it cost.
    private func recordUsage(
        _ usage: TokenUsage,
        on message: Message,
        model: ModelInfo,
        elapsed: Duration,
        firstToken: Duration?
    ) {
        message.durationMS = Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        if let firstToken {
            message.firstTokenMS = Int(firstToken.components.seconds) * 1000
                + Int(firstToken.components.attoseconds / 1_000_000_000_000_000)
        }
        message.billedInputTokens = usage.billedInputTokens
        message.cachedInputTokens = usage.cachedInputTokens
        message.outputTokens = usage.outputTokens
        message.promptTokens = usage.inputTokens
        message.completionTokens = usage.outputTokens
        if let pricing = ModelPrices.pricing(for: model.id) {
            message.costUSD = pricing.cost(for: usage)
        }
    }

    private func candidateFamilies(for model: ModelInfo) -> [APIFamily] {
        if let override = Preferences.familyOverrides[model.id], let family = APIFamily(rawValue: override) {
            return [family] + APIFamily.fallbackOrder.filter { $0 != family }
        }
        return [model.family] + APIFamily.fallbackOrder.filter { $0 != model.family }
    }

    // MARK: - Persistence

    private func saveIfNeeded() {
        let now = Date.now
        guard now.timeIntervalSince(lastSave) > 1.5 else { return }
        lastSave = now
        save()
    }

    private func save() {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            errorBanner = "Could not save the conversation: \(error.localizedDescription)"
        }
    }
}
