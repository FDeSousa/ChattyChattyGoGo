import SwiftUI

extension Color {
    /// Cross-platform "secondary background" colour used by bubbles and code blocks.
    static var chatSecondaryBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.15)
        #endif
    }
}
