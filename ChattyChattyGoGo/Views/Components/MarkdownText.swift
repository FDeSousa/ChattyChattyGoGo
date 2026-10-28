import Foundation
import SwiftUI

/// Renders markdown with a light-weight renderer: headings, lists, inline formatting
/// and fenced code blocks.
struct MarkdownText: View {
    let text: String
    /// Set while the answer is still being written.
    var isStreaming: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownParser.blocks(from: text), id: \.id) { block in
                switch block.kind {
                case .prose(let value):
                    ProseBlock(text: value)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language, isStreaming: isStreaming)
                }
            }
        }
    }
}

private struct ProseBlock: View {
    let text: String

    private enum Piece: Identifiable {
        case paragraph(String)
        case heading(String, Int)
        case bullets([String])

        var id: String {
            switch self {
            case .paragraph(let value): "p:" + value
            case .heading(let value, let level): "h\(level):" + value
            case .bullets(let values): "b:" + values.joined(separator: "|")
            }
        }
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var bullets: [String] = []

        func flushBullets() {
            if !bullets.isEmpty {
                result.append(.bullets(bullets))
                bullets.removeAll()
            }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushBullets()
                continue
            }

            if let heading = headingInfo(trimmed) {
                flushBullets()
                result.append(.heading(heading.text, heading.level))
                continue
            }

            if let bullet = bulletContent(trimmed) {
                bullets.append(bullet)
                continue
            }

            flushBullets()
            result.append(.paragraph(raw))
        }
        flushBullets()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces) { piece in
                switch piece {
                case .paragraph(let value):
                    Text(attributed(value))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .heading(let value, let level):
                    Text(attributed(value))
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .padding(.top, level <= 2 ? 4 : 0)
                        .textSelection(.enabled)
                case .bullets(let values):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(attributed(value))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func headingInfo(_ line: String) -> (text: String, level: Int)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" })
        guard hashes.count <= 6 else { return nil }
        let content = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (content, hashes.count)
    }

    private func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // Ordered list, e.g. "1. "
        if let dot = line.firstIndex(of: "."),
           line.distance(from: line.startIndex, to: dot) <= 2,
           line.index(after: dot) < line.endIndex,
           line[line.index(after: dot)] == " " {
            return String(line[line.index(dot, offsetBy: 2)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func attributed(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: value, options: options) {
            return attributed
        }
        return AttributedString(value)
    }
}

// MARK: - Previews

#Preview("Markdown", traits: .fixedLayout(width: 440, height: 520)) {
    ScrollView {
        MarkdownText(text: """
        ### Heading three

        Some **bold**, some *italic* and some `inline code`.

        - First bullet
        - Second bullet with a [link](https://opencode.ai)

        1. Numbered one
        2. Numbered two

        ```swift
        let greeting = "Hello, iPhone 17 Pro Max"
        print(greeting)
        ```
        """)
        .padding()
    }
}
