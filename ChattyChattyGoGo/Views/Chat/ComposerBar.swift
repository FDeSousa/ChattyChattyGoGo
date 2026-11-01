import SwiftUI
import UniformTypeIdentifiers

/// A file the user has picked but not sent yet.
struct PendingAttachment: Identifiable {
    let id = UUID()
    var kind: Attachment.Kind
    var name: String
    var mimeType: String
    var data: Data?
    var text: String

    var preview: UIImage? {
        guard kind == .image, let data else { return nil }
        return UIImage(data: data)
    }

    var byteCount: Int {
        data?.count ?? text.utf8.count
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

struct ComposerBar: View {
    @Binding var text: String
    var attachments: [PendingAttachment] = []
    /// The model the chat is talking to, used to filter offered attachment kinds.
    var model: ModelInfo? = nil
    var isStreaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onRemoveAttachment: ((PendingAttachment) -> Void)?
    var onAttachPhoto: (() -> Void)?
    var onAttachFile: (() -> Void)?
    var onAttachVideo: (() -> Void)? = nil
    /// Set when the model cannot read the given attachment.
    var attachmentWarning: String? = nil

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    /// Documents are text-extracted before they reach any model, so the option
    /// stays offered for every model.
    private var offersDocuments: Bool { true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            if let attachmentWarning {
                Label(attachmentWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                if onAttachPhoto != nil || onAttachFile != nil || onAttachVideo != nil {
                    Menu {
                        if let onAttachPhoto {
                            Button {
                                onAttachPhoto()
                            } label: {
                                Label("Photo or image", systemImage: "photo")
                            }
                        }
                        if let onAttachFile {
                            Button {
                                onAttachFile()
                            } label: {
                                Label("Document", systemImage: "doc")
                            }
                            .disabled(offersDocuments == false)
                        }
                        if let onAttachVideo {
                            Button {
                                onAttachVideo()
                            } label: {
                                Label("Video", systemImage: "video.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .accessibilityLabel("Attach a file")
                }

                TextField("Ask anything…", text: $text, axis: .vertical)
                    .focused($isFocused)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    }
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend { onSend() }
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.red, in: Circle())
                    }
                    .accessibilityLabel("Stop generating")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35), in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    chip(for: attachment)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(for attachment: PendingAttachment) -> some View {
        HStack(spacing: 6) {
            if let preview = attachment.preview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconFor(attachment.kind))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(labelFor(attachment.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                onRemoveAttachment?(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func iconFor(_ kind: Attachment.Kind) -> String {
        switch kind {
        case .image: "photo.fill"
        case .video: "video.fill"
        case .audio: "waveform"
        case .document: "doc.text.fill"
        }
    }

    private func labelFor(_ kind: Attachment.Kind) -> String {
        switch kind {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .document: "Text extracted"
        }
    }
}
