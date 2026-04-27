import Foundation

/// Resultado estruturado retornado pela IA para uma refeição (texto, foto ou auto).
struct FoodAnalysis: Sendable {
    var name: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var servingSizeGrams: Double
    var emoji: String?

    // Micros (g)
    var sugarG: Double?
    var addedSugarG: Double?
    var fiberG: Double?
    var saturatedFatG: Double?
    var monounsaturatedFatG: Double?
    var polyunsaturatedFatG: Double?
    // Micros (mg)
    var cholesterolMg: Double?
    var sodiumMg: Double?
    var potassiumMg: Double?

    /// IDs das entradas no `FoodCache` (Supabase) que compuseram esta análise.
    /// Usado pelo botão de thumbs up/down para registrar votos. `nil` para
    /// análises legacy (foto, rótulo, ou quando o cache está desabilitado).
    var cachedFoodIDs: [UUID]? = nil
}

/// Rótulo nutricional lido por imagem — valores por 100 g/ml.
struct NutritionLabelAnalysis: Sendable {
    var name: String
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var servingSizeGrams: Double?

    var sugarPer100g: Double?
    var addedSugarPer100g: Double?
    var fiberPer100g: Double?
    var saturatedFatPer100g: Double?
    var monounsaturatedFatPer100g: Double?
    var polyunsaturatedFatPer100g: Double?
    var cholesterolPer100g: Double?
    var sodiumPer100g: Double?
    var potassiumPer100g: Double?

    /// Converte para uma porção de `grams` em `FoodAnalysis`.
    func scaled(to grams: Double) -> FoodAnalysis {
        let factor = grams / 100.0
        func scaleOpt(_ v: Double?) -> Double? { v.map { ($0 * factor * 10).rounded() / 10 } }
        return FoodAnalysis(
            name: name,
            calories: Int((caloriesPer100g * factor).rounded()),
            protein: Int((proteinPer100g * factor).rounded()),
            carbs: Int((carbsPer100g * factor).rounded()),
            fat: Int((fatPer100g * factor).rounded()),
            servingSizeGrams: grams,
            emoji: nil,
            sugarG: scaleOpt(sugarPer100g),
            addedSugarG: scaleOpt(addedSugarPer100g),
            fiberG: scaleOpt(fiberPer100g),
            saturatedFatG: scaleOpt(saturatedFatPer100g),
            monounsaturatedFatG: scaleOpt(monounsaturatedFatPer100g),
            polyunsaturatedFatG: scaleOpt(polyunsaturatedFatPer100g),
            cholesterolMg: scaleOpt(cholesterolPer100g),
            sodiumMg: scaleOpt(sodiumPer100g),
            potassiumMg: scaleOpt(potassiumPer100g)
        )
    }
}
