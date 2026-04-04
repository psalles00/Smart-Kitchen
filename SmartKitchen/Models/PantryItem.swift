import Foundation
import SwiftData

@Model
final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    var imageData: Data? = nil
    var category: String = "Outros"
    var quantity: Double? = nil
    var unit: String? = nil
    var iconName: String? = nil
    /// When true, depleting this item auto-adds it to the grocery list.
    var isLinkedToGrocery: Bool = false
    var expirationDate: Date? = nil
    /// Default shelf-life in days. When set, sending to grocery preserves this expiry duration.
    var defaultExpiryDays: Int? = nil
    var sortOrder: Int = 0
    var addedAt: Date = Date()

    init(
        name: String,
        descriptionText: String = "",
        imageData: Data? = nil,
        category: String = "Outros",
        quantity: Double? = nil,
        unit: String? = nil,
        iconName: String? = nil,
        isLinkedToGrocery: Bool = false,
        expirationDate: Date? = nil,
        defaultExpiryDays: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.imageData = imageData
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.iconName = iconName
        self.isLinkedToGrocery = isLinkedToGrocery
        self.expirationDate = expirationDate
        self.defaultExpiryDays = defaultExpiryDays
        self.sortOrder = sortOrder
        self.addedAt = .now
    }

    /// Formatted quantity string for detailed mode (e.g. "5x", "1 kg").
    var formattedQuantity: String {
        guard let qty = quantity else { return "" }
        let num = qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", qty)
            : String(format: "%.1f", qty)
        if let u = unit, !u.isEmpty {
            return "\(num) \(u)"
        }
        return "\(num)x"
    }

    var formattedExpirationDate: String? {
        guard let expirationDate else { return nil }
        return expirationDate.formatted(date: .abbreviated, time: .omitted)
    }

    /// Plain-text summary for AI context.
    var aiReadableDescription: String {
        var text = name
        if let qty = quantity {
            let num = qty.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", qty)
                : String(format: "%.1f", qty)
            if let u = unit, !u.isEmpty {
                text += " (\(num) \(u))"
            } else {
                text += " (\(num)x)"
            }
        }
        text += " [\(category)]"
        if !descriptionText.isEmpty {
            text += " - \(descriptionText)"
        }
        if let formattedExpirationDate {
            text += " validade \(formattedExpirationDate)"
        }
        return text
    }
}
