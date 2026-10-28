import Foundation
import SwiftData

/// Backs the chat list: grouping, filtering and global search.
@MainActor
@Observable
final class ChatListViewModel {
    var searchText: String = ""
    private(set) var searchResults: [SearchResult] = []
    private(set) var isSearching = false

    private var searchTask: Task<Void, Never>?

    enum Group: String, CaseIterable, Identifiable {
        case today
        case yesterday
        case week
        case older

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .week: "Previous 7 Days"
            case .older: "Older"
            }
        }
    }

    struct Section: Identifiable {
        let group: Group
        let conversations: [Conversation]
        var id: String { group.rawValue }
    }

    func sections(for conversations: [Conversation], calendar: Calendar = .current) -> [Section] {
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        var buckets: [Group: [Conversation]] = [:]
        for conversation in conversations {
            let date = conversation.updatedAt
            let group: Group
            if date >= startOfToday {
                group = .today
            } else if date >= startOfYesterday {
                group = .yesterday
            } else if date >= startOfWeek {
                group = .week
            } else {
                group = .older
            }
            buckets[group, default: []].append(conversation)
        }

        return Group.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return Section(group: group, conversations: items)
        }
    }

    // MARK: - Search

    func search(query: String, in context: ModelContext) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            // Small debounce so fast typing does not hammer the store.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let results = Self.runSearch(query: trimmed, in: context)
            guard !Task.isCancelled else { return }
            self?.searchResults = results
            self?.isSearching = false
        }
    }

    /// Synchronous search over conversation titles and message contents.
    static func runSearch(query: String, in context: ModelContext) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let needle = SearchText.normalize(trimmed)

        var results: [SearchResult] = []

        // Titles: there are only ever a handful of conversations, so filter them in memory
        // to get proper case- and accent-insensitive matching.
        if let conversations = try? context.fetch(FetchDescriptor<Conversation>()) {
            for conversation in conversations {
                if conversation.displayTitle.localizedStandardContains(trimmed) {
                    results.append(
                        SearchResult(conversation: conversation, message: nil, snippet: conversation.displayTitle)
                    )
                }
            }
        }

        // Message bodies: matched against the pre-folded copy so the predicate stays fast.
        let messagePredicate = #Predicate<Message> { message in
            message.searchText.contains(needle)
        }
        if let messages = try? context.fetch(FetchDescriptor<Message>(predicate: messagePredicate)) {
            for message in messages {
                guard let conversation = message.conversation else { continue }
                results.append(
                    SearchResult(
                        conversation: conversation,
                        message: message,
                        snippet: snippet(from: message.content, matching: trimmed)
                    )
                )
            }
        }

        return results
            .sorted { $0.conversation.updatedAt > $1.conversation.updatedAt }
    }

    private static func snippet(from text: String, matching query: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = collapsed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(collapsed.prefix(120))
        }
        let start = collapsed.index(range.lowerBound, offsetBy: -40, limitedBy: collapsed.startIndex) ?? collapsed.startIndex
        let end = collapsed.index(range.upperBound, offsetBy: 80, limitedBy: collapsed.endIndex) ?? collapsed.endIndex
        var snippet = String(collapsed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > collapsed.startIndex { snippet = "…" + snippet }
        if end < collapsed.endIndex { snippet += "…" }
        return snippet
    }
}
