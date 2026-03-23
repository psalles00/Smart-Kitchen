import Foundation
import SwiftData

/// Defines the OpenAI function-calling tools and executes them against SwiftData.
@MainActor
struct AITools {

    // MARK: - Tool Definitions (sent to OpenAI)

    static let definitions: [[String: Any]] = [
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
        )
    ]

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
            $0.ingredients.contains(where: { $0.name.lowercased().contains(q) })
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
        let category = args["category"] as? String ?? "Outros"
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
            for (i, ingDict) in ingredientsArray.enumerated() {
                let ing = RecipeIngredient(
                    name: ingDict["name"] as? String ?? "",
                    quantity: ingDict["quantity"] as? Double,
                    unit: ingDict["unit"] as? String ?? "",
                    sortOrder: i
                )
                ing.recipe = recipe
                context.insert(ing)
            }
        }

        if let stepsArray = args["steps"] as? [String] {
            for (i, instruction) in stepsArray.enumerated() {
                let step = RecipeStep(order: i + 1, instruction: instruction)
                step.recipe = recipe
                context.insert(step)
            }
        }

        try? context.save()
        return "{\"success\": true, \"recipe\": \"\(name)\", \"id\": \"\(recipe.id.uuidString)\"}"
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
            recipe.category = category
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
            for ingredient in recipe.ingredients {
                context.delete(ingredient)
            }
            for (i, ingDict) in ingredientsArray.enumerated() {
                let ingredient = RecipeIngredient(
                    name: ingDict["name"] as? String ?? "",
                    quantity: ingDict["quantity"] as? Double,
                    unit: ingDict["unit"] as? String ?? "",
                    sortOrder: i
                )
                ingredient.recipe = recipe
                context.insert(ingredient)
            }
        }

        if let stepsArray = args["steps"] as? [String] {
            for step in recipe.steps {
                context.delete(step)
            }
            for (i, instruction) in stepsArray.enumerated() {
                let step = RecipeStep(order: i + 1, instruction: instruction)
                step.recipe = recipe
                context.insert(step)
            }
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
        let descriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.name)])
        guard let items = try? context.fetch(descriptor) else { return "[]" }
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
        let descriptor = FetchDescriptor<PantryItem>()
        guard let items = try? context.fetch(descriptor) else { return "[]" }
        let q = query.lowercased()
        let matches = items.filter { $0.name.lowercased().contains(q) }
        let results = matches.map { $0.aiReadableDescription }
        return "[\(results.joined(separator: ", "))]"
    }

    private static func addPantryItem(args: [String: Any], context: ModelContext) -> String {
        let name = args["name"] as? String ?? ""
        let category = args["category"] as? String ?? "Outros"
        let quantity = args["quantity"] as? Double
        let unit = args["unit"] as? String
        let expirationDate = parseDate(args["expirationDate"] as? String)

        let item = PantryItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit,
            expirationDate: expirationDate
        )
        context.insert(item)
        try? context.save()
        return "{\"success\": true, \"item\": \"\(name)\"}"
    }

    private static func removePantryItem(name: String, context: ModelContext) -> String {
        let descriptor = FetchDescriptor<PantryItem>()
        guard let items = try? context.fetch(descriptor) else { return "{\"error\": \"not found\"}" }
        let q = name.lowercased()
        guard let item = items.first(where: { $0.name.lowercased().contains(q) }) else {
            return "{\"error\": \"Item not found: \(name)\"}"
        }
        context.delete(item)
        try? context.save()
        return "{\"success\": true, \"removed\": \"\(item.name)\"}"
    }

    private static func getAllGrocery(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let items = try? context.fetch(descriptor) else { return "[]" }
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
        let name = args["name"] as? String ?? ""
        let category = args["category"] as? String ?? "Outros"
        let quantity = args["quantity"] as? Double
        let unit = args["unit"] as? String

        let item = GroceryItem(
            name: name,
            category: category,
            quantity: quantity,
            unit: unit
        )
        context.insert(item)
        try? context.save()
        return "{\"success\": true, \"item\": \"\(name)\"}"
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

        let categories = fetchCategories(of: type, context: context)
        guard !categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return "{\"error\": \"category exists\"}"
        }

        let category = Category(name: name, type: type, sortOrder: categories.count)
        context.insert(category)
        try? context.save()
        return "{\"success\": true, \"category\": \"\(name)\", \"type\": \"\(type.rawValue)\"}"
    }

    private static func renameCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let currentName = (args["current_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = (args["new_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentName.isEmpty, !newName.isEmpty else { return "{\"error\": \"invalid name\"}" }

        let categories = fetchCategories(of: type, context: context)
        guard let category = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(currentName) == .orderedSame }) else {
            return "{\"error\": \"category not found\"}"
        }

        category.name = newName
        reassignCategoryReferences(from: currentName, to: newName, type: type, context: context)
        try? context.save()
        return "{\"success\": true, \"category\": \"\(newName)\", \"type\": \"\(type.rawValue)\"}"
    }

    private static func deleteCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "{\"error\": \"invalid name\"}" }

        let categories = fetchCategories(of: type, context: context)
        guard let category = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return "{\"error\": \"category not found\"}"
        }

        let fallback = ensureFallbackCategory(for: type, excluding: category, context: context)
        reassignCategoryReferences(from: category.name, to: fallback.name, type: type, context: context)
        context.delete(category)
        normalizeCategoryOrder(for: type, context: context)
        try? context.save()
        return "{\"success\": true, \"deleted\": \"\(name)\", \"fallback\": \"\(fallback.name)\"}"
    }

    private static func moveCategory(args: [String: Any], context: ModelContext) -> String {
        guard let type = categoryType(from: args["type"] as? String) else {
            return "{\"error\": \"invalid type\"}"
        }
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedPosition = args["position"] as? Int ?? 0

        var categories = fetchCategories(of: type, context: context)
        guard let index = categories.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return "{\"error\": \"category not found\"}"
        }

        let safePosition = max(0, min(requestedPosition, categories.count - 1))
        let category = categories.remove(at: index)
        categories.insert(category, at: safePosition)

        for (sortOrder, item) in categories.enumerated() {
            item.sortOrder = sortOrder
        }

        try? context.save()
        return "{\"success\": true, \"category\": \"\(name)\", \"position\": \(safePosition)}"
    }

    private static func suggestRecipeContext(args: [String: Any], context: ModelContext) -> String {
        let usePantry = args["use_pantry"] as? Bool ?? true
        var contextParts = [String]()

        if usePantry {
            let descriptor = FetchDescriptor<PantryItem>()
            if let items = try? context.fetch(descriptor) {
                let names = items.map(\.name)
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
            let descriptor = FetchDescriptor<PantryItem>()
            for item in (try? context.fetch(descriptor)) ?? [] where item.category == oldName {
                item.category = newName
            }
        case .grocery:
            let descriptor = FetchDescriptor<GroceryItem>()
            for item in (try? context.fetch(descriptor)) ?? [] where item.category == oldName {
                item.category = newName
            }
        case .recipe:
            let descriptor = FetchDescriptor<Recipe>()
            for recipe in (try? context.fetch(descriptor)) ?? [] where recipe.category == oldName {
                recipe.category = newName
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
