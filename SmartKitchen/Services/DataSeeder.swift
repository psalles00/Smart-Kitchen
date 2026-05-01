import Foundation
import SwiftData

/// Seeds the database with demo data on first launch.
struct DataSeeder {
    static let pantryCategoryDefinitions: [CategorySeedDefinition] = [
        CategorySeedDefinition(name: "Frutas", iconName: "apple.png", localizedNames: ["en": "Fruits"]),
        CategorySeedDefinition(name: "Verduras e Legumes", iconName: "broccoli.png", localizedNames: ["en": "Vegetables & Greens"]),
        CategorySeedDefinition(name: "Carnes e Aves", iconName: "chicken-raw.png", localizedNames: ["en": "Meat & Poultry"]),
        CategorySeedDefinition(name: "Peixes e Frutos do Mar", iconName: "fish.png", localizedNames: ["en": "Fish & Seafood"]),
        CategorySeedDefinition(name: "Laticínios e Ovos", iconName: "milk.png", localizedNames: ["en": "Dairy & Eggs"]),
        CategorySeedDefinition(name: "Padaria", iconName: "bread-white.png", localizedNames: ["en": "Bakery"]),
        CategorySeedDefinition(name: "Grãos, Massas e Cereais", iconName: "rice.png", localizedNames: ["en": "Grains, Pasta & Cereals"]),
        CategorySeedDefinition(name: "Bebidas", iconName: "water-bottle.png", localizedNames: ["en": "Beverages"]),
        CategorySeedDefinition(name: "Temperos e Condimentos", iconName: "salt.png", localizedNames: ["en": "Seasonings & Condiments"]),
        CategorySeedDefinition(name: "Enlatados e Conservas", iconName: "canned-tuna.png", localizedNames: ["en": "Canned & Preserved Goods"]),
        CategorySeedDefinition(name: "Doces e Sobremesas", iconName: "cake.png", localizedNames: ["en": "Desserts & Sweets"]),
        CategorySeedDefinition(name: "Snacks e Petiscos", iconName: "chips.png", localizedNames: ["en": "Snacks & Bites"]),
        CategorySeedDefinition(name: "Pratos Prontos", iconName: "lunch-box.png", localizedNames: ["en": "Ready Meals"]),
        CategorySeedDefinition(name: "Limpeza e Higiene", iconName: "dish-soap.png", localizedNames: ["en": "Cleaning & Hygiene"]),
        CategorySeedDefinition(name: "Utensílios de Cozinha", iconName: "frying-pan.png", localizedNames: ["en": "Kitchen Tools"]),
        CategorySeedDefinition(name: "Eletrodomésticos", iconName: "blender.png", localizedNames: ["en": "Appliances"]),
        CategorySeedDefinition(name: "Saúde e Bem-estar", iconName: "healthy-food.png", localizedNames: ["en": "Health & Wellness"]),
        CategorySeedDefinition(name: "Outros", iconName: nil, localizedNames: ["en": "Other"]),
    ]

    static let recipeCategoryDefinitions: [CategorySeedDefinition] = [
        CategorySeedDefinition(name: "Café da manhã", iconName: "pancakes.png", localizedNames: ["en": "Breakfast"]),
        CategorySeedDefinition(name: "Almoço", iconName: "lunch-box.png", localizedNames: ["en": "Lunch"]),
        CategorySeedDefinition(name: "Jantar", iconName: "dinner.png", localizedNames: ["en": "Dinner"]),
        CategorySeedDefinition(name: "Lanche", iconName: "sandwich.png", localizedNames: ["en": "Snack"]),
        CategorySeedDefinition(name: "Sobremesa", iconName: "cake.png", localizedNames: ["en": "Dessert"]),
        CategorySeedDefinition(name: "Bebida", iconName: "smoothie.png", localizedNames: ["en": "Drink"]),
        CategorySeedDefinition(name: "Outros", iconName: "recipe-card.png", localizedNames: ["en": "Other"]),
    ]

    static let utensilCategoryDefinitions: [CategorySeedDefinition] = [
        CategorySeedDefinition(name: "Utensílios de Cozinha", iconName: "frying-pan.png", localizedNames: ["en": "Kitchen Tools"]),
        CategorySeedDefinition(name: "Eletrodomésticos", iconName: "blender.png", localizedNames: ["en": "Appliances"]),
        CategorySeedDefinition(name: "Outros", iconName: nil, localizedNames: ["en": "Other"]),
    ]

    private static let legacyPantryCategoryMapping: [String: String] = [
        "Vegetais": "Verduras e Legumes",
        "Carnes": "Carnes e Aves",
        "Laticínios": "Laticínios e Ovos",
        "Grãos": "Grãos, Massas e Cereais",
    ]

    private static let legacyUtensilCategoryMapping: [String: String] = [
        "Panelas": "Utensílios de Cozinha",
        "Talheres": "Utensílios de Cozinha",
        "Utensílios de preparo": "Utensílios de Cozinha",
    ]

    static func defaultDefinitions(for type: CategoryType) -> [CategorySeedDefinition] {
        switch type.canonicalType {
        case .pantry, .grocery:
            pantryCategoryDefinitions
        case .recipe:
            recipeCategoryDefinitions
        case .utensil:
            utensilCategoryDefinitions
        }
    }

    static func seedIfNeeded(context: ModelContext) {
        // Use a local flag to prevent re-seeding when CloudKit sync
        // delivers data from another device before local queries resolve.
        let hasSeededKey = "SmartKitchen.hasSeeded"

        // Also check if settings already exist (e.g. synced from another device)
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let existing = (try? context.fetch(settingsDescriptor))?.first
        let hasSeeded = UserDefaults.standard.bool(forKey: hasSeededKey)

        // Also check if synced data already exists (another device may have
        // pushed items before AppSettings arrived via CloudKit).
        let hasSyncedData: Bool = {
            var fd = FetchDescriptor<UnifiedItem>()
            fd.fetchLimit = 1
            return (try? !context.fetch(fd).isEmpty) ?? false
        }()

        if existing == nil, !hasSeeded, !hasSyncedData {
            let settings = AppSettings()
            context.insert(settings)

            seedCategories(context: context)
            // NOTE: As of the new first-launch onboarding, we no longer seed
            // demo pantry/grocery items or sample recipes — the user picks
            // their own initial selection during the onboarding flow. Only
            // categories are seeded here because the rest of the app needs
            // them for classification and grouping.
        }

        synchronizeCategories(context: context)

        try? context.save()
        UserDefaults.standard.set(true, forKey: hasSeededKey)
    }

    // MARK: - Categories

    private static func seedCategories(context: ModelContext) {
        insertCategories(pantryCategoryDefinitions, type: .pantry, context: context)
        insertCategories(recipeCategoryDefinitions, type: .recipe, context: context)
        insertCategories(utensilCategoryDefinitions, type: .utensil, context: context)
    }

    private static func insertCategories(
        _ definitions: [CategorySeedDefinition],
        type: CategoryType,
        context: ModelContext
    ) {
        for (order, definition) in definitions.enumerated() {
            let category = Category(
                name: definition.name,
                type: type,
                iconName: definition.iconName,
                sortOrder: order
            )
            context.insert(category)
        }
    }

    private static func synchronizeCategories(context: ModelContext) {
        synchronizeCategoryDefinitions(pantryCategoryDefinitions, type: .pantry, context: context)
        synchronizeCategoryDefinitions(recipeCategoryDefinitions, type: .recipe, context: context)
        synchronizeCategoryDefinitions(utensilCategoryDefinitions, type: .utensil, context: context)
        migrateLegacyItemCategories(context: context)
        removeLegacyUtensilCategories(context: context)
    }

    private static func synchronizeCategoryDefinitions(
        _ definitions: [CategorySeedDefinition],
        type: CategoryType,
        context: ModelContext
    ) {
        let resolvedType = type.canonicalType
        let existing = CategoryMutationService.fetchCategories(of: resolvedType, context: context)
        let deletedDefaultNames = CategoryMutationService.fetchDeletedDefaultNames(of: resolvedType, context: context)
        var nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1

        for definition in definitions {
            if let category = existing.first(where: { sameCategoryName($0.name, definition.name) }) {
                category.name = definition.name
                category.iconName = definition.iconName
            } else if !deletedDefaultNames.contains(CategoryMutationService.normalizedKey(for: definition.name)) {
                context.insert(
                    Category(
                        name: definition.name,
                        type: resolvedType,
                        iconName: definition.iconName,
                        sortOrder: nextSortOrder
                    )
                )
                nextSortOrder += 1
            }
        }
    }

    private static func migrateLegacyItemCategories(context: ModelContext) {
        migratePantryCategories(context: context)
        migrateGroceryCategories(context: context)
        migrateUtensilCategories(context: context)
    }

    private static func migratePantryCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<UnifiedItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items where item.isPantry {
            if let replacement = legacyPantryCategoryMapping[item.category] {
                item.category = replacement
            }
        }
    }

    private static func migrateGroceryCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<UnifiedItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items where item.isGrocery {
            if let replacement = legacyPantryCategoryMapping[item.category] {
                item.category = replacement
            }
        }
    }

    private static func migrateUtensilCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<UnifiedItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items where item.isUtensil {
            if let replacement = legacyUtensilCategoryMapping[item.category] {
                item.category = replacement
            }
        }
    }

    private static func removeLegacyUtensilCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existing = (try? context.fetch(descriptor)) ?? []
        for category in existing
        where category.type == .utensil && legacyUtensilCategoryMapping.keys.contains(category.name) {
            context.delete(category)
        }
    }

    private static func sameCategoryName(_ lhs: String, _ rhs: String) -> Bool {
        CategoryMutationService.matchesName(lhs, rhs)
    }

}
