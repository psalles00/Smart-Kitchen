import Foundation
import SwiftData

@Model
final class UtensilItem {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    var imageData: Data? = nil
    var category: String = "Outros"
    var iconName: String? = nil
    var sortOrder: Int = 0
    var addedAt: Date = Date()

    init(
        name: String,
        descriptionText: String = "",
        imageData: Data? = nil,
        category: String = "Outros",
        iconName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.imageData = imageData
        self.category = category
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.addedAt = .now
    }

    /// Plain-text summary for AI context.
    var aiReadableDescription: String {
        descriptionText.isEmpty ? "\(name) (\(category))" : "\(name) (\(category)) - \(descriptionText)"
    }
}
