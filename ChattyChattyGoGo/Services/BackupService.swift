import Foundation
import SwiftData

/// The on-disk format for exporting and importing chats.
enum Backup {
    struct Payload: Codable, Equatable {
        let chats: [Chat]
    }

    struct Chat: Codable, Equatable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let modelID: String
        let messages: [Entry]
    }

    struct Entry: Codable, Equatable {
        let role: String
        let content: String
        let createdAt: Date
        let reasoning: String
    }

    nonisolated(unsafe) static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Writes the chat history to a file, and reads it back.
enum BackupService {
    struct Summary: Sendable, Equatable {
        let chats: Int
        let messages: Int
    }

    static func export(conversations: [Conversation]) throws -> URL {
        let chats = conversations.map { conversation in
            Backup.Chat(
                id: conversation.id,
                title: conversation.displayTitle,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                modelID: conversation.modelID,
                messages: conversation.sortedMessages.map { message in
                    Backup.Entry(
                        role: message.role.rawValue,
                        content: message.content,
                        createdAt: message.createdAt,
                        reasoning: message.reasoning
                    )
                }
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            // Fractional seconds, so messages written within the same second keep
            // their order when the file is read back.
            var container = encoder.singleValueContainer()
            try container.encode(Backup.fractionalSeconds.string(from: date))
        }
        let data = try encoder.encode(Backup.Payload(chats: chats))

        let stamp = Date.now.formatted(.iso8601.year().month().day())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chattychatty-export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a backup file without touching the store.
    static func read(from url: URL) throws -> (payload: Backup.Payload, summary: Summary) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Backup.fractionalSeconds.date(from: string) { return date }
            if let date = Backup.wholeSeconds.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(string)"))
        }
        let payload = try decoder.decode(Backup.Payload.self, from: Data(contentsOf: url))

        let messageCount = payload.chats.reduce(0) { $0 + $1.messages.count }
        guard messageCount > 0 || payload.chats.isEmpty else {
            throw APIError.decoding("The file contains no chats.")
        }
        return (payload, Summary(chats: payload.chats.count, messages: messageCount))
    }

    /// Puts a backup into the store.
    /// - Parameter mode: merge skips chats that already exist, replace empties the store first.
    static func `import`(
        _ payload: Backup.Payload,
        into context: ModelContext,
        mode: ImportMode
    ) throws -> Summary {
        let existingIDs = Set(try context.fetch(FetchDescriptor<Conversation>()).map(\.id))
        var added = 0
        var messages = 0

        if mode == .replace {
            for conversation in try context.fetch(FetchDescriptor<Conversation>()) {
                context.delete(conversation)
            }
            try context.save()
        }

        for chat in payload.chats {
            if mode == .merge, existingIDs.contains(chat.id) { continue }

            let conversation = Conversation(
                id: chat.id,
                title: chat.title,
                createdAt: chat.createdAt,
                updatedAt: chat.updatedAt,
                modelID: chat.modelID,
                systemPrompt: "",
                sessionID: SessionIdentity.makeSessionID()
            )
            conversation.titleIsAutomatic = false
            context.insert(conversation)

            for entry in chat.messages {
                let role = MessageRole(rawValue: entry.role) ?? .user
                let message = Message(
                    role: role,
                    content: entry.content,
                    createdAt: entry.createdAt,
                    reasoning: entry.reasoning,
                    conversation: conversation
                )
                message.refreshSearchText()
                context.insert(message)
                messages += 1
            }
            added += 1
        }

        try context.save()
        return Summary(chats: added, messages: messages)
    }

    enum ImportMode: String, CaseIterable, Identifiable {
        case merge
        case replace

        var id: String { rawValue }

        var title: String {
            switch self {
            case .merge: "Add to what is here"
            case .replace: "Replace everything"
            }
        }
    }
}
