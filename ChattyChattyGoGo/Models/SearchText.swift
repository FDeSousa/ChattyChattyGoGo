import Foundation

/// Normalises text so that searches are case- and accent-insensitive.
///
/// SwiftData's `contains` predicate is case-sensitive, so the searchable copy of every
/// message is stored pre-folded and the query is folded the same way.
enum SearchText {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
