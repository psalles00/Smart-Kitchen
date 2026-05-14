import Foundation
import SwiftData

/// Defines the OpenAI function-calling tools and executes them against SwiftData.
@MainActor
struct AITools {
    private static let maxDefinitionCount = 24

    // MARK: - Tool Definitions (sent to OpenAI)

    private static let allDefinitions: [[String: Any]] = [
        makeTool(
            name: "search_recipes",
            description: "Search the user's recipes saved in the app by name, category, ingredient, or keyword.",
            parameters: [
                "query": ["type": "string", "description": "Search term (name, category, ingredient, or keyword)"]
            ],
            required: ["query"]
        ),
        makeTool(
            name: "get_recipe",
            description: "Get full details of a specific recipe already saved in the app.",
            parameters: [
                "name": ["type": "string", "description": "Exact or partial recipe name"]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "create_recipe",
            description: "Create a new recipe directly in the app. Use this when the user asks to add, create, save, or register a recipe, even if the request is not related to pantry items.",
            parameters: [
                "name":        ["type": "string", "description": "Recipe name"],
                "description": ["type": "string", "description": "Short description"],
                "category":    ["type": "string", "description": "Category (e.g. Almoço, Jantar, Sobremesa)"],
                "difficulty":  ["type": "string", "description": "Difficulty: Fácil, Médio, or Difícil"],
                "prepTime":    ["type": "integer", "description": "Preparation time in minutes"],
                "cookTime":    ["type": "integer", "description": "Cooking time in minutes"],
                "servings":    ["type": "integer", "description": "Number of servings"],
                "calories":    ["type": "integer", "description": "Approximate calories per serving"],
                "ingredients": [
                    "type": "array",
                    "description": "List of ingredients",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name":     ["type": "string"],
                            "quantity": ["type": "number"],
                            "unit":     ["type": "string"]
                        ],
                        "required": ["name"]
                    ]
                ],
                "steps": [
                    "type": "array",
                    "description": "Ordered cooking steps",
                    "items": ["type": "string"]
                ]
            ],
            required: ["name", "ingredients", "steps"]
        ),
        makeTool(
            name: "update_recipe",
            description: "Update an existing recipe saved in the app, including metadata, ingredients, and steps.",
            parameters: [
                "target_name": ["type": "string", "description": "Current recipe name to update"],
                "name":        ["type": "string", "description": "New recipe name"],
                "description": ["type": "string", "description": "Short description"],
                "category":    ["type": "string", "description": "Category"],
                "difficulty":  ["type": "string", "description": "Difficulty: Fácil, Médio, or Difícil"],
                "prepTime":    ["type": "integer", "description": "Preparation time in minutes"],
                "cookTime":    ["type": "integer", "description": "Cooking time in minutes"],
                "servings":    ["type": "integer", "description": "Number of servings"],
                "calories":    ["type": "integer", "description": "Approximate calories per serving"],
                "ingredients": [
                    "type": "array",
                    "description": "Replacement ingredient list",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name":     ["type": "string"],
                            "quantity": ["type": "number"],
                            "unit":     ["type": "string"]
                        ],
                        "required": ["name"]
                    ]
                ],
                "steps": [
                    "type": "array",
                    "description": "Replacement ordered cooking steps",
                    "items": ["type": "string"]
                ]
            ],
            required: ["target_name"]
        ),
        makeTool(
            name: "delete_recipe",
            description: "Delete an existing recipe from the app by name.",
            parameters: [
                "name": ["type": "string", "description": "Recipe name to delete"]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "get_all_pantry",
            description: "Get all items currently in the user's pantry.",
            parameters: [:],
            required: []
        ),
        makeTool(
            name: "search_pantry",
            description: "Search pantry items by name.",
            parameters: [
                "query": ["type": "string", "description": "Search term"]
            ],
            required: ["query"]
        ),
        makeTool(
            name: "add_pantry_item",
            description: "Add a new item to the pantry.",
            parameters: [
                "name":     ["type": "string", "description": "Item name"],
                "category": ["type": "string", "description": "Category (e.g. Frutas, Vegetais, Carnes)"],
                "quantity": ["type": "number", "description": "Optional quantity"],
                "unit":     ["type": "string", "description": "Optional unit (kg, L, x)"],
                "expirationDate": ["type": "string", "description": "Optional expiration date in YYYY-MM-DD format"]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "remove_pantry_item",
            description: "Remove an item from the pantry by name.",
            parameters: [
                "name": ["type": "string", "description": "Item name to remove"]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "get_all_grocery",
            description: "Get all items on the grocery list.",
            parameters: [:],
            required: []
        ),
        makeTool(
            name: "add_grocery_item",
            description: "Add a new item to the grocery list.",
            parameters: [
                "name":     ["type": "string", "description": "Item name"],
                "category": ["type": "string", "description": "Category"],
                "quantity": ["type": "number", "description": "Optional quantity"],
                "unit":     ["type": "string", "description": "Optional unit"]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "get_categories",
            description: "Get editable categories for pantry, grocery, or recipes.",
            parameters: [
                "type": ["type": "string", "description": "Category type: pantry, grocery, or recipe"]
            ],
            required: []
        ),
        makeTool(
            name: "create_category",
            description: "Create a new category for pantry, grocery, or recipes.",
            parameters: [
                "type": ["type": "string", "description": "Category type: pantry, grocery, or recipe"],
                "name": ["type": "string", "description": "New category name"]
            ],
            required: ["type", "name"]
        ),
        makeTool(
            name: "rename_category",
            description: "Rename an existing category.",
            parameters: [
                "type": ["type": "string", "description": "Category type: pantry, grocery, or recipe"],
                "current_name": ["type": "string", "description": "Current category name"],
                "new_name": ["type": "string", "description": "New category name"]
            ],
            required: ["type", "current_name", "new_name"]
        ),
        makeTool(
            name: "delete_category",
            description: "Delete a category and reassign items to Outros.",
            parameters: [
                "type": ["type": "string", "description": "Category type: pantry, grocery, or recipe"],
                "name": ["type": "string", "description": "Category name to delete"]
            ],
            required: ["type", "name"]
        ),
        makeTool(
            name: "move_category",
            description: "Change a category order position.",
            parameters: [
                "type": ["type": "string", "description": "Category type: pantry, grocery, or recipe"],
                "name": ["type": "string", "description": "Category name"],
                "position": ["type": "integer", "description": "New zero-based position"]
            ],
            required: ["type", "name", "position"]
        ),
        makeTool(
            name: "suggest_recipe",
            description: "Suggest a recipe based on available pantry ingredients or preferences.",
            parameters: [
                "preferences": ["type": "string", "description": "User preferences or dietary notes"],
                "use_pantry":  ["type": "boolean", "description": "Whether to prefer ingredients from the pantry"]
            ],
            required: []
        ),
        makeTool(
            name: "import_recipe_from_url",
            description: "Import a recipe from a web URL (blog, recipe site, social media link). Downloads the page, extracts the recipe (JSON-LD or AI-structured), saves it directly, and returns its name and ID. Use this whenever the user pastes a link and asks to save/import/add the recipe.",
            parameters: [
                "url": ["type": "string", "description": "Full URL (https://...) pointing to the recipe."]
            ],
            required: ["url"]
        ),
        makeTool(
            name: "log_food_manual",
            description: "Register a food entry for the user in the Nutrição tab. Use this when the user describes a meal or food (e.g. 'comi dois ovos mexidos e uma banana'). Estimate calories and macros yourself before calling. Weight must be in grams when provided.",
            parameters: [
                "name":             ["type": "string", "description": "Concise food name in Brazilian Portuguese (e.g. 'Ovos mexidos com banana')."],
                "calories":         ["type": "integer", "description": "Total calories for the meal."],
                "proteinG":         ["type": "number",  "description": "Total protein in grams."],
                "carbsG":           ["type": "number",  "description": "Total carbs in grams."],
                "fatG":             ["type": "number",  "description": "Total fat in grams."],
                "servingSizeGrams": ["type": "number",  "description": "Portion weight in grams (optional)."],
                "mealType":         ["type": "string", "description": "Meal type: breakfast, lunch, dinner, snack, or other."],
                "date":             ["type": "string", "description": "ISO date (YYYY-MM-DD) to log the entry. Defaults to today."],
                "emoji":            ["type": "string", "description": "Single emoji representing the food (optional)."]
            ],
            required: ["name", "calories", "proteinG", "carbsG", "fatG"]
        ),
        makeTool(
            name: "get_nutrition_today",
            description: "Get what the user has eaten today and how it compares to their daily targets (calories, protein, carbs, fat).",
            parameters: [:],
            required: []
        ),
        makeTool(
            name: "get_nutrition_profile",
            description: "Get the user's nutrition profile: body metrics, goals, and computed daily targets. Returns onboarding status when incomplete.",
            parameters: [:],
            required: []
        ),
        makeTool(
            name: "delete_food_entry",
            description: "Delete a food entry registered today (or most recent if the user asks to undo the last log). Matches by name substring.",
            parameters: [
                "name": ["type": "string", "description": "Food name or substring to match. Use empty string to delete the most recent entry."]
            ],
            required: ["name"]
        ),
        makeTool(
            name: "list_weight_entries",
            description: "List the user's weight history (most recent first). Returns id, ISO date, and weight in kilograms for each entry.",
            parameters: [
                "limit": ["type": "integer", "description": "Maximum number of entries to return. Defaults to 30."]
            ],
            required: []
        ),
        makeTool(
            name: "add_weight_entry",
            description: "Register a new body-weight entry for the user. Weight must be in kilograms. The user's nutrition profile is updated when the new entry is the most recent.",
            parameters: [
                "weightKg": ["type": "number", "description": "Body weight in kilograms."],
                "date":     ["type": "string", "description": "ISO date (YYYY-MM-DD) when the measurement was taken. Defaults to today."]
            ],
            required: ["weightKg"]
        ),
        makeTool(
            name: "update_weight_entry",
            description: "Update an existing weight entry. Provide the entry id from list_weight_entries plus the new weightKg and/or date.",
            parameters: [
                "id":       ["type": "string", "description": "Entry UUID returned by list_weight_entries."],
                "weightKg": ["type": "number", "description": "New body weight in kilograms (optional)."],
                "date":     ["type": "string", "description": "New ISO date (YYYY-MM-DD) (optional)."]
            ],
            required: ["id"]
        ),
        makeTool(
            name: "delete_weight_entry",
            description: "Delete a weight entry. Pass the id from list_weight_entries, or omit it to remove the most recent entry.",
            parameters: [
                "id": ["type": "string", "description": "Entry UUID. Omit to delete the most recent entry."]
            ],
            required: []
        )
    ]

    static var definitions: [[String: Any]] {
        capped(allDefinitions)
    }

    static func definitions(excluding excludedToolNames: Set<String>) -> [[String: Any]] {
        guard !excludedToolNames.isEmpty else {
            return capped(allDefinitions)
        }

        return capped(allDefinitions.filter { tool in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                return true
            }

            return !excludedToolNames.contains(name)
        })
    }

    private static func capped(_ definitions: [[String: Any]]) -> [[String: Any]] {
        Array(definitions.prefix(maxDefinitionCount))
    }

    // MARK: - Tool Execution

    /// Execute a tool call and return the result as a string for the AI.
    static func execute(
        _ call: ToolCallRequest,
        context: ModelContext
    ) async -> String {
        switch call.name {
        case "search_recipes":
            return searchRecipes(query: call.arguments["query"] as? String ?? "", context: context)
        case "get_recipe":
            return getRecipe(name: call.arguments["name"] as? String ?? "", context: context)
        case "create_recipe":
            return createRecipe(args: call.arguments, context: context)
        case "update_recipe":
            return updateRecipe(args: call.arguments, context: context)
        case "delete_recipe":
            return deleteRecipe(name: call.arguments["name"] as? String ?? "", context: context)
        case "get_all_pantry":
            return getAllPantry(context: context)
        case "search_pantry":
            return searchPantry(query: call.arguments["query"] as? String ?? "", context: context)
        case "add_pantry_item":
            return addPantryItem(args: call.arguments, context: context)
        case "remove_pantry_item":
            return removePantryItem(name: call.arguments["name"] as? String ?? "", context: context)
        case "get_all_grocery":
            return getAllGrocery(context: context)
        case "add_grocery_item":
            return addGroceryItem(args: call.arguments, context: context)
        case "get_categories":
            return getCategories(type: call.arguments["type"] as? String, context: context)
        case "create_category":
            return createCategory(args: call.arguments, context: context)
        case "rename_category":
            return renameCategory(args: call.arguments, context: context)
        case "delete_category":
            return deleteCategory(args: call.arguments, context: context)
        case "move_category":
            return moveCategory(args: call.arguments, context: context)
        case "suggest_recipe":
            return suggestRecipeContext(args: call.arguments, context: context)
        case "import_recipe_from_url":
            return await importRecipeFromURL(args: call.arguments, context: context)
        case "log_food_manual":
            return logFoodManual(args: call.arguments, context: context)
        case "get_nutrition_today":
            return getNutritionToday(context: context)
        case "get_nutrition_profile":
            return getNutritionProfile(context: context)
        case "delete_food_entry":
            return deleteFoodEntry(name: call.arguments["name"] as? String ?? "", context: context)
        case "list_weight_entries":
            return listWeightEntries(args: call.arguments, context: context)
        case "add_weight_entry":
            return addWeightEntry(args: call.arguments, context: context)
        case "update_weight_entry":
            return updateWeightEntry(args: call.arguments, context: context)
        case "delete_weight_entry":
            return deleteWeightEntry(args: call.arguments, context: context)
        default:
            return "{\"error\": \"Unknown tool: \(call.name)\"}"
        }
    }

    // MARK: - Tool Implementations

    private static func searchRecipes(query: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Recipe>()
        guard let recipes = try? context.fetch(descriptor) else { return "[]" }
        let q = query.lowercased()
        let matches = recipes.filter {
            $0.name.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.tags.contains(where: { $0.lowercased().contains(q) }) ||
            ($0.ingredients ?? []).contains(where: { $0.name.lowercased().contains(q) })
        }
        let results = matches.prefix(10).map { r in
            ["name": r.name, "category": r.category, "difficulty": r.difficulty.rawValue,
             "totalTime": "\(r.totalTime) min", "servings": "\(r.servings)"]
        }
        return toJSON(results)
    }

    private static func getRecipe(name: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Recipe>()
        guard let recipes = try? context.fetch(descriptor) else { return "{\"error\": \"not found\"}" }
        let q = name.lowercased()
        guard let recipe = recipes.first(where: { $0.name.lowercased().contains(q) }) else {
            return "{\"error\": \"Recipe not found: \(name)\"}"
        }
        return recipe.aiReadableDescription
    }

    private static func createRecipe(args: [String: Any], context: ModelContext) -> String {
        let name = args["name"] as? String ?? "Nova Receita"
        let desc = args["description"] as? String ?? ""
        let category = CategoryMutationService.normalizedRecipeCategoryString(
            from: args["category"] as? String ?? "",
            context: context
        )
        let diffStr = args["difficulty"] as? String ?? "Fácil"
        let difficulty = Difficulty.allCases.first { $0.rawValue == diffStr } ?? .easy
        let prepTime = args["prepTime"] as? Int ?? 0
        let cookTime = args["cookTime"] as? Int ?? 0
        let servings = args["servings"] as? Int ?? 1
        let calories = args["calories"] as? Int

        let recipe = Recipe(
            name: name, descriptionText: desc, category: category,
            prepTime: prepTime, cookTime: cookTime, servings: servings,
            calories: calories, difficulty: difficulty
        )
        context.insert(recipe)

        if let ingredientsArray = args["ingredients"] as? [[String: Any]] {
            var newIngredients: [RecipeIngredient] = []
            for (i, ingDict) in ingredientsArray.enumerated() {
                let ing = RecipeIngredient(
                    name: ingDict["name"] as? String ?? "",
                    quantity: ingDict["quantity"] as? Double,
                    unit: ingDict["unit"] as? String ?? "",
                    preparationState: ingDict["state"] as? String ?? "",
                    sortOrder: i
                )
                ing.recipe = recipe
                context.insert(ing)
                newIngredients.append(ing)
            }
            recipe.ingredients = newIngredients
        }

        if let stepsArray = args["steps"] as? [String] {
            var newSteps: [RecipeStep] = []
            for (i, instruction) in stepsArray.enumerated() {
                let step = RecipeStep(order: i + 1, instruction: instruction)
                step.recipe = recipe
                context.insert(step)
                newSteps.append(step)
            }
            recipe.steps = newSteps
        }

        try? context.save()
        return "{\"success\": true, \"recipe\": \"\(name)\", \"id\": \"\(recipe.id.uuidString)\"}"
    }

    /// Public entry point for creating a recipe from structured args (used by RecipeDetailCard).
    static func createRecipeFromArgs(_ args: [String: Any], context: ModelContext) -> String {
        createRecipe(args: args, context: context)
    }

    private static func updateRecipe(args: [String: Any], context: ModelContext) -> String {
        let targetName = args["target_name"] as? String ?? ""
        let descriptor = FetchDescriptor<Recipe>()
        guard let recipes = try? context.fetch(descriptor) else { return "{\"error\": \"not found\"}" }
        let q = targetName.lowercased()
        guard let recipe = recipes.first(where: { $0.name.lowercased().contains(q) }) else {
            return "{\"error\": \"Recipe not found: \(targetName)\"}"
        }

        if let name = args["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipe.name = name
        }
        if let description = args["description"] as? String {
            recipe.descriptionText = description
        }
        if let category = args["category"] as? String, !category.isEmpty {
            recipe.category = CategoryMutationService.normalizedRecipeCategoryString(from: category, context: context)
        }
        if let difficultyString = args["difficulty"] as? String,
           let difficulty = Difficulty.allCases.first(where: { $0.rawValue == difficultyString }) {
            recipe.difficulty = difficulty
        }
        if let prepTime = args["prepTime"] as? Int { recipe.prepTime = prepTime }
        if let cookTime = args["cookTime"] as? Int { recipe.cookTime = cookTime }
        if let servings = args["servings"] as? Int { recipe.servings = servings }
        if args.keys.contains("calories") { recipe.calories = args["calories"] as? Int }

        if let ingredientsArray = args["ingredients"] as? [[String: Any]] {
            for ingredient in (recipe.ingredients ?? []) {
                context.delete(ingredient)
            }
            var newIngredients: [RecipeIngredient] = []
            for (i, ingDict) in ingredientsArray.enumerated() {
                let ingredient = RecipeIngredient(
                    name: ingDict["name"] as? String ?? "",
                    quantity: ingDict["quantity"] as? Double,
                    unit: ingDict["unit"] as? String ?? "",
                    preparationState: ingDict["state"] as? String ?? "",
                    sortOrder: i
                )
                ingredient.recipe = recipe
                context.insert(ingredient)
                newIngredients.append(ingredient)
            }
            recipe.ingredients = newIngredients
        }

        if let stepsArray = args["steps"] as? [String] {
            for step in (recipe.steps ?? []) {
                context.delete(step)
            }
            var newSteps: [RecipeStep] = []
            for (i, instruction) in stepsArray.enumerated() {
                let step = RecipeStep(order: i + 1, instruction: instruction)
                step.recipe = recipe
                context.insert(step)
                newSteps.append(step)
            }
            recipe.steps = newSteps
        }

        recipe.updatedAt = .now
        try? context.save()
        return "{\"success\": true, \"recipe\": \"\(recipe.name)\", \"id\": \"\(recipe.id.uuidString)\"}"
    }

    private static func deleteRecipe(name: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Recipe>()
        guard let recipes = try? context.fetch(descriptor) else { return "{\"error\": \"not found\"}" }
        let q = name.lowercased()
        guard let recipe = recipes.first(where: { $0.name.lowercased().contains(q) }) else {
            return "{\"error\": \"Recipe not found: \(name)\"}"
        }
        let recipeName = recipe.name
        context.delete(recipe)
        try? context.save()
        return "{\"success\": true, \"deleted\": \"\(recipeName)\"}"
    }

    private static func getAllPantry(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<UnifiedItem>(sortBy: [SortDescriptor(\UnifiedItem.name)])
        guard let allItems = try? context.fetch(descriptor) else { return "[]" }
        let items = allItems.filter { $0.isPantry }
        if items.isEmpty { return "{\"items\": [], \"message\": \"A despensa está vazia.\"}" }
        let results = items.map { item -> [String: String] in
            var dict = ["name": item.name, "category": item.category]
            if !item.formattedQuantity.isEmpty { dict["quantity"] = item.formattedQuantity }
            if item.isLinkedToGrocery { dict["linked_to_grocery"] = "true" }
            return dict
        }
        return toJSON(["items": results, "total": items.count])
    }

    private static func searchPantry(query: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<UnifiedItem>()
        guard let allItems = try? context.fetch(descriptor) else { return "[]" }
        let q = query.lowercased()
        let matches = allItems.filter { $0.isPantry && $0.name.lowercased().contains(q) }
        let results = matches.map { $0.aiReadableDescription }
        return "[\(results.joined(separator: ", "))]"
    }

    private static func addPantryItem(args: [String: Any], context: ModelContext) -> String {
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        let category = args["category"] as? String ?? "Outros"
        let quantity = args["quantity"] as? Double
        let unit = args["unit"] as? String
        let expirationDate = parseDate(args["expirationDate"] as? String)
        let descriptor = FetchDescriptor<UnifiedItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []

        if let existingItem = UnifiedItem.existingItem(named: name, in: allItems) {
            if !existingItem.isPantry {
                existingItem.isPantry = true
                existingItem.pantrySortOrder = (allItems.filter { $0.isPantry }.map(\.pantrySortOrder).max() ?? -1) + 1
            }
            if category != "Outros" {
                existingItem.category = category
            }
            if let quantity {
                existingItem.quantity = quantity
            }
            if let unit, !unit.isEmpty {
                existingItem.unit = unit
            }
            if let expirationDate {
                existingItem.expirationDate = expirationDate
            }

            try? context.save()
            return "{\"success\": true, \"item\": \"\(existingItem.name)\", \"id\": \"\(existingItem.id.uuidString)\", \"existing\": true}"
        }

        let item = UnifiedItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            isPantry: true,
            pantrySortOrder: (allItems.filter { $0.isPantry }.map(\.pantrySortOrder).max() ?? -1) + 1,
            expirationDate: expirationDate
        )
        context.insert(item)
        try? context.save()
        return "{\"success\": true, \"item\": \"\(name)\", \"id\": \"\(item.id.uuidString)\", \"existing\": false}"
    }

    private static func removePantryItem(name: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<UnifiedItem>()
        guard let allItems = try? context.fetch(descriptor) else { return "{\"error\": \"not found\"}" }
        let q = name.lowercased()
        guard let item = allItems.first(where: { $0.isPantry && $0.name.lowercased().contains(q) }) else {
            return "{\"error\": \"Item not found: \(name)\"}"
        }
        if item.isGrocery || item.isUtensil {
            // Item is in other lists too, just remove the pantry flag
            item.isPantry = false
        } else {
            context.delete(item)
        }
        try? context.save()
        return "{\"success\": true, \"removed\": \"\(item.name)\"}"
    }

    private static func getAllGrocery(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<UnifiedItem>(sortBy: [SortDescriptor(\UnifiedItem.grocerySortOrder)])
        guard let allItems = try? context.fetch(descriptor) else { return "[]" }
        let items = allItems.filter { $0.isGrocery }
        if items.isEmpty { return "{\"items\": [], \"message\": \"A lista de compras está vazia.\"}" }
        let results = items.map { item -> [String: String] in
            var dict = ["name": item.name, "category": item.category]
            if let qty = item.quantity {
                let num = qty.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", qty) : String(format: "%.1f", qty)
                dict["quantity"] = item.unit.map { u in u.isEmpty ? "\(num)x" : "\(num) \(u)" } ?? "\(num)x"
            }
            if item.isFixed { dict["fixed"] = "true" }
            return dict
        }
        return toJSON(["items": results, "total": items.count])
    }

    private static func addGroceryItem(args: [String: Any], context: ModelContext) -> String {
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        let category = args["category"] as? String ?? "Outros"
        let quantity = args["quantity"] as? Double
        let unit = args["unit"] as? String
        let descriptor = FetchDescriptor<UnifiedItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []

        if let existingItem = UnifiedItem.existingItem(named: name, in: allItems) {
            if !existingItem.isGrocery {
                existingItem.isGrocery = true
                existingItem.grocerySortOrder = (allItems.filter { $0.isGrocery }.map(\.grocerySortOrder).max() ?? -1) + 1
            }
            if category != "Outros" {
                existingItem.category = category
            }
            if let quantity {
                existingItem.quantity = quantity
            }
            if let unit, !unit.isEmpty {
                existingItem.unit = unit
            }

            try? context.save()
            return "{\"success\": true, \"item\": \"\(existingItem.name)\", \"id\": \"\(existingItem.id.uuidString)\", \"existing\": true}"
        }

        let item = UnifiedItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            isGrocery: true,
            grocerySortOrder: (allItems.filter { $0.isGrocery }.map(\.grocerySortOrder).max() ?? -1) + 1
        )
        context.insert(item)
        try? context.save()
        return "{\"success\": true, \"item\": \"\(name)\", \"id\": \"\(item.id.uuidString)\", \"existing\": false}"
    }

    private static func getCategories(type: String?, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let categories = try? context.fetch(descriptor) else { return "[]" }

        let filtered = if let categoryType = categoryType(from: type) {
            categories.filter { $0.type == categoryType }
        } else {
            categories
        }

        let results = filtered.map {
            [
                "name": $0.name,
                "type": $0.type.rawValue,
                "sortOrder": $0.sortOrder as Any
            ]
        }
        return toJSON(results)
    }

    private static func createCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        do {
            let category = try CategoryMutationService.createCategory(named: name, type: type, context: context)
            try? context.save()
            return "{\"success\": true, \"category\": \"\(category.name)\", \"type\": \"\(type.rawValue)\"}"
        } catch CategoryMutationError.duplicateName {
            return "{\"error\": \"category exists\"}"
        } catch {
            return "{\"error\": \"invalid name\"}"
        }
    }

    private static func renameCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let currentName = (args["current_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = (args["new_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentName.isEmpty, !newName.isEmpty else { return "{\"error\": \"invalid name\"}" }

        do {
            let category = try CategoryMutationService.renameCategory(named: currentName, to: newName, type: type, context: context)
            try? context.save()
            return "{\"success\": true, \"category\": \"\(category.name)\", \"type\": \"\(type.rawValue)\"}"
        } catch CategoryMutationError.categoryNotFound {
            return "{\"error\": \"category not found\"}"
        } catch CategoryMutationError.duplicateName {
            return "{\"error\": \"category exists\"}"
        } catch {
            return "{\"error\": \"invalid name\"}"
        }
    }

    private static func deleteCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        do {
            let result = try CategoryMutationService.deleteCategory(
                named: name,
                type: type,
                strategy: .reassign(toCategoryNamed: "Outros"),
                context: context
            )
            try? context.save()
            if let reassignedName = result.reassignedName {
                return "{\"success\": true, \"deleted\": \"\(name)\", \"fallback\": \"\(reassignedName)\"}"
            }
            return "{\"success\": true, \"deleted\": \"\(name)\"}"
        } catch {
            return "{\"error\": \"category not found\"}"
        }
    }

    private static func moveCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPosition = args["position"] as? Int ?? 0

        do {
            let safePosition = try CategoryMutationService.moveCategory(named: name, type: type, to: requestedPosition, context: context)
            try? context.save()
            return "{\"success\": true, \"category\": \"\(name)\", \"position\": \(safePosition)}"
        } catch {
            return "{\"error\": \"category not found\"}"
        }
    }

    private static func suggestRecipeContext(args: [String: Any], context: ModelContext) -> String {
        let usePantry = args["use_pantry"] as? Bool ?? true
        var contextParts = [String]()

        if usePantry {
            let descriptor = FetchDescriptor<UnifiedItem>()
            if let allItems = try? context.fetch(descriptor) {
                let names = allItems.filter { $0.isPantry }.map(\.name)
                contextParts.append("Available pantry items: \(names.joined(separator: ", "))")
            }
        }

        let recipeDescriptor = FetchDescriptor<Recipe>()
        if let recipes = try? context.fetch(recipeDescriptor) {
            let names = recipes.map(\.name)
            contextParts.append("Existing recipes: \(names.joined(separator: ", "))")
        }

        if let prefs = args["preferences"] as? String, !prefs.isEmpty {
            contextParts.append("Preferences: \(prefs)")
        }

        return contextParts.joined(separator: "\n")
    }

    // MARK: - Nutrition tools

    private static let yyyyMMddFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func logFoodManual(args: [String: Any], context: ModelContext) -> String {
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        let calories = args["calories"] as? Int ?? 0
        let proteinG = (args["proteinG"] as? Double) ?? Double(args["proteinG"] as? Int ?? 0)
        let carbsG = (args["carbsG"] as? Double) ?? Double(args["carbsG"] as? Int ?? 0)
        let fatG = (args["fatG"] as? Double) ?? Double(args["fatG"] as? Int ?? 0)
        let servingSize = (args["servingSizeGrams"] as? Double) ?? (args["servingSizeGrams"] as? Int).map(Double.init)
        let emoji = (args["emoji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let mealType = MealType(rawValue: (args["mealType"] as? String ?? "").lowercased()) ?? .other

        // Log at the requested date (midday) if provided, otherwise now.
        let logDate: Date = {
            if let iso = args["date"] as? String, let parsed = parseDate(iso) {
                let now = Date()
                let calendar = Calendar.current
                var comps = calendar.dateComponents([.year, .month, .day], from: parsed)
                let timeComps = calendar.dateComponents([.hour, .minute], from: now)
                comps.hour = timeComps.hour
                comps.minute = timeComps.minute
                return calendar.date(from: comps) ?? now
            }
            return Date()
        }()

        let entry = FoodEntry(
            name: name,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            mealType: mealType,
            source: .assistant,
            timestamp: logDate,
            emoji: emoji?.isEmpty == true ? nil : emoji,
            servingSizeGrams: servingSize
        )
        context.insert(entry)
        try? context.save()

        return toJSON([
            "success": true,
            "id": entry.id.uuidString,
            "name": entry.name,
            "calories": entry.calories,
            "proteinG": entry.proteinG,
            "carbsG": entry.carbsG,
            "fatG": entry.fatG
        ])
    }

    private static func getNutritionToday(context: ModelContext) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return "{\"error\": \"date error\"}"
        }

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        let totalCal = entries.reduce(0) { $0 + $1.calories }
        let totalP = entries.reduce(0.0) { $0 + $1.proteinG }
        let totalC = entries.reduce(0.0) { $0 + $1.carbsG }
        let totalF = entries.reduce(0.0) { $0 + $1.fatG }

        let profile = NutritionProfileStore.fetch(in: context)
        let targetCal = profile?.effectiveCalories ?? 0
        let targetP = profile?.effectiveProteinG ?? 0
        let targetC = profile?.effectiveCarbsG ?? 0
        let targetF = profile?.effectiveFatG ?? 0

        let entryList = entries.map { entry -> [String: Any] in
            [
                "name": entry.name,
                "meal": entry.mealType.rawValue,
                "calories": entry.calories,
                "proteinG": entry.proteinG,
                "carbsG": entry.carbsG,
                "fatG": entry.fatG,
                "time": ISO8601DateFormatter().string(from: entry.timestamp)
            ]
        }

        return toJSON([
            "date": AITools.yyyyMMddFormatter.string(from: startOfDay),
            "totals": [
                "calories": totalCal,
                "proteinG": round(totalP),
                "carbsG": round(totalC),
                "fatG": round(totalF)
            ],
            "targets": [
                "calories": targetCal,
                "proteinG": targetP,
                "carbsG": targetC,
                "fatG": targetF
            ],
            "remaining": [
                "calories": max(0, targetCal - totalCal),
                "proteinG": max(0, Double(targetP) - totalP),
                "carbsG": max(0, Double(targetC) - totalC),
                "fatG": max(0, Double(targetF) - totalF)
            ],
            "entries": entryList,
            "entryCount": entries.count
        ])
    }

    private static func getNutritionProfile(context: ModelContext) -> String {
        guard let profile = NutritionProfileStore.fetch(in: context),
              profile.hasCompletedOnboarding else {
            return "{\"onboarding_complete\": false, \"message\": \"O usuário ainda não concluiu o onboarding de nutrição.\"}"
        }

        return toJSON([
            "onboarding_complete": true,
            "sex": profile.sex.rawValue,
            "ageYears": profile.ageYears,
            "heightCm": profile.heightCm,
            "weightKg": profile.weightKg,
            "activityLevel": profile.activityLevel.rawValue,
            "weightGoal": profile.weightGoal.rawValue,
            "weeklyChangeKg": profile.weeklyChangeKg,
            "targets": [
                "calories": profile.effectiveCalories,
                "proteinG": profile.effectiveProteinG,
                "carbsG": profile.effectiveCarbsG,
                "fatG": profile.effectiveFatG
            ],
            "useMetric": profile.useMetric
        ])
    }

    private static func deleteFoodEntry(name: String, context: ModelContext) -> String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.timestamp >= startOfDay },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else {
            return "{\"error\": \"Nenhuma refeição registrada hoje.\"}"
        }

        let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = q.isEmpty ? entries.first : entries.first(where: { $0.name.lowercased().contains(q) })
        guard let entry = target else {
            return "{\"error\": \"Refeição não encontrada: \(name)\"}"
        }

        let removedName = entry.name
        if let filename = entry.imageFilename {
            FoodImageStore.shared.delete(filename: filename)
        }
        context.delete(entry)
        try? context.save()
        return "{\"success\": true, \"deleted\": \"\(removedName)\"}"
    }

    // MARK: - Weight tracking

    private static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func listWeightEntries(args: [String: Any], context: ModelContext) -> String {
        let limit = max(1, min(args["limit"] as? Int ?? 30, 500))
        let descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let entries = Array(all.prefix(limit))

        let payload = entries.map { entry -> [String: Any] in
            [
                "id": entry.id.uuidString,
                "date": isoDateTimeFormatter.string(from: entry.date),
                "weightKg": entry.weightKg
            ]
        }

        let profile = NutritionProfileStore.fetch(in: context)
        return toJSON([
            "count": entries.count,
            "totalCount": all.count,
            "currentWeightKg": profile?.weightKg ?? entries.first?.weightKg ?? 0,
            "targetWeightKg": profile?.targetWeightKg as Any? ?? NSNull(),
            "entries": payload
        ])
    }

    private static func addWeightEntry(args: [String: Any], context: ModelContext) -> String {
        let weightKg: Double = {
            if let d = args["weightKg"] as? Double { return d }
            if let i = args["weightKg"] as? Int { return Double(i) }
            return 0
        }()
        guard weightKg > 0 else { return "{\"error\": \"invalid weightKg\"}" }

        let date: Date = {
            if let iso = args["date"] as? String, let parsed = parseDate(iso) {
                let now = Date()
                let calendar = Calendar.current
                var comps = calendar.dateComponents([.year, .month, .day], from: parsed)
                let timeComps = calendar.dateComponents([.hour, .minute], from: now)
                comps.hour = timeComps.hour
                comps.minute = timeComps.minute
                return calendar.date(from: comps) ?? now
            }
            return Date()
        }()

        let entry = WeightEntry(date: date, weightKg: weightKg)
        context.insert(entry)

        // Atualiza o perfil somente se este for o registro mais recente.
        let descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        if let mostRecent = all.first ?? Optional(entry),
           mostRecent.id == entry.id || mostRecent.date <= entry.date,
           let profile = NutritionProfileStore.fetch(in: context) {
            profile.weightKg = weightKg
            profile.updatedAt = .now
        }
        try? context.save()

        return toJSON([
            "success": true,
            "id": entry.id.uuidString,
            "date": isoDateTimeFormatter.string(from: entry.date),
            "weightKg": entry.weightKg
        ])
    }

    private static func updateWeightEntry(args: [String: Any], context: ModelContext) -> String {
        guard let idString = args["id"] as? String, let id = UUID(uuidString: idString) else {
            return "{\"error\": \"invalid id\"}"
        }
        let descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else {
            return "{\"error\": \"entry not found\"}"
        }

        if let newWeight = args["weightKg"] as? Double {
            entry.weightKg = newWeight
        } else if let newWeightInt = args["weightKg"] as? Int {
            entry.weightKg = Double(newWeightInt)
        }

        if let iso = args["date"] as? String, let parsed = parseDate(iso) {
            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day], from: parsed)
            let timeComps = calendar.dateComponents([.hour, .minute], from: entry.date)
            comps.hour = timeComps.hour
            comps.minute = timeComps.minute
            if let merged = calendar.date(from: comps) {
                entry.date = merged
            }
        }

        // Se a entrada continuar sendo a mais recente, espelha no perfil.
        let allDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(allDescriptor)) ?? []
        if let mostRecent = all.first, mostRecent.id == entry.id,
           let profile = NutritionProfileStore.fetch(in: context) {
            profile.weightKg = entry.weightKg
            profile.updatedAt = .now
        }
        try? context.save()

        return toJSON([
            "success": true,
            "id": entry.id.uuidString,
            "date": isoDateTimeFormatter.string(from: entry.date),
            "weightKg": entry.weightKg
        ])
    }

    private static func deleteWeightEntry(args: [String: Any], context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard !all.isEmpty else { return "{\"error\": \"no entries\"}" }

        let target: WeightEntry?
        if let idString = args["id"] as? String, let id = UUID(uuidString: idString) {
            target = all.first(where: { $0.id == id })
        } else {
            target = all.first
        }
        guard let entry = target else { return "{\"error\": \"entry not found\"}" }

        let removedId = entry.id.uuidString
        let wasMostRecent = (entry.id == all.first?.id)
        context.delete(entry)

        if wasMostRecent, let profile = NutritionProfileStore.fetch(in: context) {
            let remaining = all.filter { $0.id != entry.id }
            if let next = remaining.first {
                profile.weightKg = next.weightKg
                profile.updatedAt = .now
            }
        }
        try? context.save()

        return "{\"success\": true, \"deleted\": \"\(removedId)\"}"
    }

    // MARK: - Helpers

    private static func makeTool(
        name: String,
        description: String,
        parameters: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": parameters,
                    "required": required
                ]
            ]
        ]
    }

    private static func toJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    // MARK: - Import recipe from URL

    private static func importRecipeFromURL(args: [String: Any], context: ModelContext) async -> String {
        let raw = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return toJSON(["error": "missing url"])
        }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate), url.host != nil else {
            return toJSON(["error": "invalid url"])
        }

        let orchestrator = RecipeImportOrchestrator()
        do {
            let draft = try await orchestrator.importRecipe(from: .url(url)) { _ in }
            let recipe = persistImportedDraft(draft, in: context)
            return toJSON([
                "success": true,
                "id": recipe.id.uuidString,
                "name": recipe.name,
                "category": recipe.category,
                "ingredients": recipe.ingredients?.count ?? 0,
                "steps": recipe.steps?.count ?? 0,
                "source": draft.sourceLabel
            ])
        } catch {
            return toJSON(["error": error.localizedDescription])
        }
    }

    @discardableResult
    static func persistImportedDraft(_ draft: RecipeDraft, in context: ModelContext) -> Recipe {
        let recipe = Recipe(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            descriptionText: draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: draft.imageData,
            externalURLString: draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            category: CategoryMutationService.normalizedRecipeCategoryString(from: draft.category, context: context),
            prepTime: draft.prepTime,
            cookTime: draft.cookTime,
            servings: draft.servings,
            calories: draft.calories,
            difficulty: draft.difficulty
        )
        context.insert(recipe)
        recipe.requiredUtensils = draft.requiredUtensils.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Nutrição por porção (se a IA preencheu).
        recipe.proteinG = draft.proteinG
        recipe.carbsG = draft.carbsG
        recipe.fatG = draft.fatG
        recipe.fiberG = draft.fiberG
        recipe.sugarG = draft.sugarG
        recipe.sodiumMg = draft.sodiumMg
        recipe.nutritionEstimated = draft.nutritionEstimated
        if draft.calories != nil || draft.proteinG != nil || draft.carbsG != nil || draft.fatG != nil {
            recipe.nutritionUpdatedAt = .now
        }

        var sectionIDMap: [UUID: UUID] = [:]
        let sortedSectionDrafts = draft.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        for (idx, sectionDraft) in sortedSectionDrafts.enumerated() {
            let title = sectionDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = sectionDraft.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty && subtitle.isEmpty { continue }
            let newID = UUID()
            let section = RecipeIngredientSection(
                title: title,
                subtitle: subtitle,
                sortOrder: idx,
                id: newID
            )
            section.recipe = recipe
            context.insert(section)
            sectionIDMap[sectionDraft.id] = newID
        }

        for (index, ing) in draft.ingredients.enumerated() {
            let trimmedName = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let mappedSectionID: UUID? = ing.sectionID.flatMap { sectionIDMap[$0] }
            let ingredient = RecipeIngredient(
                name: trimmedName,
                quantity: ing.quantity,
                unit: ing.unit,
                preparationState: ing.preparationState,
                iconName: ing.iconName ?? ItemDatabase.shared.preferredMatch(for: trimmedName)?.nomeDoArquivo,
                sortOrder: index,
                sectionID: mappedSectionID
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        for step in draft.steps {
            let trimmed = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let s = RecipeStep(order: step.order, instruction: trimmed, durationMinutes: step.durationMinutes)
            s.recipe = recipe
            context.insert(s)
        }

        var mediaToPersist = draft.preparationMedia
        if mediaToPersist.isEmpty, let imageData = draft.imageData, !imageData.isEmpty {
            mediaToPersist = [
                ImportDraftPreparationMedia(
                    type: .photo,
                    data: imageData,
                    fileExtension: "jpg",
                    sourceOriginal: true
                )
            ]
        }

        for (index, media) in mediaToPersist.enumerated() {
            guard !media.data.isEmpty else { continue }
            let attachment = RecipePreparationMedia(
                mediaType: media.type,
                data: media.data,
                fileExtension: media.fileExtension,
                sortOrder: index,
                sourceOriginal: media.sourceOriginal
            )
            attachment.recipe = recipe
            context.insert(attachment)
        }

        try? context.save()
        return recipe
    }

    private static func categoryType(from rawValue: String?) -> CategoryType? {
        guard let rawValue else { return nil }
        return CategoryType(rawValue: rawValue.lowercased())?.canonicalType
    }

    private static func fetchCategories(of type: CategoryType, context: ModelContext) -> [Category] {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor))?.filter { $0.type == type.canonicalType } ?? []
    }

    private static func ensureFallbackCategory(for type: CategoryType, excluding category: Category, context: ModelContext) -> Category {
        let resolvedType = type.canonicalType
        let categories = fetchCategories(of: resolvedType, context: context)
        if let existing = categories.first(where: {
            $0.id != category.id && $0.name.localizedCaseInsensitiveCompare("Outros") == .orderedSame
        }) {
            return existing
        }

        let fallback = Category(name: "Outros", type: resolvedType, sortOrder: categories.count)
        context.insert(fallback)
        return fallback
    }

    private static func reassignCategoryReferences(from oldName: String, to newName: String, type: CategoryType, context: ModelContext) {
        switch type.canonicalType {
        case .pantry:
            let descriptor = FetchDescriptor<UnifiedItem>()
            for item in (try? context.fetch(descriptor)) ?? [] where item.isPantry && item.category == oldName {
                item.category = newName
            }
        case .grocery:
            let descriptor = FetchDescriptor<UnifiedItem>()
            for item in (try? context.fetch(descriptor)) ?? [] where item.isGrocery && item.category == oldName {
                item.category = newName
            }
        case .recipe:
            let descriptor = FetchDescriptor<Recipe>()
            for recipe in (try? context.fetch(descriptor)) ?? [] where recipe.categories.contains(oldName) {
                recipe.categories = recipe.categories.map { $0 == oldName ? newName : $0 }
            }
        case .utensil:
            let descriptor = FetchDescriptor<UnifiedItem>()
            for item in (try? context.fetch(descriptor)) ?? [] where item.isUtensil && item.category == oldName {
                item.category = newName
            }
        }
    }

    private static func normalizeCategoryOrder(for type: CategoryType, context: ModelContext) {
        let categories = fetchCategories(of: type.canonicalType, context: context)
        for (index, category) in categories.enumerated() {
            category.sortOrder = index
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
