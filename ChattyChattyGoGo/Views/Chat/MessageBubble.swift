import SwiftUI

struct MessageBubble: View {
    let message: Message
    var modelName: String = ""
    var isStreaming: Bool = false
    var onCopy: () -> Void = {}
    var onRegenerate: (() -> Void)?
    var onDelete: () -> Void = {}
    var onEdit: (() -> Void)?
    var onSendEdit: ((String) -> Void)?

    var body: some View {
        switch message.role {
        case .user:
            if isEditing {
                editForm
            } else {
                userBubble
            }
        case .assistant:
            assistantBubble
        case .system:
            EmptyView()
        }
    }

    // MARK: - Edit

    private var isEditing: Bool {
        onSendEdit != nil
    }

    @State private var draft = ""

    private var editForm: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 160)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button("Cancel") {
                    onEdit?()
                }
                .font(.caption)

                Button {
                    onSendEdit?(draft)
                } label: {
                    Label("Save & rerun", systemImage: "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear { draft = message.content }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty {
                    AttachmentPreview(attachments: message.attachments)
                        .frame(maxWidth: 240)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }
            }
        }
        .contextMenu {
            Button {
                onEdit?()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                if !modelName.isEmpty {
                    Text(modelName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if isStreaming && message.content.isEmpty {
                    TypingIndicator()
                }
            }

            if !message.reasoning.isEmpty {
                ReasoningView(text: message.reasoning)
            }

            if !message.content.isEmpty {
                MarkdownText(text: message.content, isStreaming: isStreaming)
            }

            if message.isFailed {
                failureView
            }

            if !message.content.isEmpty {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if let onRegenerate {
                Button {
                    onRegenerate()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if !message.errorDetail.isEmpty {
                Text(message.errorDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            if let onRegenerate {
                Button {
                    onRegenerate()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            Button {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            Spacer(minLength: 0)
            if let summary = message.usageSummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }
}

/// Thumbnails and file chips for the files that came with a message.
struct AttachmentPreview: View {
    let attachments: [Attachment]

    private var images: [Attachment] {
        attachments.filter { $0.kind == .image }
    }

    private var documents: [Attachment] {
        attachments.filter { $0.kind != .image }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images.prefix(3)) { attachment in
                        if let data = attachment.data, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    if images.count > 3 {
                        Text("+\(images.count - 3)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 76)
                            .background(Color.chatSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            ForEach(documents) { attachment in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(attachment.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.chatSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

/// Collapsed "thinking" output, when the provider exposes reasoning separately.
struct ReasoningView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            Label("Thinking", systemImage: "brain.head.profile")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.chatSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Three-dot shimmer shown while the first tokens are still arriving.
struct TypingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: 6, height: 6)
                        .foregroundStyle(Color.secondary)
                        .opacity(phase == index ? 1 : 0.35)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Message bubbles", traits: .fixedLayout(width: 440, height: 560)) {
    VStack(alignment: .leading, spacing: 18) {
        MessageBubble(message: PreviewData.message(.user, "What is an actor in Swift?"))
        MessageBubble(
            message: PreviewData.message(
                .assistant,
                "An actor is a reference type that protects mutable state. Only one task can touch it at a time, so there is no data race.",
                reasoning: "Actors serialise access to their state, which removes the need for locks in most cases."
            ),
            modelName: "Kimi K3"
        )
        MessageBubble(
            message: PreviewData.message(
                .assistant,
                "",
                failed: true,
                errorDetail: "HTTP 401: invalid api key"
            ),
            modelName: "Kimi K3"
        )
    }
    .padding(16)
}

#Preview("Typing indicator", traits: .fixedLayout(width: 200, height: 60)) {
    TypingIndicator()
        .padding()
}
