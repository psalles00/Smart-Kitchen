import Foundation

@MainActor
protocol NutritionAIClient {
    func sendNutritionChat(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        apiKey: String,
        model: String?,
        acceptLanguage: String?
    ) async throws -> ChatCompletionResponse

    func analyzeNutritionImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String,
        maxTokens: Int,
        acceptLanguage: String?
    ) async throws -> String
}

extension AIService: NutritionAIClient {
    func sendNutritionChat(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        apiKey: String,
        model: String?,
        acceptLanguage: String?
    ) async throws -> ChatCompletionResponse {
        try await sendChat(
            messages: messages,
            tools: tools,
            apiKey: apiKey,
            model: model,
            acceptLanguage: acceptLanguage
        )
    }

    func analyzeNutritionImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String,
        maxTokens: Int,
        acceptLanguage: String?
    ) async throws -> String {
        try await analyzeImage(
            prompt: prompt,
            imageData: imageData,
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            acceptLanguage: acceptLanguage
        )
    }
}

@MainActor
protocol NutritionItemParsing {
    func parse(_ description: String) async throws -> [NutritionItemParser.ParsedItem]
}

extension NutritionItemParser: NutritionItemParsing {}

@MainActor
protocol NutritionUSDALookingUp {
    func fetchPer100g(for names: [String], locale: String) async -> [Per100gNutrition]
}

extension USDANutritionLookup: NutritionUSDALookingUp {}

@MainActor
protocol NutritionExaLookingUp {
    func fetchPer100g(for names: [String], locale: String) async throws -> [Per100gNutrition]
}

extension ExaNutritionLookup: NutritionExaLookingUp {}

@MainActor
protocol NutritionFoodCaching {
    var isEnabled: Bool { get }

    func lookup(canonicalName: String, locale: String) async -> Per100gNutrition?

    @discardableResult
    func upsert(_ food: Per100gNutrition) async throws -> UUID
}

extension FoodCache: NutritionFoodCaching {}
