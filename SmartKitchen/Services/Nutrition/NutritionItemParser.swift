import Foundation

/// Parses a free-form Brazilian Portuguese description like
/// "2 ovos com 100g de arroz e meia xícara de feijão" into discrete items.
///
/// Uses the existing `AIService` (OpenAI → OpenRouter fallback) with a forced
/// tool call to get structured JSON back. Apple Intelligence is not used here
/// yet because `FoundationModels` has no equivalent of OpenAI tool calls.
@MainActor
final class NutritionItemParser {

    struct ParsedItem: Sendable {
        var name: String       // free-form, e.g. "ovo"
        var quantity: Double?  // nil when unspecified
        var unit: String?      // free-form unit ("g", "ml", "un", "xícara")
    }

    private let ai: any NutritionAIClient

    init(ai: any NutritionAIClient = AIService()) {
        self.ai = ai
    }

    /// Parses `description`. Returns at least one item; falls back to a single
    /// default-portion item when the LLM can't produce structure.
    func parse(_ description: String) async throws -> [ParsedItem] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let systemPrompt = """
        Você é um extrator de itens alimentares. A partir do texto do usuário em \
        português brasileiro, identifique cada alimento mencionado com sua \
        quantidade e unidade canônica. Use unidades curtas: "g", "ml", "un", \
        "xícara", "colher de sopa", "colher de chá", "fatia". Se a quantidade \
        não estiver explícita, use null.
        """

        let userPrompt = "Texto: \(trimmed)"

        let tool: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "emit_items",
                "description": "Devolve a lista de itens alimentares.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "items": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name":     ["type": "string"],
                                    "quantity": ["type": ["number", "null"]],
                                    "unit":     ["type": ["string", "null"]]
                                ],
                                "required": ["name"]
                            ]
                        ]
                    ],
                    "required": ["items"]
                ]
            ]
        ]]

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userPrompt],
            ["role": "user",   "content": "Chame a função emit_items. Não envie texto fora da chamada."]
        ]

        let apiKey = APIConfig.openAIAPIKey
        let response = try await ai.sendNutritionChat(
            messages: messages,
            tools: tool,
            apiKey: apiKey,
            model: nil,
            acceptLanguage: AppLocalization.current().acceptLanguageHeader
        )

        guard let call = response.toolCalls.first,
              let data = call.argumentsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = dict["items"] as? [[String: Any]] else {
            // Fallback: treat the whole string as a single item with no quantity.
            return [ParsedItem(name: trimmed, quantity: nil, unit: nil)]
        }

        var items: [ParsedItem] = []
        for entry in raw {
            guard let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let qty = Self.numeric(entry["quantity"])
            let unit = (entry["unit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(ParsedItem(name: name, quantity: qty, unit: unit))
        }

        if items.isEmpty {
            return [ParsedItem(name: trimmed, quantity: nil, unit: nil)]
        }
        return items
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
