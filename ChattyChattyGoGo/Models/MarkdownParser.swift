import Foundation

/// A block of markdown content: either prose or a fenced code block.
struct MarkdownBlock: Identifiable {
    enum Kind {
        case prose(String)
        case code(code: String, language: String?)
    }

    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    /// Splits markdown into prose and code blocks. Unterminated fences are treated as code.
    static func blocks(from text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                result.append(MarkdownBlock(id: result.count, kind: .prose(joined)))
            }
            prose.removeAll()
        }

        func flushCode() {
            result.append(MarkdownBlock(id: result.count, kind: .code(code: code.joined(separator: "\n"), language: language)))
            code.removeAll()
            language = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                } else {
                    flushProse()
                    let raw = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = raw.isEmpty ? nil : raw
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(String(line))
            } else {
                prose.append(String(line))
            }
        }

        if inCode {
            flushCode()
        } else {
            flushProse()
        }
        return result
    }
}
