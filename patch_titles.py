import pathlib

p = pathlib.Path("ChattyChattyGoGo/ViewModels/ChatViewModel.swift")
s = p.read_text()

old = """                assistant.isFailed = false
                assistant.errorDetail = ""
                assistant.refreshSearchText()
                self.recordUsage("""
new = """                assistant.isFailed = false
                assistant.errorDetail = ""
                assistant.refreshSearchText()
                await self.generateTitleIfNeeded(for: conversation)
                self.recordUsage("""
assert old in s
s = s.replace(old, new, 1)

old = """    /// Stores how long the request took and what it cost."""
new = """    // MARK: - Title

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
            apiKey: apiKey,
            reasoning: .off,
            sessionID: conversation.resolvedSessionID()
        )

        do {
            let title = try await service.complete(request, family: model.family)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, conversation.titleIsAutomatic else { return }
            var cleaned = title.replacingOccurrences(of: "\"", with: "")
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

    /// Stores how long the request took and what it cost."""
assert old in s
s = s.replace(old, new, 1)
p.write_text(s)
print("ok")
PYEOF