import Foundation
import SwiftData

@Model
final class GroceryItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = "Outros"
    var quantity: Double? = nil
    var unit: String? = nil
    var iconName: String? = nil
    var isChecked: Bool = false
    /// Fixed items are auto-added back when the linked pantry item is depleted.
    var isFixed: Bool = false
    var linkedPantryItemId: UUID? = nil
    var sortOrder: Int = 0
    var addedAt: Date = Date()

    init(
        name: String,
        category: String = "Outros",
        quantity: Double? = nil,
        unit: String? = nil,
        iconName: String? = nil,
        isChecked: Bool = false,
        isFixed: Bool = false,
        linkedPantryItemId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.iconName = iconName
        self.isChecked = isChecked
        self.isFixed = isFixed
        self.linkedPantryItemId = linkedPantryItemId
        self.sortOrder = sortOrder
        self.addedAt = .now
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
        if isChecked { text += " ✓" }
        if isFixed { text += " 📌" }
        return text
    }
}
