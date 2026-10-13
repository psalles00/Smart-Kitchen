import Foundation

/// Asks Exa for canonical per-100g nutritional facts of a batch of items in
/// a single `/answer` call. Source restrictions are checked locally because
/// `/answer` does not document a domain-filter parameter.
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
        let schema = Self.outputSchema(names: names)

        let result: ExaClient.AnswerResult
        do {
            result = try await client.answer(
                query: query,
                systemPrompt: Self.buildInstructions(names: names, locale: locale),
                outputSchema: schema,
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

    static func buildQuery(names: [String], locale: String) -> String {
        // Search the foods, not the conversion examples or response rules.
        "Official nutrition label per 100g or 100ml: " + names.map { name in
            let manufacturers = manufacturerDomains(for: name)
            return manufacturers.isEmpty ? name : name + " (" + manufacturers.joined(separator: ", ") + ")"
        }.joined(separator: "; ")
    }

    private static func buildInstructions(names: [String], locale: String) -> String {
        let list = names.map { name in
            let manufacturers = manufacturerDomains(for: name)
            let sourceRule = manufacturers.isEmpty ? "" : " [fonte obrigatória: " + manufacturers.joined(separator: ", ") + "]"
            return "- \(name)\(sourceRule)"
        }.joined(separator: "\n")
        return """
        Para cada alimento listado abaixo, retorne os valores nutricionais por 100g \
        (ou por 100ml para líquidos). Responda em \(locale). Priorize o rótulo \
        oficial do fabricante para a marca, variante e país informados. Para \
        alimentos comuns, use USDA FoodData Central ou TBCA/TACO Unicamp; \
        Open Food Facts é uma alternativa apenas quando o item não exige uma \
        fonte de fabricante. Para fonte obrigatória, use somente os domínios \
        indicados e a página do país solicitado; omita o item se não encontrar. \
        Nunca substitua marca, \
        país ou variante por um produto semelhante. Nunca confunda valores por \
        porção com valores por 100g/100ml. Copie exatamente o nome da lista no \
        campo name e inclua citation_url da fonte de cada item. Se não houver \
        rótulo compatível ou fonte verificável, omita o item, sem inventar números.
        Açúcares, fibra e gorduras são em gramas. Colesterol, sódio e potássio \
        usam os campos *_mg_per_100g, sempre em miligramas: 0,1g de sódio = \
        100mg. Sal não é sódio: converta sal em sódio dividindo por 2,5; \
        0,1g de sal = 40mg de sódio. Use null se a unidade não estiver confirmada.

        Alimentos:
        \(list)
        """
    }

    static func outputSchema(names: [String]) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name":              ["type": "string", "enum": names],
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
                            "cholesterol_mg_per_100g": ["type": ["number", "null"], "description": "Cholesterol in milligrams per 100g, never grams"],
                            "sodium_mg_per_100g":      ["type": ["number", "null"], "description": "Sodium in milligrams per 100g; salt grams / 2.5 * 1000"],
                            "potassium_mg_per_100g":   ["type": ["number", "null"], "description": "Potassium in milligrams per 100g, never grams"],
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
                  acceptsCitation(citation, for: name),
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
                // Legacy keys did not declare units and could contain grams.
                cholesterol:        numeric(entry["cholesterol_mg_per_100g"]),
                sodium:             numeric(entry["sodium_mg_per_100g"]),
                potassium:          numeric(entry["potassium_mg_per_100g"]),
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

    /// A community entry is not a substitute for a known manufacturer's label.
    /// The same rule also applies to cached references from older analyses.
    static func acceptsCitation(_ raw: String?, for name: String) -> Bool {
        guard let raw, trustedCitationKey(raw) != nil,
              let url = URL(string: raw), let host = url.host?.lowercased() else { return false }
        let manufacturers = manufacturerDomains(for: name)
        guard !manufacturers.isEmpty else { return true }
        guard manufacturers.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        let normalized = sourceIdentity(name)
        let words = Set(normalized.components(separatedBy: " "))
        let path = url.path.lowercased()
        guard matchesProductPath(path, requested: normalized) else { return false }
        let regionalCodes: Set<String> = ["us", "uk", "gb", "br", "mx", "ca", "au", "fr", "de", "es", "it"]
        let pathRegions = Set(path.split(separator: "/").compactMap { component -> String? in
            let value = String(component)
            if regionalCodes.contains(value) { return value }
            // Manufacturers use both language-region (en_US) and region-language (us-en).
            guard value.range(of: #"^[a-z]{2}[_-][a-z]{2}$"#, options: .regularExpression) != nil else { return nil }
            let parts = value.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
            if let last = parts.last, regionalCodes.contains(last) { return last }
            if let first = parts.first, regionalCodes.contains(first) { return first }
            return nil
        })
        if words.contains("uk") || normalized.contains("reino unido") || normalized.contains("united kingdom") {
            guard !host.hasSuffix(".br") else { return false }
            guard pathRegions.isSubset(of: ["uk", "gb"]) else { return false }
            return path.hasPrefix("/uk/") || path == "/uk" || host.hasSuffix(".co.uk") || path.hasPrefix("/gb/")
        }
        if words.contains("eua") || words.contains("usa") || words.contains("us") || normalized.contains("estados unidos") || normalized.contains("united states") {
            guard !host.hasSuffix(".co.uk"), !host.hasSuffix(".br") else { return false }
            guard pathRegions.isSubset(of: ["us"]) else { return false }
            return path.hasPrefix("/us/") || path == "/us"
        }
        if !words.isDisjoint(with: ["brasil", "brazil", "brazilian", "brasileiro", "brasileira"]) {
            guard !host.hasSuffix(".co.uk") else { return false }
            guard pathRegions.isSubset(of: ["br"]) else { return false }
            return host.hasSuffix(".br") || path.hasPrefix("/br/") || path == "/br"
        }
        return true
    }

    private static func matchesProductPath(_ path: String, requested name: String) -> Bool {
        let sections = Set(path.split(separator: "/").map(String.init))
        let editorialSections: Set<String> = ["recipes", "receitas", "recetas", "recettes", "rezepte", "ricette", "get-inspired", "articles", "artigos", "news", "noticias", "stories", "blog"]
        guard sections.isDisjoint(with: editorialSections),
              !sections.isDisjoint(with: ["products", "produtos", "productos", "produits", "produkte", "prodotti"]) else { return false }
        let identity = sourceIdentity(path)
        if name.contains("coca cola") {
            guard identity.contains("coca cola") else { return false }
            for aliases in [["original"], ["zero"], ["diet"], ["light"], ["vanilla", "baunilha"], ["cherry", "cereja"], ["caffeine free", "sem cafeina"]] {
                if aliases.contains(where: { name.contains($0) }) != aliases.contains(where: { identity.contains($0) }) { return false }
            }
            return true
        }
        if name.contains("nutella") {
            guard identity.contains("nutella") else { return false }
            for variant in ["biscuits", "b ready", "plant based", "ice cream"] {
                if name.contains(variant) != identity.contains(variant) { return false }
            }
            return true
        }
        if name.components(separatedBy: " ").contains("moca") {
            guard identity.contains("moca"), path.contains("/produtos/") || path.contains("/products/") else { return false }
            if name.contains("tradicional") || name.contains("traditional") {
                guard identity.contains("tradicional") || identity.contains("traditional") else { return false }
            }
            if name.contains("integral"), !identity.contains("integral"), !identity.contains("tradicional") { return false }
            if name.contains("semidesnatado") != identity.contains("semidesnatado") { return false }
            return true
        }
        if name.contains("kellogg") {
            // A brand and "cereal" alone cannot identify one of its many products.
            let variants = [["corn flakes", "cornflakes"], ["sucrilhos", "frosted flakes"], ["all bran"], ["special k"], ["nutri grain"], ["froot loops"]]
            let requestedVariants = variants.indices.filter { index in variants[index].contains(where: { name.contains($0) }) }
            let sourceVariants = variants.indices.filter { index in variants[index].contains(where: { identity.contains($0) }) }
            return requestedVariants.count == 1 && requestedVariants == sourceVariants
        }
        return false
    }

    private static func manufacturerDomains(for name: String) -> [String] {
        let normalized = sourceIdentity(name)
        if normalized.contains("coca cola") { return ["coca-cola.com"] }
        if normalized.contains("nutella") { return ["nutella.com", "ferrero.com"] }
        if normalized.components(separatedBy: " ").contains("moca") { return ["receitasnestle.com.br", "nestle.com.br"] }
        if normalized.contains("kellogg") { return ["kelloggs.com", "kelloggs.co.uk"] }
        return []
    }

    private static func sourceIdentity(_ name: String) -> String {
        FoodCache.canonicalize(name)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
