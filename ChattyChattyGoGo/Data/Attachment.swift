import Foundation
import SwiftData

/// A file attached to a message: a photo, or a document whose text was extracted.
@Model
final class Attachment {
    enum Kind: String {
        case image
        case document
    }

    var id: UUID = UUID()
    var kindRaw: String = Kind.document.rawValue
    var name: String = ""
    var mimeType: String = ""
    /// The original bytes, kept so the image can be shown again.
    @Attribute(.externalStorage) var data: Data?
    /// Text pulled out of a document, so any model can read it.
    var extractedText: String = ""
    var byteCount: Int = 0

    var message: Message?

    init(
        kind: Kind,
        name: String,
        mimeType: String,
        data: Data? = nil,
        extractedText: String = ""
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.name = name
        self.mimeType = mimeType
        self.data = data
        self.extractedText = extractedText
        self.byteCount = data?.count ?? extractedText.utf8.count
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .document }
        set { kindRaw = newValue.rawValue }
    }

    /// The wire representation of this attachment.
    var wire: WireAttachment {
        switch kind {
        case .image:
            return .image(mimeType: mimeType, base64: data?.base64EncodedString() ?? "")
        case .document:
            return .document(text: extractedText)
        }
    }
}
