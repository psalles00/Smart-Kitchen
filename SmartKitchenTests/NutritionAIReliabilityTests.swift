import XCTest
@testable import Savoria

#if DEBUG && os(iOS)
import StoreKit
import StoreKitTest

@MainActor
final class SavoriaDebugTests: XCTestCase {
    func testStoreKitDecimalParsingWithIsolatedCatalogues() async throws {
        // Diagnostic only: this creates temporary, isolated catalogues and exposes
        // SDK serialization differences. The real catalogue assertion below
        // remains part of the normal suite and must not be weakened.
        guard ProcessInfo.processInfo.environment["SAVORIA_STOREKIT_DECIMAL_PROBE"] == "1" else {
            throw XCTSkip("Set SAVORIA_STOREKIT_DECIMAL_PROBE=1 to investigate StoreKit decimal parsing.")
        }
        let originalURL = try XCTUnwrap(Bundle.main.url(forResource: "Configuration", withExtension: "storekit"))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: originalURL)) as? [String: Any])
        for (locale, separator) in [("en_US", "."), ("pt_BR", ",")] {
            var catalogue = original
            catalogue["identifier"] = UUID().uuidString
            var settings = try XCTUnwrap(catalogue["settings"] as? [String: Any])
            settings["_locale"] = locale
            catalogue["settings"] = settings
            var groups = try XCTUnwrap(catalogue["subscriptionGroups"] as? [[String: Any]])
            var subscriptions = try XCTUnwrap(groups[0]["subscriptions"] as? [[String: Any]])
            let groupID = String(Int.random(in: 30_000_000...39_999_999))
            groups[0]["id"] = groupID
            var productIDs: [String] = []
            for index in subscriptions.indices {
                let id = "com.pedrosalles.smartkitchen.sync.decimal-probe.\(locale).\(index)"
                subscriptions[index]["productID"] = id
                subscriptions[index]["internalID"] = String(Int.random(in: 40_000_000...49_999_999))
                subscriptions[index]["subscriptionGroupID"] = groupID
                subscriptions[index]["displayPrice"] = (index == 0 ? "99" : "49") + separator + "90"
                productIDs.append(id)
            }
            groups[0]["subscriptions"] = subscriptions
            catalogue["subscriptionGroups"] = groups
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("storekit")
            try JSONSerialization.data(withJSONObject: catalogue).write(to: url)
            let session = try SKTestSession(contentsOf: url)
            session.disableDialogs = true
            let products = try await Product.products(for: productIDs)
            let prices = products.map { "\($0.id):\($0.price)" }
            print("STOREKIT_DECIMAL_PROBE locale=\(locale) separator=\(separator) prices=\(prices)")
            for product in products {
                print("STOREKIT_DECIMAL_JSON \(String(decoding: product.jsonRepresentation, as: UTF8.self))")
                print("STOREKIT_DECIMAL_DISPLAY \(product.id) \(product.displayPrice)")
            }
            XCTAssertEqual(products.count, 2)
            XCTAssertEqual(products.first { $0.id == productIDs[0] }?.price, Decimal(string: "99.90"))
            XCTAssertEqual(products.first { $0.id == productIDs[1] }?.price, Decimal(string: "49.90"))
            withExtendedLifetime(session) {}
        }
    }

    func testBrazilSubscriptionCatalogueMatchesAnnualAndMonthlyPlans() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Configuration", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        // Keep the local StoreKit session alive across the asynchronous product lookup.
        defer { withExtendedLifetime(session) {} }
        session.disableDialogs = true
        let previousStorefront = session.storefront
        let previousLocale = session.locale
        defer {
            session.storefront = previousStorefront
            session.locale = previousLocale
        }
        // SKTestSession shares its environment across sessions. This test's
        // Brazilian prices must not depend on another session's region.
        session.storefront = "BRA"
        session.locale = Locale(identifier: "pt_BR")
        XCTAssertEqual(session.storefront, "BRA")
        let products = try await Product.products(for: [SubscriptionManager.annualProductID, SubscriptionManager.monthlyProductID])
        XCTAssertEqual(products.count, 2)
        let annual = try XCTUnwrap(products.first { $0.id == SubscriptionManager.annualProductID })
        let monthly = try XCTUnwrap(products.first { $0.id == SubscriptionManager.monthlyProductID })
        // Compare both Apple APIs against the same local server response. This
        // keeps a decimal failure actionable without changing the expected price.
        let legacy = try await LegacyPriceProbe().load([SubscriptionManager.annualProductID, SubscriptionManager.monthlyProductID])
        for product in [annual, monthly] {
            let raw = String(decoding: product.jsonRepresentation, as: UTF8.self)
            let attachment = XCTAttachment(string: "id=\(product.id)\nStoreKit2=\(product.price)\nStoreKit1=\(String(describing: legacy[product.id]))\ndisplay=\(product.displayPrice)\njson=\(raw)")
            attachment.name = "StoreKit price boundary - \(product.id)"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("STOREKIT_PRICE_BOUNDARY id=\(product.id) sk2=\(product.price) sk1=\(String(describing: legacy[product.id])) display=\(product.displayPrice) json=\(raw)")
        }
        XCTAssertEqual(annual.price, Decimal(string: "99.00"))
        XCTAssertEqual(monthly.price, Decimal(string: "49.00"))
        XCTAssertEqual(annual.displayPrice.filter { !$0.isWhitespace }, "R$99,00")
        XCTAssertEqual(monthly.displayPrice.filter { !$0.isWhitespace }, "R$49,00")
        XCTAssertEqual(annual.priceFormatStyle.currencyCode, "BRL")
        XCTAssertEqual(monthly.priceFormatStyle.currencyCode, "BRL")
        XCTAssertEqual(annual.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(annual.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.value, 1)
    }

    @MainActor
    private final class LegacyPriceProbe: NSObject, SKProductsRequestDelegate {
        private var continuation: CheckedContinuation<[String: Decimal], Error>?
        private var request: SKProductsRequest?

        func load(_ identifiers: Set<String>) async throws -> [String: Decimal] {
            defer { request?.cancel(); request = nil }
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SKProductsRequest(productIdentifiers: identifiers)
                self.request = request
                request.delegate = self
                request.start()
            }
        }

        nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
            let prices = Dictionary(uniqueKeysWithValues: response.products.map {
                ($0.productIdentifier, $0.price.decimalValue)
            })
            Task { @MainActor in
                continuation?.resume(returning: prices)
                continuation = nil
            }
        }

        nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
            Task { @MainActor in
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }

    func testSimulatedPlansPersistLocallyWithoutChangingEntitlement() {
        let defaults = UserDefaults(suiteName: "SavoriaDebugTests.\(UUID().uuidString)")!
        let manager = SubscriptionManager(defaults: defaults, observesTransactions: false)
        XCTAssertEqual(manager.debugMode, .appStore)
        manager.setDebugMode(.premium)
        XCTAssertTrue(manager.isSubscribed)
        XCTAssertFalse(manager.storeIsSubscribed)
        XCTAssertNil(manager.activeProductID)
        XCTAssertNil(manager.expirationDate)
        let reopened = SubscriptionManager(defaults: defaults, observesTransactions: false)
        XCTAssertEqual(reopened.debugMode, .premium)
        reopened.setDebugMode(.basic)
        XCTAssertFalse(reopened.isSubscribed)
        reopened.setDebugMode(.appStore)
        XCTAssertEqual(reopened.isSubscribed, reopened.storeIsSubscribed)
    }

    func testBuiltInCategoriesAndMarketSectionsAreLocalizedInEveryLanguage() throws {
        let categoryNames = Set(CategoryType.allCases.flatMap { DataSeeder.defaultDefinitions(for: $0).map(\.name) })
        let sectionNames = Set(CategoryDatabase.shared.allCategories.map(\.marketSection))
        for language in AppLanguage.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.bundleLocalizationIdentifier, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for name in categoryNames.union(sectionNames) {
                let translated = bundle.localizedString(forKey: name, value: "__MISSING__", table: nil)
                XCTAssertNotEqual(translated, "__MISSING__", "Missing \(language.rawValue) translation for \(name)")
            }
            let other = try XCTUnwrap(DataSeeder.pantryCategoryDefinitions.first { $0.name == "Outros" })
            let expected: [AppLanguage: String] = [.ptBR: "Outros", .en: "Other", .es: "Otros", .fr: "Autres", .de: "Sonstige", .it: "Altri", .ja: "その他"]
            XCTAssertEqual(other.displayName(localization: AppLocalization(language: language)), expected[language])
            XCTAssertEqual(other.name, "Outros", "The stored category name must not change")
        }
        XCTAssertEqual(CategoryMutationService.localizedDisplayName(for: "Categoria personalizada 983", type: .utensil), "Categoria personalizada 983")
        XCTAssertEqual(CategoryDatabase.shared.marketSection(for: "Categoria personalizada 983"), AppLocalization.current().builtInLabel("Outros"))
    }

    func testSimulatedCountersPreserveActualUsageAndDoNotCallAI() {
        let defaults = UserDefaults(suiteName: "SavoriaDebugTests.\(UUID().uuidString)")!
        let manager = SubscriptionManager(defaults: defaults, observesTransactions: false)
        let gate = FeatureGate(defaults: defaults)
        gate.subscriptionManager = manager
        manager.setDebugMode(.basic)
        gate.consume(.nutritionAI)
        XCTAssertEqual(gate.usage(of: .nutritionAI), 1)
        let baseline = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("featureGate.") }
        gate.setDebugUsageMode(.exhausted)
        for feature in FeatureGate.Feature.allCases { XCTAssertFalse(gate.canUse(feature)) }
        manager.setDebugMode(.premium)
        for feature in FeatureGate.Feature.allCases { XCTAssertTrue(gate.canUse(feature)) }
        gate.consume(.nutritionAI)
        XCTAssertEqual(gate.usage(of: .nutritionAI), 2)
        manager.setDebugMode(.basic)
        gate.setDebugUsageMode(.available)
        gate.consume(.nutritionAI)
        gate.consume(.nutritionAI)
        XCTAssertFalse(gate.canUse(.nutritionAI))
        gate.setDebugUsageMode(.actual)
        XCTAssertEqual(gate.usage(of: .nutritionAI), 1)
        XCTAssertEqual(defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("featureGate.") } as NSDictionary, baseline as NSDictionary)
        XCTAssertFalse(gate.canShareWithFamily)
        manager.setDebugMode(.premium)
        XCTAssertTrue(gate.canShareWithFamily)
    }
}
#endif

@MainActor
final class NutritionAIReliabilityTests: XCTestCase {
    func testUSDAReferenceMealsStayInsideExactTolerance() async throws {
        let cases = NutritionAITestFixtures.reliabilityCases
        var reportRows: [NutritionAIReport.Row] = []

        for testCase in cases {
            let service = makeService(for: testCase)
            let analysis = try await service.analyzeText(description: testCase.input)
            let row = NutritionAIReport.Row(testCase: testCase, actual: analysis)
            reportRows.append(row)

            XCTContext.runActivity(named: testCase.title) { _ in
                assertAnalysis(analysis, matches: testCase.expected, id: testCase.id)
            }
        }

        let markdown = NutritionAIReport.markdown(rows: reportRows)
        add(XCTAttachment(string: markdown))
        try NutritionAIReport.writeIfRequested(markdown)

        let passed = reportRows.filter(\.passed).count
        XCTAssertEqual(passed, cases.count, "Nutrition AI reliability score dropped below 100%.")
    }

    private func makeService(for testCase: NutritionReliabilityCase) -> NutritionAIService {
        let parser = MockNutritionItemParser(itemsByDescription: [
            testCase.input: testCase.foods.map(\.item)
        ])

        let foodsByName = Dictionary(uniqueKeysWithValues: testCase.foods.map { input in
            (
                FoodCache.canonicalize(input.item.name),
                input.reference.per100g(appName: input.item.name, servingGrams: input.servingGrams)
            )
        })

        return NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: foodsByName),
            exa: EmptyExaNutritionLookup(),
            parser: parser,
            cache: DisabledFoodCache()
        )
    }

    private func assertAnalysis(
        _ analysis: FoodAnalysis,
        matches expected: ExpectedFoodAnalysis,
        id: String
    ) {
        XCTAssertEqual(analysis.calories, expected.calories, "kcal mismatch for \(id)")
        XCTAssertEqual(analysis.protein, expected.protein, "protein mismatch for \(id)")
        XCTAssertEqual(analysis.carbs, expected.carbs, "carbs mismatch for \(id)")
        XCTAssertEqual(analysis.fat, expected.fat, "fat mismatch for \(id)")
        XCTAssertEqual(analysis.servingSizeGrams, expected.grams, accuracy: 0.1, "grams mismatch for \(id)")
        assertOptional(analysis.sugarG, expected.sugar, accuracy: 0.1, label: "sugar", id: id)
        assertOptional(analysis.fiberG, expected.fiber, accuracy: 0.1, label: "fiber", id: id)
        assertOptional(analysis.saturatedFatG, expected.saturatedFat, accuracy: 0.1, label: "saturated fat", id: id)
        assertOptional(analysis.sodiumMg, expected.sodium, accuracy: 0.1, label: "sodium", id: id)
        assertOptional(analysis.potassiumMg, expected.potassium, accuracy: 0.1, label: "potassium", id: id)
    }

    private func assertOptional(
        _ actual: Double?,
        _ expected: Double?,
        accuracy: Double,
        label: String,
        id: String
    ) {
        switch (actual, expected) {
        case let (actual?, expected?):
            XCTAssertEqual(actual, expected, accuracy: accuracy, "\(label) mismatch for \(id)")
        case (nil, nil):
            break
        default:
            XCTFail("\(label) optionality mismatch for \(id): actual=\(String(describing: actual)) expected=\(String(describing: expected))")
        }
    }
}

enum NutritionAIReport {
    struct Row {
        let testCase: NutritionReliabilityCase
        let actual: FoodAnalysis

        var passed: Bool {
            actual.calories == testCase.expected.calories &&
            actual.protein == testCase.expected.protein &&
            actual.carbs == testCase.expected.carbs &&
            actual.fat == testCase.expected.fat &&
            abs(actual.servingSizeGrams - testCase.expected.grams) <= 0.1
        }
    }

    static func markdown(rows: [Row]) -> String {
        let passed = rows.filter(\.passed).count
        let score = rows.isEmpty ? 0 : (Double(passed) / Double(rows.count)) * 100
        var lines: [String] = [
            "# Nutrition AI Reliability Report",
            "",
            "- Reference source: USDA FoodData Central",
            "- Deterministic cases: \(rows.count)",
            "- Reliability score: \(String(format: "%.1f", score))%",
            "- Accuracy rule: exact rounded kcal/protein/carbs/fat and +/-0.1g or mg for tracked micros.",
            "",
            "## Results",
            "",
            "| Case | Cuisine | Channel | Expected kcal/P/C/F | Actual kcal/P/C/F | Grams | Status |",
            "| --- | --- | --- | --- | --- | ---: | --- |"
        ]

        for row in rows {
            let expected = row.testCase.expected
            let actual = row.actual
            lines.append(
                "| \(row.testCase.title) | \(row.testCase.cuisine) | \(row.testCase.channel) | \(expected.calories)/\(expected.protein)/\(expected.carbs)/\(expected.fat) | \(actual.calories)/\(actual.protein)/\(actual.carbs)/\(actual.fat) | \(String(format: "%.1f", actual.servingSizeGrams)) | \(row.passed ? "PASS" : "FAIL") |"
            )
        }

        lines += [
            "",
            "## USDA References",
            "",
            "| Food | FDC ID | Data type | kcal | Protein | Carbs | Fat | URL |",
            "| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |"
        ]

        for food in NutritionAITestFixtures.referenceFoods {
            lines.append(
                "| \(food.description) | \(food.fdcId) | \(food.dataType) | \(food.kcal) | \(food.protein) | \(food.carbs) | \(food.fat) | \(food.citationURL) |"
            )
        }

        return lines.joined(separator: "\n")
    }

    static func writeIfRequested(_ markdown: String) throws {
        guard let path = ProcessInfo.processInfo.environment["NUTRITION_AI_REPORT_PATH"],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class AssistantSuggestionTests: XCTestCase {
    func testFoodDescriptionIsNotAQuestionAndQuantityPromotesFoodLogging() {
        let ranker = AssistantSuggestionRanker(defaults: isolatedDefaults())
        let query = "suco de limao com 6cs de acucar"
        XCTAssertFalse(AssistantSuggestionRanker.isQuestion(query))
        XCTAssertEqual(ranker.orderedIDs(query: query).first, "register-food-text")
        XCTAssertEqual(ranker.orderedIDs(query: "como preparar suco de limao?").first, "ask-assistant")
        XCTAssertEqual(ranker.orderedIDs(query: "comprar 2kg de arroz").first, "add-grocery")
        XCTAssertEqual(ranker.orderedIDs(query: "receita de bolo de limao").first, "create-recipe")
    }

    func testSelectionsLearnKeywordsFrequencyAndPersistAcrossLaunches() {
        let defaults = isolatedDefaults()
        let ranker = AssistantSuggestionRanker(defaults: defaults)
        for _ in 0..<8 { ranker.record(actionID: "register-food-text", query: "banana") }
        XCTAssertEqual(ranker.orderedIDs(query: "banana").first, "register-food-text")
        let reloaded = AssistantSuggestionRanker(defaults: defaults)
        XCTAssertEqual(reloaded.orderedIDs(query: "banana").first, "register-food-text")
        // A learned preference must not overpower an explicit shopping request.
        XCTAssertEqual(reloaded.orderedIDs(query: "comprar banana").first, "add-grocery")
        XCTAssertEqual(Set(reloaded.orderedIDs(query: "banana")).count, 5)
    }

    func testLongVisibleLabelIsBoundedWithoutChangingActionPayload() {
        let query = String(repeating: "limão 🍋 ", count: 30)
        let item = CommandBarHelpers.orderedActions(query: query, isQuestion: false)[0]
        let visible = CommandBarHelpers.limitedSuggestionText(query, limit: 40)
        XCTAssertLessThanOrEqual(visible.count, 40)
        XCTAssertTrue(visible.hasSuffix("..."))
        XCTAssertEqual(CommandBarHelpers.limitedSuggestionText("banana", limit: 40), "banana")
        XCTAssertEqual(item.title, query)
        var payload: String?
        item.perform(query) { action in
            if case .addPantryItem(let prefill) = action { payload = prefill }
            if case .registerFood(let prefill) = action { payload = prefill }
            if case .askAssistant(let prefill) = action { payload = prefill }
        }
        XCTAssertEqual(payload, query)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "Savoria.tests.suggestions." + UUID().uuidString)!
    }
}

@MainActor
final class NutritionHouseholdMeasureTests: XCTestCase {
    func testExactLemonJuiceRequestPreservesDrinkAndSixTablespoonsWhenModelIsWrong() async throws {
        let input = "suco de limao com 6cs de acucar"
        let service = NutritionAIService(
            ai: MockNutritionAIClient(), usda: MockUSDANutritionLookup(foodsByName: [:]),
            exa: EmptyExaNutritionLookup(),
            parser: MockNutritionItemParser(itemsByDescription: [input: [
                .init(name: "6cs de acucar", quantity: 5, unit: "g")
            ]]), cache: DisabledFoodCache()
        )
        let result = try await service.analyzeText(description: input)
        XCTAssertEqual(result.name, input)
        XCTAssertEqual(result.componentCount, 2)
        XCTAssertEqual(result.addedSugarG, 90)
        XCTAssertEqual(result.servingSizeGrams, 290)
        XCTAssertEqual(result.calories, 393)
        XCTAssertFalse(result.reviewNotes.isEmpty)
    }

    func testAbbreviatedMeasuresAreEquivalentToWrittenMeasuresAndRemainDecimalSafe() {
        for (short, full) in [("cs", "colheres de sopa"), ("cc", "colheres de cha"), ("c.s.", "colheres de sopa"), ("tbsp", "colheres de sopa"), ("tsp", "colheres de cha")] {
            let abbreviated = LocalNutritionFallback.analyzeText("suco de limao com 1,5\(short) de acucar")
            let written = LocalNutritionFallback.analyzeText("suco de limao com 1,5 \(full) de acucar")
            XCTAssertNotNil(abbreviated, short)
            XCTAssertNotNil(written, full)
            XCTAssertEqual(abbreviated?.calories, written?.calories, short)
            XCTAssertEqual(abbreviated?.servingSizeGrams, written?.servingSizeGrams, short)
        }
    }

    func testExplicitJuiceVolumeDoesNotLeakToSugar() {
        let parsed = NutritionItemParser.expandedItems(from: [.init(name: "300ml suco de limao com 6cs de acucar", quantity: nil, unit: nil)])
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].name, "suco de limao")
        XCTAssertEqual(parsed[0].quantity, 300)
        XCTAssertEqual(parsed[0].unit, "ml")
        XCTAssertEqual(parsed[1].name, "acucar")
        XCTAssertEqual(parsed[1].quantity, 6)
        XCTAssertEqual(parsed[1].unit, "colher de sopa")
    }

    func testLocalFallbackRejectsPartialMealRatherThanReturningOnlySugar() {
        XCTAssertNil(LocalNutritionFallback.analyzeText("alimento desconhecido com 6cs de acucar"))
    }

    func testIncompleteRemoteResolutionDoesNotReturnPartialNutrition() async throws {
        let input = "alimento desconhecido com 6cs de acucar"
        let ai = MockNutritionAIClient()
        ai.chatContent = """
        {"name":"Refeição completa","calories":450,"protein":10,"carbs":90,"fat":6,"serving_size_grams":300}
        """
        let service = NutritionAIService(ai: ai, usda: MockUSDANutritionLookup(foodsByName: [:]), exa: EmptyExaNutritionLookup(),
            parser: MockNutritionItemParser(itemsByDescription: [input: [.init(name: "alimento desconhecido", quantity: nil, unit: nil), .init(name: "acucar", quantity: 6, unit: "colher de sopa")]]), cache: DisabledFoodCache())
        let result = try await service.analyzeText(description: input)
        // Missing components require a full-request fallback, not sugar-only calories.
        XCTAssertEqual(result.calories, 450)
        XCTAssertEqual(result.name, "Refeição completa")
    }
}
