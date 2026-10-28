import HighlightSwift
import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?
    /// While an answer is still streaming, the code is shown plain: highlighting on
    /// every token would flash colours at the user for no benefit.
    var isStreaming: Bool = false

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.isEmpty == false ? (language ?? "") : "code")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Button {
                    Clipboard.copy(code)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                if isStreaming {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HighlightedCodeText(code: code, language: language)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    /// Which language to ask highlight.js for.
    ///
    /// A fence tag that maps to a known grammar is used directly; anything else is passed
    /// through as an alias, and a missing tag falls back to automatic detection.
    var highlightMode: HighlightMode {
        Self.highlightMode(forTag: language)
    }

    static func highlightMode(forTag tag: String?) -> HighlightMode {
        guard let tag, !tag.isEmpty else { return .automatic }
        let lowered = tag.lowercased()
        if let known = languages[lowered] {
            return .language(known)
        }
        return .languageAliasIgnoreIllegal(lowered)
    }

    private static let languages: [String: HighlightLanguage] = [
        "applescript": .appleScript,
        "arduino": .arduino,
        "awk": .awk,
        "basic": .basic,
        "c": .c,
        "c++": .cPlusPlus,
        "cpp": .cPlusPlus,
        "c#": .cSharp,
        "csharp": .cSharp,
        "cs": .cSharp,
        "clojure": .clojure,
        "css": .css,
        "dart": .dart,
        "delphi": .delphi,
        "diff": .diff,
        "django": .django,
        "docker": .dockerfile,
        "dockerfile": .dockerfile,
        "elixir": .elixir,
        "elm": .elm,
        "erlang": .erlang,
        "gherkin": .gherkin,
        "go": .go,
        "golang": .go,
        "gradle": .gradle,
        "graphql": .graphQL,
        "haskell": .haskell,
        "html": .html,
        "xml": .html,
        "java": .java,
        "javascript": .javaScript,
        "js": .javaScript,
        "json": .json,
        "julia": .julia,
        "kotlin": .kotlin,
        "latex": .latex,
        "tex": .latex,
        "less": .less,
        "lisp": .lisp,
        "lua": .lua,
        "makefile": .makefile,
        "matlab": .matlab,
        "nix": .nix,
        "objc": .objectiveC,
        "objectivec": .objectiveC,
        "objective-c": .objectiveC,
        "perl": .perl,
        "php": .php,
        "plaintext": .plaintext,
        "text": .plaintext,
        "postgres": .postgreSQL,
        "postgresql": .postgreSQL,
        "protobuf": .protocolBuffers,
        "proto": .protocolBuffers,
        "python": .python,
        "py": .python,
        "r": .r,
        "ruby": .ruby,
        "rb": .ruby,
        "rust": .rust,
        "rs": .rust,
        "scala": .scala,
        "scss": .scss,
        "bash": .bash,
        "sh": .bash,
        "zsh": .shell,
        "shell": .shell,
        "shellscript": .shell,
        "sql": .sql,
        "swift": .swift,
        "toml": .toml,
        "typescript": .typeScript,
        "ts": .typeScript,
        "vb": .visualBasic,
        "wasm": .webAssembly,
        "yaml": .yaml,
        "yml": .yaml,
        "md": .markdown,
        "markdown": .markdown
    ]
}
