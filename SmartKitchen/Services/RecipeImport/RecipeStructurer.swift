import Foundation

/// Transforms unstructured text (pasted, OCR'd, scraped) into a `RecipeDraft`
/// using the best available language model.
///
/// Strategy:
///   1. If Apple FoundationModels is available (iOS 26 + Apple Intelligence),
///      use `LanguageModelSession` with a `@Generable` schema — on-device,
///      private, free. (Wired up in Fase 5; currently returns nil so we fall back.)
///   2. Fallback to OpenAI gpt-4.1-mini via the existing `AIService`.
///
/// The AI is instructed to use only the canonical unit/state labels from
/// `RecipeOptionCatalog` so downstream normalization is cheap.
@MainActor
struct RecipeStructurer {

    let aiService: AIService
    let apiKey: String

    init(aiService: AIService = AIService(), apiKey: String = APIConfig.openAIAPIKey) {
        self.aiService = aiService
        self.apiKey = apiKey
    }

    /// Structure the given raw text into a draft recipe.
    /// - Parameters:
    ///   - text: raw text (caption, OCR output, paste, scraped body). Already cleaned of HTML.
    ///   - hints: known metadata to seed the draft (title, source URL, cover image URL…).
    func structure(text: String, hints: Hints = .init()) async throws -> RecipeDraft {
        // 1. Try on-device Foundation Models (Fase 5 will implement; no-op for now).
        if let draft = try await structureOnDevice(text: text, hints: hints) {
            return merge(draft: draft, hints: hints)
        }

        // 2. OpenAI fallback.
        let draft = try await structureWithOpenAI(text: text, hints: hints)
        return merge(draft: draft, hints: hints)
    }

    // MARK: - Hints

    struct Hints {
        var title: String? = nil
        var description: String? = nil
        var externalURL: URL? = nil
        var imageURL: URL? = nil
        var sourceLabel: String = ""
    }

    // MARK: - On-device (Fase 5: Apple Foundation Models)

    private func structureOnDevice(text: String, hints: Hints) async throws -> RecipeDraft? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await structureOnDeviceFoundationModels(text: text, hints: hints)
        }
        #endif
        return nil
    }

    // MARK: - OpenAI

    private func structureWithOpenAI(text: String, hints: Hints) async throws -> RecipeDraft {
        let systemPrompt = Self.systemPrompt
        let userPrompt = Self.userPrompt(text: text, hints: hints)

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        // Force JSON output using the tool definition pattern.
        let tool: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "emit_recipe",
                "description": "Retorna a receita estruturada.",
                "parameters": Self.jsonSchema
            ]
        ]]

        // Nudge the model to call the tool.
        messages.append([
            "role": "user",
            "content": "Chame a função emit_recipe com a receita estruturada. Não envie texto fora da chamada."
        ])

        let response = try await aiService.sendChat(messages: messages, tools: tool, apiKey: apiKey)

        guard let call = response.toolCalls.first else {
            // Sometimes models return JSON in content instead; try to parse that.
            if let content = response.content, let data = content.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parse(dict: dict)
            }
            throw RecipeImportError.aiFailed("A resposta do modelo não contém dados estruturados.")
        }

        guard let data = call.argumentsJSON.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecipeImportError.aiFailed("Argumentos da função em formato inválido.")
        }

        return parse(dict: dict)
    }

    // MARK: - Parsing

    private func parse(dict: [String: Any]) -> RecipeDraft {
        var d = RecipeDraft()
        if let s = dict["name"] as? String { d.name = s.trimmingCharacters(in: .whitespacesAndNewlines); d.nameConfidence = .high }
        if let s = dict["description"] as? String { d.descriptionText = s.trimmingCharacters(in: .whitespacesAndNewlines); d.descriptionConfidence = s.isEmpty ? .low : .medium }
        if let s = dict["category"] as? String, !s.isEmpty {
            d.category = s
            d.categoryConfidence = .medium
        }
        if let difficulty = dict["difficulty"] as? String,
           let matched = Difficulty.allCases.first(where: {
               $0.rawValue.compare(difficulty, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           }) {
            d.difficulty = matched
        }
        if let v = dict["prep_time_minutes"] as? Int, v > 0 {
            d.prepTime = v
            d.prepTimeConfidence = .high
        }
        if let v = dict["cook_time_minutes"] as? Int, v > 0 {
            d.cookTime = v
            d.cookTimeConfidence = .high
        }
        if let v = dict["servings"] as? Int, v > 0 {
            d.servings = v
            d.servingsConfidence = .high
        }
        if let v = dict["calories"] as? Int { d.calories = v }
        if let utensils = dict["required_utensils"] as? [String] {
            d.requiredUtensils = utensils.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        if let ingredients = dict["ingredients"] as? [[String: Any]] {
            d.ingredients = ingredients.enumerated().compactMap { _, item in
                guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                let qty: Double? = {
                    if let n = item["quantity"] as? Double { return n }
                    if let n = item["quantity"] as? Int { return Double(n) }
                    if let s = item["quantity"] as? String, let n = Double(s.replacingOccurrences(of: ",", with: ".")) { return n }
                    return nil
                }()
                let unit = (item["unit"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let state = (item["state"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let conf = confidenceString(item["confidence"] as? String) ?? .medium
                return IngredientDraft(
                    name: name,
                    quantity: qty,
                    unit: unit,
                    preparationState: state,
                    confidence: conf
                )
            }
        }

        if let steps = dict["steps"] as? [[String: Any]] {
            d.steps = steps.enumerated().compactMap { index, item in
                let instruction = (item["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !instruction.isEmpty else { return nil }
                let order = (item["order"] as? Int) ?? (index + 1)
                let duration = item["duration_minutes"] as? Int
                let conf = confidenceString(item["confidence"] as? String) ?? .medium
                return StepDraft(order: order, instruction: instruction, durationMinutes: duration, confidence: conf)
            }
        }

        return d
    }

    private func confidenceString(_ raw: String?) -> FieldConfidence? {
        switch raw?.lowercased() {
        case "high", "alta":   return .high
        case "medium", "média", "media": return .medium
        case "low", "baixa":   return .low
        default:                return nil
        }
    }

    // MARK: - Merge hints

    private func merge(draft: RecipeDraft, hints: Hints) -> RecipeDraft {
        var d = draft
        if d.name.isEmpty, let t = hints.title {
            d.name = t
            d.nameConfidence = .medium
        }
        if d.descriptionText.isEmpty, let desc = hints.description {
            d.descriptionText = desc
            d.descriptionConfidence = .medium
        }
        if d.imageURL == nil { d.imageURL = hints.imageURL }
        if d.externalURLString.isEmpty, let url = hints.externalURL { d.externalURLString = url.absoluteString }
        if d.sourceLabel.isEmpty { d.sourceLabel = hints.sourceLabel }
        return d
    }

    // MARK: - Prompts & schema

    private static var unitLabels: [String] {
        RecipeOptionCatalog.unitOptions.map { $0.menuLabel }
    }
    private static var stateLabels: [String] {
        RecipeOptionCatalog.stateOptions.map { $0.menuLabel }
    }

    static let systemPrompt: String = """
    Você é um assistente especializado em estruturar receitas culinárias em português brasileiro.
    Receba o texto de uma receita (pode estar bagunçado, vir de OCR, legenda de rede social ou texto colado) e transforme-a em dados estruturados.

    Regras:
    - Preserve as quantidades exatas do texto original sempre que possível.
    - Se uma quantidade não estiver clara, deixe o campo vazio e marque confiança "low" para o ingrediente.
    - Use apenas unidades desta lista (campo unit): \(unitLabels.joined(separator: " | ")).
      Você pode escolher a abreviação (ex.: "g", "mL", "c.s.") ou o nome completo. Se a unidade no texto não encaixar, deixe vazio.
    - Use apenas estados desta lista (campo state): \(stateLabels.joined(separator: " | ")). Se o texto não mencionar estado, deixe vazio.
    - Separe quantidade + unidade + nome + estado do ingrediente. Exemplo: "2 xícaras de farinha peneirada" → quantity=2, unit="Xícara", name="Farinha", state="Peneirada".
    - Passos devem ser curtos, imperativos e numerados.
    - Categoria: escolha a melhor entre "Café da manhã", "Almoço", "Jantar", "Lanche", "Sobremesa", "Bebida" ou "Outros".
    - Dificuldade: "Fácil", "Médio" ou "Difícil".
    - Não invente ingredientes nem passos. Se o texto for insuficiente, devolva arrays vazios.
    - Preserve o idioma do texto original (provavelmente pt-BR).
    - Não use emojis, hashtags ou texto promocional no resultado.
    """

    static func userPrompt(text: String, hints: Hints) -> String {
        var parts = ["Texto da receita:\n\"\"\"\n\(text)\n\"\"\""]
        if let t = hints.title, !t.isEmpty {
            parts.append("Título sugerido da fonte: \(t)")
        }
        if let d = hints.description, !d.isEmpty {
            parts.append("Descrição da fonte: \(d)")
        }
        if let url = hints.externalURL {
            parts.append("URL original: \(url.absoluteString)")
        }
        return parts.joined(separator: "\n\n")
    }

    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name":           ["type": "string", "description": "Nome da receita."],
            "description":    ["type": "string"],
            "category":       ["type": "string"],
            "difficulty":     ["type": "string", "enum": ["Fácil", "Médio", "Difícil"]],
            "prep_time_minutes": ["type": "integer", "minimum": 0],
            "cook_time_minutes": ["type": "integer", "minimum": 0],
            "servings":       ["type": "integer", "minimum": 1],
            "calories":       ["type": "integer", "minimum": 0],
            "required_utensils": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "ingredients": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name":       ["type": "string"],
                        "quantity":   ["type": ["number", "null"]],
                        "unit":       ["type": "string"],
                        "state":      ["type": "string"],
                        "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
                    ],
                    "required": ["name"]
                ]
            ],
            "steps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "order":       ["type": "integer", "minimum": 1],
                        "instruction": ["type": "string"],
                        "duration_minutes": ["type": ["integer", "null"]],
                        "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
                    ],
                    "required": ["instruction"]
                ]
            ]
        ],
        "required": ["name", "ingredients", "steps"]
    ]
}
