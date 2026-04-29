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
            seedPantryItems(context: context)
            seedGroceryItems(context: context)
            seedRecipes(context: context)
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

    // MARK: - Pantry Items

    private static func seedPantryItems(context: ModelContext) {
        let items: [(String, String, String?)] = [
            (localizedSeedItemName(fileName: "banana.png", fallbackName: "Banana"), "Frutas", "banana.png"),
            (localizedSeedItemName(fileName: "rice.png", fallbackName: "Arroz"), "Grãos, Massas e Cereais", "rice.png"),
            (localizedSeedItemName(fileName: "milk.png", fallbackName: "Leite"), "Laticínios e Ovos", "milk.png"),
        ]
        for (name, category, icon) in items {
            let item = UnifiedItem(name: name, category: category, iconName: icon, isPantry: true)
            context.insert(item)
        }
    }

    // MARK: - Grocery Items

    private static func seedGroceryItems(context: ModelContext) {
        let items: [(String, String, String?, Int)] = [
            (localizedSeedItemName(fileName: "tomato.png", fallbackName: "Tomate"), "Verduras e Legumes", "tomato.png", 0),
            (localizedSeedItemName(fileName: "chicken.png", fallbackName: "Frango"), "Carnes e Aves", "chicken.png", 1),
            (localizedSeedItemName(fileName: "olive-oil.png", fallbackName: "Azeite"), "Outros", "olive-oil.png", 2),
        ]
        for (name, category, icon, order) in items {
            let item = UnifiedItem(name: name, category: category, iconName: icon, isGrocery: true, grocerySortOrder: order)
            context.insert(item)
        }
    }

    // MARK: - Recipes

    private static func seedRecipes(context: ModelContext) {
        // 1 — Panqueca Americana
        let pancake = Recipe(
            name: String(localized: "Panqueca Americana"),
            descriptionText: String(localized: "Panquecas fofas e douradas, perfeitas para o café da manhã."),
            category: "Café da manhã",
            tags: [String(localized: "doce"), String(localized: "café da manhã"), String(localized: "rápido")],
            prepTime: 10,
            cookTime: 15,
            servings: 4,
            calories: 320,
            difficulty: .easy
        )
        context.insert(pancake)

        let pancakeIngredients: [(String, Double?, String, String?, Int)] = [
            (String(localized: "Farinha de trigo"), 2, String(localized: "xícaras"), "flour.png", 0),
            (String(localized: "Leite"), 1.5, String(localized: "xícaras"), "milk.png", 1),
            (String(localized: "Ovos"), 2, "", "egg.png", 2),
            (String(localized: "Açúcar"), 3, String(localized: "colheres de sopa"), "sugar.png", 3),
            (String(localized: "Fermento em pó"), 2, String(localized: "colheres de chá"), nil, 4),
            (String(localized: "Manteiga"), 2, String(localized: "colheres de sopa"), "butter.png", 5),
        ]
        for (name, qty, unit, icon, order) in pancakeIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = pancake
            context.insert(ing)
        }

        let pancakeSteps = [
            String(localized: "Misture a farinha, o açúcar e o fermento em uma tigela grande."),
            String(localized: "Em outra tigela, bata os ovos com o leite e a manteiga derretida."),
            String(localized: "Combine os ingredientes líquidos com os secos, mexendo até formar uma massa homogênea."),
            String(localized: "Aqueça uma frigideira antiaderente em fogo médio."),
            String(localized: "Despeje uma concha de massa e cozinhe até formar bolhas. Vire e cozinhe o outro lado."),
            String(localized: "Sirva com mel, frutas ou manteiga."),
        ]
        for (index, instruction) in pancakeSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = pancake
            context.insert(step)
        }

        // 2 — Salada Caesar
        let salad = Recipe(
            name: String(localized: "Salada Caesar"),
            descriptionText: String(localized: "Salada clássica com alface crocante, croutons e molho caesar cremoso."),
            category: "Almoço",
            tags: [String(localized: "saudável"), String(localized: "salada"), String(localized: "leve")],
            prepTime: 15,
            cookTime: 0,
            servings: 2,
            calories: 280,
            difficulty: .easy
        )
        context.insert(salad)

        let saladIngredients: [(String, Double?, String, String?, Int)] = [
            (String(localized: "Alface romana"), 1, String(localized: "pé"), "lettuce.png", 0),
            (String(localized: "Croutons"), 1, String(localized: "xícara"), "bread.png", 1),
            (String(localized: "Parmesão ralado"), 50, "g", "cheese.png", 2),
            (String(localized: "Peito de frango grelhado"), 200, "g", "chicken.png", 3),
            (String(localized: "Molho caesar"), 4, String(localized: "colheres de sopa"), nil, 4),
        ]
        for (name, qty, unit, icon, order) in saladIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = salad
            context.insert(ing)
        }

        let saladSteps = [
            String(localized: "Lave e rasgue as folhas de alface em pedaços."),
            String(localized: "Grelhe o peito de frango temperado e corte em tiras."),
            String(localized: "Em uma tigela grande, combine a alface, croutons e frango."),
            String(localized: "Regue com o molho caesar e polvilhe o parmesão."),
            String(localized: "Misture delicadamente e sirva."),
        ]
        for (index, instruction) in saladSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = salad
            context.insert(step)
        }

        // 3 — Brigadeiro
        let brigadeiro = Recipe(
            name: String(localized: "Brigadeiro"),
            descriptionText: String(localized: "O doce brasileiro mais amado — cremoso e irresistível."),
            category: "Sobremesa",
            tags: [String(localized: "doce"), String(localized: "sobremesa"), String(localized: "brasileiro"), String(localized: "chocolate")],
            prepTime: 5,
            cookTime: 15,
            servings: 20,
            calories: 45,
            difficulty: .easy
        )
        context.insert(brigadeiro)

        let brigadeiroIngredients: [(String, Double?, String, String?, Int)] = [
            (String(localized: "Leite condensado"), 1, String(localized: "lata (395g)"), "milk.png", 0),
            (String(localized: "Achocolatado em pó"), 3, String(localized: "colheres de sopa"), "chocolate.png", 1),
            (String(localized: "Manteiga"), 1, String(localized: "colher de sopa"), "butter.png", 2),
            (String(localized: "Granulado de chocolate"), nil, String(localized: "a gosto"), "chocolate.png", 3),
        ]
        for (name, qty, unit, icon, order) in brigadeiroIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = brigadeiro
            context.insert(ing)
        }

        let brigadeiroSteps = [
            String(localized: "Em uma panela, misture o leite condensado, o achocolatado e a manteiga."),
            String(localized: "Cozinhe em fogo médio, mexendo sem parar, até a massa desgrudar do fundo da panela."),
            String(localized: "Transfira para um prato untado e deixe esfriar."),
            String(localized: "Com as mãos untadas, enrole pequenas bolinhas."),
            String(localized: "Passe no granulado de chocolate e coloque em forminhas."),
        ]
        for (index, instruction) in brigadeiroSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = brigadeiro
            context.insert(step)
        }
    }

    private static func localizedSeedItemName(fileName: String, fallbackName: String) -> String {
        ItemDatabase.shared.entry(forFilename: fileName)?
            .preferredTitle(localization: .current())
            ?? NSLocalizedString(fallbackName, comment: "")
    }
}
