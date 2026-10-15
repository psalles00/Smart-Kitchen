import Foundation
import SwiftData
import XCTest
@testable import Savoria

@MainActor
final class RecipeIdeaRequestTests: XCTestCase {
    private let original = "Tenho arroz, ovos e tomate. Quero jantar em até 20 minutos para uma pessoa, sem leite. Não registre nem altere dados."

    func testConversationSurvivesReopeningStoreWithAutosaveDisabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Chat.store"), cloudKitDatabase: .none)
        let conversationID: UUID
        let messageID: UUID
        let content = "**Mingau**\n**Ingredientes**\n- 0.25 xícara de Aveia\n- 0.125 xícara de Leite\n- 1.75 g de Canela"
        do {
            let container = try ModelContainer(for: ChatConversation.self, ChatMessage.self, configurations: configuration)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let conversation = ChatConversation()
            context.insert(conversation)
            conversationID = conversation.id
            try ChatConversation.persist(ChatMessage(role: .user, content: "Receita de teste", conversationId: conversationID), in: context)
            let response = ChatMessage(role: .assistant, content: content, conversationId: conversationID)
            messageID = response.id
            try ChatConversation.persist(response, in: context)
            XCTAssertFalse(context.hasChanges)
        }
        let reopened = try ModelContainer(for: ChatConversation.self, ChatMessage.self, configurations: configuration)
        let context = ModelContext(reopened)
        let conversations = try context.fetch(FetchDescriptor<ChatConversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, conversationID)
        XCTAssertEqual(conversations.first?.title, "Receita de teste")
        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        XCTAssertEqual(messages.count, 2)
        let response = try XCTUnwrap(messages.first { $0.id == messageID })
        XCTAssertEqual(response.conversationId, conversationID)
        XCTAssertEqual(response.content, content)
    }

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

    func testOpeningRecipeAndImportEditorsPreservesFractionalAmounts() {
        let section = RecipeIngredientSection(title: "Mistura")
        for quantity in [0.25, 0.125, 1.75, 0.000001, 1e20] {
            for sectionID in [nil, section.id] {
                let ingredient = RecipeIngredient(name: "Aveia", quantity: quantity, unit: "xic", sectionID: sectionID)
                let rows = [RecipeIngredientEditorItem].fromRecipe(sections: [section], ingredients: [ingredient])
                let row = rows.first { !$0.isSection }
                XCTAssertEqual(row.flatMap { Double($0.quantity) }, quantity)
                XCTAssertEqual(row?.existingIngredientID, ingredient.id)
                XCTAssertEqual(row?.unit, "xic")
            }
            let draft = IngredientDraft(name: "Aveia", quantity: quantity, unit: "xic")
            let imported = [RecipeIngredientEditorItem].fromDrafts(sections: [], ingredients: [draft])
            XCTAssertEqual(imported.first.flatMap { Double($0.quantity) }, quantity)
        }
        XCTAssertEqual(RecipeIngredientEditorItem.quantityText(nil), "")
        XCTAssertEqual(RecipeIngredientEditorItem.quantityText(-1.25), "-1.25")
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

@MainActor
final class RecipeIdeasPantryModeTests: XCTestCase {
    func testFreeModeResolvesDescriptiveIngredientsWithoutWeakeningPantryChecks() async {
        for strict in [false, true] {
            let backend = RecipeIdeasFixtureBackend(
                ideas: [("Salada de atum", "atum"), ("Frango grelhado", "frango"), ("Ingrediente ausente", "sal"), ("Ambíguo", "frango")],
                ingredients: ["Salada de atum": ["atum em lata", "alface"],
                              "Frango grelhado": ["peito de frango", "limão"],
                              "Ingrediente ausente": ["salmão", "limão"],
                              "Ambíguo": ["peito de frango", "coxa de frango"]])
            let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
            let ideas = await generator.generate(pantryItems: ["atum", "frango", "alface", "limão"], occasion: nil,
                                                 refinement: nil, customQuery: nil, language: .ptBR, filterByPantry: strict)
            XCTAssertEqual(Set(ideas.map(\.mainIngredient)), strict ? [] : ["atum em lata", "peito de frango"])
        }
    }

    func testRejectsSingleIngredientFillerAndUnlistedSecondaryIngredient() async {
        let backend = RecipeIdeasFixtureBackend(
            ideas: [("Tomate picado", "Tomate"), ("Omelete com tomate", "Ovos"), ("Omelete com óleo", "Ovos")],
            ingredients: ["Tomate picado": ["Tomate"], "Omelete com tomate": ["Ovos", "Tomate"], "Omelete com óleo": ["Ovos", "Óleo"]])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        let ideas = await generator.generate(pantryItems: ["Ovos", "Tomate"], occasion: nil, refinement: nil, customQuery: nil, language: .ptBR)
        XCTAssertEqual(ideas.map(\.title), ["Omelete com tomate"])
        XCTAssertEqual(ideas.first?.ingredientNames, ["Ovos", "Tomate"])
    }

    func testOlderIdeaCardsDecodeWithoutPlannedIngredients() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"Omelete\",\"mainIngredient\":\"Ovos\"}"
        let idea = try JSONDecoder().decode(RecipeQuickIdea.self, from: Data(json.utf8))
        XCTAssertEqual(idea.id, id)
        XCTAssertEqual(idea.title, "Omelete")
        XCTAssertNil(idea.ingredientNames)
        XCTAssertNil(idea.precookedIngredientNames)
    }

    func testPreparedStatesNeedExplicitEvidenceAndRejectNegations() {
        for name in ["Arroz cozido", "Batata cozida", "Cooked rice", "Riz cuit", "Gekochter Reis", "Patata cocida", "Riso cotto", "調理済みご飯"] {
            XCTAssertTrue(RecipeQuickIdeasGenerator.isAlreadyCookedName(name), name)
        }
        for name in ["Arroz", "Feijão", "Raw rice", "Uncooked rice", "Arroz não cozido", "Riz non cuit", "Nicht gekochter Reis", "Patata no cocida", "Riso non cotto", "未調理の米"] {
            XCTAssertFalse(RecipeQuickIdeasGenerator.isAlreadyCookedName(name), name)
        }
    }

    func testDoesNotAssumeRawBeansAreAlreadyCooked() async {
        for prepared in [false, true] {
            let rice = prepared ? "Arroz cozido" : "Arroz"
            let beans = prepared ? "Feijão cozido" : "Feijão"
            let backend = RecipeIdeasFixtureBackend(ideas: [("Arroz com feijão", rice)],
                                                   ingredients: ["Arroz com feijão": [rice, beans]],
                                                   precooked: ["Arroz com feijão": [rice, beans]])
            let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
            let ideas = await generator.generate(pantryItems: [rice, beans], occasion: nil, refinement: nil,
                                                 customQuery: "Jantar em 20 minutos para uma pessoa", language: .ptBR)
            XCTAssertEqual(ideas.count, prepared ? 1 : 0)
        }
    }

    func testStrictRequestSendsIngredientEnumAndKnownTimeAndServingsInSchema() async throws {
        let backend = RecipeIdeasFixtureBackend(ideas: [("Omelete", "Ovos")])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        _ = await generator.generate(pantryItems: ["Ovos", "Leite integral"], occasion: nil, refinement: nil,
                                     customQuery: "Sem leite, 20 minutos para uma pessoa", language: .ptBR)
        let body = try XCTUnwrap(backend.bodies.first)
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let settings = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(settings["strict"] as? Bool, true)
        let schema = try XCTUnwrap(settings["schema"] as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        XCTAssertEqual(definitions["ingredientName"]?["enum"] as? [String], ["Ovos"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        let idea = try XCTUnwrap(properties["ideas"]?["items"] as? [String: Any])
        let fields = try XCTUnwrap(idea["properties"] as? [String: [String: Any]])
        XCTAssertEqual(fields["totalMinutes"]?["maximum"] as? Int, 20)
        XCTAssertEqual(fields["servings"]?["enum"] as? [Int], [1])
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
    }

    func testUnrestrictedEmptyPantryStillGeneratesIdeasWithActualIngredients() async throws {
        let backend = RecipeIdeasFixtureBackend(ideas: [("Risoto de cogumelos", "Cogumelos"), ("Sopa de abóbora", "Abóbora")], ingredients: ["Risoto de cogumelos": ["Cogumelos", "Arroz"], "Sopa de abóbora": ["Abóbora", "Água"]])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        let ideas = await generator.generate(pantryItems: [], occasion: nil, refinement: nil, customQuery: "Quero ideias novas", language: .ptBR, filterByPantry: false)
        XCTAssertEqual(Set(ideas.map(\.mainIngredient)), ["Cogumelos", "Abóbora"])
        XCTAssertEqual(backend.bodies.count, 1)
        let system = try XCTUnwrap(backend.messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("not requirements"))
        XCTAssertTrue(system.contains("Pode incluir ingredientes de fora"))
        XCTAssertFalse(system.contains("Every recipe must use ONLY"))
    }

    func testStrictEmptyPantryDoesNotDispatchAndCannotInventAvailability() async {
        let backend = RecipeIdeasFixtureBackend(ideas: [("Omelete", "Ovos")])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        let ideas = await generator.generate(pantryItems: [], occasion: nil, refinement: nil, customQuery: nil, language: .ptBR)
        XCTAssertTrue(ideas.isEmpty)
        XCTAssertTrue(backend.bodies.isEmpty)
    }

    func testStrictPantryRejectsUnavailableIconIngredientAndPreservesDairyExclusion() async throws {
        let backend = RecipeIdeasFixtureBackend(ideas: [("Omelete simples", "Ovos"), ("Frango grelhado", "Frango"), ("Omelete com queijo", "Ovos"), ("Omelete sem manteiga", "Ovos")])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        let ideas = await generator.generate(pantryItems: ["Ovos", "Leite integral"], occasion: nil, refinement: nil, customQuery: "Sem leite, em 20 minutos para uma pessoa", language: .ptBR)
        XCTAssertEqual(Set(ideas.map(\.title)), ["Omelete simples", "Omelete sem manteiga"])
        XCTAssertTrue(ideas.allSatisfy { $0.mainIngredient == "Ovos" })
        let user = try XCTUnwrap(backend.messages.last?["content"] as? String)
        XCTAssertFalse(user.contains("Leite integral"))
        let system = try XCTUnwrap(backend.messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Tempo total máximo: 20"))
        XCTAssertTrue(system.contains("Número exato de porções: 1"))
    }

    func testTopSuggestionsVaryIngredientsBeforeRepeatingPopularIngredient() async {
        let backend = RecipeIdeasFixtureBackend(ideas: [("Omelete A", "Ovos"), ("Omelete B", "Ovos"), ("Omelete C", "Ovos"), ("Salada", "Tomate"), ("Tapioca", "Goma de tapioca")], ingredients: ["Omelete A": ["Ovos", "Tomate"], "Omelete B": ["Ovos", "Tomate"], "Omelete C": ["Ovos", "Tomate"], "Salada": ["Tomate", "Ovos"], "Tapioca": ["Goma de tapioca", "Ovos"]])
        let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
        let ideas = await generator.generate(pantryItems: ["Ovos", "Tomate", "Goma de tapioca"], occasion: nil, refinement: nil, customQuery: nil, language: .ptBR, limit: 3)
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(Set(ideas.map(\.mainIngredient)).count, 3)
    }

    func testIngredientModesSurviveResultReopenAndLegacyResultsKeepStrictBehavior() throws {
        let payload = InlineChatView.ResultsPayload(ideas: [], quickIdeas: [.init(title: "Risoto", mainIngredient: "Cogumelos")], localRecipeIDs: [], occasionRaw: nil, refinement: nil, customQuery: "Jantar", filterByPantry: false)
        let reopened = InlineChatView.ResultsPayload.decode(payload.encoded())
        XCTAssertEqual(reopened.filterByPantry, false)
        XCTAssertEqual(reopened.quickIdeas, payload.quickIdeas)
        let unknownMode = InlineChatView.ResultsPayload.decode(payload.encoded().replacingOccurrences(of: "false", with: "\"future-mode\""))
        XCTAssertEqual(unknownMode.quickIdeas, payload.quickIdeas)
        XCTAssertTrue(unknownMode.filterByPantry ?? true)
        let legacy = InlineChatView.ResultsPayload.decode(#"{"ideas":[],"quickIdeas":[],"localRecipeIDs":[]}"#)
        XCTAssertTrue(legacy.filterByPantry ?? true)
        let request = RecipeIdeaRequest(occasion: nil, refinement: nil, customQuery: nil)
        XCTAssertTrue(request.ingredientPrompt(pantryItems: [], filterByPantry: true).contains("APENAS"))
        XCTAssertFalse(request.ingredientPrompt(pantryItems: [], filterByPantry: false).contains("APENAS"))
    }

    func testEverySupportedLanguageReachesProviderPromptInBothModes() async throws {
        for language in AppLanguage.allCases {
            for strict in [true, false] {
                let backend = RecipeIdeasFixtureBackend(ideas: [("Omelete", "Ovos")])
                let generator = RecipeQuickIdeasGenerator(aiService: AIService(supabase: backend))
                let ideas = await generator.generate(pantryItems: ["Ovos"], occasion: nil, refinement: nil, customQuery: nil, language: language, filterByPantry: strict)
                XCTAssertEqual(ideas.count, 1)
                let system = try XCTUnwrap(backend.messages.first?["content"] as? String)
                XCTAssertTrue(system.contains(language.aiModelLanguageName))
                XCTAssertEqual(backend.acceptLanguage, AppLocalization(language: language).acceptLanguageHeader)
            }
        }
    }
}

@MainActor
private final class RecipeIdeasFixtureBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    let ideas: [(String, String)]
    var bodies: [[String: Any]] = []
    let ingredients: [String: [String]]
    let precooked: [String: [String]]
    var acceptLanguage: String?
    var messages: [[String: Any]] { bodies.last?["messages"] as? [[String: Any]] ?? [] }
    init(ideas: [(String, String)], ingredients: [String: [String]] = [:], precooked: [String: [String]] = [:]) {
        self.ideas = ideas; self.ingredients = ingredients; self.precooked = precooked
    }
    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        bodies.append(body)
        self.acceptLanguage = acceptLanguage
        let content = try JSONSerialization.data(withJSONObject: ["ideas": ideas.map { ["title": $0.0, "mainIngredient": $0.1, "ingredients": ingredients[$0.0] ?? [$0.1], "totalMinutes": 15, "servings": 1, "requiresPrecooked": precooked[$0.0] ?? []] as [String: Any] }])
        return try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": String(decoding: content, as: UTF8.self)]]]])
    }
    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        throw URLError(.unsupportedURL)
    }
}

/// Opt-in native provider smoke test. Normal test runs never dispatch paid calls.
@MainActor
final class RecipeIdeasLiveProviderTests: XCTestCase {
    func testNativeProviderHonorsBothPantryModesWithinReservedBudget() async throws {
        guard ProcessInfo.processInfo.environment["SAVORIA_LIVE_RECIPE_TESTS"] == "1" else {
            throw XCTSkip("Live provider validation requires an explicitly prepared budget reservation.")
        }
        continueAfterFailure = false
        let backend = try ReservedRecipeValidationBackend()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        DirectChatURLProtocol.requestHandler = { _ in throw URLError(.unsupportedURL) }
        let service = AIService(supabase: backend, urlSession: URLSession(configuration: configuration),
                                openRouterKey: { "" }, prefersDirectOpenRouter: { false })
        let generator = RecipeQuickIdeasGenerator(aiService: service)
        let pantry = ["Ovos", "Arroz", "Tomate", "Cenoura", "Feijão"]
        let strict = await generator.generate(pantryItems: pantry, occasion: .jantar, refinement: nil,
                                             customQuery: "Jantar sem leite em 20 minutos para uma pessoa", language: .ptBR, limit: 6)
        try backend.saveIdeas(strict, name: "strict")
        XCTAssertGreaterThanOrEqual(strict.count, 2)
        XCTAssertGreaterThanOrEqual(Set(strict.map(\.mainIngredient)).count, 2)
        XCTAssertTrue(strict.allSatisfy { Set($0.ingredientNames ?? []).count >= 2 })
        XCTAssertTrue(strict.allSatisfy { pantry.contains($0.mainIngredient) })
        guard strict.count >= 2, Set(strict.map(\.mainIngredient)).count >= 2,
              strict.allSatisfy({ Set($0.ingredientNames ?? []).count >= 2 && pantry.contains($0.mainIngredient) }) else { return }
        let unrestricted = await generator.generate(pantryItems: [], occasion: .jantar, refinement: nil,
                                                    customQuery: "Quero quatro jantares diferentes, sem depender de uma despensa", language: .ptBR,
                                                    filterByPantry: false, limit: 4)
        try backend.saveIdeas(unrestricted, name: "unrestricted")
        XCTAssertEqual(unrestricted.count, 4)
        XCTAssertEqual(Set(unrestricted.map(\.title)).count, 4)
        XCTAssertTrue(unrestricted.allSatisfy { !$0.mainIngredient.isEmpty })
        XCTAssertEqual(backend.calls, 2)
    }
}

@MainActor
private final class ReservedRecipeValidationBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    private(set) var calls = 0
    private let actual = SupabaseClient()
    private let directory: URL
    private var receipt: [String: Any]
    private let ceiling: Double

    init() throws {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveRecipeValidation", isDirectory: true)
        receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("reservation.json"))) as? [String: Any] ?? [:]
        ceiling = receipt["reservedUSD"] as? Double ?? 0
        guard receipt["purpose"] as? String == "recipe-discovery-validation",
              receipt["maximumCalls"] as? Int == 2,
              ceiling.isFinite, ceiling > 0, ceiling <= 0.20,
              receipt["status"] as? String == "prepared" else { throw URLError(.userAuthenticationRequired) }
        receipt["requests"] = [[String: Any]]()
        receipt["status"] = "started"
        try persist()
    }

    private func persist() throws {
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("reservation.json"), options: .atomic)
    }

    func saveIdeas(_ ideas: [RecipeQuickIdea], name: String) throws {
        try JSONEncoder().encode(ideas).write(to: directory.appendingPathComponent("\(name)-\((receipt["id"] as? String ?? "unknown").filter { $0.isLetter || $0.isNumber || $0 == "-" })-ideas.json"), options: .atomic)
    }

    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        try await invokeFunctionData(name: name, body: JSONSerialization.data(withJSONObject: body),
                                     contentType: "application/json", acceptLanguage: acceptLanguage)
    }

    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        guard name == "openai-chat", contentType == "application/json", body.count <= 65536, calls < 2 else {
            throw URLError(.unsupportedURL)
        }
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let maxTokens = request?["max_tokens"] as? Int ?? 8192
        guard (1...8192).contains(maxTokens) else { throw URLError(.unsupportedURL) }
        let reserve = 3 * ((Double(body.count) + 4096) * 0.0000004 + Double(maxTokens) * 0.0000016)
        var requests = receipt["requests"] as? [[String: Any]] ?? []
        let used = requests.reduce(0.0) { $0 + ($1["reserved_usd"] as? Double ?? 0.20) }
        guard used + reserve <= ceiling else { throw URLError(.dataLengthExceedsMaximum) }
        let index = requests.count
        requests.append(["function": name, "request_body_bytes": body.count, "reserved_usd": reserve, "status": "dispatched-reserved"])
        receipt["requests"] = requests
        try persist() // Reservation is durable before the real network dispatch.
        calls += 1
        let response = try await actual.invokeFunctionData(name: name, body: body, contentType: contentType, acceptLanguage: acceptLanguage)
        let json = try JSONSerialization.jsonObject(with: response) as? [String: Any] ?? [:]
        requests[index]["status"] = "response-reserve-retained"
        requests[index]["usage"] = json["usage"]
        requests[index]["model"] = json["model"]
        requests[index]["response_id"] = json["id"]
        let messages = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        requests[index]["response_content"] = messages?["content"]
        receipt["requests"] = requests
        receipt["status"] = calls == 2 ? "completed" : "in-progress"
        try persist()
        return response
    }
}
