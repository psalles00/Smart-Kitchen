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

        let explicitItems = Self.expandedItems(from: [ParsedItem(name: trimmed, quantity: nil, unit: nil)])
        // Unambiguous local foods with explicit measures need no remote extraction.
        if explicitItems.contains(where: { $0.quantity != nil }),
           explicitItems.allSatisfy({ LocalNutritionFallback.nutrition(for: $0.name) != nil }) {
            return explicitItems
        }

        let systemPrompt = """
        Você é um extrator de itens alimentares. A partir do texto do usuário em \
        português brasileiro, identifique cada alimento mencionado com sua \
        quantidade e unidade canônica. Use unidades curtas: "g", "ml", "un", \
        "xícara", "colher de sopa", "colher de chá", "fatia". Se a quantidade \
        não estiver explícita, use null. "cs", "c.s." e "tbsp" significam colher \
        de sopa; "cc", "c.c." e "tsp" significam colher de chá. Exemplo: \
        "suco de limao com 6cs de acucar" => suco de limão (quantidade null) e \
        açúcar (quantidade 6, unidade "colher de sopa"). Nunca inclua medida no nome \
        do alimento nem substitua uma quantidade explícita por uma porção padrão.

        Regra crítica: se o texto descreve vários alimentos ligados por ";", ",", \
        "com" ou "e", emita cada alimento separadamente. Não emita um item composto \
        como "café com leite e açúcar" ou "pão com requeijão"; emita "café", \
        "leite", "açúcar", "pão" e "requeijão" como itens distintos. Quando uma \
        quantidade antes do alimento se aplica apenas ao primeiro alimento, não copie \
        essa quantidade para os complementos.
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
            return Self.expandedItems(from: [ParsedItem(name: trimmed, quantity: nil, unit: nil)])
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
            return Self.expandedItems(from: [ParsedItem(name: trimmed, quantity: nil, unit: nil)])
        }
        return Self.reconciledItems(items, description: trimmed)
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    static func expandedItems(from items: [ParsedItem]) -> [ParsedItem] {
        items.flatMap(expandedItems(from:))
    }

    private static func expandedItems(from item: ParsedItem) -> [ParsedItem] {
        let fragments = splitCompositeName(item.name)
        guard fragments.count > 1 else {
            return [extractEmbeddedQuantity(from: item)]
        }

        return fragments.enumerated().compactMap { index, fragment in
            var parsed = extractEmbeddedQuantity(
                from: ParsedItem(name: fragment, quantity: nil, unit: nil)
            )
            if index == 0, parsed.quantity == nil, item.quantity != nil {
                parsed.quantity = item.quantity
                parsed.unit = item.unit
            }
            return parsed.name.isEmpty ? nil : parsed
        }
    }

    private static func splitCompositeName(_ value: String) -> [String] {
        let protected = protectCompositeFoodNames(value)
        let pattern = #"(?i)\s*(?:;|(?<!\d),|,(?!\d)|\+|\bcom\b|\be\b)\s*"#
        let pieces = protected
            .replacingOccurrences(of: pattern, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map { restoreCompositeFoodNames($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? [value.trimmingCharacters(in: .whitespacesAndNewlines)] : pieces
    }

    private static func protectCompositeFoodNames(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)\bpão\s+de\s+forma\b"#, with: "pao_de_forma", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpao\s+de\s+forma\b"#, with: "pao_de_forma", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpão\s+de\s+queijo\b"#, with: "pao_de_queijo", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpao\s+de\s+queijo\b"#, with: "pao_de_queijo", options: .regularExpression)
    }

    private static func restoreCompositeFoodNames(_ value: String) -> String {
        value
            .replacingOccurrences(of: "pao_de_forma", with: "pao de forma")
            .replacingOccurrences(of: "pao_de_queijo", with: "pao de queijo")
    }

    private static func extractEmbeddedQuantity(from item: ParsedItem) -> ParsedItem {
        let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Explicit source measures take precedence even when the model guessed a portion.
        if let match = firstMatch(
            in: trimmed,
            pattern: #"^(\d+(?:[\.,]\d+)?)\s*(kg|g|gramas?|ml|l|litros?|un|unidades?|und|x[ií]caras?|cs|c\.s\.|cc|c\.c\.|tbsp|tsp|colheres?\s+de\s+sopa|colheres?\s+de\s+ch[aá]|fatias?|por(?:ç|c)(?:a|o|oes|ões)|copos?)(?=\s|$)(?:\s+de)?\s*(.+)$"#
        ) {
            return ParsedItem(name: cleanName(match[2]), quantity: numeric(match[0]), unit: canonicalUnit(match[1]))
        }
        if let match = firstMatch(in: trimmed, pattern: #"^(\d+(?:[\.,]\d+)?)\s+(.+)$"#),
           LocalNutritionFallback.nutrition(for: cleanName(match[1])) != nil {
            return ParsedItem(name: cleanName(match[1]), quantity: numeric(match[0]), unit: "un")
        }
        return ParsedItem(name: cleanName(trimmed), quantity: item.quantity, unit: item.unit.map(canonicalUnit))
    }

    /// Preserve explicit quantities and missing components from a simple composite request.
    /// AI remains responsible for natural-language requests and unspecified portions.
    static func reconciledItems(_ items: [ParsedItem], description: String) -> [ParsedItem] {
        let expanded = expandedItems(from: items)
        let source = expandedItems(from: [ParsedItem(name: description, quantity: nil, unit: nil)])
        guard source.contains(where: { $0.quantity != nil && $0.unit != nil }) else { return expanded }
        // Restrict reconstruction to complete local composites. Other AI food names
        // may be translated, singularized or refined and must not be duplicated.
        guard source.count > 1, source.allSatisfy({ LocalNutritionFallback.nutrition(for: $0.name) != nil }) else {
            return expanded.map { item in
                guard let explicit = source.first(where: {
                    FoodCache.canonicalize($0.name) == FoodCache.canonicalize(item.name) && $0.quantity != nil
                }) else { return item }
                return explicit
            }
        }
        let result = source.map { part -> ParsedItem in
            let referenceName = LocalNutritionFallback.nutrition(for: part.name)?.canonicalName
            guard var matching = expanded.first(where: {
                FoodCache.canonicalize($0.name) == FoodCache.canonicalize(part.name)
                    || (referenceName != nil && LocalNutritionFallback.nutrition(for: $0.name)?.canonicalName == referenceName)
            }) else { return part }
            if let quantity = part.quantity {
                matching.quantity = quantity
                matching.unit = part.unit
            }
            return matching
        }
        return result
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        let groups = (1..<result.numberOfRanges).compactMap { index -> String? in
            let groupRange = result.range(at: index)
            guard groupRange.location != NSNotFound else { return nil }
            return nsText.substring(with: groupRange)
        }
        return groups
    }

    private static func cleanName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^(de|da|do|das|dos)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalUnit(_ raw: String) -> String {
        let unit = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if unit == "grama" || unit == "gramas" { return "g" }
        if unit == "litro" || unit == "litros" { return "l" }
        if unit == "unidade" || unit == "unidades" || unit == "und" { return "un" }
        if unit == "xicaras" { return "xicara" }
        if ["colheres de sopa", "cs", "c.s.", "tbsp"].contains(unit) { return "colher de sopa" }
        if ["colheres de cha", "cc", "c.c.", "tsp"].contains(unit) { return "colher de cha" }
        if unit == "fatias" { return "fatia" }
        if unit == "porcao" || unit == "porcoes" { return "porcao" }
        if unit == "copos" { return "copo" }
        return unit
    }
}
