import Foundation

/// Resultado curto produzido pelo modelo para a seção "Ideias Rápidas":
/// receitas simples cujos ingredientes estão TODOS na despensa do usuário.
struct RecipeQuickIdea: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    /// Ingrediente principal — usado para resolver um ícone do banco de imagens.
    let mainIngredient: String

    init(id: UUID = UUID(), title: String, mainIngredient: String) {
        self.id = id
        self.title = title
        self.mainIngredient = mainIngredient
    }
}

/// Pede ao modelo da OpenAI uma lista enxuta de "ideias rápidas" — receitas
/// simples, cobertas 100% pela despensa do usuário. Sem chamadas externas
/// e sem dependência de receitas locais.
@MainActor
final class RecipeQuickIdeasGenerator {
    static let shared = RecipeQuickIdeasGenerator()

    /// Retorna até `limit` ideias rápidas. Lança erro silenciado se faltar API key.
    func generate(
        pantryItems: [String],
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        limit: Int = 10
    ) async -> [RecipeQuickIdea] {
        let apiKey = APIConfig.openAIAPIKey
        guard !apiKey.isEmpty, !pantryItems.isEmpty else { return [] }
        let generationLimit = max(limit + 6, limit)

        let pantryList = pantryItems.isEmpty ? "(despensa vazia)" : pantryItems.joined(separator: ", ")

        var contextLines: [String] = []
        if let occasion {
            contextLines.append("Ocasião: \(occasion.label)")
        }
        if let refinement, !refinement.isEmpty {
            contextLines.append("Refinamento: \(refinement)")
        }
        if let customQuery, !customQuery.isEmpty {
            contextLines.append("Pedido do usuário: \(customQuery)")
        }
        let context = contextLines.isEmpty ? "" : "\n\nContexto:\n" + contextLines.joined(separator: "\n")

        let system = buildSystemPrompt(
            generationLimit: generationLimit,
            occasion: occasion,
            refinement: refinement,
            customQuery: customQuery
        )

        let user = """
        Pantry items: \(pantryList)\(context)
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]

        do {
            let response = try await sendJSONChat(messages: messages, apiKey: apiKey)
            guard let content = response.content,
                  let data = content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawIdeas = json["ideas"] as? [[String: Any]] else {
                return []
            }
            var seenTitles = Set<String>()
            var ideas: [RecipeQuickIdea] = []

            for dict in rawIdeas {
                guard let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else { continue }

                let normalizedTitle = normalized(title)
                guard seenTitles.insert(normalizedTitle).inserted else { continue }

                let suggestedMainIngredient = (dict["mainIngredient"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedMainIngredient = resolvedMainIngredient(
                    suggestedMainIngredient: suggestedMainIngredient,
                    title: title,
                    pantryItems: pantryItems
                )

                ideas.append(RecipeQuickIdea(title: title, mainIngredient: resolvedMainIngredient))
                if ideas.count >= generationLimit { break }
            }

            return rankIdeas(
                ideas,
                pantryItems: pantryItems,
                occasion: occasion,
                refinement: refinement,
                customQuery: customQuery,
                limit: limit
            )
        } catch {
            return []
        }
    }

    private func buildSystemPrompt(
        generationLimit: Int,
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?
    ) -> String {
        var rules: [String] = [
            "You generate quick recipe ideas. Reply ONLY with a JSON object of the form:",
            "{\"ideas\": [{\"title\": \"...\", \"mainIngredient\": \"...\"}]}",
            "Rules:",
            "- Generate up to \(generationLimit) ideas. Prefer a diverse set.",
            "- Every recipe must use ONLY ingredients from the user's pantry. Never include any ingredient outside the pantry.",
            "- Match the user's requested dish type and eating occasion, not just pantry popularity.",
            "- Keep titles short (max 4 words) in the user's language.",
            "- Pick simple, fast recipes.",
            "- \"mainIngredient\" must be a single pantry item name from the list (used to render an icon).",
            "- No extra commentary, no markdown, no code fences."
        ]

        if let occasion {
            rules.append(contentsOf: occasionPromptRules(for: occasion))
        }

        if let refinement, !refinement.isEmpty {
            rules.append(contentsOf: refinementPromptRules(for: refinement))
        }

        if let customQuery, !customQuery.isEmpty {
            rules.append("- The request text is the main constraint: \"\(customQuery)\".")
        }

        return rules.joined(separator: "\n")
    }

    private func occasionPromptRules(for occasion: RecipeIdeaOccasion) -> [String] {
        switch occasion {
        case .lancheRapido:
            return [
                "- For quick snacks, suggest snack-style or mini-meal dishes commonly eaten as a snack.",
                "- Never suggest full lunch or dinner staples for a snack.",
                "- Reject examples such as rice and beans, pasta dishes, lasagna, risotto, stew, or plated main meals."
            ]
        case .cafeDaManha:
            return [
                "- For breakfast, suggest foods commonly associated with breakfast or brunch.",
                "- Avoid lunch or dinner plates."
            ]
        case .almoco:
            return [
                "- For lunch, prefer complete savory meals rather than desserts, drinks, or tiny snacks."
            ]
        case .jantar:
            return [
                "- For dinner, prefer dinner-appropriate savory dishes or light evening plates, not breakfast items or desserts."
            ]
        case .drinks:
            return [
                "- Suggest only drink-style ideas."
            ]
        case .bebidas:
            return [
                "- Suggest only beverage-style ideas."
            ]
        case .sobremesa:
            return [
                "- Suggest only dessert-style ideas."
            ]
        case .outro:
            return []
        }
    }

    private func refinementPromptRules(for refinement: String) -> [String] {
        let normalizedRefinement = normalized(refinement)

        if normalizedRefinement.contains("fit") || normalizedRefinement.contains("saudavel") || normalizedRefinement.contains("leve") {
            return [
                "- Favor lighter, healthier, protein-forward, or vegetable-forward options.",
                "- Avoid heavy carb plates, fried foods, sugary desserts, and comfort-food style dishes unless the user explicitly asked for them."
            ]
        }

        if normalizedRefinement.contains("doce") || normalizedRefinement.contains("chocolate") || normalizedRefinement.contains("frutas") {
            return [
                "- Lean the suggestions toward sweeter profiles that still match the user's occasion."
            ]
        }

        if normalizedRefinement.contains("proteico") {
            return [
                "- Prefer protein-rich ideas over carb-heavy staples."
            ]
        }

        return []
    }

    private func rankIdeas(
        _ ideas: [RecipeQuickIdea],
        pantryItems: [String],
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        limit: Int
    ) -> [RecipeQuickIdea] {
        let assessed = ideas.map { idea in
            assessIdea(
                idea,
                pantryItems: pantryItems,
                occasion: occasion,
                refinement: refinement,
                customQuery: customQuery
            )
        }

        let filtered = assessed
            .filter { !$0.isHardRejected }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.idea.title.localizedCaseInsensitiveCompare($1.idea.title) == .orderedAscending
            }

        let preferred = filtered.filter { $0.score >= 0 }.map(\.idea)
        if preferred.count >= min(limit, 4) {
            return Array(preferred.prefix(limit))
        }

        return Array(filtered.map(\.idea).prefix(limit))
    }

    private func assessIdea(
        _ idea: RecipeQuickIdea,
        pantryItems: [String],
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?
    ) -> QuickIdeaAssessment {
        let title = normalized(idea.title)
        var score = 0
        var isHardRejected = false

        let snackKeywords = ["lanche", "snack", "torrada", "toast", "omelete", "wrap", "sanduiche", "sanduiche", "tapioca", "crepioca", "iogurte", "yogurt", "shake", "smoothie", "salada", "bowl", "bruschetta", "quesadilla", "rolinho"]
        let mainMealKeywords = ["arroz", "feijao", "pasta", "macarrao", "spaghetti", "lasanha", "lasagna", "risoto", "strogonoff", "prato", "almoco", "jantar", "parmegiana", "ensopado", "feijoada", "picadinho", "bife", "file", "pure", "farofa"]
        let lightKeywords = ["fit", "light", "leve", "salada", "grelhado", "assado", "omelete", "iogurte", "yogurt", "bowl", "wrap", "proteico", "protein", "frango", "ovo", "ovos", "atum", "tofu"]
        let heavyKeywords = ["frito", "frita", "frita", "empanado", "gratinado", "recheado", "pizza", "hamburguer", "hamburger", "lasanha", "macarrao", "pasta", "feijoada", "brigadeiro", "bolo", "doce", "chocolate", "mel"]
        let breakfastKeywords = ["cafe", "panqueca", "pancake", "overnight", "granola", "iogurte", "yogurt", "omelete", "torrada", "toast"]
        let drinkKeywords = ["shake", "smoothie", "suco", "vitamina", "drink", "coquetel", "cocktail", "cha", "cafe"]
        let dessertKeywords = ["bolo", "brigadeiro", "mousse", "cookie", "brownie", "doce", "sobremesa", "chocolate"]

        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains(where: { title.contains($0) })
        }

        if let occasion {
            switch occasion {
            case .lancheRapido:
                if containsAny(mainMealKeywords) {
                    isHardRejected = true
                    score -= 10
                }
                if containsAny(snackKeywords) { score += 5 }
                if containsAny(lightKeywords) { score += 1 }
            case .cafeDaManha:
                if containsAny(mainMealKeywords) {
                    isHardRejected = true
                    score -= 10
                }
                if containsAny(breakfastKeywords) { score += 4 }
            case .almoco:
                if containsAny(mainMealKeywords) { score += 4 }
                if containsAny(snackKeywords) { score -= 2 }
                if containsAny(drinkKeywords) || containsAny(dessertKeywords) { score -= 4 }
            case .jantar:
                if containsAny(mainMealKeywords) { score += 3 }
                if containsAny(breakfastKeywords) { score -= 2 }
                if containsAny(dessertKeywords) || containsAny(drinkKeywords) { score -= 4 }
            case .drinks, .bebidas:
                if containsAny(drinkKeywords) { score += 5 } else { isHardRejected = true }
            case .sobremesa:
                if containsAny(dessertKeywords) { score += 5 } else { isHardRejected = true }
            case .outro:
                break
            }
        }

        if let refinement {
            let normalizedRefinement = normalized(refinement)
            if normalizedRefinement.contains("fit") || normalizedRefinement.contains("saudavel") || normalizedRefinement.contains("leve") {
                if containsAny(lightKeywords) { score += 4 }
                if containsAny(heavyKeywords) { score -= 5 }
            }
            if normalizedRefinement.contains("proteico") {
                if containsAny(["proteico", "protein", "frango", "ovo", "ovos", "atum", "tofu", "iogurte", "yogurt"]) {
                    score += 4
                }
                if containsAny(["arroz", "pasta", "macarrao", "bolo", "brigadeiro"]) {
                    score -= 4
                }
            }
        }

        if let customQuery, !customQuery.isEmpty {
            let query = normalized(customQuery)
            let hasNightCue = ["noite", "de noite", "a noite", "noturno", "noturna"].contains(where: query.contains)
            if hasNightCue && containsAny(mainMealKeywords) && occasion == .lancheRapido {
                isHardRejected = true
                score -= 8
            }

            let queryTokens = query
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map(normalized)
                .filter { $0.count >= 4 }

            for token in queryTokens where title.contains(token) {
                score += 1
            }
        }

        if pantryItems.contains(where: { normalized($0) == normalized(idea.mainIngredient) }) {
            score += 1
        }

        return QuickIdeaAssessment(idea: idea, score: score, isHardRejected: isHardRejected)
    }

    private struct QuickIdeaAssessment {
        let idea: RecipeQuickIdea
        let score: Int
        let isHardRejected: Bool
    }

    private func resolvedMainIngredient(
        suggestedMainIngredient: String,
        title: String,
        pantryItems: [String]
    ) -> String {
        let normalizedTitle = normalized(title)
        let pantryWithIcons = pantryItems.filter { IconResolver.resolve($0) != nil }
        let titleMatches = pantryItems.filter { pantryItem in
            let normalizedPantryItem = normalized(pantryItem)
            guard !normalizedPantryItem.isEmpty else { return false }
            if normalizedTitle.contains(normalizedPantryItem) {
                return true
            }

            let tokens = normalizedPantryItem.split(separator: " ").map(String.init)
            return tokens.contains { token in
                token.count >= 3 && normalizedTitle.contains(token)
            }
        }

        let candidates = [suggestedMainIngredient, title] + titleMatches + pantryWithIcons + pantryItems
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if IconResolver.resolve(trimmed) != nil {
                return trimmed
            }
        }

        return pantryWithIcons.first ?? pantryItems.first ?? suggestedMainIngredient
    }

    private func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chamada dedicada que pede `response_format: json_object` à OpenAI.
    private func sendJSONChat(
        messages: [[String: Any]],
        apiKey: String
    ) async throws -> ChatCompletionResponse {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "messages": messages,
            "response_format": ["type": "json_object"],
            "temperature": 0.35
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 30

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
        guard let http = httpResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }
        let content = message["content"] as? String
        return ChatCompletionResponse(content: content, toolCalls: [])
    }
}
