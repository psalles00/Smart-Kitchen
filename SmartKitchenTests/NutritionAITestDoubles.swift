import Foundation
@testable import Savoria

@MainActor
final class MockNutritionAIClient: NutritionAIClient {
    var chatContent: String?
    var toolCalls: [ToolCallRequest] = []
    var imageContent: String = "{}"

    func sendNutritionChat(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        apiKey: String,
        model: String?,
        acceptLanguage: String?
    ) async throws -> ChatCompletionResponse {
        ChatCompletionResponse(content: chatContent, toolCalls: toolCalls)
    }

    func analyzeNutritionImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String,
        maxTokens: Int,
        acceptLanguage: String?
    ) async throws -> String {
        imageContent
    }
}

@MainActor
final class MockNutritionItemParser: NutritionItemParsing {
    private let itemsByDescription: [String: [NutritionItemParser.ParsedItem]]

    init(itemsByDescription: [String: [NutritionItemParser.ParsedItem]]) {
        self.itemsByDescription = itemsByDescription
    }

    func parse(_ description: String) async throws -> [NutritionItemParser.ParsedItem] {
        itemsByDescription[description] ?? []
    }
}

@MainActor
final class ThrowingNutritionItemParser: NutritionItemParsing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func parse(_ description: String) async throws -> [NutritionItemParser.ParsedItem] {
        throw error
    }
}

@MainActor
final class MockUSDANutritionLookup: NutritionUSDALookingUp {
    private let foodsByName: [String: Per100gNutrition]

    init(foodsByName: [String: Per100gNutrition]) {
        self.foodsByName = foodsByName
    }

    func fetchPer100g(for names: [String], locale: String) async -> [Per100gNutrition] {
        names.map { name in
            foodsByName[FoodCache.canonicalize(name)] ?? Self.emptyResult(name: name, locale: locale)
        }
    }

    private static func emptyResult(name: String, locale: String) -> Per100gNutrition {
        Per100gNutrition(
            canonicalName: FoodCache.canonicalize(name),
            locale: locale,
            displayName: name,
            kcal: nil,
            protein: nil,
            carbs: nil,
            fat: nil,
            sugar: nil,
            addedSugar: nil,
            fiber: nil,
            saturatedFat: nil,
            monounsaturatedFat: nil,
            polyunsaturatedFat: nil,
            cholesterol: nil,
            sodium: nil,
            potassium: nil,
            emoji: nil,
            servingGrams: nil,
            source: "usda",
            citationURL: nil,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }
}

@MainActor
final class EmptyExaNutritionLookup: NutritionExaLookingUp {
    func fetchPer100g(for names: [String], locale: String) async throws -> [Per100gNutrition] {
        names.map { name in
            Per100gNutrition(
                canonicalName: FoodCache.canonicalize(name),
                locale: locale,
                displayName: name,
                kcal: nil,
                protein: nil,
                carbs: nil,
                fat: nil,
                sugar: nil,
                addedSugar: nil,
                fiber: nil,
                saturatedFat: nil,
                monounsaturatedFat: nil,
                polyunsaturatedFat: nil,
                cholesterol: nil,
                sodium: nil,
                potassium: nil,
                emoji: nil,
                servingGrams: nil,
                source: "exa",
                citationURL: nil,
                id: nil,
                upvotes: 0,
                downvotes: 0
            )
        }
    }
}

@MainActor
final class DisabledFoodCache: NutritionFoodCaching {
    var isEnabled: Bool { false }

    func lookup(canonicalName: String, locale: String) async -> Per100gNutrition? {
        nil
    }

    func upsert(_ food: Per100gNutrition) async throws -> UUID {
        UUID()
    }
}

@MainActor
final class FailingWriteFoodCache: NutritionFoodCaching {
    var isEnabled: Bool { true }

    func lookup(canonicalName: String, locale: String) async -> Per100gNutrition? {
        nil
    }

    func upsert(_ food: Per100gNutrition) async throws -> UUID {
        throw URLError(.cannotFindHost)
    }
}
