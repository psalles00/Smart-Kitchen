import Foundation
import SwiftData

@Model
final class ChatConversation {
    var id: UUID = UUID()
    var title: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Auto-generates a title from the first user message (truncated to 50 chars).
    func generateTitle(from firstMessage: String) {
        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.count > 50 ? String(trimmed.prefix(50)) + "…" : trimmed
    }

    /// The app disables autosave; each completed message must reach the store.
    @MainActor
    static func persist(_ message: ChatMessage, in context: ModelContext) throws {
        context.insert(message)
        if let conversationID = message.conversationId {
            let descriptor = FetchDescriptor<ChatConversation>(
                predicate: #Predicate { $0.id == conversationID }
            )
            if let conversation = try context.fetch(descriptor).first {
                conversation.updatedAt = .now
                if conversation.title == nil && message.role == .user {
                    conversation.generateTitle(from: message.content)
                }
            }
        }
        try context.save()
    }
}
