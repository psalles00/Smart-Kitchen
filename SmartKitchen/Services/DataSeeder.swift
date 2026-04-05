import Foundation
import SwiftData

/// Seeds the database with demo data on first launch.
struct DataSeeder {
    private static let pantryCategoryDefinitions: [(name: String, iconName: String?)] = [
        ("Frutas", "apple.png"),
        ("Verduras e Legumes", "broccoli.png"),
        ("Carnes e Aves", "chicken-raw.png"),
        ("Peixes e Frutos do Mar", "fish.png"),
        ("Laticínios e Ovos", "milk.png"),
        ("Padaria", "bread-white.png"),
        ("Grãos, Massas e Cereais", "rice.png"),
        ("Bebidas", "water-bottle.png"),
        ("Temperos e Condimentos", "salt.png"),
        ("Enlatados e Conservas", "canned-tuna.png"),
        ("Doces e Sobremesas", "cake.png"),
        ("Snacks e Petiscos", "chips.png"),
        ("Pratos Prontos", "lunch-box.png"),
        ("Limpeza e Higiene", "dish-soap.png"),
        ("Utensílios de Cozinha", "frying-pan.png"),
        ("Eletrodomésticos", "blender.png"),
        ("Saúde e Bem-estar", "healthy-food.png"),
        ("Outros", nil),
    ]

    private static let recipeCategoryDefinitions: [(name: String, iconName: String?)] = [
        ("Café da manhã", "pancakes.png"),
        ("Almoço", "lunch-box.png"),
        ("Jantar", "dinner.png"),
        ("Lanche", "sandwich.png"),
        ("Sobremesa", "cake.png"),
        ("Bebida", "smoothie.png"),
        ("Outros", nil),
    ]

    private static let utensilCategoryDefinitions: [(name: String, iconName: String?)] = [
        ("Utensílios de Cozinha", "frying-pan.png"),
        ("Eletrodomésticos", "blender.png"),
        ("Outros", nil),
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
            var fd = FetchDescriptor<PantryItem>()
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
        _ definitions: [(name: String, iconName: String?)],
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
        _ definitions: [(name: String, iconName: String?)],
        type: CategoryType,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<Category>()
        let existing = ((try? context.fetch(descriptor)) ?? []).filter { $0.type == type }

        for (order, definition) in definitions.enumerated() {
            if let category = existing.first(where: { sameCategoryName($0.name, definition.name) }) {
                category.name = definition.name
                category.iconName = definition.iconName
                category.sortOrder = order
            } else {
                context.insert(
                    Category(
                        name: definition.name,
                        type: type,
                        iconName: definition.iconName,
                        sortOrder: order
                    )
                )
            }
        }
    }

    private static func migrateLegacyItemCategories(context: ModelContext) {
        migratePantryCategories(context: context)
        migrateGroceryCategories(context: context)
        migrateUtensilCategories(context: context)
    }

    private static func migratePantryCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<PantryItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            if let replacement = legacyPantryCategoryMapping[item.category] {
                item.category = replacement
            }
        }
    }

    private static func migrateGroceryCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<GroceryItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            if let replacement = legacyPantryCategoryMapping[item.category] {
                item.category = replacement
            }
        }
    }

    private static func migrateUtensilCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<UtensilItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
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
        lhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ==
        rhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    // MARK: - Pantry Items

    private static func seedPantryItems(context: ModelContext) {
        let items: [(String, String, String?)] = [
            ("Banana", "Frutas", "banana.png"),
            ("Arroz", "Grãos", "rice.png"),
            ("Leite", "Laticínios", "milk.png"),
        ]
        for (name, category, icon) in items {
            let item = PantryItem(name: name, category: category, iconName: icon)
            context.insert(item)
        }
    }

    // MARK: - Grocery Items

    private static func seedGroceryItems(context: ModelContext) {
        let items: [(String, String, String?, Int)] = [
            ("Tomate", "Vegetais", "tomato.png", 0),
            ("Frango", "Carnes", "chicken.png", 1),
            ("Azeite", "Outros", "olive-oil.png", 2),
        ]
        for (name, category, icon, order) in items {
            let item = GroceryItem(name: name, category: category, iconName: icon, sortOrder: order)
            context.insert(item)
        }
    }

    // MARK: - Recipes

    private static func seedRecipes(context: ModelContext) {
        // 1 — Panqueca Americana
        let pancake = Recipe(
            name: "Panqueca Americana",
            descriptionText: "Panquecas fofas e douradas, perfeitas para o café da manhã.",
            category: "Café da manhã",
            tags: ["doce", "café da manhã", "rápido"],
            prepTime: 10,
            cookTime: 15,
            servings: 4,
            calories: 320,
            difficulty: .easy
        )
        context.insert(pancake)

        let pancakeIngredients: [(String, Double?, String, String?, Int)] = [
            ("Farinha de trigo", 2, "xícaras", "flour.png", 0),
            ("Leite", 1.5, "xícaras", "milk.png", 1),
            ("Ovos", 2, "", "egg.png", 2),
            ("Açúcar", 3, "colheres de sopa", "sugar.png", 3),
            ("Fermento em pó", 2, "colheres de chá", nil, 4),
            ("Manteiga", 2, "colheres de sopa", "butter.png", 5),
        ]
        for (name, qty, unit, icon, order) in pancakeIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = pancake
            context.insert(ing)
        }

        let pancakeSteps = [
            "Misture a farinha, o açúcar e o fermento em uma tigela grande.",
            "Em outra tigela, bata os ovos com o leite e a manteiga derretida.",
            "Combine os ingredientes líquidos com os secos, mexendo até formar uma massa homogênea.",
            "Aqueça uma frigideira antiaderente em fogo médio.",
            "Despeje uma concha de massa e cozinhe até formar bolhas. Vire e cozinhe o outro lado.",
            "Sirva com mel, frutas ou manteiga.",
        ]
        for (index, instruction) in pancakeSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = pancake
            context.insert(step)
        }

        // 2 — Salada Caesar
        let salad = Recipe(
            name: "Salada Caesar",
            descriptionText: "Salada clássica com alface crocante, croutons e molho caesar cremoso.",
            category: "Almoço",
            tags: ["saudável", "salada", "leve"],
            prepTime: 15,
            cookTime: 0,
            servings: 2,
            calories: 280,
            difficulty: .easy
        )
        context.insert(salad)

        let saladIngredients: [(String, Double?, String, String?, Int)] = [
            ("Alface romana", 1, "pé", "lettuce.png", 0),
            ("Croutons", 1, "xícara", "bread.png", 1),
            ("Parmesão ralado", 50, "g", "cheese.png", 2),
            ("Peito de frango grelhado", 200, "g", "chicken.png", 3),
            ("Molho caesar", 4, "colheres de sopa", nil, 4),
        ]
        for (name, qty, unit, icon, order) in saladIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = salad
            context.insert(ing)
        }

        let saladSteps = [
            "Lave e rasgue as folhas de alface em pedaços.",
            "Grelhe o peito de frango temperado e corte em tiras.",
            "Em uma tigela grande, combine a alface, croutons e frango.",
            "Regue com o molho caesar e polvilhe o parmesão.",
            "Misture delicadamente e sirva.",
        ]
        for (index, instruction) in saladSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = salad
            context.insert(step)
        }

        // 3 — Brigadeiro
        let brigadeiro = Recipe(
            name: "Brigadeiro",
            descriptionText: "O doce brasileiro mais amado — cremoso e irresistível.",
            category: "Sobremesa",
            tags: ["doce", "sobremesa", "brasileiro", "chocolate"],
            prepTime: 5,
            cookTime: 15,
            servings: 20,
            calories: 45,
            difficulty: .easy
        )
        context.insert(brigadeiro)

        let brigadeiroIngredients: [(String, Double?, String, String?, Int)] = [
            ("Leite condensado", 1, "lata (395g)", "milk.png", 0),
            ("Achocolatado em pó", 3, "colheres de sopa", "chocolate.png", 1),
            ("Manteiga", 1, "colher de sopa", "butter.png", 2),
            ("Granulado de chocolate", nil, "a gosto", "chocolate.png", 3),
        ]
        for (name, qty, unit, icon, order) in brigadeiroIngredients {
            let ing = RecipeIngredient(name: name, quantity: qty, unit: unit, iconName: icon, sortOrder: order)
            ing.recipe = brigadeiro
            context.insert(ing)
        }

        let brigadeiroSteps = [
            "Em uma panela, misture o leite condensado, o achocolatado e a manteiga.",
            "Cozinhe em fogo médio, mexendo sem parar, até a massa desgrudar do fundo da panela.",
            "Transfira para um prato untado e deixe esfriar.",
            "Com as mãos untadas, enrole pequenas bolinhas.",
            "Passe no granulado de chocolate e coloque em forminhas.",
        ]
        for (index, instruction) in brigadeiroSteps.enumerated() {
            let step = RecipeStep(order: index + 1, instruction: instruction)
            step.recipe = brigadeiro
            context.insert(step)
        }
    }
}
