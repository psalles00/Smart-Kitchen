import Foundation
import SwiftData

/// Performs the one-time migration from separate PantryItem/GroceryItem/UtensilItem
/// models to the unified UnifiedItem model.
///
/// SwiftData with CloudKit only supports lightweight (additive) migration,
/// so we keep the old model classes in the schema and migrate data manually.
struct UnifiedItemMigration {
    private static let migrationKey = "SmartKitchen.unifiedItemMigrationCompleted"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        do {
            try performMigration(context: context)
            UserDefaults.standard.set(true, forKey: migrationKey)
            NSLog("[Migration] Unified item migration completed successfully")
        } catch {
            NSLog("[Migration] Unified item migration failed: %@", error.localizedDescription)
            // Don't set the flag so it retries next launch
        }
    }

    private static func performMigration(context: ModelContext) throws {
        // Check if there's any data to migrate
        let pantryItems = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let groceryItems = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        let utensilItems = (try? context.fetch(FetchDescriptor<UtensilItem>())) ?? []

        // If no old items exist, check if UnifiedItem already has data (fresh install or already migrated)
        if pantryItems.isEmpty && groceryItems.isEmpty && utensilItems.isEmpty {
            return
        }

        // Build a map of grocery items by normalized name for cross-referencing
        let normalizedGroceryNames: [String: GroceryItem] = Dictionary(
            groceryItems.map { item in
                let key = item.name
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
                return (key, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Track pantry item UUIDs that have been migrated (for grocery linking)
        var pantryIDMap: [UUID: UUID] = [:] // old pantry UUID -> new UnifiedItem UUID

        // 1. Migrate pantry items
        for item in pantryItems {
            let normalizedName = item.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()

            // Check if a grocery item with the same name exists
            let matchingGrocery = normalizedGroceryNames[normalizedName]

            let unified = UnifiedItem(
                name: item.name,
                descriptionText: item.descriptionText,
                imageData: item.imageData,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                iconName: item.iconName,
                isPantry: true,
                isGrocery: matchingGrocery != nil,
                isUtensil: false,
                pantrySortOrder: item.sortOrder,
                grocerySortOrder: matchingGrocery?.sortOrder ?? 0,
                isLinkedToGrocery: item.isLinkedToGrocery,
                expirationDate: item.expirationDate,
                defaultExpiryDays: item.defaultExpiryDays,
                isChecked: matchingGrocery?.isChecked ?? false,
                isFixed: matchingGrocery?.isFixed ?? false,
                linkedPantryItemId: nil
            )
            unified.id = item.id
            unified.addedAt = item.addedAt

            // If grocery match exists, merge its default expiry days if pantry doesn't have one
            if let grocery = matchingGrocery, unified.defaultExpiryDays == nil {
                unified.defaultExpiryDays = grocery.defaultExpiryDays
            }

            context.insert(unified)
            pantryIDMap[item.id] = unified.id
        }

        // 2. Migrate grocery items that DON'T have a matching pantry item
        let migratedGroceryNames = Set(
            pantryItems.map { $0.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            }
        )

        for item in groceryItems {
            let normalizedName = item.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()

            // Skip if already merged with a pantry item
            if migratedGroceryNames.contains(normalizedName) { continue }

            let unified = UnifiedItem(
                name: item.name,
                descriptionText: item.descriptionText,
                imageData: item.imageData,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                iconName: item.iconName,
                isPantry: false,
                isGrocery: true,
                isUtensil: false,
                grocerySortOrder: item.sortOrder,
                defaultExpiryDays: item.defaultExpiryDays,
                isChecked: item.isChecked,
                isFixed: item.isFixed,
                linkedPantryItemId: item.linkedPantryItemId.flatMap { pantryIDMap[$0] ?? $0 }
            )
            unified.id = item.id
            unified.addedAt = item.addedAt
            context.insert(unified)
        }

        // 3. Migrate utensil items
        for item in utensilItems {
            let unified = UnifiedItem(
                name: item.name,
                descriptionText: item.descriptionText,
                imageData: item.imageData,
                category: item.category,
                iconName: item.iconName,
                isUtensil: true,
                utensilSortOrder: item.sortOrder
            )
            unified.id = item.id
            unified.addedAt = item.addedAt
            context.insert(unified)
        }

        // 4. Save migrated data
        try context.save()

        // 5. Delete old records
        for item in pantryItems { context.delete(item) }
        for item in groceryItems { context.delete(item) }
        for item in utensilItems { context.delete(item) }
        try context.save()
    }
}
