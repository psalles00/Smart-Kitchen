import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Chama a OpenAI Chat Completions com prompts calibrados para análise nutricional
/// (foto de comida, rótulo nutricional e descrição em texto).
///
/// Reutiliza `AIService` para rede + auth. Para vision usa `gpt-4o-mini`; para texto, o default.
@MainActor
final class NutritionAIService {
    enum NutritionAIError: LocalizedError {
        case missingAPIKey
        case emptyResponse
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Chave de API não configurada. Adicione sua chave OpenAI em Ajustes.")
            case .emptyResponse:
                return String(localized: "Resposta vazia da IA.")
            case .invalidJSON(let msg):
                return String(localized: "Não foi possível entender a resposta da IA: \(msg)")
            }
        }
    }

    private let ai = AIService()
    private let usda = USDANutritionLookup()
    private let exa = ExaNutritionLookup()
    private let parser = NutritionItemParser()
    private let cache = FoodCache.shared
    private let visionModel = "gpt-4o-mini"
    private let textModel = "gpt-4.1-mini"

    // MARK: - Public API

    /// Text-based nutrition analysis. Pipeline:
    /// 1. Parse `description` into discrete items (`{name, qty, unit}`).
    /// 2. For each item: Supabase cache → USDA FoodData Central → Exa → LLM fallback.
    /// 3. Cache hits/misses are written back to Supabase (write-through).
    /// 4. `NutritionCalculator` does the final scaling+sum in pure Swift.
    func analyzeText(description: String) async throws -> FoodAnalysis {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NutritionAIError.emptyResponse }

        // 1. Parse into items.
        let parsed: [NutritionItemParser.ParsedItem]
        do {
            parsed = try await parser.parse(trimmed)
        } catch {
            // If even parsing fails, fall back to the legacy single-shot LLM
            // estimate so the user still gets *something*.
            LLMLog.error("Nutrition parse failed, using legacy LLM: \(error.localizedDescription)")
            return try await legacyLLMEstimate(description: trimmed)
        }
        guard !parsed.isEmpty else { return try await legacyLLMEstimate(description: trimmed) }

        // 2. Resolve per-100g for each item.
        let (resolved, ids) = await resolvePer100g(for: parsed)
        guard !resolved.isEmpty else { return try await legacyLLMEstimate(description: trimmed) }

        // 3. Combine via pure Swift.
        var combined = NutritionCalculator.combine(items: resolved, originalDescription: trimmed)
        combined.cachedFoodIDs = ids.isEmpty ? nil : ids
        return combined
    }

    func analyzeFoodImage(imageData: Data, description: String? = nil) async throws -> FoodAnalysis {
        var prompt = """
        Analyze this food image. Identify the food and estimate its nutritional content.

        Respond ONLY with a JSON object in this exact format, no other text:
        {"name":"Food Name","calories":0,"protein":0,"carbs":0,"fat":0,"serving_size_grams":0.0,"sugar":0.0,"added_sugar":0.0,"fiber":0.0,"saturated_fat":0.0,"monounsaturated_fat":0.0,"polyunsaturated_fat":0.0,"cholesterol":0.0,"sodium":0.0,"potassium":0.0}

        Calories/protein/carbs/fat are integers. serving_size_grams is the estimated weight in grams of the serving shown. Micronutrients are numbers (sugar/fiber/sat fat/mono fat/poly fat in grams, cholesterol/sodium/potassium in milligrams).
        Give your best estimate for a typical serving size shown in the image. Use null for any nutrient you cannot estimate.
        Respond in Brazilian Portuguese for the "name" field when possible.
        """
        if let description, !description.isEmpty {
            prompt += "\n\nAdditional context from the user about this meal: \(description)\nUse this context to improve accuracy of identification, portion size, and nutrition estimates."
        }
        let raw = try await callVision(prompt: prompt, imageData: imageData)
        return try Self.parseFoodAnalysis(from: raw)
    }

    func analyzeNutritionLabel(imageData: Data) async throws -> NutritionLabelAnalysis {
        let prompt = """
        Read this nutrition label image. Extract the nutritional values per 100g (or per 100ml).
        If the label shows per-serving values, convert them to per-100g using the serving size.

        For the name, identify the product or brand name visible on the packaging or label.
        If no name is visible, describe the food type (e.g. "Protein Bar", "Yogurt", "Cereal").

        Respond ONLY with JSON:
        {"name":"Product Name","calories_per_100g":0.0,"protein_per_100g":0.0,"carbs_per_100g":0.0,"fat_per_100g":0.0,"serving_size_grams":0.0,"sugar_per_100g":0.0,"added_sugar_per_100g":0.0,"fiber_per_100g":0.0,"saturated_fat_per_100g":0.0,"monounsaturated_fat_per_100g":0.0,"polyunsaturated_fat_per_100g":0.0,"cholesterol_per_100g":0.0,"sodium_per_100g":0.0,"potassium_per_100g":0.0}

        All values should be numbers. If serving size or any nutrient is not available, use null.
        """
        let raw = try await callVision(prompt: prompt, imageData: imageData)
        return try Self.parseNutritionLabel(from: raw)
    }

    // MARK: - Networking primitives

    /// Resolves per-100g data for each parsed item, going cache → USDA → Exa → LLM.
    /// Successful USDA, Exa, or LLM lookups are written back to Supabase and the
    /// returned IDs are surfaced so the UI can attach votes.
    private func resolvePer100g(
        for items: [NutritionItemParser.ParsedItem]
    ) async -> (resolved: [NutritionCalculator.Resolved], ids: [UUID]) {
        var slots: [Per100gNutrition?] = Array(repeating: nil, count: items.count)
        var pendingUSDA: [(index: Int, name: String)] = []
        var pendingLLMOnly: [(index: Int, item: NutritionItemParser.ParsedItem)] = []

        // 1. Cache lookup (sequential — Supabase REST is fast enough for small N).
        for (i, item) in items.enumerated() {
            if Self.shouldResolveWithLLMOnly(item.name) {
                pendingLLMOnly.append((i, item))
                continue
            }
            let canonical = FoodCache.canonicalize(item.name)
            if let hit = await cache.lookup(canonicalName: canonical),
               Self.shouldTrustCachedNutrition(hit, for: item.name) {
                slots[i] = hit
            } else {
                pendingUSDA.append((i, item.name))
            }
        }

        // 2. USDA batch for the misses.
        if !pendingUSDA.isEmpty {
            let names = pendingUSDA.map { $0.name }
            let usdaResults = await usda.fetchPer100g(for: names)
            for (offset, usdaItem) in usdaResults.enumerated() {
                let slot = pendingUSDA[offset].index
                if usdaItem.hasMacros {
                    var copy = usdaItem
                    if cache.isEnabled {
                        do {
                            let id = try await cache.upsert(usdaItem)
                            copy.id = id
                        } catch {
                            LLMLog.error("FoodCache upsert (usda) failed: \(error.localizedDescription)")
                        }
                    }
                    slots[slot] = copy
                }
            }
        }

        var pendingExa: [(index: Int, name: String)] = []
        for pending in pendingUSDA where slots[pending.index]?.hasMacros != true {
            pendingExa.append(pending)
        }

        // 3. Exa batch for the USDA misses.
        if !pendingExa.isEmpty {
            let names = pendingExa.map { $0.name }
            do {
                let exaResults = try await exa.fetchPer100g(for: names)
                for (offset, exaItem) in exaResults.enumerated() {
                    let slot = pendingExa[offset].index
                    if exaItem.hasMacros {
                        var copy = exaItem
                        if cache.isEnabled {
                            do {
                                let id = try await cache.upsert(exaItem)
                                copy.id = id
                            } catch {
                                LLMLog.error("FoodCache upsert (exa) failed: \(error.localizedDescription)")
                            }
                        }
                        slots[slot] = copy
                    }
                }
            } catch {
                LLMLog.error("Exa batch failed: \(error.localizedDescription)")
            }
        }

        // 4. LLM fallback for any remaining empty/incomplete slots.
        for pending in pendingLLMOnly where slots[pending.index]?.hasMacros != true {
            if let llmEntry = await llmPer100gEstimate(for: pending.item) {
                slots[pending.index] = llmEntry
            }
        }

        for (i, item) in items.enumerated() where slots[i]?.hasMacros != true {
            if let llmEntry = await llmPer100gEstimate(for: item) {
                var copy = llmEntry
                if cache.isEnabled {
                    do {
                        let id = try await cache.upsert(llmEntry)
                        copy.id = id
                    } catch {
                        LLMLog.error("FoodCache upsert (llm) failed: \(error.localizedDescription)")
                    }
                }
                slots[i] = copy
            }
        }

        // Build Resolved list, dropping items we couldn't resolve at all.
        var resolved: [NutritionCalculator.Resolved] = []
        var ids: [UUID] = []
        for (i, item) in items.enumerated() {
            if let p = slots[i], p.hasMacros {
                resolved.append(NutritionCalculator.Resolved(item: item, per100g: p))
                if let id = p.id { ids.append(id) }
            }
        }
        return (resolved, ids)
    }

    private static func shouldResolveWithLLMOnly(_ name: String) -> Bool {
        let n = normalizedFoodName(name)
        let localCompositeTerms = [
            "x ", "xis ", "x-", "xtudo", "x tudo", "xduplo", "x duplo",
            "hamburguer", "hamburger", "burger", "sanduiche", "sandwich",
            "lanche", "hot dog", "cachorro quente", "coxinha", "pastel"
        ]
        return localCompositeTerms.contains { term in
            let trimmed = term.trimmingCharacters(in: .whitespaces)
            return n == trimmed || n.contains(term)
        }
    }

    private static func shouldTrustCachedNutrition(_ food: Per100gNutrition, for name: String) -> Bool {
        guard food.hasMacros else { return false }
        if shouldResolveWithLLMOnly(name) {
            return food.source == "llm"
        }

        let display = normalizedFoodName(food.displayName ?? "")
        let query = normalizedFoodName(name)
        if food.source == "usda",
           display.contains("strawberr"),
           !query.contains("strawberr"),
           !query.contains("morango") {
            return false
        }
        return true
    }

    private static func normalizedFoodName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Single-item per-100g estimate via LLM (Gemini 3 Flash via OpenRouter or
    /// OpenAI, depending on `AIService` routing). Used when cache and Exa miss.
    private func llmPer100gEstimate(
        for item: NutritionItemParser.ParsedItem
    ) async -> Per100gNutrition? {
        let prompt = """
        Estime os valores nutricionais por 100g para o alimento abaixo. Considere \
        valores típicos brasileiros se aplicável. Responda APENAS com JSON:
        {"display_name":"...","serving_size_grams":0,"kcal_per_100g":0,"protein_per_100g":0,"carbs_per_100g":0,"fat_per_100g":0,"sugar_per_100g":null,"added_sugar_per_100g":null,"fiber_per_100g":null,"saturated_fat_per_100g":null,"monounsaturated_fat_per_100g":null,"polyunsaturated_fat_per_100g":null,"cholesterol_per_100g":null,"sodium_per_100g":null,"potassium_per_100g":null,"emoji":"🍽️"}
        macros em g, micros em g (sat/mono/poly/sugar/fiber) ou mg (cholesterol/sodium/potassium).
        serving_size_grams é a porção típica inteira desse alimento quando o usuário não informa quantidade.
        Use null para o que não souber estimar com confiança.

        Alimento: \(item.name)
        """
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        do {
            let response = try await ai.sendChat(messages: messages, apiKey: APIConfig.openAIAPIKey)
            guard let content = response.content, !content.isEmpty else { return nil }
            return Self.parsePer100g(rawJSON: content, name: item.name)
        } catch {
            LLMLog.error("LLM per-100g failed for \(item.name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses the per-100g JSON object emitted by the LLM fallback prompt.
    private static func parsePer100g(rawJSON: String, name: String) -> Per100gNutrition? {
        let cleaned = extractJSON(from: rawJSON)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        func d(_ key: String) -> Double? {
            if let v = obj[key] as? Double { return v }
            if let v = obj[key] as? Int { return Double(v) }
            return nil
        }
        guard let kcal = d("kcal_per_100g"),
              let protein = d("protein_per_100g"),
              let carbs = d("carbs_per_100g"),
              let fat = d("fat_per_100g") else {
            return nil
        }
        return Per100gNutrition(
            canonicalName: FoodCache.canonicalize(name),
            locale: AppLocalization.current().nutritionCacheLocaleIdentifier,
            displayName: (obj["display_name"] as? String) ?? name,
            kcal: kcal, protein: protein, carbs: carbs, fat: fat,
            sugar: d("sugar_per_100g"),
            addedSugar: d("added_sugar_per_100g"),
            fiber: d("fiber_per_100g"),
            saturatedFat: d("saturated_fat_per_100g"),
            monounsaturatedFat: d("monounsaturated_fat_per_100g"),
            polyunsaturatedFat: d("polyunsaturated_fat_per_100g"),
            cholesterol: d("cholesterol_per_100g"),
            sodium: d("sodium_per_100g"),
            potassium: d("potassium_per_100g"),
            emoji: obj["emoji"] as? String,
            servingGrams: d("serving_size_grams"),
            source: "llm",
            citationURL: nil,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }

    /// Last-ditch fallback when even item parsing fails: fire the original
    /// single-shot prompt and return its `FoodAnalysis` directly. Preserves
    /// pre-Exa behavior for pathological inputs.
    private func legacyLLMEstimate(description: String) async throws -> FoodAnalysis {
        let prompt = """
        Estimate the nutritional content for: \(description)
        Parse any quantities, brands, and multiple items from the text. If a brand is mentioned, use that brand's known nutritional data. If multiple items are described, sum up the total nutrition.
        Respond ONLY with JSON:
        {"name":"...","calories":0,"protein":0,"carbs":0,"fat":0,"serving_size_grams":0.0,"emoji":"🍽️","sugar":0.0,"added_sugar":0.0,"fiber":0.0,"saturated_fat":0.0,"monounsaturated_fat":0.0,"polyunsaturated_fat":0.0,"cholesterol":0.0,"sodium":0.0,"potassium":0.0}
        Calories/protein/carbs/fat are integers. serving_size_grams is the estimated total weight in grams. Micronutrients are numbers (sugar/fiber/sat fat/mono fat/poly fat in grams, cholesterol/sodium/potassium in milligrams).
        Include a single food emoji that best represents the food. Use null for any nutrient you cannot estimate.
        Respond in Brazilian Portuguese for the "name" field when possible.
        """
        let raw = try await callText(prompt: prompt)
        return try Self.parseFoodAnalysis(from: raw)
    }

    private func callText(prompt: String) async throws -> String {
        let apiKey = APIConfig.openAIAPIKey
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        let response = try await ai.sendChat(
            messages: messages,
            apiKey: apiKey,
            model: textModel,
            acceptLanguage: AppLocalization.current().acceptLanguageHeader
        )
        guard let content = response.content, !content.isEmpty else {
            throw NutritionAIError.emptyResponse
        }
        return content
    }

    private func callVision(prompt: String, imageData: Data) async throws -> String {
        try await ai.analyzeImage(
            prompt: prompt,
            imageData: imageData,
            apiKey: APIConfig.openAIAPIKey,
            model: visionModel,
            maxTokens: 1024,
            acceptLanguage: AppLocalization.current().acceptLanguageHeader
        )
    }

    // MARK: - JSON extraction + parsing

    /// Remove fences markdown (```json / ```) e extrai o primeiro objeto JSON válido.
    static func extractJSON(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // remove abertura ```json ou ```
            if let endOfFence = s.range(of: "\n") {
                s = String(s[endOfFence.upperBound...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }

    static func parseFoodAnalysis(from raw: String) throws -> FoodAnalysis {
        let jsonString = extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NutritionAIError.invalidJSON(raw)
        }

        func intValue(_ key: String) -> Int {
            if let v = obj[key] as? Int { return v }
            if let v = obj[key] as? Double { return Int(v.rounded()) }
            return 0
        }
        func doubleOpt(_ key: String) -> Double? {
            if let v = obj[key] as? Double { return v }
            if let v = obj[key] as? Int { return Double(v) }
            return nil
        }

        return FoodAnalysis(
            name: (obj["name"] as? String) ?? "",
            calories: intValue("calories"),
            protein: intValue("protein"),
            carbs: intValue("carbs"),
            fat: intValue("fat"),
            servingSizeGrams: doubleOpt("serving_size_grams") ?? 100,
            emoji: obj["emoji"] as? String,
            sugarG: doubleOpt("sugar"),
            addedSugarG: doubleOpt("added_sugar"),
            fiberG: doubleOpt("fiber"),
            saturatedFatG: doubleOpt("saturated_fat"),
            monounsaturatedFatG: doubleOpt("monounsaturated_fat"),
            polyunsaturatedFatG: doubleOpt("polyunsaturated_fat"),
            cholesterolMg: doubleOpt("cholesterol"),
            sodiumMg: doubleOpt("sodium"),
            potassiumMg: doubleOpt("potassium")
        )
    }

    static func parseNutritionLabel(from raw: String) throws -> NutritionLabelAnalysis {
        let jsonString = extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NutritionAIError.invalidJSON(raw)
        }
        func d(_ key: String) -> Double {
            if let v = obj[key] as? Double { return v }
            if let v = obj[key] as? Int { return Double(v) }
            return 0
        }
        func dOpt(_ key: String) -> Double? {
            if let v = obj[key] as? Double { return v }
            if let v = obj[key] as? Int { return Double(v) }
            return nil
        }
        return NutritionLabelAnalysis(
            name: (obj["name"] as? String) ?? "",
            caloriesPer100g: d("calories_per_100g"),
            proteinPer100g: d("protein_per_100g"),
            carbsPer100g: d("carbs_per_100g"),
            fatPer100g: d("fat_per_100g"),
            servingSizeGrams: dOpt("serving_size_grams"),
            sugarPer100g: dOpt("sugar_per_100g"),
            addedSugarPer100g: dOpt("added_sugar_per_100g"),
            fiberPer100g: dOpt("fiber_per_100g"),
            saturatedFatPer100g: dOpt("saturated_fat_per_100g"),
            monounsaturatedFatPer100g: dOpt("monounsaturated_fat_per_100g"),
            polyunsaturatedFatPer100g: dOpt("polyunsaturated_fat_per_100g"),
            cholesterolPer100g: dOpt("cholesterol_per_100g"),
            sodiumPer100g: dOpt("sodium_per_100g"),
            potassiumPer100g: dOpt("potassium_per_100g")
        )
    }
}
