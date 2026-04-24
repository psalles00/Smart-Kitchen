import Foundation
import SwiftData

/// Uma entrada de alimento registrada pelo usuário em qualquer refeição.
/// A imagem (se houver) é armazenada em disco via `FoodImageStore`, nunca inline no modelo.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()

    var name: String = ""
    var emoji: String? = nil

    // MARK: Macros

    var calories: Int = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    // MARK: Micros (opcionais, em gramas exceto onde indicado)

    var sugarG: Double? = nil
    var addedSugarG: Double? = nil
    var fiberG: Double? = nil
    var saturatedFatG: Double? = nil
    var monounsaturatedFatG: Double? = nil
    var polyunsaturatedFatG: Double? = nil
    /// em mg
    var cholesterolMg: Double? = nil
    /// em mg
    var sodiumMg: Double? = nil
    /// em mg
    var potassiumMg: Double? = nil

    /// Tamanho da porção registrada, em gramas.
    var servingSizeGrams: Double? = nil

    // MARK: Origem

    var mealTypeRaw: String = MealType.other.rawValue
    var sourceRaw: String = FoodSource.manual.rawValue

    /// Arquivo (apenas nome) em Application Support/sk-food-images/. Nunca bytes inline.
    var imageFilename: String? = nil

    init(
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        mealType: MealType = .other,
        source: FoodSource = .manual,
        timestamp: Date = .now,
        emoji: String? = nil,
        servingSizeGrams: Double? = nil,
        imageFilename: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.name = name
        self.emoji = emoji
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.servingSizeGrams = servingSizeGrams
        self.mealTypeRaw = mealType.rawValue
        self.sourceRaw = source.rawValue
        self.imageFilename = imageFilename
    }

    // MARK: - Enum accessors

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .other }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
