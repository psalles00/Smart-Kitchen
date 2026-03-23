import Foundation
import SwiftData

// MARK: - Recipe

@Model
final class Recipe {
    var id: UUID
    var name: String
    var descriptionText: String
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]
    var imageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \RecipePreparationMedia.recipe)
    var preparationMedia: [RecipePreparationMedia]
    var externalURLString: String
    var category: String
    var tags: [String]
    var prepTime: Int       // minutes
    var cookTime: Int       // minutes
    var servings: Int
    var calories: Int?
    var difficulty: Difficulty
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        descriptionText: String = "",
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        imageData: Data? = nil,
        preparationMedia: [RecipePreparationMedia] = [],
        externalURLString: String = "",
        category: String = "",
        tags: [String] = [],
        prepTime: Int = 0,
        cookTime: Int = 0,
        servings: Int = 1,
        calories: Int? = nil,
        difficulty: Difficulty = .easy,
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.descriptionText = descriptionText
        self.ingredients = ingredients
        self.steps = steps
        self.imageData = imageData
        self.preparationMedia = preparationMedia
        self.externalURLString = externalURLString
        self.category = category
        self.tags = tags
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
        self.calories = calories
        self.difficulty = difficulty
        self.isFavorite = isFavorite
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Total preparation + cooking time.
    var totalTime: Int { prepTime + cookTime }

    /// Plain-text summary for AI context.
    var aiReadableDescription: String {
        var parts = [String]()
        parts.append("Receita: \(name)")
        if !descriptionText.isEmpty { parts.append("Descrição: \(descriptionText)") }
        if !externalURLString.isEmpty { parts.append("Link: \(externalURLString)") }
        parts.append("Categoria: \(category)")
        parts.append("Dificuldade: \(difficulty.rawValue)")
        parts.append("Tempo: preparo \(prepTime)min, cozimento \(cookTime)min")
        parts.append("Porções: \(servings)")
        if let cal = calories { parts.append("Calorias: \(cal) kcal") }
        if !tags.isEmpty { parts.append("Tags: \(tags.joined(separator: ", "))") }

        let ingredientList = ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ing in
                if let qty = ing.quantity, !ing.unit.isEmpty {
                    return "- \(ing.name): \(qty) \(ing.unit)"
                } else if let qty = ing.quantity {
                    return "- \(ing.name): \(qty)"
                }
                return "- \(ing.name)"
            }
        if !ingredientList.isEmpty {
            parts.append("Ingredientes:\n\(ingredientList.joined(separator: "\n"))")
        }

        let stepList = steps
            .sorted { $0.order < $1.order }
            .map { "  \($0.order). \($0.instruction)" }
        if !stepList.isEmpty {
            parts.append("Passos:\n\(stepList.joined(separator: "\n"))")
        }

        if !preparationMedia.isEmpty {
            parts.append("Mídias de preparo: \(preparationMedia.count)")
        }

        return parts.joined(separator: "\n")
    }

    func compatibility(against pantryNames: [String]) -> RecipeCompatibility? {
        let normalizedIngredients = ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.name)
            .map(Self.normalizedIngredient)

        guard !normalizedIngredients.isEmpty else { return nil }

        let matchedIngredients = normalizedIngredients.reduce(into: 0) { total, ingredient in
            if pantryNames.contains(where: { pantry in
                pantry == ingredient || pantry.contains(ingredient) || ingredient.contains(pantry)
            }) {
                total += 1
            }
        }

        guard matchedIngredients > 0 else { return nil }
        return RecipeCompatibility(matchedIngredients: matchedIngredients, totalIngredients: normalizedIngredients.count)
    }

    private static func normalizedIngredient(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

enum RecipePreparationMediaType: String, Codable, CaseIterable {
    case photo
    case video

    var label: String {
        switch self {
        case .photo: "Foto"
        case .video: "Vídeo"
        }
    }
}

@Model
final class RecipePreparationMedia {
    var id: UUID
    var mediaTypeRaw: String
    var data: Data
    var fileExtension: String
    var sortOrder: Int
    var recipe: Recipe?

    init(
        mediaType: RecipePreparationMediaType,
        data: Data,
        fileExtension: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.mediaTypeRaw = mediaType.rawValue
        self.data = data
        self.fileExtension = fileExtension
        self.sortOrder = sortOrder
    }

    var mediaType: RecipePreparationMediaType {
        get { RecipePreparationMediaType(rawValue: mediaTypeRaw) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }
}

struct RecipeCompatibility {
    let matchedIngredients: Int
    let totalIngredients: Int

    var ratio: Double { Double(matchedIngredients) / Double(totalIngredients) }
    var compactText: String { "\(matchedIngredients)/\(totalIngredients)" }
    var longText: String { "\(matchedIngredients) de \(totalIngredients) ingredientes" }
}

// MARK: - Difficulty

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy   = "Fácil"
    case medium = "Médio"
    case hard   = "Difícil"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .easy:   "leaf"
        case .medium: "flame"
        case .hard:   "bolt.fill"
        }
    }
}

// MARK: - RecipeIngredient

@Model
final class RecipeIngredient {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: String
    var iconName: String?
    var sortOrder: Int
    var recipe: Recipe?

    init(
        name: String,
        quantity: Double? = nil,
        unit: String = "",
        iconName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.iconName = iconName
        self.sortOrder = sortOrder
    }

    /// Formatted display string (e.g. "200 g" or "2 xícaras").
    var formattedQuantity: String {
        guard let qty = quantity else { return "" }
        let num = qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", qty)
            : String(format: "%.1f", qty)
        return unit.isEmpty ? num : "\(num) \(unit)"
    }
}

// MARK: - RecipeStep

@Model
final class RecipeStep {
    var id: UUID
    var order: Int
    var instruction: String
    var durationMinutes: Int?
    var recipe: Recipe?

    init(order: Int, instruction: String, durationMinutes: Int? = nil) {
        self.id = UUID()
        self.order = order
        self.instruction = instruction
        self.durationMinutes = durationMinutes
    }
}
