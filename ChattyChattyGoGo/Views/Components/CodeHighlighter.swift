import Foundation
import HighlightSwift
import SwiftUI

/// One syntax highlighter for the whole app.
///
/// The package's `CodeText` view creates its own engine per view, which would mean one
/// JavaScript engine per code block in a chat. This wrapper keeps a single engine and
/// remembers results, so scrolling back to a highlighted block is instant.
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private let highlight = Highlight()
    private var cache: [Key: HighlightResult] = [:]

    private struct Key: Hashable {
        let code: String
        let language: String?
        let dark: Bool
    }

    func cached(_ code: String, language: String?, dark: Bool) -> HighlightResult? {
        cache[Key(code: code, language: language, dark: dark)]
    }

    /// Highlights a block of code, or returns the plain text when highlighting fails.
    func highlight(_ code: String, language: String?, dark: Bool) async -> HighlightResult? {
        let key = Key(code: code, language: language, dark: dark)
        if let hit = cache[key] { return hit }

        do {
            let result = try await highlight.request(
                code,
                mode: CodeBlockView.highlightMode(forTag: language),
                colors: dark ? .dark(.xcode) : .light(.xcode)
            )
            if result.isUndefined || code.count > 100_000 {
                return nil
            }
            cache[key] = result
            trimCacheIfNeeded()
            return result
        } catch {
            return nil
        }
    }

    /// Keeps the cache from growing without bound.
    private func trimCacheIfNeeded(limit: Int = 200) {
        guard cache.count > limit else { return }
        for key in cache.keys.prefix(cache.count - limit) {
            cache.removeValue(forKey: key)
        }
    }

    func clearCache() {
        cache.removeAll()
    }
}

/// A code block whose text is syntax highlighted.
struct HighlightedCodeText: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var result: HighlightResult?

    var body: some View {
        Group {
            if let result {
                Text(result.attributedText)
            } else {
                Text(code)
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(code)-\(language ?? "")-\(colorScheme == .dark)") {
            let dark = colorScheme == .dark
            if let cached = CodeHighlighter.shared.cached(code, language: language, dark: dark) {
                result = cached
                return
            }
            result = await CodeHighlighter.shared.highlight(code, language: language, dark: dark)
        }
    }
}
