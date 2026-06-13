import XCTest
@testable import Savoria

@MainActor
final class NutritionAITypeCoverageTests: XCTestCase {
    func testNutritionEntrySheetIdentifiersCoverAllLoggingTypes() {
        let sheets: [(NutritionEntrySheet, String)] = [
            (.manual(), "manual"),
            (.recents, "recents"),
            (.capturePhotoCamera, "capture-photo-camera"),
            (.capturePhotoGallery, "capture-photo-gallery"),
            (.captureLabel, "capture-label"),
            (.captureText(prefillText: nil, autoAnalyze: false), "capture-text"),
            (.captureVoice, "capture-voice")
        ]

        XCTAssertEqual(sheets.map { $0.0.id }, sheets.map(\.1))
        XCTAssertTrue(NutritionEntrySheet.manual().prefersFullScreenPresentation)
        XCTAssertFalse(NutritionEntrySheet.captureText(prefillText: nil, autoAnalyze: false).prefersFullScreenPresentation)
    }

    func testTextAndVoiceTranscriptUseTheSameNutritionPipeline() async throws {
        let input = "150g arroz branco"
        let parser = MockNutritionItemParser(itemsByDescription: [
            input: [
                NutritionItemParser.ParsedItem(name: "arroz branco", quantity: 150, unit: "g")
            ]
        ])
        let rice = NutritionAITestFixtures.rice.per100g(appName: "arroz branco")
        let service = NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [FoodCache.canonicalize("arroz branco"): rice]),
            exa: EmptyExaNutritionLookup(),
            parser: parser,
            cache: DisabledFoodCache()
        )

        let textAnalysis = try await service.analyzeText(description: input)
        let voiceTranscriptAnalysis = try await service.analyzeText(description: input)

        XCTAssertEqual(textAnalysis.calories, 195)
        XCTAssertEqual(voiceTranscriptAnalysis.calories, textAnalysis.calories)
        XCTAssertEqual(voiceTranscriptAnalysis.protein, textAnalysis.protein)
        XCTAssertEqual(voiceTranscriptAnalysis.carbs, textAnalysis.carbs)
        XCTAssertEqual(voiceTranscriptAnalysis.fat, textAnalysis.fat)
    }

    func testTextAnalysisContinuesWhenRemoteFoodCacheIsUnavailable() async throws {
        let input = "150g arroz branco"
        let parser = MockNutritionItemParser(itemsByDescription: [
            input: [
                NutritionItemParser.ParsedItem(name: "arroz branco", quantity: 150, unit: "g")
            ]
        ])
        let rice = NutritionAITestFixtures.rice.per100g(appName: "arroz branco")
        let service = NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [FoodCache.canonicalize("arroz branco"): rice]),
            exa: EmptyExaNutritionLookup(),
            parser: parser,
            cache: FailingWriteFoodCache()
        )

        let analysis = try await service.analyzeText(description: input)

        XCTAssertEqual(analysis.calories, 195)
        XCTAssertEqual(analysis.protein, 4)
        XCTAssertNil(analysis.cachedFoodIDs)
    }

    func testTextAnalysisUsesLocalFallbackWhenAIBackendCannotResolveHost() async throws {
        let service = NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: ThrowingNutritionItemParser(error: URLError(.cannotFindHost)),
            cache: DisabledFoodCache()
        )

        let analysis = try await service.analyzeText(description: "2 ovos com 100g de arroz branco")

        XCTAssertEqual(analysis.name, "2 ovos com 100g de arroz branco")
        XCTAssertEqual(analysis.calories, 271)
        XCTAssertEqual(analysis.protein, 15)
        XCTAssertEqual(analysis.carbs, 29)
        XCTAssertEqual(analysis.fat, 10)
        XCTAssertEqual(analysis.servingSizeGrams, 200)
    }

    func testPackagedDrinkTextUsesLocalFallbackWhenAIBackendCannotResolveHost() async throws {
        let service = NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: ThrowingNutritionItemParser(error: URLError(.cannotFindHost)),
            cache: DisabledFoodCache()
        )

        let analysis = try await service.analyzeText(description: "Coca-Cola 350ml")

        XCTAssertEqual(analysis.name, "coca-cola")
        XCTAssertEqual(analysis.calories, 147)
        XCTAssertEqual(analysis.carbs, 37)
        XCTAssertEqual(analysis.servingSizeGrams, 350)
        XCTAssertEqual(analysis.sugarG ?? -1, 37.1, accuracy: 0.1)
    }

    func testCompositeBreakfastIsResolvedAsSeparateFoodsAndMarkedComposite() async throws {
        let input = "Café com leite e açúcar; 2 fatias de pão de forma com requeijao light"
        let parser = MockNutritionItemParser(itemsByDescription: [
            input: NutritionItemParser.expandedItems(from: [
                NutritionItemParser.ParsedItem(name: input, quantity: nil, unit: nil)
            ])
        ])
        let service = NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: parser,
            cache: DisabledFoodCache()
        )

        let analysis = try await service.analyzeText(description: input)

        XCTAssertEqual(analysis.componentCount, 5)
        XCTAssertEqual(analysis.calories, 234)
        XCTAssertEqual(analysis.protein, 8)
        XCTAssertEqual(analysis.carbs, 32)
        XCTAssertEqual(analysis.fat, 7)
        XCTAssertEqual(analysis.servingSizeGrams, 235)
    }

    func testCameraAndGalleryPhotoContractParsesFoodAnalysis() async throws {
        let ai = MockNutritionAIClient()
        ai.imageContent = """
        {"name":"Prato de salmao","calories":"361","protein":"29","carbs":"45","fat":"6","serving_size_grams":"260","sugar":0.1,"fiber":0.6,"saturated_fat":1.1,"sodium":91.6,"potassium":495}
        """
        let service = NutritionAIService(
            ai: ai,
            usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: MockNutritionItemParser(itemsByDescription: [:]),
            cache: DisabledFoodCache()
        )

        let cameraAnalysis = try await service.analyzeFoodImage(imageData: Data([0xFF, 0xD8, 0xFF]))
        let galleryAnalysis = try await service.analyzeFoodImage(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            description: "Imagem escolhida da galeria"
        )

        XCTAssertEqual(cameraAnalysis.calories, 361)
        XCTAssertEqual(galleryAnalysis.calories, cameraAnalysis.calories)
        XCTAssertEqual(galleryAnalysis.servingSizeGrams, 260)
    }

    func testNutritionLabelContractScalesPer100gToServing() async throws {
        let ai = MockNutritionAIClient()
        ai.imageContent = """
        ```json
        {"name":"Iogurte","calories_per_100g":"80","protein_per_100g":"5","carbs_per_100g":"9","fat_per_100g":"2","serving_size_grams":"170","sugar_per_100g":"8","fiber_per_100g":0}
        ```
        """
        let service = NutritionAIService(
            ai: ai,
            usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: MockNutritionItemParser(itemsByDescription: [:]),
            cache: DisabledFoodCache()
        )

        let label = try await service.analyzeNutritionLabel(imageData: Data([0x01, 0x02]))
        let scaled = label.scaled(to: label.servingSizeGrams ?? 100)

        XCTAssertEqual(label.caloriesPer100g, 80)
        XCTAssertEqual(scaled.calories, 136)
        XCTAssertEqual(scaled.protein, 9)
        XCTAssertEqual(scaled.carbs, 15)
        XCTAssertEqual(scaled.fat, 3)
        XCTAssertEqual(scaled.sugarG ?? -1, 13.6, accuracy: 0.1)
    }

    func testFoodAnalysisParserToleratesMarkdownFencesAndNumericStrings() throws {
        let analysis = try NutritionAIService.parseFoodAnalysis(from: """
        ```json
        {"name":"Banana","calories":"116","protein":"1","carbs":"27","fat":"0","serving_size_grams":"120","sugar":"19.0","fiber":"2.0"}
        ```
        """)

        XCTAssertEqual(analysis.name, "Banana")
        XCTAssertEqual(analysis.calories, 116)
        XCTAssertEqual(analysis.protein, 1)
        XCTAssertEqual(analysis.carbs, 27)
        XCTAssertEqual(analysis.fat, 0)
        XCTAssertEqual(analysis.servingSizeGrams, 120)
        XCTAssertEqual(analysis.sugarG, 19.0)
        XCTAssertEqual(analysis.fiberG, 2.0)
    }
}
