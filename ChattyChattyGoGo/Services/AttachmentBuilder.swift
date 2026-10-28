import Foundation
import PDFKit
import UIKit

/// Builds attachments from files the user picks.
///
/// Images are downscaled so the request stays small; documents are turned into text so
/// that every model, not just the ones that understand PDFs, can read them.
enum AttachmentBuilder {
    /// Longest edge of an attached image, in pixels.
    static let maxImageDimension: CGFloat = 1_600
    /// Documents larger than this are truncated.
    static let maxDocumentCharacters = 200_000

    enum BuildError: LocalizedError {
        case unsupportedType(String)
        case unreadable(String)
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let name):
                "\(name) cannot be attached. Images, PDFs, text and code files are supported."
            case .unreadable(let name):
                "\(name) could not be read."
            case .tooLarge(let name):
                "\(name) is too large to attach."
            }
        }
    }

    /// Prepares an image for sending.
    static func image(from data: Data, name: String) throws -> (data: Data, mimeType: String) {
        guard let image = UIImage(data: data) else {
            throw BuildError.unreadable(name)
        }
        let scaled = downscale(image)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.82) else {
            throw BuildError.unreadable(name)
        }
        return (jpeg, "image/jpeg")
    }

    /// Extracts the text of a document.
    static func document(from url: URL) throws -> (text: String, mimeType: String) {
        let name = url.lastPathComponent
        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.preferredMIMEType
            ?? "application/octet-stream"

        if mime == "application/pdf" || url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw BuildError.unreadable(name)
            }
            var text = ""
            for index in 0..<document.pageCount {
                if let pageText = document.page(at: index)?.string {
                    text += pageText + "\n\n"
                }
                if text.count > maxDocumentCharacters { break }
            }
            guard !text.isEmpty else {
                throw BuildError.unreadable(name)
            }
            return (truncate(text), mime)
        }

        if isTextual(mime) {
            guard let data = try? Data(contentsOf: url) else {
                throw BuildError.unreadable(name)
            }
            guard data.count <= 20_000_000 else {
                throw BuildError.tooLarge(name)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw BuildError.unreadable(name)
            }
            return (truncate(text), mime)
        }

        throw BuildError.unsupportedType(name)
    }

    private static func isTextual(_ mimeType: String) -> Bool {
        if mimeType.hasPrefix("text/") { return true }
        return ["application/json", "application/xml", "application/x-yaml", "application/javascript"]
            .contains(mimeType)
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxDocumentCharacters else { return text }
        return String(text.prefix(maxDocumentCharacters)) + "\n\n… (truncated)"
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxImageDimension else { return image }
        let scale = maxImageDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
