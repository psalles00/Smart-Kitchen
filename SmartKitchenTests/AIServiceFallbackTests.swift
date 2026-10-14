import Foundation
import XCTest
@testable import Savoria

@MainActor
final class RecipeIdeaRequestTests: XCTestCase {
    private let original = "Tenho arroz, ovos e tomate. Quero jantar em até 20 minutos para uma pessoa, sem leite. Não registre nem altere dados."

    func testOriginalContextSurvivesExpansionAndStructuring() {
        let request = RecipeIdeaRequest(occasion: "Jantar", refinement: "Usar arroz", customQuery: original)
        XCTAssertTrue(request.prompt.contains(original))
        XCTAssertTrue(request.prompt.contains("Usar arroz"))
        XCTAssertEqual(request.maximumMinutes, 20)
        XCTAssertEqual(RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: "jantar em até20minutos").maximumMinutes, 20)
        XCTAssertEqual(request.requestedServings, 1)
        let prompt = RecipeStructurer.userPrompt(text: "receita da web", hints: .init(requestContext: request.prompt))
        XCTAssertTrue(prompt.contains(original))
    }

    func testRejectsDairyEvenWhenPantryOrSourceContainsIt() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        for ingredient in ["Leite integral", "Queijo", "Manteiga", "Leite de coco e leite integral"] {
            XCTAssertFalse(request.accepts(ingredients: ["Ovos", ingredient], totalMinutes: 15, servings: 1), ingredient)
        }
        XCTAssertTrue(request.accepts(ingredients: ["Arroz", "Ovos", "Tomate"], totalMinutes: 20, servings: 1))
        XCTAssertTrue(request.accepts(ingredients: ["Leite de coco"], totalMinutes: 15, servings: 1))
    }

    func testMinuteLimitRequiresKnownTotalAndServingCount() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        XCTAssertFalse(request.accepts(ingredients: ["Ovos"], totalMinutes: nil, servings: 1))
        XCTAssertFalse(request.accepts(ingredients: ["Ovos"], totalMinutes: 21, servings: 1))
        XCTAssertFalse(request.accepts(ingredients: ["Ovos"], totalMinutes: 20, servings: 2))
        XCTAssertFalse(request.accepts(ingredients: ["Ovos"], totalMinutes: 20, servings: nil))
        var draft = RecipeDraft()
        draft.ingredients = [.init(name: "Ovos")]
        draft.prepTime = 5; draft.cookTime = 16
        draft.prepTimeConfidence = .high; draft.cookTimeConfidence = .high
        draft.servingsConfidence = .high
        XCTAssertFalse(request.accepts(draft))
        draft.cookTime = 15
        XCTAssertTrue(request.accepts(draft))
        draft.servingsConfidence = .low
        XCTAssertFalse(request.accepts(draft), "Default one serving is not an explicitly supplied serving count")
        draft.servingsConfidence = .high; draft.cookTimeConfidence = .low
        XCTAssertFalse(request.accepts(draft), "Missing cook time is not a known total")
        draft.cookTimeConfidence = .high; draft.prepTime = Int.max; draft.cookTime = 1
        XCTAssertFalse(request.accepts(draft), "Invalid time totals must not overflow")
    }

    func testExcludedPantryFoodIsRemovedBeforeGenerationWithoutChangingOriginalInventory() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        let pantry = ["Arroz", "Leite integral", "Ovos", "Tomate", "Leite de coco", "Manteiga"]
        XCTAssertEqual(request.allowedPantryItems(pantry), ["Arroz", "Ovos", "Tomate", "Leite de coco"])
        XCTAssertEqual(pantry.count, 6)
        XCTAssertEqual(RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: nil).allowedPantryItems(pantry), pantry)
    }

    func testRejectsDairyAddedOnlyInInstructionsForQuickAndWebRecipes() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        XCTAssertFalse(request.accepts(ingredients: ["Arroz", "Ovos"], steps: ["Adicione leite para cremosidade."], totalMinutes: 15, servings: 1))
        XCTAssertTrue(request.accepts(ingredients: ["Arroz", "Ovos"], steps: ["Sirva o arroz com os ovos."], totalMinutes: 15, servings: 1))
        var draft = RecipeStructurer.parse(dict: ["prep_time_minutes": 5, "cook_time_minutes": 10, "servings": 1])
        draft.ingredients = [.init(name: "Ovos")]
        draft.steps = [.init(order: 1, instruction: "Bata os ovos com leite.")]
        XCTAssertFalse(request.accepts(draft))
        draft.steps = [.init(order: 1, instruction: "Bata os ovos.")]
        XCTAssertTrue(request.accepts(draft))
    }

    func testRecipeStructuringPromotesAdaptationConstraintsToBothModelInstructions() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        let instructions = RecipeStructurer.instructions(hints: .init(requestContext: request.prompt))
        XCTAssertTrue(instructions.contains(original))
        XCTAssertTrue(instructions.contains("Não use leite animal"))
        XCTAssertTrue(instructions.contains("Tempo total máximo: 20"))
        XCTAssertTrue(instructions.contains("Número exato de porções: 1"))
        XCTAssertTrue(instructions.contains("Adapte a receita da fonte"))
        XCTAssertEqual(RecipeStructurer.instructions(hints: .init()), RecipeStructurer.systemPrompt)
    }

    func testStepExclusionsDoNotRejectTheValidNativeRecipe() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        for step in ["Refogue o tomate por 2 minutos sem óleo ou manteiga.",
                     "Frite os ovos mexidos sem gordura ou manteiga.",
                     "Cook without fat or butter.", "Cocine sin grasa o mantequilla.",
                     "Cuire sans matière grasse ou beurre.",
                     "Ohne Fett oder Butter kochen.", "Cuocere senza grassi o burro.",
                     "Não use manteiga nem leite.", "Cook without butter or milk.",
                     "Sem óleo, manteiga ou leite, cozinhe os ovos."] {
            XCTAssertTrue(request.accepts(ingredients: ["Arroz", "Ovos", "Tomate"], steps: [step], totalMinutes: 15, servings: 1), step)
        }
    }

    func testQuotedWebRecipeMetadataConfirmsTimeAndServings() throws {
        let payload = #"{"name":"Arroz com ovo e tomate","prep_time_minutes":"5","cook_time_minutes":"15","servings":"1","ingredients":[{"name":"Arroz"},{"name":"Ovos"},{"name":"Tomate"}],"steps":[{"instruction":"Misture e cozinhe os ovos."}]}"#
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let draft = RecipeStructurer.parse(dict: dict)
        XCTAssertEqual(draft.prepTime, 5)
        XCTAssertEqual(draft.cookTime, 15)
        XCTAssertEqual(draft.servings, 1)
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        XCTAssertTrue(request.accepts(draft))
    }

    func testAmbiguousWebMetadataCannotConfirmRestrictions() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        let invalidValues: [Any] = ["20 min", "1-2", "5.5", "NaN", "999999999999999999999999999", true, 5.5, Double.infinity, NSNull(), -1]
        for invalid in invalidValues {
            let draft = RecipeStructurer.parse(dict: ["prep_time_minutes": invalid, "cook_time_minutes": invalid, "servings": invalid])
            XCTAssertFalse(request.accepts(draft), "Invalid metadata: \(invalid)")
        }
        let known = RecipeStructurer.parse(dict: ["prep_time_minutes": 0, "cook_time_minutes": 15, "servings": 1])
        XCTAssertTrue(request.accepts(known), "JSON integer one must not be confused with a boolean")
        let explicitZero = RecipeStructurer.parse(dict: ["prep_time_minutes": "0", "cook_time_minutes": "15", "servings": "1"])
        XCTAssertTrue(request.accepts(explicitZero))
        let unknown = RecipeStructurer.parse(dict: [:])
        XCTAssertFalse(request.accepts(unknown))
    }

    func testJSONIntegerMetadataIsPreservedWithoutFloatingPointRounding() throws {
        let payload = #"{"prep_time_minutes":9007199254740993,"cook_time_minutes":0,"servings":1}"#
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let draft = RecipeStructurer.parse(dict: dict)
        XCTAssertEqual(draft.prepTime, 9_007_199_254_740_993)
        XCTAssertEqual(draft.cookTime, 0)
        XCTAssertEqual(draft.servings, 1)
    }

    func testRoundedJSONFractionCannotConfirmRecipeMetadata() throws {
        let payload = #"{"prep_time_minutes":1.0000000000000001,"cook_time_minutes":15,"servings":1.0000000000000001}"#
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let draft = RecipeStructurer.parse(dict: dict)
        XCTAssertEqual(draft.prepTimeConfidence, .low)
        XCTAssertEqual(draft.servingsConfidence, .low)
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        XCTAssertFalse(request.accepts(draft))
    }

    func testStructuredIngredientAmountSurvivesCardReload() throws {
        for quantity in [-0.0, 0.0, 0.25, 0.125, 1.75, 200.0, 0.000001, 1e20] {
            let encoded = try XCTUnwrap(AssistantRecipeIngredientAmount.encode(quantity))
            let amount = AssistantRecipeIngredientAmount.decode(encoded + "Xícara")
            let draft = RecipeStructurer.parse(dict: ["ingredients": [["name": "Arroz", "quantity": try XCTUnwrap(amount.quantity), "unit": try XCTUnwrap(amount.unit)]]])
            XCTAssertEqual(draft.ingredients.first?.quantity, quantity)
            XCTAssertEqual(draft.ingredients.first?.unit, "Xícara")
        }
        XCTAssertEqual(AssistantRecipeIngredientAmount.decode("0,25 xícara").quantity, 0.25)
        XCTAssertEqual(AssistantRecipeIngredientAmount.encode(2), "2")
        XCTAssertEqual(AssistantRecipeIngredientAmount.encode(-0.0), "0")
    }

    func testInvalidCardAmountNeverBecomesAQuantity() {
        XCTAssertNil(AssistantRecipeIngredientAmount.encode(.nan))
        XCTAssertNil(AssistantRecipeIngredientAmount.encode(.infinity))
        XCTAssertNil(AssistantRecipeIngredientAmount.encode(-1))
        XCTAssertNil(AssistantRecipeIngredientAmount.decode("1e999 g").quantity)
        XCTAssertNil(AssistantRecipeIngredientAmount.decode("NaN g").quantity)
    }

    func testStepNegationNeverHidesAnotherDairyAddition() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        for step in ["Refogue sem manteiga; adicione leite.", "Não use leite, adicione manteiga.",
                     "Sem gordura ou manteiga, adicione leite.", "Without fat or butter, add cream.",
                     "Sem óleo, use manteiga.", "Without butter, add milk.",
                     "Refogue o tomate sem pele e adicione queijo."] {
            XCTAssertFalse(request.accepts(ingredients: ["Arroz", "Ovos"], steps: [step], totalMinutes: 15, servings: 1), step)
        }
        XCTAssertFalse(request.accepts(ingredients: ["Leite"], steps: ["Não use manteiga."], totalMinutes: 15, servings: 1))
    }

    func testCanonicalCardMetadataAndEnglishRequest() {
        let content = "**Omelete**\nTempo total: 15 min\nPorções: 1\n**Ingredientes**\n- 2 un de Ovos"
        XCTAssertEqual(RecipeIdeaRequest.totalMinutes(in: content), 15)
        XCTAssertEqual(RecipeIdeaRequest.servings(in: content), 1)
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: "Dinner in 20 minutes for one person, dairy-free")
        XCTAssertTrue(request.excludesMilk)
        XCTAssertEqual(request.requestedServings, 1)
        XCTAssertFalse(request.accepts(ingredients: ["Milk"], totalMinutes: 15, servings: 1))
        XCTAssertTrue(request.accepts(ingredients: ["Oat milk"], totalMinutes: 15, servings: 1))
        for text in ["no dairy", "without dairy"] {
            let exclusion = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: text)
            XCTAssertFalse(exclusion.accepts(ingredients: ["Milk"], totalMinutes: nil, servings: nil), text)
        }
    }

    func testServerMappingDistinguishesMissingMetadataFromExplicitZeroAndOne() {
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        let missing = RecipeStructurer.parse(dict: ["prep_time_minutes": 15])
        XCTAssertEqual(missing.cookTimeConfidence, .low)
        XCTAssertEqual(missing.servingsConfidence, .low)
        XCTAssertFalse(request.accepts(missing))
        let null = RecipeStructurer.parse(dict: ["prep_time_minutes": 15, "cook_time_minutes": NSNull(), "servings": NSNull()])
        XCTAssertFalse(request.accepts(null))
        let explicit = RecipeStructurer.parse(dict: ["prep_time_minutes": 15, "cook_time_minutes": 0, "servings": 1])
        XCTAssertEqual(explicit.cookTimeConfidence, .high)
        XCTAssertEqual(explicit.servingsConfidence, .high)
        XCTAssertTrue(request.accepts(explicit))
    }

    #if canImport(FoundationModels)
    func testAppleMappingKeepsUnknownMetadataOptional() {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: original)
        var generated = RecipeStructurer.GeneratedRecipe(name: "Omelete", description: "", category: "Jantar", difficulty: "Fácil",
                                                       prepTimeMinutes: 15, cookTimeMinutes: nil, servings: nil, calories: 0,
                                                       requiredUtensils: [], ingredients: [], steps: [])
        let missing = RecipeStructurer.draft(from: generated, hints: .init())
        XCTAssertEqual(missing.cookTimeConfidence, .low)
        XCTAssertEqual(missing.servingsConfidence, .low)
        XCTAssertFalse(request.accepts(missing))
        generated.cookTimeMinutes = 0; generated.servings = 1
        let explicit = RecipeStructurer.draft(from: generated, hints: .init())
        XCTAssertTrue(request.accepts(explicit))
    }
    #endif

    func testUnconstrainedLegacyIdeasStillAcceptExistingRecipe() {
        let request = RecipeIdeaRequest(occasion: "Jantar", refinement: nil, customQuery: nil)
        XCTAssertTrue(request.accepts(ingredients: ["Leite"], totalMinutes: nil, servings: nil))
    }
}

@MainActor
final class AIServiceFallbackTests: XCTestCase {
    func testConfiguredBackendWinsOverAvailableDirectRouterKey() async throws {
        let backend = AvailableChatBackend()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        var directCalls = 0
        DirectChatURLProtocol.requestHandler = { _ in
            directCalls += 1
            throw URLError(.badURL)
        }
        let service = AIService(supabase: backend,
                                urlSession: URLSession(configuration: configuration),
                                openRouterKey: { "unused-local-router-key" })
        let response = try await service.sendNutritionChat(
            messages: [["role": "user", "content": "arroz"]],
            tools: nil, apiKey: "", model: "gpt-4.1-mini", acceptLanguage: "pt-BR")
        XCTAssertFalse(APIConfig.usesLocalOpenRouter)
        XCTAssertEqual(response.content, "backend-ok")
        XCTAssertEqual(backend.calls, 1)
        XCTAssertEqual(directCalls, 0)
    }
    func testExplicitOpenRouterSkipsUnavailableBackendAndOpenAI() async throws {
        try await assertOpenRouterRouting(preferred: true)
    }

    func testBackendFailureFallsBackToOpenRouterWithNoOpenAIKey() async throws {
        try await assertOpenRouterRouting(preferred: false)
    }

    private func assertOpenRouterRouting(preferred: Bool) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        DirectChatURLProtocol.requestHandler = { request in
            capturedRequest = request
            if let data = request.httpBody {
                capturedBody = data
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var bytes = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                capturedBody = data
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!,
                    Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8))
        }
        let backend = CountingUnavailableBackend()
        let service = AIService(supabase: backend,
                                urlSession: URLSession(configuration: configuration),
                                openRouterKey: { "test-router-key" },
                                prefersDirectOpenRouter: { preferred })
        let response = try await service.sendNutritionChat(messages: [["role": "user", "content": "refeição de teste"]],
                                                           tools: nil, apiKey: "", model: "gpt-4.1-mini", acceptLanguage: "pt-BR")
        XCTAssertEqual(response.content, "ok")
        XCTAssertEqual(backend.calls, preferred ? 0 : 1)
        XCTAssertEqual(capturedRequest?.url?.host, "openrouter.ai")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-router-key")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, OpenRouterModel.default)
    }
    override func tearDown() {
        super.tearDown()
        DirectChatURLProtocol.requestHandler = nil
    }

    func testChatFallsBackToDirectOpenAIWhenSupabaseHostCannotBeFound() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var capturedRequest: URLRequest?
        DirectChatURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {"choices":[{"message":{"content":"{\\"name\\":\\"Banana\\",\\"calories\\":105,\\"protein\\":1,\\"carbs\\":27,\\"fat\\":0,\\"serving_size_grams\\":118}"}}]}
            """.data(using: .utf8)!
            return (response, body)
        }

        let service = AIService(
            supabase: CannotFindHostSupabaseFunctionInvoker(),
            urlSession: session
        )

        let response = try await service.sendNutritionChat(
            messages: [["role": "user", "content": "banana"]],
            tools: nil,
            apiKey: "test-openai-key",
            model: "gpt-4.1-mini",
            acceptLanguage: "pt-BR"
        )

        XCTAssertEqual(response.content, "{\"name\":\"Banana\",\"calories\":105,\"protein\":1,\"carbs\":27,\"fat\":0,\"serving_size_grams\":118}")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-openai-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept-Language"), "pt-BR")
    }
}

@MainActor
private final class AvailableChatBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    private(set) var calls = 0
    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        calls += 1
        return Data("{\"choices\":[{\"message\":{\"content\":\"backend-ok\"}}]}".utf8)
    }
    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        throw URLError(.unsupportedURL)
    }
}

@MainActor
private final class CountingUnavailableBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    private(set) var calls = 0
    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        calls += 1
        throw URLError(.cannotFindHost)
    }
    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        calls += 1
        throw URLError(.cannotFindHost)
    }
}

@MainActor
private final class CannotFindHostSupabaseFunctionInvoker: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }

    func invokeFunctionData(
        name: String,
        body: [String: Any],
        acceptLanguage: String?
    ) async throws -> Data {
        throw URLError(.cannotFindHost)
    }

    func invokeFunctionData(
        name: String,
        body: Data,
        contentType: String,
        acceptLanguage: String?
    ) async throws -> Data {
        throw URLError(.cannotFindHost)
    }
}

private final class DirectChatURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
