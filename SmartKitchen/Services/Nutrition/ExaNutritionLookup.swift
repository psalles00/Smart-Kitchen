import Foundation

/// Asks Exa for canonical per-100g nutritional facts of a batch of items in
/// a single `/answer` call, restricted to authoritative sources.
///
/// Exa returns a JSON object matching our schema (`items[]`), each element
/// covering one input name. The orchestrator then matches the response back to
/// the originally parsed items by canonical name.
@MainActor
final class ExaNutritionLookup {

    private let client: ExaClient

    /// Authoritative sources for nutritional data:
    /// - Open Food Facts: best for branded/Brazilian packaged products
    /// - USDA FoodData Central: gold standard for whole foods
    /// - TBCA / Unicamp TACO: Brazilian table of food composition
    private static let domains = [
        "world.openfoodfacts.org",
        "fdc.nal.usda.gov",
        "tbca.net.br",
        "unicamp.br",
        "coca-cola.com",
        "nutella.com",
        "ferrero.com",
        "nestle.com.br",
        "receitasnestle.com.br",
        "nestle.co.uk",
        "kelloggs.com",
        "kelloggs.co.uk"
    ]

    init(client: ExaClient = ExaClient()) {
        self.client = client
    }

    /// Returns one `Per100gNutrition` entry per input name. Items Exa couldn't
    /// resolve are returned with empty macros (`hasMacros == false`) so the
    /// orchestrator can fall back to the LLM for just those.
    func fetchPer100g(for names: [String], locale: String = AppLocalization.current().nutritionCacheLocaleIdentifier) async throws -> [Per100gNutrition] {
        guard !names.isEmpty else { return [] }
        guard APIConfig.hasExaBackend else {
            // Exa not configured — return empty placeholders so the caller
            // falls straight through to the LLM path.
            return names.map { Self.emptyResult(name: $0, locale: locale) }
        }

        let query = Self.buildQuery(names: names, locale: locale)
        let schema = Self.outputSchema()

        let result: ExaClient.AnswerResult
        do {
            result = try await client.answer(
                query: query,
                outputSchema: schema,
                includeDomains: Self.domains,
                apiKey: APIConfig.exaAPIKey
            )
        } catch {
            LLMLog.error("Exa lookup failed: \(error.localizedDescription)")
            return names.map { Self.emptyResult(name: $0, locale: locale) }
        }

        let parsed = Self.parse(answer: result.rawAnswer, citations: result.citations.map(\.url), locale: locale)

        // Re-align: ensure one entry per requested name (matched by canonical
        // form). Missing entries become empty placeholders for LLM fallback.
        let byKey = Dictionary(parsed.map {
            (FoodCache.canonicalize($0.canonicalName), $0)
        }, uniquingKeysWith: { first, _ in first })
        return names.map { name in
            let key = FoodCache.canonicalize(name)
            if let hit = byKey[key], hit.hasReliableMacros { return hit }
            return Self.emptyResult(name: name, locale: locale)
        }
    }

    // MARK: - Query / Schema

    private static func buildQuery(names: [String], locale: String) -> String {
        let list = names.map { "- \($0)" }.joined(separator: "\n")
        return """
        Para cada alimento listado abaixo, retorne os valores nutricionais por 100g \
        (ou por 100ml para líquidos). Responda em \(locale). Priorize o rótulo \
        oficial do fabricante para a marca, variante e país informados. Para \
        alimentos comuns, use USDA FoodData Central ou TBCA/TACO Unicamp; \
        Open Food Facts é uma alternativa de rótulo. Nunca substitua marca, \
        país ou variante por um produto semelhante. Nunca confunda valores por \
        porção com valores por 100g/100ml. Copie exatamente o nome da lista no \
        campo name e inclua citation_url da fonte de cada item. Se não houver \
        rótulo compatível ou fonte verificável, omita o item, sem inventar números.

        Alimentos:
        \(list)
        """
    }

    private static func outputSchema() -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name":              ["type": "string"],
                            "display_name":      ["type": "string"],
                            "citation_url":      ["type": "string"],
                            "kcal_per_100g":     ["type": "number"],
                            "protein_per_100g":  ["type": "number"],
                            "carbs_per_100g":    ["type": "number"],
                            "fat_per_100g":      ["type": "number"],
                            "sugar_per_100g":         ["type": ["number", "null"]],
                            "added_sugar_per_100g":   ["type": ["number", "null"]],
                            "fiber_per_100g":         ["type": ["number", "null"]],
                            "saturated_fat_per_100g": ["type": ["number", "null"]],
                            "monounsaturated_fat_per_100g": ["type": ["number", "null"]],
                            "polyunsaturated_fat_per_100g": ["type": ["number", "null"]],
                            "cholesterol_per_100g":   ["type": ["number", "null"]],
                            "sodium_per_100g":        ["type": ["number", "null"]],
                            "potassium_per_100g":     ["type": ["number", "null"]],
                            "emoji":                  ["type": ["string", "null"]]
                        ],
                        "required": ["name", "citation_url", "kcal_per_100g", "protein_per_100g", "carbs_per_100g", "fat_per_100g"]
                    ]
                ]
            ],
            "required": ["items"]
        ]
    }

    // MARK: - Parsing

    static func parse(answer: Any, citations: [String], locale: String) -> [Per100gNutrition] {
        // `answer` may already be a dict (when outputSchema is honored) or a
        // JSON string (Exa sometimes returns the schema value as a string).
        var dict: [String: Any]?
        if let d = answer as? [String: Any] {
            dict = d
        } else if let s = answer as? String,
                  let data = s.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = parsed
        }
        guard let items = dict?["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { entry -> Per100gNutrition? in
            guard let name = entry["name"] as? String,
                  let citation = entry["citation_url"] as? String,
                  let citationKey = trustedCitationKey(citation),
                  citations.contains(where: { trustedCitationKey($0) == citationKey }) else { return nil }
            let kcal     = numeric(entry["kcal_per_100g"])
            let protein  = numeric(entry["protein_per_100g"])
            let carbs    = numeric(entry["carbs_per_100g"])
            let fat      = numeric(entry["fat_per_100g"])
            guard let kcal, let protein, let carbs, let fat else { return nil }

            let food = Per100gNutrition(
                canonicalName: FoodCache.canonicalize(name),
                locale: locale,
                displayName: (entry["display_name"] as? String) ?? name,
                kcal: kcal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                sugar:              numeric(entry["sugar_per_100g"]),
                addedSugar:         numeric(entry["added_sugar_per_100g"]),
                fiber:              numeric(entry["fiber_per_100g"]),
                saturatedFat:       numeric(entry["saturated_fat_per_100g"]),
                monounsaturatedFat: numeric(entry["monounsaturated_fat_per_100g"]),
                polyunsaturatedFat: numeric(entry["polyunsaturated_fat_per_100g"]),
                cholesterol:        numeric(entry["cholesterol_per_100g"]),
                sodium:             numeric(entry["sodium_per_100g"]),
                potassium:          numeric(entry["potassium_per_100g"]),
                emoji: entry["emoji"] as? String,
                servingGrams: nil,
                source: "exa",
                citationURL: citation,
                id: nil,
                upvotes: 0,
                downvotes: 0
            )
            return food.hasReliableMacros ? food : nil
        }
    }

    private static func trustedCitationKey(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw), components.scheme == "https",
              let host = components.host?.lowercased(),
              domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        components.fragment = nil
        return components.string
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
            kcal: nil, protein: nil, carbs: nil, fat: nil,
            sugar: nil, addedSugar: nil, fiber: nil,
            saturatedFat: nil, monounsaturatedFat: nil, polyunsaturatedFat: nil,
            cholesterol: nil, sodium: nil, potassium: nil,
            emoji: nil, servingGrams: nil, source: "exa", citationURL: nil, id: nil,
            upvotes: 0, downvotes: 0
        )
    }
}
