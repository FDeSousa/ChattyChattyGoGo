import Foundation

/// A block of markdown content: prose, a fenced code block, or a table.
struct MarkdownBlock: Identifiable {
    enum Kind {
        case prose(String)
        case code(code: String, language: String?)
        case table(rows: [[String]])
    }

    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    /// Returns true when a line looks like a markdown table row.
    /// Must start with `|` (optional leading whitespace) and contain at least two columns.
    private static func isTableRow(_ trimmed: String) -> Bool {
        guard trimmed.first == "|" else { return false }
        let pipes = trimmed.filter { $0 == "|" }
        return pipes.count >= 2
    }

    /// Splits a table row into cells, dropping empty leading/trailing cells
    /// caused by the boundary pipes.
    private static func parseTableRow(_ trimmed: String) -> [String] {
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Splits markdown into prose, code and table blocks.
    ///
    /// Tables are detected as consecutive lines that look like table rows
    /// (start with `|` and contain at least two columns). Separator rows
    /// (`|---|---|`) are dropped.
    static func blocks(from text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false
        var inTable = false
        var tableRows: [[String]] = []

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

        func flushTable() {
            // Drop separator rows (|---|---|) and empty rows.
            let dataRows = tableRows.filter { row in
                !row.isEmpty && !row.allSatisfy { cell in
                    let trimmed = cell.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return true }
                    return trimmed.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0 == " " }
                }
            }
            guard !dataRows.isEmpty else {
                tableRows.removeAll()
                return
            }
            result.append(MarkdownBlock(id: result.count, kind: .table(rows: dataRows)))
            tableRows.removeAll()
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
            } else if isTableRow(trimmed) {
                flushProse()
                tableRows.append(Self.parseTableRow(trimmed))
                inTable = true
            } else {
                if inTable {
                    flushTable()
                    inTable = false
                }
                prose.append(String(line))
            }
        }

        if inCode {
            flushCode()
        } else if inTable {
            flushTable()
        } else {
            flushProse()
        }
        return result
    }
}
