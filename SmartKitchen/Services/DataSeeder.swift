import Foundation
import SwiftData

/// Seeds the database with demo data on first launch.
struct DataSeeder {

    static func seedIfNeeded(context: ModelContext) {
        // Check if already seeded by looking for any settings object
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let existing = (try? context.fetch(settingsDescriptor))?.first
        if existing != nil { return }

        // Create default settings
        let settings = AppSettings()
        context.insert(settings)

        // Seed categories
        seedCategories(context: context)

        // Seed pantry items (3)
        seedPantryItems(context: context)

        // Seed grocery items (3)
        seedGroceryItems(context: context)

        // Seed recipes (3)
        seedRecipes(context: context)

        try? context.save()
    }

    // MARK: - Categories

    private static func seedCategories(context: ModelContext) {
        let pantryCategories = [
            ("Frutas", "apple.png", 0),
            ("Vegetais", "broccoli.png", 1),
            ("Carnes", "steak.png", 2),
            ("Laticínios", "milk.png", 3),
            ("Grãos", "rice.png", 4),
            ("Bebidas", "water-bottle.png", 5),
            ("Temperos", "salt.png", 6),
            ("Outros", nil as String?, 7),
        ]

        for (name, icon, order) in pantryCategories {
            let cat = Category(name: name, type: .pantry, iconName: icon, sortOrder: order)
            context.insert(cat)
        }

        let recipeCategories = [
            ("Café da manhã", "pancakes.png", 0),
            ("Almoço", "lunch-box.png", 1),
            ("Jantar", "dinner.png", 2),
            ("Lanche", "sandwich.png", 3),
            ("Sobremesa", "cake.png", 4),
            ("Bebida", "smoothie.png", 5),
            ("Outros", nil as String?, 6),
        ]

        for (name, icon, order) in recipeCategories {
            let cat = Category(name: name, type: .recipe, iconName: icon, sortOrder: order)
            context.insert(cat)
        }
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
