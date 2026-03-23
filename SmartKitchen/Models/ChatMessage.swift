import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// A quick-action button the assistant can embed in a message.
struct QuickAction: Codable, Identifiable {
    var id: UUID
    var label: String
    /// Prompt text sent when the user taps this action.
    var prompt: String

    init(label: String, prompt: String) {
        self.id = UUID()
        self.label = label
        self.prompt = prompt
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    /// Recipe IDs attached to this message (rendered as inline cards).
    var attachedRecipeIds: [UUID]
    /// Quick-action buttons the assistant suggests.
    var quickActions: [QuickAction]

    init(
        role: MessageRole,
        content: String,
        attachedRecipeIds: [UUID] = [],
        quickActions: [QuickAction] = []
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
        self.attachedRecipeIds = attachedRecipeIds
        self.quickActions = quickActions
    }
}
