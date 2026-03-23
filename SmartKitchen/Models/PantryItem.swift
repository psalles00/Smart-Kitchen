import Foundation
import SwiftData

@Model
final class PantryItem {
    var id: UUID
    var name: String
    var category: String
    var quantity: Double?
    var unit: String?
    var iconName: String?
    /// When true, depleting this item auto-adds it to the grocery list.
    var isLinkedToGrocery: Bool
    var expirationDate: Date?
    var sortOrder: Int
    var addedAt: Date

    init(
        name: String,
        category: String = "Outros",
        quantity: Double? = nil,
        unit: String? = nil,
        iconName: String? = nil,
        isLinkedToGrocery: Bool = false,
        expirationDate: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.iconName = iconName
        self.isLinkedToGrocery = isLinkedToGrocery
        self.expirationDate = expirationDate
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
        if let formattedExpirationDate {
            text += " validade \(formattedExpirationDate)"
        }
        return text
    }
}
