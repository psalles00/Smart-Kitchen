import Foundation

/// Resultado curto produzido pelo modelo para a seção "Ideias Rápidas":
/// receitas simples, com ingredientes restritos à despensa quando essa opção está ativa.
struct RecipeQuickIdea: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    /// Ingrediente principal — usado para resolver um ícone do banco de imagens.
    let mainIngredient: String
    /// Optional for older conversation cards; new ideas include their planned ingredients.
    let ingredientNames: [String]?
    let precookedIngredientNames: [String]?

    init(id: UUID = UUID(), title: String, mainIngredient: String, ingredientNames: [String]? = nil, precookedIngredientNames: [String]? = nil) {
        self.id = id
        self.title = title
        self.mainIngredient = mainIngredient
        self.ingredientNames = ingredientNames
        self.precookedIngredientNames = precookedIngredientNames
    }
}

/// Keeps the original request attached to an idea after it is selected.
/// Deterministic checks cover explicit milk exclusions, minute limits and serving counts;
/// other restrictions remain in the full prompt rather than being silently discarded.
struct RecipeIdeaRequest {
    let text: String

    init(occasion: String?, refinement: String?, customQuery: String?) {
        text = [occasion, refinement, customQuery].compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var prompt: String {
        guard !text.isEmpty else { return "" }
        return """
        Pedido original do usuário, incluindo todas as restrições:
        \(text)
        As restrições deste pedido têm prioridade sobre o título sugerido, a receita da fonte e os itens da despensa.
        Respeite o tempo total e as porções solicitadas. Se não for possível, não ofereça uma receita incompatível.
        \(generationRules)
        """
    }

    var generationRules: String {
        var rules = ["Restrições obrigatórias para ingredientes E passos do preparo:"]
        if excludesMilk {
            rules.append("Não use leite animal, queijo, manteiga, iogurte, nata, requeijão ou creme de leite, mesmo se constarem na despensa ou na receita original. Não acrescente esses ingredientes nos passos. Alternativas vegetais explicitamente identificadas são permitidas.")
        }
        if let maximumMinutes { rules.append("Tempo total máximo: \(maximumMinutes) minutos, incluindo preparo e cozimento.") }
        if let requestedServings { rules.append("Número exato de porções: \(requestedServings). Ajuste todas as quantidades para essas porções.") }
        return rules.joined(separator: "\n")
    }

    func allowedPantryItems(_ names: [String]) -> [String] {
        excludesMilk ? names.filter { !Self.containsDairy($0) } : names
    }

    func acceptsIdea(title: String, mainIngredient: String) -> Bool {
        !excludesMilk || (!Self.containsDairy(mainIngredient) && !Self.containsDairyUse(title))
    }

    func ingredientPrompt(pantryItems: [String], filterByPantry: Bool) -> String {
        let names = allowedPantryItems(pantryItems)
        let list = names.isEmpty ? "(despensa vazia)" : names.joined(separator: ", ")
        if filterByPantry {
            return "Use APENAS ingredientes desta despensa: \(list). Não inclua ingredientes fora da lista, nem nos passos. Copie os nomes exatos da lista; coloque quantidades nos campos de quantidade e cortes nos passos, sem modificar os nomes dos ingredientes."
        }
        return "Priorize os ingredientes disponíveis quando combinarem com o pedido: \(list). Pode incluir ingredientes de fora da despensa; não os apresente como disponíveis. Uma despensa vazia não impede sugerir receitas."
    }

    /// Availability requires exact names, never icon identity, substrings or fuzzy matches.
    func acceptsPantry(ingredients: [String], pantryItems: [String], filterByPantry: Bool) -> Bool {
        guard filterByPantry else { return true }
        let allowed = Set(allowedPantryItems(pantryItems).map { Self.normalized($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return !ingredients.isEmpty && ingredients.allSatisfy {
            let name = Self.normalized($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && allowed.contains(name)
        }
    }

    var maximumMinutes: Int? {
        Self.firstNumber(in: Self.normalized(text), pattern: #"(?<![0-9])(\d+)\s*(?:min(?:uto[s]?)?|minutes?|minuten|minuti)\b"#)
    }

    var requestedServings: Int? {
        let normalized = Self.normalized(text)
        if let number = Self.firstNumber(in: normalized, pattern: #"\b(\d+)\s*(?:pessoas?|persons?|people|porcoes|servings?|portions?|raciones?|personen|persone)\b"#) { return number }
        if normalized.range(of: #"\b(?:uma pessoa|one person|une personne|una persona|eine person)\b"#, options: .regularExpression) != nil { return 1 }
        return nil
    }

    var excludesMilk: Bool {
        Self.normalized(text).range(of: #"\b(?:sem leite|sem (?:nenhum )?laticinio[s]?|without milk|no milk|milk free|dairy free|no dairy|without dairy|sans lait|sin leche|ohne milch|senza latte)\b"#, options: .regularExpression) != nil
    }

    func accepts(ingredients: [String], steps: [String] = [], totalMinutes: Int?, servings: Int?) -> Bool {
        if excludesMilk,
           ingredients.contains(where: Self.containsDairy) || steps.contains(where: Self.containsDairyUse) { return false }
        if let maximumMinutes {
            guard let totalMinutes, totalMinutes > 0, totalMinutes <= maximumMinutes else { return false }
        }
        if let requestedServings, servings != requestedServings { return false }
        return true
    }

    func accepts(_ draft: RecipeDraft) -> Bool {
        let knownTime = draft.prepTimeConfidence == .high && draft.cookTimeConfidence == .high
        return accepts(ingredients: draft.ingredients.map(\.name),
                       steps: draft.steps.map(\.instruction),
                       totalMinutes: knownTime ? Self.totalMinutes(in: draft) : nil,
                       servings: draft.servingsConfidence == .high ? draft.servings : nil)
    }

    static func totalMinutes(in draft: RecipeDraft) -> Int? {
        let (total, overflow) = draft.prepTime.addingReportingOverflow(draft.cookTime)
        return !overflow && total > 0 ? total : nil
    }

    static func totalMinutes(in content: String) -> Int? {
        firstNumber(in: normalized(content), pattern: #"(?m)^tempo total:\s*(\d+)\s*min\b"#)
    }

    static func servings(in content: String) -> Int? {
        firstNumber(in: normalized(content), pattern: #"(?m)^porcoes:\s*(\d+)\s*$"#)
    }

    private static func containsDairy(_ ingredient: String) -> Bool {
        // Remove only named plant alternatives, then check remaining ingredients.
        // "Leite de coco e leite integral" must still fail.
        let name = normalized(ingredient).replacingOccurrences(
            of: #"\b(?:leite (?:vegetal|de (?:coco|aveia|soja|amendoas|arroz))|(?:coconut|oat|soy|almond|rice|plant) milk)\b"#,
            with: "", options: .regularExpression)
        return name.range(of: #"\b(?:leite|milk|lait|leche|milch|latte|queijo|cheese|fromage|queso|kase|formaggio|manteiga|butter|beurre|mantequilla|burro|iogurte|yogurt|yoghurt|joghurt|yaourt|yogur|nata|requeijao|cream)\b"#, options: .regularExpression) != nil
    }

    private static func containsDairyUse(_ step: String) -> Bool {
        // A prohibition such as "sem óleo ou manteiga" is not an addition.
        // Remove only explicit, bounded ingredient lists after a negation;
        // "sem manteiga; adicione leite" must still fail.
        let ingredient = #"(?:leite|milk|lait|leche|milch|latte|queijo|cheese|fromage|queso|kase|formaggio|manteiga|butter|beurre|mantequilla|burro|iogurte|yogurt|yoghurt|joghurt|yaourt|yogur|nata|requeijao|cream|oleo|oil|huile|aceite|ol|olio|gordura|fat|grasa|grasas|matiere grasse|matieres grasses|fett|grassi)\b"#
        let separator = #"(?:\s*,\s*|\s+(?:e|ou|nem|and|or|nor|et|y|o|ni|und|oder)\s+)"#
        let negation = #"\b(?:sem|without|sans|sin|ohne|senza|nao\s+(?:use|adicione|inclua|coloque|utilize)|do\s+not\s+(?:use|add|include))\s+"#
        let additions = normalized(step).replacingOccurrences(
            of: negation + ingredient + "(?:" + separator + ingredient + ")*",
            with: "", options: .regularExpression)
        return containsDairy(additions)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func firstNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Int(text[range]), value > 0 else { return nil }
        return value
    }
}

/// Pede ao modelo da OpenAI uma lista enxuta de "ideias rápidas" — receitas
/// simples, respeitando a preferência de despensa, sem depender de receitas locais
/// nem de uma busca na web.
@MainActor
final class RecipeQuickIdeasGenerator {
    static let shared = RecipeQuickIdeasGenerator()
    private let aiService: AIService

    init(aiService: AIService = AIService()) {
        self.aiService = aiService
    }

    /// Retorna até `limit` ideias rápidas. Lança erro silenciado se faltar API key.
    func generate(
        pantryItems: [String],
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        language: AppLanguage,
        filterByPantry: Bool = true,
        limit: Int = 10
    ) async -> [RecipeQuickIdea] {
        let request = RecipeIdeaRequest(occasion: occasion?.label, refinement: refinement, customQuery: customQuery)
        let pantryItems = request.allowedPantryItems(pantryItems).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !filterByPantry || !pantryItems.isEmpty else { return [] }

        let apiKey = APIConfig.openAIAPIKey
        let generationLimit = max(limit + 6, limit)

        let pantryList = pantryItems.isEmpty ? "(despensa vazia)" : pantryItems.joined(separator: ", ")

        var contextLines: [String] = []
        if let occasion {
            contextLines.append("Occasion: \(occasion.label)")
        }
        if let refinement, !refinement.isEmpty {
            contextLines.append("Refinement: \(refinement)")
        }
        if let customQuery, !customQuery.isEmpty {
            contextLines.append("User request: \(customQuery)")
        }
        let context = contextLines.isEmpty ? "" : "\n\nContext:\n" + contextLines.joined(separator: "\n")

        let system = buildSystemPrompt(
            generationLimit: generationLimit,
            filterByPantry: filterByPantry,
            occasion: occasion,
            refinement: refinement,
            customQuery: customQuery,
            language: language
        ) + "\n" + request.ingredientPrompt(pantryItems: pantryItems, filterByPantry: filterByPantry) + "\n" + request.prompt

        let user = """
        Pantry items: \(pantryList)\(context)
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]

        do {
            let response = try await sendJSONChat(messages: messages, apiKey: apiKey, language: language,
                                                  responseFormat: responseFormat(pantryItems: pantryItems, filterByPantry: filterByPantry,
                                                                                 request: request, limit: generationLimit))
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

                var mainIngredient = filterByPantry ? resolvedMainIngredient : suggestedMainIngredient
                guard !mainIngredient.isEmpty,
                      let ingredients = dict["ingredients"] as? [String] else { continue }
                let names = ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let normalizedNames = Set(names.map(normalized))
                // Free-mode names may describe the cut or packaging ("frango" /
                // "peito de frango"). Resolve only an unambiguous whole phrase;
                // this is never evidence that an ingredient exists in the pantry.
                if !filterByPantry, !normalizedNames.contains(normalized(mainIngredient)) {
                    let phrase = " " + normalized(mainIngredient) + " "
                    let matches = names.filter { (" " + normalized($0) + " ").contains(phrase) }
                    guard matches.count == 1, let match = matches.first else { continue }
                    mainIngredient = match
                }
                let minimumIngredients = pantryItems.count == 1 ? 1 : 2
                guard normalizedNames.count >= minimumIngredients,
                      normalizedNames.contains(normalized(mainIngredient)) else { continue }
                let precooked = dict["requiresPrecooked"] as? [String] ?? []
                guard Set(precooked.map(normalized)).isSubset(of: normalizedNames) else { continue }
                if filterByPantry {
                    let allowed = Set(pantryItems.map(normalized))
                    guard normalizedNames.isSubset(of: allowed),
                          precooked.allSatisfy(Self.isAlreadyCookedName) else { continue }
                }
                guard request.acceptsIdea(title: title, mainIngredient: mainIngredient),
                      request.accepts(ingredients: names, totalMinutes: dict["totalMinutes"] as? Int, servings: dict["servings"] as? Int) else { continue }
                ideas.append(RecipeQuickIdea(title: title, mainIngredient: mainIngredient, ingredientNames: names, precookedIngredientNames: precooked))
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

    static func isAlreadyCookedName(_ name: String) -> Bool {
        let text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if ["cru", "raw", "uncooked", "nao", "not cooked", "not ready", "ungekocht", "nicht gekocht", "non cuit", "pas cuit", "no cocid", "sin cocer", "non cott", "未調理", "未加熱", "炊いていない", "茹でていない"].contains(where: text.contains) { return false }
        return ["cozid", "cooked", "cuit", "gekocht", "cocid", "cott", "pront", "ready", "pret a", "enlatado", "canned", "conserva", "em lata", "炊いた", "茹でた", "調理済", "炊飯済", "加熱済"].contains(where: text.contains)
    }

    private func responseFormat(pantryItems: [String], filterByPantry: Bool, request: RecipeIdeaRequest, limit: Int) -> [String: Any] {
        var ingredient: [String: Any] = ["type": "string", "description": "Exact ingredient name, without quantities or instructions"]
        let uniqueNames = Array(Set(pantryItems)).sorted()
        if filterByPantry, !uniqueNames.isEmpty, uniqueNames.count <= 1000, uniqueNames.joined().utf8.count <= 12000 {
            ingredient["enum"] = uniqueNames
        }
        var minutes: [String: Any] = ["type": "integer", "minimum": 1]
        if let max = request.maximumMinutes { minutes["maximum"] = max }
        var servings: [String: Any] = ["type": "integer", "minimum": 1]
        if let count = request.requestedServings { servings["enum"] = [count] }
        let reference: [String: Any] = ["$ref": "#/$defs/ingredientName"]
        let properties: [String: Any] = [
            "title": ["type": "string"], "mainIngredient": reference,
            "ingredients": ["type": "array", "minItems": pantryItems.count == 1 ? 1 : 2, "items": reference],
            "totalMinutes": minutes, "servings": servings,
            "requiresPrecooked": ["type": "array", "items": reference]
        ]
        let idea: [String: Any] = ["type": "object", "properties": properties,
                                   "required": ["title", "mainIngredient", "ingredients", "totalMinutes", "servings", "requiresPrecooked"],
                                   "additionalProperties": false]
        let schema: [String: Any] = ["type": "object", "$defs": ["ingredientName": ingredient],
                                     "properties": ["ideas": ["type": "array", "maxItems": limit, "items": idea]],
                                     "required": ["ideas"], "additionalProperties": false]
        return ["type": "json_schema", "json_schema": ["name": "recipe_ideas", "strict": true, "schema": schema]]
    }

    private func buildSystemPrompt(
        generationLimit: Int,
        filterByPantry: Bool,
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        language: AppLanguage
    ) -> String {
        var rules: [String] = [
            "You generate quick recipe ideas. Reply ONLY with a JSON object of the form:",
            "{\"ideas\": [{\"title\": \"...\", \"mainIngredient\": \"...\", \"ingredients\": [\"...\"], \"totalMinutes\": 15, \"servings\": 1, \"requiresPrecooked\": []}]}",
            "Rules:",
            "- Generate up to \(generationLimit) ideas. Prefer a diverse set of recognizable dishes, using different combinations and cooking methods.",
            "- Do not fill the list with plain chopped, boiled or heated single ingredients. Prefer fewer worthwhile dishes over trivial preparations or renamed duplicates.",
            "- Combine at least two distinct ingredients when possible. If only one pantry item exists, offer a real dish only when viable.",
            "- ingredients contains ONLY ingredient names, never quantities, units, cuts or preparation instructions. In pantry-only mode copy the exact pantry names, including their stated condition.",
            "- List ALL actual ingredients, including oils, seasoning and dairy. Never assume salt, water, oil or other unlisted items in pantry-only mode.",
            "- requiresPrecooked lists ingredient names that must ALREADY be cooked to achieve totalMinutes. Do not pretend dry rice or beans are cooked; omit such ideas unless the pantry name explicitly says cooked/canned/ready.",
            "- If there are no viable dishes, return an empty ideas array rather than inventing availability or preparation time.",
            "- totalMinutes includes preparation AND cooking from the available ingredients' stated condition; servings is the actual portion count.",
            filterByPantry
                ? "- Every recipe must use ONLY ingredients from the user's pantry. Never include any ingredient outside the pantry."
                : "- Pantry ingredients are preferences, not requirements. Suggest useful new recipes even with an empty pantry.",
            "- Match the user's requested dish type and eating occasion, not just pantry popularity.",
            "- The target language for every title is \(language.aiModelLanguageName).",
            "- Keep titles short (max 4 words) and write them only in \(language.aiModelLanguageName).",
            "- Pick simple, fast recipes.",
            filterByPantry
                ? "- \"mainIngredient\" must be a single pantry item name from the list."
                : "- \"mainIngredient\" must name the actual main ingredient of the dish, even when it is not in the pantry.",
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

        guard limit > 0 else { return [] }
        let preferred = filtered.filter { $0.score >= 0 }
        var remaining = (preferred.count >= min(limit, 4) ? preferred : filtered).map(\.idea)
        var selected: [RecipeQuickIdea] = []
        // Round-robin ingredients within relevance order so one popular item
        // cannot occupy the entire first row when other good options exist.
        while !remaining.isEmpty && selected.count < limit {
            var roundIngredients = Set<String>()
            var deferred: [RecipeQuickIdea] = []
            for idea in remaining {
                if selected.count < limit && roundIngredients.insert(normalized(idea.mainIngredient)).inserted {
                    selected.append(idea)
                } else {
                    deferred.append(idea)
                }
            }
            remaining = deferred
        }
        return selected
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
        let suggested = normalized(suggestedMainIngredient)
        if let exact = pantryItems.first(where: { normalized($0) == suggested }) { return exact }
        let titleTokens = Set(normalized(title).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        return pantryItems.first { item in
            let tokens = normalized(item).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
            return !tokens.isEmpty && tokens.allSatisfy { titleTokens.contains($0) }
        } ?? ""
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
        apiKey: String,
        language: AppLanguage,
        responseFormat: [String: Any]
    ) async throws -> ChatCompletionResponse {
        try await aiService.sendChat(
            messages: messages,
            apiKey: apiKey,
            model: "gpt-4.1-mini",
            temperature: 0.35,
            responseFormat: responseFormat,
            maxTokens: 4096,
            acceptLanguage: AppLocalization(language: language).acceptLanguageHeader
        )
    }
}
