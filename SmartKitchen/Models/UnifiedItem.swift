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

    var localizedCategoryDisplayName: String {
        let categoryType: CategoryType = isUtensil ? .utensil : .pantry
        return CategoryMutationService.localizedDisplayName(for: category, type: categoryType)
    }

    func resolvedIconName(categoryIconName: String? = nil) -> String? {
        iconName
            ?? IconResolver.resolve(name)
            ?? categoryIconName
            ?? CategoryDatabase.shared.entry(for: category)?.iconFileName
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
    @discardableResult
    static func mergeDuplicateNames(in context: ModelContext) throws -> Int {
        let items = try context.fetch(FetchDescriptor<UnifiedItem>())
        return mergeDuplicateNames(in: items, context: context)
    }

    @discardableResult
    static func mergeDuplicateNames(in items: [UnifiedItem], context: ModelContext) -> Int {
        var grouped: [String: [UnifiedItem]] = [:]
        for item in items {
            let key = normalizedName(item.name)
            guard !key.isEmpty else { continue }
            grouped[key, default: []].append(item)
        }

        var deleted = 0
        for duplicates in grouped.values where duplicates.count > 1 {
            let survivor = preferredMergeSurvivor(from: duplicates)
            for duplicate in duplicates where duplicate.id != survivor.id {
                survivor.mergeDetails(from: duplicate)
                relinkItems(from: duplicate.id, to: survivor.id, in: items)
                context.delete(duplicate)
                deleted += 1
            }
        }
        return deleted
    }

    static func containsDuplicateNames(in items: [UnifiedItem]) -> Bool {
        var seen = Set<String>()
        for item in items {
            let key = normalizedName(item.name)
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted { return true }
        }
        return false
    }

    static func mergedExistingItem(
        named name: String,
        in items: [UnifiedItem],
        context: ModelContext,
        excluding excludedID: UUID? = nil
    ) -> UnifiedItem? {
        let normalized = normalizedName(name)
        guard !normalized.isEmpty else { return nil }

        let matches = items.filter { item in
            if let excludedID, item.id == excludedID { return false }
            return normalizedName(item.name) == normalized
        }
        guard !matches.isEmpty else { return nil }

        let survivor = preferredMergeSurvivor(from: matches)
        for duplicate in matches where duplicate.id != survivor.id {
            survivor.mergeDetails(from: duplicate)
            relinkItems(from: duplicate.id, to: survivor.id, in: items)
            context.delete(duplicate)
        }
        return survivor
    }

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

    func mergeDetails(from source: UnifiedItem) {
        let hadPantry = isPantry
        let hadGrocery = isGrocery
        let hadUtensil = isUtensil

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = source.name
        }
        descriptionText = Self.mergedDescription(descriptionText, source.descriptionText)
        if imageData == nil {
            imageData = source.imageData
        }
        if Self.shouldReplaceCategory(category, with: source.category) {
            category = source.category
        }
        if quantity == nil {
            quantity = source.quantity
        }
        if (unit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let sourceUnit = source.unit,
           !sourceUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unit = sourceUnit
        }
        if iconName == nil {
            iconName = source.iconName
        }
        addedAt = min(addedAt, source.addedAt)

        if source.isPantry {
            isPantry = true
            if !hadPantry {
                pantrySortOrder = source.pantrySortOrder
            } else {
                pantrySortOrder = min(pantrySortOrder, source.pantrySortOrder)
            }
            isLinkedToGrocery = isLinkedToGrocery || source.isLinkedToGrocery
            expirationDate = Self.earliestDate(expirationDate, source.expirationDate)
        }

        if source.isGrocery {
            isGrocery = true
            if !hadGrocery {
                grocerySortOrder = source.grocerySortOrder
                isChecked = source.isChecked
            } else {
                grocerySortOrder = min(grocerySortOrder, source.grocerySortOrder)
                isChecked = isChecked && source.isChecked
            }
            isFixed = isFixed || source.isFixed
        }

        if source.isUtensil {
            isUtensil = true
            if !hadUtensil {
                utensilSortOrder = source.utensilSortOrder
            } else {
                utensilSortOrder = min(utensilSortOrder, source.utensilSortOrder)
            }
        }

        defaultExpiryDays = Self.shortestDuration(defaultExpiryDays, source.defaultExpiryDays)
        if linkedPantryItemId == nil {
            linkedPantryItemId = source.linkedPantryItemId
        }
        if linkedPantryItemId == id || linkedPantryItemId == source.id {
            linkedPantryItemId = nil
        }
    }

    private static func preferredMergeSurvivor(from items: [UnifiedItem]) -> UnifiedItem {
        items.max { lhs, rhs in
            let lhsScore = mergeScore(lhs)
            let rhsScore = mergeScore(rhs)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            return lhs.addedAt > rhs.addedAt
        } ?? items[0]
    }

    private static func mergeScore(_ item: UnifiedItem) -> Int {
        var score = item.activeFlags.count * 100
        if !item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 12 }
        if item.imageData != nil { score += 10 }
        if item.quantity != nil { score += 8 }
        if item.unit?.isEmpty == false { score += 6 }
        if item.iconName != nil { score += 5 }
        if !isGenericCategory(item.category) { score += 4 }
        if item.expirationDate != nil { score += 3 }
        if item.defaultExpiryDays != nil { score += 2 }
        if item.isFixed || item.isLinkedToGrocery { score += 1 }
        return score
    }

    private static func relinkItems(from oldID: UUID, to newID: UUID, in items: [UnifiedItem]) {
        for item in items where item.linkedPantryItemId == oldID {
            item.linkedPantryItemId = item.id == newID ? nil : newID
        }
    }

    private static func mergedDescription(_ current: String, _ incoming: String) -> String {
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTrimmed.isEmpty else { return incomingTrimmed }
        guard !incomingTrimmed.isEmpty else { return currentTrimmed }

        var seen = Set<String>()
        var lines: [String] = []
        for value in [currentTrimmed, incomingTrimmed] {
            let key = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard seen.insert(key).inserted else { continue }
            lines.append(value)
        }
        return lines.joined(separator: "\n\n")
    }

    private static func shouldReplaceCategory(_ current: String, with incoming: String) -> Bool {
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty, incomingTrimmed != currentTrimmed else { return false }
        return currentTrimmed.isEmpty || isGenericCategory(currentTrimmed)
    }

    private static func isGenericCategory(_ value: String) -> Bool {
        let normalized = normalizedName(value)
        return normalized.isEmpty || normalized == normalizedName("Outros")
    }

    private static func earliestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (date?, nil), let (nil, date?):
            return date
        case let (left?, right?):
            return min(left, right)
        }
    }

    private static func shortestDuration(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (days?, nil), let (nil, days?):
            return days
        case let (left?, right?):
            return min(left, right)
        }
    }
}
