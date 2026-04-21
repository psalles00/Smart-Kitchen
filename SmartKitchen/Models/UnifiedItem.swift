import Foundation
import SwiftData

@Model
final class UnifiedItem {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    var imageData: Data? = nil
    var category: String = "Outros"
    var quantity: Double? = nil
    var unit: String? = nil
    var iconName: String? = nil
    var addedAt: Date = Date()

    // MARK: - List flags

    var isPantry: Bool = false
    var isGrocery: Bool = false
    var isUtensil: Bool = false

    // MARK: - Per-list sort order

    var pantrySortOrder: Int = 0
    var grocerySortOrder: Int = 0
    var utensilSortOrder: Int = 0

    // MARK: - Pantry-specific

    /// When true, depleting this item auto-adds it to the grocery list.
    var isLinkedToGrocery: Bool = false
    var expirationDate: Date? = nil
    /// Default shelf-life in days. When set, sending to grocery preserves this expiry duration.
    var defaultExpiryDays: Int? = nil

    // MARK: - Grocery-specific

    var isChecked: Bool = false
    /// Fixed items are auto-added back when the linked pantry item is depleted.
    var isFixed: Bool = false
    var linkedPantryItemId: UUID? = nil

    init(
        name: String,
        descriptionText: String = "",
        imageData: Data? = nil,
        category: String = "Outros",
        quantity: Double? = nil,
        unit: String? = nil,
        iconName: String? = nil,
        isPantry: Bool = false,
        isGrocery: Bool = false,
        isUtensil: Bool = false,
        pantrySortOrder: Int = 0,
        grocerySortOrder: Int = 0,
        utensilSortOrder: Int = 0,
        isLinkedToGrocery: Bool = false,
        expirationDate: Date? = nil,
        defaultExpiryDays: Int? = nil,
        isChecked: Bool = false,
        isFixed: Bool = false,
        linkedPantryItemId: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.imageData = imageData
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.iconName = iconName
        self.isPantry = isPantry
        self.isGrocery = isGrocery
        self.isUtensil = isUtensil
        self.pantrySortOrder = pantrySortOrder
        self.grocerySortOrder = grocerySortOrder
        self.utensilSortOrder = utensilSortOrder
        self.isLinkedToGrocery = isLinkedToGrocery
        self.expirationDate = expirationDate
        self.defaultExpiryDays = defaultExpiryDays
        self.isChecked = isChecked
        self.isFixed = isFixed
        self.linkedPantryItemId = linkedPantryItemId
        self.addedAt = .now
    }

    // MARK: - Convenience sort order

    /// Legacy single sortOrder accessor for backward compat in drag/drop.
    var sortOrder: Int {
        get {
            if isPantry { return pantrySortOrder }
            if isGrocery { return grocerySortOrder }
            return utensilSortOrder
        }
        set {
            if isPantry { pantrySortOrder = newValue }
            if isGrocery { grocerySortOrder = newValue }
            if isUtensil { utensilSortOrder = newValue }
        }
    }

    // MARK: - Computed Properties

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
        if isPantry, let formattedExpirationDate {
            text += " validade \(formattedExpirationDate)"
        }
        if isGrocery {
            if isChecked { text += " ✓" }
            if isFixed { text += " 📌" }
        }
        return text
    }

    /// Which list flags are active.
    var activeFlags: [ItemListType] {
        var flags: [ItemListType] = []
        if isPantry { flags.append(.pantry) }
        if isGrocery { flags.append(.grocery) }
        if isUtensil { flags.append(.utensil) }
        return flags
    }
}

extension UnifiedItem {
    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    static func hasExactNameMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedName(lhs)
        let right = normalizedName(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    static func existingItem(
        named name: String,
        in items: [UnifiedItem],
        excluding excludedID: UUID? = nil
    ) -> UnifiedItem? {
        let normalized = normalizedName(name)
        guard !normalized.isEmpty else { return nil }

        return items.first { item in
            if let excludedID, item.id == excludedID {
                return false
            }
            return normalizedName(item.name) == normalized
        }
    }
}
