import Foundation

/// Resultado estruturado de uma ideia de receita retornada pela EXA.
struct RecipeIdeaResult: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let summary: String
    let ingredients: [String]
    let steps: [String]
    let sourceURL: String?
    /// URL de imagem hero retornada pela EXA (favicon/imagem do artigo).
    let heroImageURL: String?
    /// Nome do principal ingrediente, usado como fallback de ícone.
    let mainIngredient: String?
    /// Texto bruto da página (usado para parser sob demanda quando o usuário abre o card).
    let rawText: String?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        ingredients: [String],
        steps: [String],
        sourceURL: String?,
        heroImageURL: String?,
        mainIngredient: String?,
        rawText: String?
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.ingredients = ingredients
        self.steps = steps
        self.sourceURL = sourceURL
        self.heroImageURL = heroImageURL
        self.mainIngredient = mainIngredient
        self.rawText = rawText
    }

    var sourceHost: String? {
        guard let urlString = sourceURL,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

/// Conservative source evidence, before a card is offered. Unknown formats stay
/// unknown; a title, icon, summary, or a related-recipe block never proves stock.
@MainActor
private struct RecipeWebSourceFacts {
    let ingredients: [String]
    let preparation: String
    let totalMinutes: Int?

    init?(text: String) {
        let lines = text.components(separatedBy: .newlines)
        func heading(_ line: String) -> String {
            EXARecipeIdeasService.normalize(line)
                .replacingOccurrences(of: #"^[#*\s]+|[:：*\s]+$"#, with: "", options: .regularExpression)
        }
        let ingredientHeaders = ["ingredientes", "ingredients", "zutaten", "ingredienti", "材料"]
        let methodHeaders = ["modo de preparo", "modo de fazer", "como fazer", "preparation", "method", "directions", "instructions", "instrucciones", "preparacion", "zubereitung", "preparazione", "procedimento", "作り方", "手順"]
        guard let start = lines.firstIndex(where: { ingredientHeaders.contains(heading($0)) }),
              let end = lines.indices.dropFirst(start + 1).first(where: { methodHeaders.contains(heading(lines[$0])) }),
              end > start + 1, end - start < 100 else { return nil }
        let rawIngredients = lines[(start + 1)..<end].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A second section or a truncated list cannot be silently skipped.
        guard !rawIngredients.isEmpty, rawIngredients.count <= 50,
              !rawIngredients.contains(where: { $0.hasPrefix("#") }) else { return nil }
        let required = rawIngredients.filter {
            EXARecipeIdeasService.normalize($0).range(of: #"\((?:opcional|optional|facultatif|facultative|opzionale|任意|お好みで)\)\s*$"#, options: .regularExpression) == nil
        }
        let names = required.map(Self.ingredientName)
        guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty }) else { return nil }
        ingredients = names
        let tail = lines.dropFirst(end + 1)
        let methodEnd = tail.firstIndex { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#") ||
            ["sobraram ingredientes?", "comentarios", "comments", "related recipes"].contains(heading(line))
        } ?? lines.endIndex
        preparation = lines[(end + 1)..<methodEnd].joined(separator: "\n")
        guard !preparation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let metadata = lines[..<start].suffix(40).joined(separator: "\n")
        totalMinutes = Self.totalTime(in: metadata)
    }

    func availableIngredients(in pantry: [String]) -> [String]? {
        var available: [String] = []
        for ingredient in ingredients {
            if let item = pantry.first(where: { Self.canonicalName($0) == Self.canonicalName(ingredient) }) {
                available.append(item)
                continue
            }
            // "Sal e pimenta" requires both. No salt/oil/water is assumed.
            let components = ingredient.components(separatedBy: " e ")
            guard components.count > 1 else { return nil }
            for component in components {
                guard let item = pantry.first(where: { Self.canonicalName($0) == Self.canonicalName(component) }) else { return nil }
                available.append(item)
            }
        }
        return available
    }

    static func canonicalName(_ value: String) -> String {
        // Explicit grammatical forms only; cooking state and compound names
        // remain significant. In particular, rice != cooked rice.
        let plurals = ["ovos": "ovo", "tomates": "tomate", "cenouras": "cenoura", "cebolas": "cebola", "batatas": "batata",
                       "eggs": "egg", "tomatoes": "tomato", "carrots": "carrot", "onions": "onion", "potatoes": "potato",
                       "huevos": "huevo", "zanahorias": "zanahoria", "cebollas": "cebolla", "patatas": "patata",
                       "oeufs": "oeuf", "oignons": "oignon", "carottes": "carotte", "eier": "ei", "tomaten": "tomate",
                       "karotten": "karotte", "zwiebeln": "zwiebel", "pomodori": "pomodoro", "carote": "carota", "cipolle": "cipolla"]
        return EXARecipeIdeasService.normalize(value).split(whereSeparator: \.isWhitespace)
            .map { plurals[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func ingredientName(_ line: String) -> String {
        var value = EXARecipeIdeasService.normalize(line)
            .replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
        let number = #"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?|[½¼¾⅓⅔])"#
        value = value.replacingOccurrences(of: "^" + number + #"\s*"#, with: "", options: .regularExpression)
        let unit = #"(?:kg|mg|gr|g|ml|l|unidades?|un|dentes?|folhas?|pitadas?|tabletes?|xicaras?(?:\s*\([^)]*\))?|colheres?(?:\s*\([^)]*\)|\s+de\s+(?:sopa|cha|cafe))?|cups?|tablespoons?|teaspoons?|tbsp|tsp|cloves?|stuck|el|tl|cucharadas?|cucharaditas?|cucchiai?|cucchiaini?)"#
        value = value.replacingOccurrences(of: "^" + unit + #"(?=\s|$)\s*(?:de\s+|of\s+)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:de|of)\s+"#, with: "", options: .regularExpression)
        let cut = #"(?:picad[oa]s?|ralad[oa]s?|a gosto|em cubos|em rodelas|chopped|diced|grated|to taste|gehackt|gerieben|al gusto|trite|tritato|hach[eé]es?|nach geschmack)"#
        value = value.replacingOccurrences(of: #"(?:[,\s]+"# + cut + #")+\s*$"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func totalTime(in text: String) -> Int? {
        // "Prep time" alone is not a total; never add unrelated step timings.
        let value = EXARecipeIdeasService.normalize(text)
        let pattern = #"(?:\b(?:tempo total|tempo|total time|temps total|tiempo total|gesamtzeit|tempo totale)|調理時間)\s*[:：]\s*(\d+)\s*(?:min|minutos?|minutes?|minuten|minuti|分)\b|(?m)^\s*(\d+)\s*min\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        for group in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: group), in: value), let minutes = Int(value[range]) { return minutes }
        }
        return nil
    }

    static func isCollection(title: String, url: String?) -> Bool {
        let title = EXARecipeIdeasService.normalize(title)
        if title.range(of: #"\b\d+\s+(?:receitas|pratos|recipes|dishes|recetas|platos|recettes|plats|rezepte|gerichte|ricette|piatti)\b|\d+\s*(?:選|品のレシピ)"#, options: .regularExpression) != nil { return true }
        let path = URL(string: url ?? "")?.path.lowercased() ?? ""
        return ["/dicas-de-cozinha/", "/recipe-collection/", "/recipe-collections/", "/collections/"].contains(where: path.contains)
    }
}

// MARK: - Service

/// Busca ideias de receitas via EXA `/search` (web search com extração de conteúdo).
@MainActor
final class EXARecipeIdeasService {
    static let shared = EXARecipeIdeasService()

    private let endpoint = URL(string: "https://api.exa.ai/search")!
    private let supabase: any SupabaseFunctionInvoking

    init(supabase: any SupabaseFunctionInvoking = SupabaseClient()) {
        self.supabase = supabase
    }

    /// Cache em memória por sessão.
    private struct CacheEntry {
        let results: [RecipeIdeaResult]
        let date: Date
    }
    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 60 * 60 * 6 // 6h

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case empty

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return String(localized: "Chave Exa não configurada.")
            case .invalidResponse: return String(localized: "Resposta inválida da EXA.")
            case .apiError(let code, let msg): return String(localized: "EXA \(code): \(msg)")
            case .empty: return String(localized: "Nenhuma ideia encontrada agora. Tente novamente.")
            }
        }
    }

    // MARK: Public

    /// Busca novas ideias de receitas.
    func search(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        pantryItems: [String],
        filterByPantry: Bool,
        language: AppLanguage,
        requestContext: RecipeIdeaRequest? = nil,
        excludingURLs: [String] = [],
        limit: Int = 6,
        seed: Int = 0
    ) async throws -> [RecipeIdeaResult] {
        guard limit > 0 else { return [] }
        let limit = min(limit, 10)
        let request = requestContext ?? RecipeIdeaRequest(occasion: occasion?.label, refinement: refinement, customQuery: customQuery)
        guard !request.onlySavedRecipes else { return [] }
        let filterByPantry = request.pantryOverride ?? filterByPantry
        let pantryItems = request.allowedPantryItems(pantryItems).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !filterByPantry || !pantryItems.isEmpty else { return [] }
        let key = cacheKey(
            occasion: occasion,
            refinement: refinement,
            customQuery: request.searchText,
            pantryItems: pantryItems,
            filterByPantry: filterByPantry,
            language: language,
            seed: seed,
            limit: limit,
            excludingURLs: excludingURLs
        )

        if let entry = cache[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.results
        }

        let apiKey = APIConfig.exaAPIKey

        let query = buildQuery(
            occasion: occasion,
            refinement: nil,
            customQuery: request.searchText,
            pantryItems: pantryItems,
            filterByPantry: filterByPantry,
            language: language,
            seed: seed,
            maximumMinutes: request.maximumMinutes
        )

        var results = try await performSearch(
            query: query,
            limit: limit,
            apiKey: apiKey,
            preferDomains: true,
            language: language,
            excludingURLs: excludingURLs,
            requestContext: request,
            pantryItems: pantryItems,
            filterByPantry: filterByPantry
        )

        // Fallback 1: tenta sem restringir domínios (broader web).
        if results.isEmpty {
            results = try await performSearch(
                query: query,
                limit: limit,
                apiKey: apiKey,
                preferDomains: false,
                language: language,
                excludingURLs: excludingURLs,
                requestContext: request,
                pantryItems: pantryItems,
                filterByPantry: filterByPantry
            )
        }

        guard !results.isEmpty else { throw ServiceError.empty }

        // Keep source relevance within a food group, but do not fill the first
        // row with six variations of the same main ingredient.
        var remaining = results
        var diverse: [RecipeIdeaResult] = []
        while !remaining.isEmpty {
            var foods = Set<String>()
            var next: [RecipeIdeaResult] = []
            for result in remaining {
                let food = result.mainIngredient.map(RecipeWebSourceFacts.canonicalName) ?? result.title
                if foods.insert(food).inserted { diverse.append(result) } else { next.append(result) }
            }
            remaining = next
        }
        results = Array(diverse.prefix(limit))
        cache[key] = CacheEntry(results: results, date: Date())
        return results
    }

    // MARK: HTTP

    private func performSearch(
        query: String,
        limit: Int,
        apiKey: String,
        preferDomains: Bool,
        language: AppLanguage,
        excludingURLs: [String],
        requestContext: RecipeIdeaRequest,
        pantryItems: [String],
        filterByPantry: Bool
    ) async throws -> [RecipeIdeaResult] {
        var body: [String: Any] = [
            "query": query,
            "type": "auto",
            "numResults": limit,
            "contents": [
                "summary": [
                    "query": "Summarize this recipe in up to 90 characters in \(language.aiModelLanguageName), focusing on the dish and its style."
                ],
                "text": [
                    "maxCharacters": 6000,
                    "includeHtmlTags": false
                ]
            ]
        ]
        if let userLocation = language.exaUserLocationCode {
            body["userLocation"] = userLocation
        }
        if preferDomains, !language.exaPreferredDomains.isEmpty {
            body["includeDomains"] = language.exaPreferredDomains
        }

        let acceptLanguage = AppLocalization(language: language).acceptLanguageHeader
        let data: Data
        let resp: URLResponse
        if supabase.isConfigured {
            data = try await supabase.invokeFunctionData(
                name: "exa-search",
                body: body,
                acceptLanguage: acceptLanguage
            )
            resp = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        } else {
            guard !apiKey.isEmpty else { throw ServiceError.missingAPIKey }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = 30
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            try await AIDataConsent.shared.request()
            let result = try await URLSession.shared.data(for: request)
            data = result.0
            resp = result.1
        }

        guard let http = resp as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawResults = json["results"] as? [[String: Any]] else {
            throw ServiceError.invalidResponse
        }

        var titles = Set<String>()
        var urls = Set<String>()
        let excluded = Set(excludingURLs.compactMap { Self.canonicalRecipeURL($0) })
        return rawResults.compactMap { dict in
            guard let result = decodeSearchResult(dict, request: requestContext,
                                                  pantryItems: pantryItems, filterByPantry: filterByPantry) else { return nil }
            let title = Self.normalize(result.title)
            let url = Self.canonicalRecipeURL(result.sourceURL)
            guard !titles.contains(title) else { return nil }
            if let url, urls.contains(url) || excluded.contains(url) { return nil }
            titles.insert(title)
            if let url { urls.insert(url) }
            return result
        }
    }

    private static func canonicalRecipeURL(_ value: String?) -> String? {
        guard let value, var url = URLComponents(string: value) else { return nil }
        url.fragment = nil
        url.queryItems = url.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && $0.name.lowercased() != "fbclid" }
        if url.queryItems?.isEmpty == true { url.queryItems = nil }
        return url.string
    }

    private func decodeSearchResult(_ dict: [String: Any], request: RecipeIdeaRequest,
                                    pantryItems: [String], filterByPantry: Bool) -> RecipeIdeaResult? {
        guard let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let url = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let image = (dict["image"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (dict["text"] as? String) ?? ""

        guard !RecipeWebSourceFacts.isCollection(title: title, url: url) else { return nil }
        let facts = RecipeWebSourceFacts(text: text)
        var ingredients = facts?.ingredients ?? []
        if filterByPantry {
            guard let facts, let available = facts.availableIngredients(in: pantryItems) else { return nil }
            ingredients = available
            guard request.acceptsPantry(ingredients: available, steps: [facts.preparation],
                                        pantryItems: pantryItems, filterByPantry: true) else { return nil }
        }
        // Missing facts cannot certify dietary or time restrictions. Servings can
        // be scaled when opening the recipe, where the full draft is validated.
        if request.excludesMilk && facts == nil { return nil }
        guard request.acceptsDiet(ingredients: ingredients, steps: [facts?.preparation ?? title]),
              request.acceptsIdea(title: title, mainIngredient: "") else { return nil }
        if let maximum = request.maximumMinutes {
            guard let minutes = facts?.totalMinutes, minutes > 0, minutes <= maximum else { return nil }
        }
        let detectedIngredient = ingredients.first { ingredient in
            Self.normalize(title).range(of: "\\b" + NSRegularExpression.escapedPattern(for: RecipeWebSourceFacts.canonicalName(ingredient)) + "\\b", options: .regularExpression) != nil
        } ?? ingredients.first

        return RecipeIdeaResult(
            title: title,
            summary: summary,
            ingredients: ingredients,
            steps: [],
            sourceURL: url,
            heroImageURL: (image?.isEmpty == false) ? image : nil,
            mainIngredient: detectedIngredient,
            rawText: text.isEmpty ? nil : text
        )
    }

    // MARK: Query builders

    private func buildQuery(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        pantryItems: [String],
        filterByPantry: Bool,
        language: AppLanguage,
        seed: Int,
        maximumMinutes: Int?
    ) -> String {
        var parts: [String] = [language.recipeSearchKeyword]
        if let occasion, occasion != .outro,
           !(customQuery ?? "").contains(Self.normalize(occasion.label)) {
            parts.append(occasion.label.lowercased())
        }
        if let refinement, !refinement.isEmpty, refinement != "Outro" {
            parts.append(refinement.lowercased())
        }
        if let customQuery, !customQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(customQuery)
        }
        if !pantryItems.isEmpty {
            // Change the ingredients emphasized by a refresh, rather than
            // appending an unrelated "v2" keyword to the search query.
            let offset = ((seed % pantryItems.count) + pantryItems.count) % pantryItems.count
            var rotated = Array(pantryItems[offset...]) + Array(pantryItems[..<offset])
            let context = RecipeWebSourceFacts.canonicalName(customQuery ?? "")
            let mentioned = rotated.filter {
                let name = NSRegularExpression.escapedPattern(for: RecipeWebSourceFacts.canonicalName($0))
                return context.range(of: "\\b" + name + "\\b", options: .regularExpression) != nil
            }
            var others = rotated.filter { !mentioned.contains($0) }
            if let maximumMinutes, maximumMinutes <= 30 {
                // Search ranking only. A raw grain/bean is not evidence of a
                // precooked ingredient; opening a recipe still validates it.
                func needsLongCooking(_ name: String) -> Bool {
                    !RecipeQuickIdeasGenerator.isAlreadyCookedName(name) &&
                    Self.normalize(name).range(of: #"\b(?:arroz|feijao|rice|beans|riz|haricots|reis|bohnen|riso|fagioli)\b|米|豆"#, options: .regularExpression) != nil
                }
                others = others.filter { !needsLongCooking($0) } + others.filter(needsLongCooking)
            }
            rotated = mentioned + others
            let topItems = Array(rotated.prefix(2)).joined(separator: ", ")
            parts.append("\(language.recipeIngredientJoiner) \(topItems)")
            if filterByPantry {
                // A focus pair is not the allowed inventory. Explicitly state
                // the actual restriction rather than asking for generic dishes.
                var named: [String] = []
                var bytes = 0
                for item in pantryItems {
                    guard bytes + item.utf8.count + 2 <= 4000 else { continue }
                    named.append(item)
                    bytes += item.utf8.count + 2
                }
                parts.append(language.recipePantryConstraint(named))
            }
        }
        parts.append(language.recipeSourcePageHint)
        if !filterByPantry && seed != 0 {
            let variants = language.recipeSearchVariations
            let index = ((seed % variants.count) + variants.count) % variants.count
            parts.append(variants[index])
        }
        return parts.joined(separator: " ")
    }

    // MARK: Cache key

    private func cacheKey(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        pantryItems: [String],
        filterByPantry: Bool,
        language: AppLanguage,
        seed: Int,
        limit: Int,
        excludingURLs: [String]
    ) -> String {
        let pantryHash = pantryItems
            .map { Self.normalize($0) }
            .sorted()
            .joined(separator: "|")
        return [
            "v6-pantry-search-scope",
            language.rawValue,
            occasion?.rawValue ?? "-",
            refinement ?? "-",
            customQuery ?? "-",
            pantryHash,
            filterByPantry ? "1" : "0",
            String(seed),
            String(limit),
            excludingURLs.compactMap { Self.canonicalRecipeURL($0) }.sorted().joined(separator: "|")
        ].joined(separator: "::")
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
