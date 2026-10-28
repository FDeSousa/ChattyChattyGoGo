import Foundation
import SwiftData

enum MessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case system
}

/// One message inside a conversation.
@Model
final class Message {
    var id: UUID = UUID()
    var roleRaw: String = MessageRole.user.rawValue
    var content: String = ""
    /// Case- and accent-folded copy of `content`, used by the search predicate.
    var searchText: String = ""
    var createdAt: Date = Date.now
    /// Set when the assistant turn ended in an error.
    var isFailed: Bool = false
    /// Raw provider error text, shown under a failed bubble.
    var errorDetail: String = ""
    /// Chain-of-thought style output, when the provider exposes it separately.
    var reasoning: String = ""
    var promptTokens: Int?
    var completionTokens: Int?

    // Markers for the request that produced this message.
    /// Total time from sending the request to the last token, in milliseconds.
    var durationMS: Int = 0
    /// Time until the first token arrived, in milliseconds.
    var firstTokenMS: Int = 0
    /// Tokens billed at the full input rate.
    var billedInputTokens: Int = 0
    /// Input tokens served from the provider's prompt cache.
    var cachedInputTokens: Int = 0
    /// Output tokens generated.
    var outputTokens: Int = 0
    /// Estimated share of the monthly allowance this message consumed, in US dollars.
    var costUSD: Double = 0
    /// The model that produced this message.
    var modelIDUsed: String = ""

    var conversation: Conversation?
    /// Files that were sent with this message.
    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment] = []

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String = "",
        createdAt: Date = .now,
        isFailed: Bool = false,
        errorDetail: String = "",
        reasoning: String = "",
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isFailed = isFailed
        self.errorDetail = errorDetail
        self.reasoning = reasoning
        self.conversation = conversation
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFailed
    }

    /// Keeps the searchable copy in sync with the message text.
    func refreshSearchText() {
        searchText = SearchText.normalize(content)
    }

    /// True once the request that produced this message has been measured.
    var hasUsage: Bool {
        durationMS > 0 || totalInputTokens > 0 || outputTokens > 0
    }

    var totalInputTokens: Int {
        billedInputTokens + cachedInputTokens
    }

    /// A short summary such as `1.4s · 1.2k in · 380 out · $0.0031`.
    var usageSummary: String? {
        guard hasUsage else { return nil }
        var parts: [String] = []
        if durationMS > 0 {
            parts.append(String(format: "%.1fs", Double(durationMS) / 1000))
        }
        if totalInputTokens > 0 {
            parts.append("\(totalInputTokens.formatted(.number.notation(.compactName))) in")
        }
        if outputTokens > 0 {
            parts.append("\(outputTokens.formatted(.number.notation(.compactName))) out")
        }
        if costUSD > 0 {
            parts.append(costUSD.usdFormatted)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
