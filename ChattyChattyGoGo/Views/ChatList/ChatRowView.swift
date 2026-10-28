import SwiftData
import SwiftUI

struct ChatRowView: View {
    let conversation: Conversation
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.displayTitle)
                .font(.headline)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if let preview = conversation.lastMessage?.content, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Empty chat")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("Chat row", traits: .fixedLayout(width: 440, height: 200)) {
    List {
        ChatRowView(conversation: PreviewData.conversations()[0])
        ChatRowView(conversation: PreviewData.conversations()[2])
    }
    .listStyle(.plain)
}
