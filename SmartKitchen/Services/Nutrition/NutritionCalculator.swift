import Foundation

/// Pure-Swift combiner: turns a list of `(parsed item, per-100g data)` into a
/// single `FoodAnalysis` for the meal.
///
/// Unit normalization tries to be generous but conservative. When a lookup
/// provides a typical serving size, unknown-unit entries use that; otherwise
/// they fall back to a local portion heuristic.
@MainActor
enum NutritionCalculator {

    /// Default portion grams when `quantity`/`unit` cannot be resolved.
    static let defaultPortionGrams: Double = 100

    struct Resolved {
        let item: NutritionItemParser.ParsedItem
        let per100g: Per100gNutrition
    }

    static func combine(
        items: [Resolved],
        originalDescription: String,
        componentCount: Int? = nil
    ) -> FoodAnalysis {
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0, totalGrams = 0.0
        var sugar = 0.0, addedSugar = 0.0, fiber = 0.0
        var sat = 0.0, mono = 0.0, poly = 0.0
        var cholesterol = 0.0, sodium = 0.0, potassium = 0.0
        var hasSugar = false, hasAddedSugar = false, hasFiber = false
        var hasSat = false, hasMono = false, hasPoly = false
        var hasCholesterol = false, hasSodium = false, hasPotassium = false

        for entry in items {
            let grams = grams(for: entry.item, nutrition: entry.per100g)
            let f = grams / 100.0
            totalGrams += grams

            kcal    += (entry.per100g.kcal    ?? 0) * f
            protein += (entry.per100g.protein ?? 0) * f
            carbs   += (entry.per100g.carbs   ?? 0) * f
            fat     += (entry.per100g.fat     ?? 0) * f

            if let v = entry.per100g.sugar              { sugar += v * f; hasSugar = true }
            if let v = entry.per100g.addedSugar         { addedSugar += v * f; hasAddedSugar = true }
            if let v = entry.per100g.fiber              { fiber += v * f; hasFiber = true }
            if let v = entry.per100g.saturatedFat       { sat += v * f; hasSat = true }
            if let v = entry.per100g.monounsaturatedFat { mono += v * f; hasMono = true }
            if let v = entry.per100g.polyunsaturatedFat { poly += v * f; hasPoly = true }
            if let v = entry.per100g.cholesterol        { cholesterol += v * f; hasCholesterol = true }
            if let v = entry.per100g.sodium             { sodium += v * f; hasSodium = true }
            if let v = entry.per100g.potassium          { potassium += v * f; hasPotassium = true }
        }

        let displayName: String = {
            if items.count == 1 {
                return items[0].item.name
            }
            return originalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let emoji = items.first?.per100g.emoji

        return FoodAnalysis(
            name: displayName,
            calories: Int(kcal.rounded()),
            protein:  Int(protein.rounded()),
            carbs:    Int(carbs.rounded()),
            fat:      Int(fat.rounded()),
            servingSizeGrams: totalGrams > 0 ? round1(totalGrams) : defaultPortionGrams,
            emoji: emoji,
            componentCount: max(componentCount ?? items.count, 1),
            sugarG:              hasSugar         ? round1(sugar)       : nil,
            addedSugarG:         hasAddedSugar    ? round1(addedSugar)  : nil,
            fiberG:              hasFiber         ? round1(fiber)       : nil,
            saturatedFatG:       hasSat           ? round1(sat)         : nil,
            monounsaturatedFatG: hasMono          ? round1(mono)        : nil,
            polyunsaturatedFatG: hasPoly          ? round1(poly)        : nil,
            cholesterolMg:       hasCholesterol   ? round1(cholesterol) : nil,
            sodiumMg:            hasSodium        ? round1(sodium)      : nil,
            potassiumMg:         hasPotassium     ? round1(potassium)   : nil
        )
    }

    // MARK: - Unit normalization

    /// Best-effort conversion of `(quantity, unit)` to grams. Returns
    /// `defaultPortionGrams` when the unit is missing or unrecognized.
    static func grams(for item: NutritionItemParser.ParsedItem, name: String) -> Double {
        grams(for: item, name: name, servingGrams: nil)
    }

    static func grams(for item: NutritionItemParser.ParsedItem, nutrition: Per100gNutrition) -> Double {
        grams(for: item, name: nutrition.canonicalName, servingGrams: nutrition.servingGrams)
    }

    private static func grams(for item: NutritionItemParser.ParsedItem, name: String, servingGrams: Double?) -> Double {
        let qty = item.quantity ?? 1.0
        guard let rawUnit = item.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUnit.isEmpty else {
            return qty * (validServingGrams(servingGrams) ?? perPieceGrams(for: name))
        }
        let unit = rawUnit
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()

        switch unit {
        case "g", "grama", "gramas":
            return qty
        case "kg", "kilo", "quilo", "quilos":
            return qty * 1000
        case "mg":
            return qty / 1000
        case "ml", "mililitro", "mililitros":
            // Treat 1 ml ~= 1 g for cooking purposes (water-equivalent). Good
            // enough for nutrition estimation.
            return qty
        case "l", "litro", "litros":
            return qty * 1000
        case "un", "unidade", "unidades", "und":
            return qty * (validServingGrams(servingGrams) ?? perPieceGrams(for: name))
        case "xicara", "xicaras", "xicara de cha", "xicara de cafe":
            return qty * 240
        case "colher de sopa", "colher sopa", "colheres de sopa":
            return qty * 15
        case "colher de cha", "colher cha", "colheres de cha":
            return qty * 5
        case "fatia", "fatias":
            return qty * sliceGrams(for: name)
        case "concha", "conchas":
            return qty * 100
        case "copo", "copos":
            return qty * 200
        case "porcao", "porcoes":
            return qty * defaultPortionGrams
        default:
            return qty * defaultPortionGrams
        }
    }

    private static func validServingGrams(_ value: Double?) -> Double? {
        guard let value, value >= 5, value <= 1500 else { return nil }
        return value
    }

    /// Heuristic per-piece weight when `unit == "un"` or no unit is given.
    /// Conservative defaults that round to a recognizable number of grams.
    private static func perPieceGrams(for name: String) -> Double {
        let n = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
        if n.contains("x tudo") || n.contains("xis tudo") { return 350 }
        if n.contains("x duplo") || n.contains("xis duplo") { return 300 }
        if n.hasPrefix("x ") || n.hasPrefix("xis ") || n.contains(" x-") { return 280 }
        if n.contains("requeijao") || n.contains("cream cheese") { return 30 }
        if n.contains("acucar") || n.contains("sugar") { return 5 }
        if n.contains("leite") || n.contains("milk") { return 200 }
        if n.contains("cafe") || n.contains("coffee") { return 100 }
        if n.contains("hamburguer") || n.contains("hamburger") || n.contains("burger") { return 220 }
        if n.contains("sanduiche") || n.contains("sandwich") { return 160 }
        if n.contains("hot dog") || n.contains("cachorro quente") { return 170 }
        if n.contains("coxinha") { return 110 }
        if n.contains("pastel") { return 130 }
        if n.contains("pizza") { return 120 }
        if n.contains("ovo")      { return 50 }
        if n.contains("banana")   { return 120 }
        if n.contains("maca")     { return 180 }
        if n.contains("laranja")  { return 130 }
        if n.contains("pao frances") || n.contains("pao") { return 50 }
        if n.contains("biscoito") || n.contains("bolacha") { return 8 }
        if n.contains("queijo")   { return 30 }
        return defaultPortionGrams
    }

    private static func sliceGrams(for name: String) -> Double {
        let n = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
        if n.contains("pizza") { return 120 }
        if n.contains("pao de forma") || n.contains("bread") { return 25 }
        if n.contains("queijo") || n.contains("cheese") { return 20 }
        return 30
    }

    private static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
