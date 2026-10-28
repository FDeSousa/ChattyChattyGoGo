import Foundation
import SwiftData

/// Builds the app's data store.
enum Persistence {
    static let schema = Schema([Conversation.self, Message.self, Attachment.self, JevTrial.self, JevRun.self, JevRunAnswer.self])

    /// Opens the on-device store, falling back to an in-memory one if it cannot be read.
    ///
    /// The schema grows as the app gains features, and a store written by an older
    /// build may not always be migratable. Losing the store is bad, but refusing to
    /// launch is worse.
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            print("Could not open the conversation store: \(error). Falling back to a temporary store.")
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                fatalError("Could not create a container: \(error)")
            }
        }
    }
}
