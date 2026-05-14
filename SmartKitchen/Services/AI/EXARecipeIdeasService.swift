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

// MARK: - Service

/// Busca ideias de receitas via EXA `/search` (web search com extração de conteúdo).
@MainActor
final class EXARecipeIdeasService {
    static let shared = EXARecipeIdeasService()

    private let endpoint = URL(string: "https://api.exa.ai/search")!
    private let supabase = SupabaseClient()

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
        limit: Int = 6,
        seed: Int = 0
    ) async throws -> [RecipeIdeaResult] {
        let key = cacheKey(
            occasion: occasion,
            refinement: refinement,
            customQuery: customQuery,
            pantryItems: pantryItems,
            filterByPantry: filterByPantry,
            language: language,
            seed: seed
        )

        if let entry = cache[key], Date().timeIntervalSince(entry.date) < ttl {
            return entry.results
        }

        let apiKey = APIConfig.exaAPIKey

        let query = buildQuery(
            occasion: occasion,
            refinement: refinement,
            customQuery: customQuery,
            pantryItems: pantryItems,
            filterByPantry: filterByPantry,
            language: language,
            seed: seed
        )

        let hint = mainIngredientHint(
            pantryItems: pantryItems,
            filterByPantry: filterByPantry,
            customQuery: customQuery
        )

        var results = try await performSearch(
            query: query,
            limit: limit,
            apiKey: apiKey,
            preferDomains: true,
                language: language,
            mainIngredientHint: hint
        )

        // Fallback 1: tenta sem restringir domínios (broader web).
        if results.isEmpty {
            results = try await performSearch(
                query: query,
                limit: limit,
                apiKey: apiKey,
                preferDomains: false,
                language: language,
                mainIngredientHint: hint
            )
        }

        // Fallback 2: query mais simples (apenas ocasião/refinamento).
        if results.isEmpty {
            let simple = buildSimpleQuery(
                occasion: occasion,
                refinement: refinement,
                customQuery: customQuery,
                language: language
            )
            results = try await performSearch(
                query: simple,
                limit: limit,
                apiKey: apiKey,
                preferDomains: false,
                language: language,
                mainIngredientHint: nil
            )
        }

        guard !results.isEmpty else { throw ServiceError.empty }

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
        mainIngredientHint: String?
    ) async throws -> [RecipeIdeaResult] {
        var body: [String: Any] = [
            "query": query,
            "type": "auto",
            "numResults": max(limit, 6),
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

        return rawResults.compactMap { dict in
            decodeSearchResult(dict, mainIngredientHint: mainIngredientHint)
        }
    }

    private func decodeSearchResult(_ dict: [String: Any], mainIngredientHint: String?) -> RecipeIdeaResult? {
        guard let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let url = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let image = (dict["image"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (dict["text"] as? String) ?? ""

        // Ingredientes/passos são extraídos depois pela LLM (RecipeStructurer).
        // Aqui apenas detectamos o ingrediente principal a partir do título para o card de sugestão.
        let detectedIngredient = mainIngredientHint ?? guessMainIngredient(title: title)

        return RecipeIdeaResult(
            title: title,
            summary: summary,
            ingredients: [],
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
        seed: Int
    ) -> String {
        var parts: [String] = [language.recipeSearchKeyword]
        if let occasion, occasion != .outro {
            parts.append(occasion.label.lowercased())
        }
        if let refinement, !refinement.isEmpty, refinement != "Outro" {
            parts.append(refinement.lowercased())
        }
        if let customQuery, !customQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(customQuery)
        }
        if filterByPantry, !pantryItems.isEmpty {
            let topItems = Array(pantryItems.prefix(6)).joined(separator: ", ")
            parts.append("\(language.recipeIngredientJoiner) \(topItems)")
        }
        if seed > 0 {
            parts.append("v\(seed + 1)")
        }
        return parts.joined(separator: " ")
    }

    private func buildSimpleQuery(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        language: AppLanguage
    ) -> String {
        var parts: [String] = [language.recipeSearchKeyword]
        if let occasion, occasion != .outro {
            parts.append(occasion.label.lowercased())
        }
        if let refinement, !refinement.isEmpty, refinement != "Outro" {
            parts.append(refinement.lowercased())
        }
        if let customQuery, !customQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(customQuery)
        }
        return parts.joined(separator: " ")
    }

    // MARK: Heuristics

    private func mainIngredientHint(
        pantryItems: [String],
        filterByPantry: Bool,
        customQuery: String?
    ) -> String? {
        if let customQuery, !customQuery.isEmpty {
            return firstWord(customQuery)
        }
        if filterByPantry, let first = pantryItems.first { return first }
        return nil
    }

    private func guessMainIngredient(title: String) -> String? {
        let lower = title.lowercased()
        let separators = [" de ", " com ", " ao ", " à "]
        for sep in separators {
            if let r = lower.range(of: sep) {
                let after = title[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return firstWord(after) }
            }
        }
        return firstWord(title)
    }

    private func firstWord(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    // MARK: Cache key

    private func cacheKey(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        pantryItems: [String],
        filterByPantry: Bool,
        language: AppLanguage,
        seed: Int
    ) -> String {
        let pantryHash = pantryItems
            .map { Self.normalize($0) }
            .sorted()
            .joined(separator: "|")
        return [
            "v2",
            language.rawValue,
            occasion?.rawValue ?? "-",
            refinement ?? "-",
            customQuery ?? "-",
            pantryHash,
            filterByPantry ? "1" : "0",
            String(seed)
        ].joined(separator: "::")
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
