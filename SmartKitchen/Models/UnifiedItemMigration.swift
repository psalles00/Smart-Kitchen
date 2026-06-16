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
        // Always run a reconciliation pass: even when the "migration completed" flag is set,
        // legacy PantryItem/GroceryItem/UtensilItem rows can still exist (e.g. after a store
        // split migration that copied them forward). The reconciliation pass inserts any
        // missing UnifiedItem and only deletes legacy rows that were successfully reconciled.
        do {
            try reconcileLegacyItemsIntoUnified(context: context)
            let mergedDuplicates = try UnifiedItem.mergeDuplicateNames(in: context)
            if mergedDuplicates > 0 {
                try context.save()
                NSLog("[Migration] Merged %d duplicate unified item(s) by name", mergedDuplicates)
            }
        } catch {
            NSLog("[Migration] Unified item reconciliation failed: %@", error.localizedDescription)
        }

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

    /// Idempotent reconciliation for installs where legacy records survived alongside
    /// a UnifiedItem store (typical after a store-split or device restore).
    ///
    /// - Preserves every UnifiedItem already present (never touches them).
    /// - For each legacy row missing a UnifiedItem counterpart, creates one with
    ///   the same id/name/metadata and the appropriate isPantry/isGrocery/isUtensil flag.
    /// - Legacy rows that have a surviving UnifiedItem counterpart (by id OR normalized
    ///   name+role) are deleted to prevent future duplicate reconciliation loops.
    private static func reconcileLegacyItemsIntoUnified(context: ModelContext) throws {
        let pantryItems = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let groceryItems = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        let utensilItems = (try? context.fetch(FetchDescriptor<UtensilItem>())) ?? []

        if pantryItems.isEmpty && groceryItems.isEmpty && utensilItems.isEmpty { return }

        let existing = (try? context.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        func normalized(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        }

        let pantryByName = Dictionary(
            existing.filter { $0.isPantry }.map { (normalized($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let groceryByName = Dictionary(
            existing.filter { $0.isGrocery }.map { (normalized($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let utensilByName = Dictionary(
            existing.filter { $0.isUtensil }.map { (normalized($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var inserted = 0
        var deletedLegacy = 0

        // --- Pantry ---
        for legacy in pantryItems {
            let key = normalized(legacy.name)
            if existingByID[legacy.id] != nil || pantryByName[key] != nil {
                context.delete(legacy); deletedLegacy += 1
                continue
            }
            let unified = UnifiedItem(
                name: legacy.name,
                descriptionText: legacy.descriptionText,
                imageData: legacy.imageData,
                category: legacy.category,
                quantity: legacy.quantity,
                unit: legacy.unit,
                iconName: legacy.iconName,
                isPantry: true,
                isGrocery: false,
                isUtensil: false,
                pantrySortOrder: legacy.sortOrder,
                grocerySortOrder: 0,
                isLinkedToGrocery: legacy.isLinkedToGrocery,
                expirationDate: legacy.expirationDate,
                defaultExpiryDays: legacy.defaultExpiryDays,
                isChecked: false,
                isFixed: false,
                linkedPantryItemId: nil
            )
            unified.id = legacy.id
            unified.addedAt = legacy.addedAt
            context.insert(unified)
            context.delete(legacy)
            inserted += 1
            deletedLegacy += 1
        }

        // --- Grocery ---
        for legacy in groceryItems {
            let key = normalized(legacy.name)
            // If a UnifiedItem with the same name already represents a pantry row, add grocery role.
            if let matchPantry = pantryByName[key] {
                if !matchPantry.isGrocery {
                    matchPantry.isGrocery = true
                    matchPantry.grocerySortOrder = legacy.sortOrder
                    matchPantry.isChecked = legacy.isChecked
                    matchPantry.isFixed = legacy.isFixed
                }
                context.delete(legacy); deletedLegacy += 1
                continue
            }
            if existingByID[legacy.id] != nil || groceryByName[key] != nil {
                context.delete(legacy); deletedLegacy += 1
                continue
            }
            let unified = UnifiedItem(
                name: legacy.name,
                descriptionText: legacy.descriptionText,
                imageData: legacy.imageData,
                category: legacy.category,
                quantity: legacy.quantity,
                unit: legacy.unit,
                iconName: legacy.iconName,
                isPantry: false,
                isGrocery: true,
                isUtensil: false,
                grocerySortOrder: legacy.sortOrder,
                defaultExpiryDays: legacy.defaultExpiryDays,
                isChecked: legacy.isChecked,
                isFixed: legacy.isFixed,
                linkedPantryItemId: legacy.linkedPantryItemId
            )
            unified.id = legacy.id
            unified.addedAt = legacy.addedAt
            context.insert(unified)
            context.delete(legacy)
            inserted += 1
            deletedLegacy += 1
        }

        // --- Utensil ---
        for legacy in utensilItems {
            let key = normalized(legacy.name)
            if existingByID[legacy.id] != nil || utensilByName[key] != nil {
                context.delete(legacy); deletedLegacy += 1
                continue
            }
            let unified = UnifiedItem(
                name: legacy.name,
                descriptionText: legacy.descriptionText,
                imageData: legacy.imageData,
                category: legacy.category,
                iconName: legacy.iconName,
                isUtensil: true,
                utensilSortOrder: legacy.sortOrder
            )
            unified.id = legacy.id
            unified.addedAt = legacy.addedAt
            context.insert(unified)
            context.delete(legacy)
            inserted += 1
            deletedLegacy += 1
        }

        if inserted > 0 || deletedLegacy > 0 {
            try context.save()
            NSLog("[Migration] Reconciled legacy items -> unified (inserted: %d, legacy removed: %d)",
                  inserted, deletedLegacy)
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
