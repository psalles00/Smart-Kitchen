import Foundation
import SwiftData

// MARK: - Identified Utensil (for Form ForEach)

struct IdentifiedUtensil: Identifiable {
    let id = UUID()
    var name: String
    var category: String?
    var iconName: String?

    init(name: String = "", category: String? = nil, iconName: String? = nil) {
        self.name = name
        self.category = category
        self.iconName = iconName
    }
}

struct RecipeOptionDefinition: Hashable {
    let fullName: String
    let abbreviation: String?

    init(_ fullName: String, abbreviation: String? = nil) {
        self.fullName = fullName
        self.abbreviation = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var menuLabel: String {
        guard let abbreviation, !abbreviation.isEmpty else { return fullName }
        return "\(fullName) (\(abbreviation))"
    }

    var ingredientLabel: String {
        guard let abbreviation, !abbreviation.isEmpty else { return fullName }
        return abbreviation
    }

    func matches(_ rawValue: String) -> Bool {
        let normalizedValue = RecipeOptionCatalog.normalized(rawValue)
        guard !normalizedValue.isEmpty else { return false }

        if RecipeOptionCatalog.normalized(fullName) == normalizedValue {
            return true
        }

        if let abbreviation, RecipeOptionCatalog.normalized(abbreviation) == normalizedValue {
            return true
        }

        return false
    }
}

enum RecipeOptionCatalog {
    static let stateOptions: [RecipeOptionDefinition] = [
        RecipeOptionDefinition("Ralado"),
        RecipeOptionDefinition("Desfiado"),
        RecipeOptionDefinition("Grelhado"),
        RecipeOptionDefinition("Assado"),
        RecipeOptionDefinition("Frito"),
        RecipeOptionDefinition("Cozido"),
        RecipeOptionDefinition("Refogado"),
        RecipeOptionDefinition("Picado"),
        RecipeOptionDefinition("Fatiado"),
        RecipeOptionDefinition("Em cubos"),
        RecipeOptionDefinition("Moído"),
        RecipeOptionDefinition("Triturado"),
        RecipeOptionDefinition("Amassado"),
        RecipeOptionDefinition("Derretido"),
        RecipeOptionDefinition("Temperado"),
        RecipeOptionDefinition("Gelado"),
        RecipeOptionDefinition("Congelado"),
        RecipeOptionDefinition("Inteiro"),
        RecipeOptionDefinition("Sem casca"),
        RecipeOptionDefinition("Com casca")
    ]

    static let unitOptions: [RecipeOptionDefinition] = [
        RecipeOptionDefinition("Unidade", abbreviation: "un"),
        RecipeOptionDefinition("Colher de Sopa", abbreviation: "c.s."),
        RecipeOptionDefinition("Colher de Chá", abbreviation: "c.c."),
        RecipeOptionDefinition("Gramas", abbreviation: "g"),
        RecipeOptionDefinition("Quilogramas", abbreviation: "kg"),
        RecipeOptionDefinition("Xícara", abbreviation: "xic"),
        RecipeOptionDefinition("Copo"),
        RecipeOptionDefinition("Mililitros", abbreviation: "mL"),
        RecipeOptionDefinition("Litros", abbreviation: "L"),
        RecipeOptionDefinition("Pé"),
        RecipeOptionDefinition("Pitada"),
        RecipeOptionDefinition("Lata", abbreviation: "lat"),
        RecipeOptionDefinition("Pacote", abbreviation: "pct"),
        RecipeOptionDefinition("Fatia", abbreviation: "fat"),
        RecipeOptionDefinition("Ramo", abbreviation: "ram"),
        RecipeOptionDefinition("Dente", abbreviation: "dte"),
        RecipeOptionDefinition("Caixa", abbreviation: "cx"),
        RecipeOptionDefinition("Garrafa"),
        RecipeOptionDefinition("Tablete", abbreviation: "tbl")
    ]

    static func options(for kind: RecipeCustomOptionKind) -> [RecipeOptionDefinition] {
        switch kind {
        case .state:
            return stateOptions
        case .unit:
            return unitOptions
        }
    }

    static func resolve(_ rawValue: String, for kind: RecipeCustomOptionKind) -> RecipeOptionDefinition? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return options(for: kind).first { $0.matches(trimmed) }
    }

    static func menuLabel(for rawValue: String, kind: RecipeCustomOptionKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return resolve(trimmed, for: kind)?.menuLabel ?? trimmed
    }

    static func ingredientLabel(for rawValue: String, kind: RecipeCustomOptionKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return resolve(trimmed, for: kind)?.ingredientLabel ?? trimmed
    }

    static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

// MARK: - Recipe

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]? = []
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]? = []
    var imageData: Data? = nil
    @Relationship(deleteRule: .cascade, inverse: \RecipePreparationMedia.recipe)
    var preparationMedia: [RecipePreparationMedia]? = []
    var externalURLString: String = ""
    var category: String = ""
    var tags: [String] = []

    /// Categories as an array (supports comma-separated multi-category storage).
    @Transient
    var categories: [String] {
        get {
            category.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        set {
            category = newValue.joined(separator: ", ")
        }
    }
    var prepTime: Int = 0       // minutes
    var cookTime: Int = 0       // minutes
    var servings: Int = 1
    var calories: Int? = nil
    var difficulty: Difficulty = Difficulty.easy
    var isFavorite: Bool = false
    var requiredUtensils: [String]? = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

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

        let ingredientList = (ingredients ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ing in
                let labeledName = ing.preparationState.isEmpty ? ing.name : "\(ing.name) \(ing.preparationState)"
                if let qty = ing.quantity, !ing.unit.isEmpty {
                    return "- \(labeledName): \(qty) \(ing.unit)"
                } else if let qty = ing.quantity {
                    return "- \(labeledName): \(qty)"
                }
                return "- \(labeledName)"
            }
        if !ingredientList.isEmpty {
            parts.append("Ingredientes:\n\(ingredientList.joined(separator: "\n"))")
        }

        let stepList = (steps ?? [])
            .sorted { $0.order < $1.order }
            .map { "  \($0.order). \($0.instruction)" }
        if !stepList.isEmpty {
            parts.append("Passos:\n\(stepList.joined(separator: "\n"))")
        }

        if let media = preparationMedia, !media.isEmpty {
            parts.append("Mídias de preparo: \(media.count)")
        }

        return parts.joined(separator: "\n")
    }

    func compatibility(against pantryNames: [String]) -> RecipeCompatibility? {
        let normalizedIngredients = (ingredients ?? [])
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
    var id: UUID = UUID()
    var mediaTypeRaw: String = RecipePreparationMediaType.photo.rawValue
    var data: Data = Data()
    var fileExtension: String = ""
    var sortOrder: Int = 0
    var recipe: Recipe? = nil

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
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double? = nil
    var unit: String = ""
    var preparationState: String = ""
    var iconName: String? = nil
    var sortOrder: Int = 0
    var recipe: Recipe? = nil

    init(
        name: String,
        quantity: Double? = nil,
        unit: String = "",
        preparationState: String = "",
        iconName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.iconName = iconName
        self.sortOrder = sortOrder
    }

    /// Formatted display string (e.g. "200 g" or "2 xícaras").
    var formattedQuantity: String {
        guard let qty = quantity else { return "" }
        let num = qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", qty)
            : String(format: "%.1f", qty)
        let resolvedUnit = RecipeOptionCatalog.ingredientLabel(for: unit, kind: .unit)
        return resolvedUnit.isEmpty ? num : "\(num) \(resolvedUnit)"
    }

    var formattedState: String {
        RecipeOptionCatalog.ingredientLabel(for: preparationState, kind: .state)
    }

    var formattedQuantityAndState: String {
        let quantityText = formattedQuantity
        let stateText = formattedState

        if quantityText.isEmpty { return stateText }
        if stateText.isEmpty { return quantityText }
        return "\(quantityText) \(stateText)"
    }
}

// MARK: - RecipeStep

@Model
final class RecipeStep {
    var id: UUID = UUID()
    var order: Int = 0
    var instruction: String = ""
    var durationMinutes: Int? = nil
    var recipe: Recipe? = nil

    init(order: Int, instruction: String, durationMinutes: Int? = nil) {
        self.id = UUID()
        self.order = order
        self.instruction = instruction
        self.durationMinutes = durationMinutes
    }
}
