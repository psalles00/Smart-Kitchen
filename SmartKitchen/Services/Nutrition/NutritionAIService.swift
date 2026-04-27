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
                return "Chave de API não configurada. Adicione sua chave OpenAI em Ajustes."
            case .emptyResponse:
                return "Resposta vazia da IA."
            case .invalidJSON(let msg):
                return "Não foi possível entender a resposta da IA: \(msg)"
            }
        }
    }

    private let ai = AIService()
    private let openRouter = OpenRouterClient()
    private let visionModel = "gpt-4o-mini"
    private let textModel = "gpt-4.1-mini"

    // MARK: - Public API

    func analyzeText(description: String) async throws -> FoodAnalysis {
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

    private func callText(prompt: String) async throws -> String {
        // AIService already routes OpenAI → OpenRouter on failure; just delegate.
        let apiKey = APIConfig.openAIAPIKey
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        let response = try await ai.sendChat(messages: messages, apiKey: apiKey)
        guard let content = response.content, !content.isEmpty else {
            throw NutritionAIError.emptyResponse
        }
        _ = textModel
        return content
    }

    private func callVision(prompt: String, imageData: Data) async throws -> String {
        let openAIKey = APIConfig.openAIAPIKey

        // 1. Try OpenAI vision (gpt-4o-mini).
        if !openAIKey.isEmpty {
            do {
                return try await callVisionOpenAI(prompt: prompt, imageData: imageData, apiKey: openAIKey)
            } catch {
                LLMLog.error("OpenAI vision failed, falling back to OpenRouter: \(error.localizedDescription)")
            }
        } else {
            LLMLog.info("OpenAI key empty; trying OpenRouter for vision directly")
        }

        // 2. Fallback: OpenRouter (multimodal model).
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else { throw NutritionAIError.missingAPIKey }
        LLMLog.info("Routing vision to OpenRouter (\(OpenRouterModel.default))")
        return try await openRouter.analyzeImage(prompt: prompt, imageData: imageData, apiKey: orKey)
    }

    private func callVisionOpenAI(prompt: String, imageData: Data, apiKey: String) async throws -> String {
        let b64 = imageData.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(b64)"

        let body: [String: Any] = [
            "model": visionModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": dataURL]],
                    ["type": "text", "text": prompt]
                ]
            ]],
            "max_tokens": 1024
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else {
            throw NutritionAIError.emptyResponse
        }
        return content
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
