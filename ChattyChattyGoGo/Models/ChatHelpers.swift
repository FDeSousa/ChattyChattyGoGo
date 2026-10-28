import Foundation
import SwiftData

/// Builds a short, readable title from the first thing the user asked.
enum ChatTitle {
    static func make(from text: String, limit: Int = 42) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "New Chat" }
        guard singleLine.count > limit else { return singleLine }
        let prefix = singleLine.prefix(limit)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}

/// A hit produced by the global search.
struct SearchResult: Identifiable, Hashable {
    let conversation: Conversation
    let message: Message?
    let snippet: String

    var id: UUID { message?.id ?? conversation.id }
}
