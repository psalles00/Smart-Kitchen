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
            let byKey = Dictionary(parsed.map {
                (FoodCache.canonicalize($0.canonicalName), $0)
            }, uniquingKeysWith: { first, _ in first })

            return names.map { name in
                let key = FoodCache.canonicalize(name)
                if let hit = byKey[key], hit.hasReliableMacros {
                    return hit
                }
                return Self.emptyResult(name: name, locale: locale)
            }
        } catch {
            LLMLog.error("USDA lookup failed: \(error.localizedDescription)")
            return names.map { Self.emptyResult(name: $0, locale: locale) }
        }
    }

    static func parse(data: Data, locale: String) -> [Per100gNutrition] {
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

            let food = Per100gNutrition(
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
                servingGrams: nil,
                source: "usda",
                citationURL: entry["citation_url"] as? String,
                id: nil,
                upvotes: 0,
                downvotes: 0
            )
            guard food.hasReliableMacros, matchesIdentity(food.displayName ?? "", requestedName: name) else { return nil }
            return food
        }
    }

    /// Also protects clients while an older server function is still deployed.
    /// Translation aliases apply only to an entire known unbranded identity.
    static func matchesIdentity(_ displayName: String, requestedName: String) -> Bool {
        func tokens(_ text: String) -> Set<String> {
            Set(FoodCache.canonicalize(text)
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace).map(String.init))
        }
        let requested = FoodCache.canonicalize(requestedName)
        let alternatives = [requested] + (usdaIdentityAliases[requested] ?? [])
        let actual = tokens(displayName)
        let knownWholeFood = usdaIdentityAliases[requested] != nil
            || usdaIdentityAliases.values.flatMap { $0 }.contains { tokens($0) == tokens(requested) }
        let forms = [["bar", "bars"], ["powder", "powdered"], ["condensed"], ["dried", "dehydrated"], ["formula", "babyfood"],
                     ["sandwich", "sandwiches"], ["soup"], ["salad"], ["sauce"], ["with"]]
        return alternatives.contains { name in
            let expected = tokens(name)
            // Extra descriptors are allowed only for known whole foods. A brand
            // contained in a meal name is not proof of the requested product.
            return !expected.isEmpty && (knownWholeFood ? expected.isSubset(of: actual) : expected == actual) && forms.allSatisfy { forms in
                !forms.contains(where: actual.contains) || forms.contains(where: expected.contains)
            }
        }
    }

    private static let usdaIdentityAliases: [String: [String]] = [
        "arroz": ["rice"], "arroz branco": ["rice white"], "arroz cozido": ["rice cooked"],
        "arroz branco cozido": ["rice white cooked"], "arroz integral cozido": ["rice brown cooked"],
        "banana": ["banana"], "batata": ["potato"], "batata cozida": ["potato cooked"],
        "cebola": ["onion"], "cenoura": ["carrot"], "feijao": ["beans"], "feijao cozido": ["beans cooked"],
        "frango": ["chicken"], "frango grelhado": ["chicken grilled"], "peito de frango": ["chicken breast"],
        "peito de frango grelhado": ["chicken breast grilled"], "peito de frango assado": ["chicken breast roasted"],
        "iogurte": ["yogurt"], "iogurte natural": ["yogurt plain"],
        "leite": ["milk"], "leite integral": ["milk whole"], "leite desnatado": ["milk nonfat"],
        "maca": ["apple"], "ovo": ["egg"], "ovos": ["egg"], "pao": ["bread"], "pao branco": ["bread white"],
        "queijo": ["cheese"], "queijo cheddar": ["cheese cheddar"], "queijo mussarela": ["cheese mozzarella"], "tomate": ["tomato"]
    ]

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
            servingGrams: nil,
            source: "usda",
            citationURL: nil,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }
}
