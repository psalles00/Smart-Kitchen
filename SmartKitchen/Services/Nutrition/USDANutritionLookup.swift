import Foundation

/// Looks up per-100g nutritional facts via a Supabase Edge Function backed by
/// USDA FoodData Central.
@MainActor
final class USDANutritionLookup {
    private let supabase = SupabaseClient()

    func fetchPer100g(
        for names: [String],
        locale: String = AppLocalization.current().nutritionCacheLocaleIdentifier
    ) async -> [Per100gNutrition] {
        guard !names.isEmpty else { return [] }
        guard supabase.isConfigured else {
            return names.map { Self.emptyResult(name: $0, locale: locale) }
        }

        do {
            let data = try await supabase.invokeFunctionData(
                name: "usda-food-search",
                body: [
                    "names": names,
                    "locale": locale
                ],
                acceptLanguage: AppLocalization.current().acceptLanguageHeader
            )

            let parsed = Self.parse(data: data, locale: locale)
            let byKey = Dictionary(uniqueKeysWithValues: parsed.map {
                (FoodCache.canonicalize($0.canonicalName), $0)
            })

            return names.map { name in
                let key = FoodCache.canonicalize(name)
                if let hit = byKey[key], hit.hasMacros {
                    return hit
                }
                return Self.emptyResult(name: name, locale: locale)
            }
        } catch {
            LLMLog.error("USDA lookup failed: \(error.localizedDescription)")
            return names.map { Self.emptyResult(name: $0, locale: locale) }
        }
    }

    private static func parse(data: Data, locale: String) -> [Per100gNutrition] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let kcal = numeric(entry["kcal_per_100g"])
            let protein = numeric(entry["protein_per_100g"])
            let carbs = numeric(entry["carbs_per_100g"])
            let fat = numeric(entry["fat_per_100g"])

            guard let kcal, let protein, let carbs, let fat else {
                return nil
            }

            return Per100gNutrition(
                canonicalName: FoodCache.canonicalize(name),
                locale: locale,
                displayName: (entry["display_name"] as? String) ?? name,
                kcal: kcal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                sugar: numeric(entry["sugar_per_100g"]),
                addedSugar: numeric(entry["added_sugar_per_100g"]),
                fiber: numeric(entry["fiber_per_100g"]),
                saturatedFat: numeric(entry["saturated_fat_per_100g"]),
                monounsaturatedFat: numeric(entry["monounsaturated_fat_per_100g"]),
                polyunsaturatedFat: numeric(entry["polyunsaturated_fat_per_100g"]),
                cholesterol: numeric(entry["cholesterol_per_100g"]),
                sodium: numeric(entry["sodium_per_100g"]),
                potassium: numeric(entry["potassium_per_100g"]),
                emoji: entry["emoji"] as? String,
                source: "usda",
                citationURL: entry["citation_url"] as? String,
                id: nil,
                upvotes: 0,
                downvotes: 0
            )
        }
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func emptyResult(name: String, locale: String) -> Per100gNutrition {
        Per100gNutrition(
            canonicalName: FoodCache.canonicalize(name),
            locale: locale,
            displayName: name,
            kcal: nil,
            protein: nil,
            carbs: nil,
            fat: nil,
            sugar: nil,
            addedSugar: nil,
            fiber: nil,
            saturatedFat: nil,
            monounsaturatedFat: nil,
            polyunsaturatedFat: nil,
            cholesterol: nil,
            sodium: nil,
            potassium: nil,
            emoji: nil,
            source: "usda",
            citationURL: nil,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }
}