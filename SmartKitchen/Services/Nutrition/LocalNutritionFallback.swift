import Foundation

/// Local nutrition safety net used when the AI/backend path is unavailable.
///
/// This is intentionally conservative: it handles common text logs and a small
/// set of branded products with per-100g/per-100ml values. Unknown inputs still
/// fall through to the normal AI path.
@MainActor
enum LocalNutritionFallback {
    static func analyzeText(_ description: String) -> FoodAnalysis? {
        let parsed = parse(description)
        guard !parsed.isEmpty else { return nil }

        let resolved = parsed.compactMap { item -> NutritionCalculator.Resolved? in
            guard let nutrition = nutrition(for: item.name) else { return nil }
            return NutritionCalculator.Resolved(item: item, per100g: nutrition)
        }

        guard !resolved.isEmpty else { return nil }
        return NutritionCalculator.combine(items: resolved, originalDescription: description)
    }

    static func nutrition(for rawName: String) -> Per100gNutrition? {
        let normalized = normalize(rawName)
        let candidates = entries
            .flatMap { entry in entry.aliases.map { (alias: $0, entry: entry) } }

        let exactMatch = candidates
            .filter { alias, _ in normalized == alias }
            .max { lhs, rhs in lhs.alias.count < rhs.alias.count }

        let fuzzyMatch = candidates
            .filter { alias, _ in
                normalized.contains(alias) || alias.contains(normalized)
            }
            .max { lhs, rhs in lhs.alias.count < rhs.alias.count }

        guard let entry = (exactMatch ?? fuzzyMatch)?.entry else { return nil }
        return Per100gNutrition(
            canonicalName: FoodCache.canonicalize(entry.aliases[0]),
            locale: AppLocalization.current().nutritionCacheLocaleIdentifier,
            displayName: entry.displayName,
            kcal: entry.kcal,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat,
            sugar: entry.sugar,
            addedSugar: entry.addedSugar,
            fiber: entry.fiber,
            saturatedFat: entry.saturatedFat,
            monounsaturatedFat: nil,
            polyunsaturatedFat: nil,
            cholesterol: entry.cholesterol,
            sodium: entry.sodium,
            potassium: entry.potassium,
            emoji: entry.emoji,
            servingGrams: entry.servingGrams,
            source: "local",
            citationURL: entry.citationURL,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }

    private static func parse(_ description: String) -> [NutritionItemParser.ParsedItem] {
        let chunks = splitItems(description)
        return chunks.compactMap(parseItem)
    }

    private static func splitItems(_ description: String) -> [String] {
        let normalized = description
            .replacingOccurrences(of: " + ", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")

        return normalized
            .components(separatedBy: CharacterSet(charactersIn: ","))
            .flatMap { chunk in
                chunk
                    .replacingOccurrences(of: " com ", with: ",", options: [.caseInsensitive])
                    .replacingOccurrences(of: " e ", with: ",", options: [.caseInsensitive])
                    .components(separatedBy: ",")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseItem(_ raw: String) -> NutritionItemParser.ParsedItem? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = firstMatch(
            in: trimmed,
            pattern: #"(\d+(?:[\.,]\d+)?)\s*(kg|g|gramas?|ml|l|litros?|un|unidades?|und|xicaras?|colheres?\s+de\s+sopa|colheres?\s+de\s+cha|fatias?|por(?:ç|c)(?:a|o|oes|ões)|copos?)\b"#
        ) {
            let quantity = number(match.groups[0])
            let unit = canonicalUnit(match.groups[1])
            var name = (trimmed as NSString).replacingCharacters(in: match.range, with: " ")
            name = cleanName(name)
            guard !name.isEmpty else { return nil }
            return NutritionItemParser.ParsedItem(name: name, quantity: quantity, unit: unit)
        }

        if let match = firstMatch(in: trimmed, pattern: #"^(\d+(?:[\.,]\d+)?)\s+(.+)$"#),
           let quantity = number(match.groups[0]) {
            let name = cleanName(match.groups[1])
            guard !name.isEmpty else { return nil }
            return NutritionItemParser.ParsedItem(name: name, quantity: quantity, unit: "un")
        }

        let name = cleanName(trimmed)
        guard !name.isEmpty else { return nil }
        return NutritionItemParser.ParsedItem(name: name, quantity: nil, unit: nil)
    }

    private static func firstMatch(in text: String, pattern: String) -> (range: NSRange, groups: [String])? {
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
        return (result.range, groups)
    }

    private static func cleanName(_ value: String) -> String {
        normalize(value)
            .replacingOccurrences(of: #"^(de|da|do|das|dos)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func canonicalUnit(_ raw: String) -> String {
        let unit = normalize(raw)
        if unit == "grama" || unit == "gramas" { return "g" }
        if unit == "litro" || unit == "litros" { return "l" }
        if unit == "unidade" || unit == "unidades" || unit == "und" { return "un" }
        if unit == "xicaras" { return "xicara" }
        if unit == "colheres de sopa" { return "colher de sopa" }
        if unit == "colheres de cha" { return "colher de cha" }
        if unit == "fatias" { return "fatia" }
        if unit == "porcao" || unit == "porcoes" { return "porcao" }
        if unit == "copos" { return "copo" }
        return unit
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Entry {
        let displayName: String
        let aliases: [String]
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let sugar: Double?
        let addedSugar: Double?
        let fiber: Double?
        let saturatedFat: Double?
        let cholesterol: Double?
        let sodium: Double?
        let potassium: Double?
        let servingGrams: Double
        let emoji: String?
        let citationURL: String?
    }

    private static let entries: [Entry] = [
        Entry(displayName: "Banana", aliases: ["banana"], kcal: 89, protein: 1.1, carbs: 22.8, fat: 0.3, sugar: 12.2, addedSugar: nil, fiber: 2.6, saturatedFat: 0.1, cholesterol: 0, sodium: 1, potassium: 358, servingGrams: 118, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Maca", aliases: ["maca", "apple"], kcal: 52, protein: 0.3, carbs: 13.8, fat: 0.2, sugar: 10.4, addedSugar: nil, fiber: 2.4, saturatedFat: 0, cholesterol: 0, sodium: 1, potassium: 107, servingGrams: 180, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Ovo", aliases: ["ovo", "ovos", "egg", "eggs"], kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5, sugar: 0.4, addedSugar: nil, fiber: 0, saturatedFat: 3.1, cholesterol: 372, sodium: 142, potassium: 138, servingGrams: 50, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Arroz branco cozido", aliases: ["arroz branco", "arroz cozido", "white rice", "rice"], kcal: 128, protein: 2.5, carbs: 28.1, fat: 0.2, sugar: 0.1, addedSugar: nil, fiber: 1.6, saturatedFat: 0.1, cholesterol: 0, sodium: 1, potassium: 35, servingGrams: 100, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Arroz integral cozido", aliases: ["arroz integral", "brown rice"], kcal: 124, protein: 2.6, carbs: 25.8, fat: 1.0, sugar: nil, addedSugar: nil, fiber: 2.7, saturatedFat: 0.3, cholesterol: 0, sodium: 1.2, potassium: 75, servingGrams: 100, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Feijao cozido", aliases: ["feijao", "feijao carioca", "beans"], kcal: 76, protein: 4.8, carbs: 13.6, fat: 0.5, sugar: nil, addedSugar: nil, fiber: 8.5, saturatedFat: 0.1, cholesterol: 0, sodium: 2, potassium: 255, servingGrams: 100, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Frango grelhado", aliases: ["frango", "peito de frango", "chicken breast", "grilled chicken"], kcal: 165, protein: 31, carbs: 0, fat: 3.6, sugar: 0, addedSugar: nil, fiber: 0, saturatedFat: 1.0, cholesterol: 85, sodium: 74, potassium: 256, servingGrams: 120, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Pao frances", aliases: ["pao frances", "pao", "bread"], kcal: 300, protein: 8, carbs: 58, fat: 3.1, sugar: 2.0, addedSugar: nil, fiber: 2.3, saturatedFat: 0.7, cholesterol: 0, sodium: 648, potassium: 115, servingGrams: 50, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Pao de forma", aliases: ["pao de forma", "pao forma", "sandwich bread", "white bread"], kcal: 253, protein: 8.0, carbs: 45.0, fat: 3.3, sugar: 5.0, addedSugar: nil, fiber: 2.7, saturatedFat: 0.8, cholesterol: 0, sodium: 491, potassium: 115, servingGrams: 25, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Leite integral", aliases: ["leite integral", "leite", "whole milk", "milk"], kcal: 61, protein: 3.2, carbs: 4.8, fat: 3.3, sugar: 5.1, addedSugar: nil, fiber: 0, saturatedFat: 1.9, cholesterol: 10, sodium: 43, potassium: 150, servingGrams: 200, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Cafe sem acucar", aliases: ["cafe", "cafe preto", "coffee", "black coffee"], kcal: 2, protein: 0.1, carbs: 0, fat: 0, sugar: 0, addedSugar: 0, fiber: 0, saturatedFat: 0, cholesterol: 0, sodium: 2, potassium: 49, servingGrams: 100, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Acucar", aliases: ["acucar", "sugar"], kcal: 387, protein: 0, carbs: 100, fat: 0, sugar: 100, addedSugar: 100, fiber: 0, saturatedFat: 0, cholesterol: 0, sodium: 1, potassium: 2, servingGrams: 5, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Requeijao light", aliases: ["requeijao light", "requeijao", "light cream cheese", "cream cheese light"], kcal: 185, protein: 9.0, carbs: 6.0, fat: 13.0, sugar: 3.0, addedSugar: nil, fiber: 0, saturatedFat: 8.0, cholesterol: 40, sodium: 520, potassium: nil, servingGrams: 30, emoji: nil, citationURL: "https://tbca.net.br/"),
        Entry(displayName: "Aveia", aliases: ["aveia", "oats", "oatmeal"], kcal: 389, protein: 16.9, carbs: 66.3, fat: 6.9, sugar: 1.0, addedSugar: nil, fiber: 10.6, saturatedFat: 1.2, cholesterol: 0, sodium: 2, potassium: 429, servingGrams: 40, emoji: nil, citationURL: "https://fdc.nal.usda.gov/"),
        Entry(displayName: "Coca-Cola", aliases: ["coca-cola", "coca cola", "coke"], kcal: 42, protein: 0, carbs: 10.6, fat: 0, sugar: 10.6, addedSugar: 10.6, fiber: 0, saturatedFat: 0, cholesterol: 0, sodium: 4, potassium: nil, servingGrams: 350, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Soda Antarctica", aliases: ["soda antarctica", "soda limonada antarctica"], kcal: 40, protein: 0, carbs: 10, fat: 0, sugar: 10, addedSugar: 10, fiber: 0, saturatedFat: 0, cholesterol: 0, sodium: 4, potassium: nil, servingGrams: 350, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Leite Moca", aliases: ["leite moca", "moca", "leite condensado", "condensed milk"], kcal: 321, protein: 7.6, carbs: 55, fat: 8.4, sugar: 55, addedSugar: nil, fiber: 0, saturatedFat: 5.2, cholesterol: 28, sodium: 127, potassium: nil, servingGrams: 20, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Nescau 2.0", aliases: ["nescau", "nescau 2 0", "nescau 2.0"], kcal: 400, protein: 4.2, carbs: 90, fat: 2.0, sugar: 75, addedSugar: nil, fiber: 3.0, saturatedFat: 1.0, cholesterol: 0, sodium: 160, potassium: nil, servingGrams: 20, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Corn Flakes", aliases: ["corn flakes", "kelloggs corn flakes", "kellogg corn flakes"], kcal: 357, protein: 7.5, carbs: 84, fat: 0.4, sugar: 8, addedSugar: nil, fiber: 3.0, saturatedFat: 0.1, cholesterol: 0, sodium: 729, potassium: 168, servingGrams: 30, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Jif Peanut Butter", aliases: ["jif", "jif peanut butter", "peanut butter", "pasta de amendoim"], kcal: 588, protein: 22, carbs: 22, fat: 50, sugar: 9.4, addedSugar: nil, fiber: 6.3, saturatedFat: 9.4, cholesterol: 0, sodium: 438, potassium: nil, servingGrams: 33, emoji: nil, citationURL: "https://world.openfoodfacts.org/"),
        Entry(displayName: "Lay's Classic", aliases: ["lays", "lay s", "lays classic", "batata lays", "potato chips"], kcal: 536, protein: 7.1, carbs: 53.6, fat: 35.7, sugar: 0, addedSugar: nil, fiber: 3.6, saturatedFat: 5.4, cholesterol: 0, sodium: 607, potassium: nil, servingGrams: 28, emoji: nil, citationURL: "https://world.openfoodfacts.org/")
    ].map { entry in
        Entry(
            displayName: entry.displayName,
            aliases: entry.aliases.map { normalize($0) },
            kcal: entry.kcal,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat,
            sugar: entry.sugar,
            addedSugar: entry.addedSugar,
            fiber: entry.fiber,
            saturatedFat: entry.saturatedFat,
            cholesterol: entry.cholesterol,
            sodium: entry.sodium,
            potassium: entry.potassium,
            servingGrams: entry.servingGrams,
            emoji: entry.emoji,
            citationURL: entry.citationURL
        )
    }
}
