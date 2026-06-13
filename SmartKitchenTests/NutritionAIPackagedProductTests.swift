import XCTest
@testable import Savoria

struct PackagedProductReference {
    let code: String
    let productName: String
    let brand: String
    let market: String
    let servingGrams: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugar: Double?
    let fiber: Double?
    let saturatedFat: Double?
    /// Open Food Facts exposes sodium per 100g in grams. The app stores mg.
    let sodiumG: Double?

    var citationURL: String {
        "https://world.openfoodfacts.org/product/\(code)"
    }

    @MainActor
    func per100g(appName: String) -> Per100gNutrition {
        Per100gNutrition(
            canonicalName: FoodCache.canonicalize(appName),
            locale: "en_US",
            displayName: "\(brand) \(productName) (OFF \(code))",
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            sugar: sugar,
            addedSugar: nil,
            fiber: fiber,
            saturatedFat: saturatedFat,
            monounsaturatedFat: nil,
            polyunsaturatedFat: nil,
            cholesterol: nil,
            sodium: sodiumG.map { $0 * 1000 },
            potassium: nil,
            emoji: nil,
            servingGrams: servingGrams,
            source: "open_food_facts",
            citationURL: citationURL,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }
}

struct PackagedProductCase {
    let id: String
    let channel: String
    let input: String
    let itemName: String
    let product: PackagedProductReference
    let expected: ExpectedFoodAnalysis
}

@MainActor
final class NutritionAIPackagedProductTests: XCTestCase {
    private let cases: [PackagedProductCase] = [
        PackagedProductCase(
            id: "us-coca-cola-original",
            channel: "Text",
            input: "1 lata Coca-Cola Original Taste",
            itemName: "Coca-Cola Original Taste",
            product: PackagedProductReference(
                code: "5449000000996",
                productName: "Original Taste",
                brand: "Coca-Cola",
                market: "United States",
                servingGrams: 330,
                kcal: 42,
                protein: 0,
                carbs: 10.6,
                fat: 0,
                sugar: 10.6,
                fiber: nil,
                saturatedFat: 0,
                sodiumG: 0
            ),
            expected: ExpectedFoodAnalysis(
                calories: 139, protein: 0, carbs: 35, fat: 0, grams: 330,
                sugar: 35.0, fiber: nil, saturatedFat: 0, sodium: 0, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "us-kelloggs-corn-flakes",
            channel: "Text",
            input: "1 porcao Kellogg's Corn Flakes",
            itemName: "Kellogg's Corn Flakes",
            product: PackagedProductReference(
                code: "038000001277",
                productName: "Corn Flakes Cereal",
                brand: "Kellogg's",
                market: "United States",
                servingGrams: 28,
                kcal: 357,
                protein: 7.14,
                carbs: 85.71,
                fat: 0,
                sugar: 10.71,
                fiber: 3.6,
                saturatedFat: 0,
                sodiumG: 0.714
            ),
            expected: ExpectedFoodAnalysis(
                calories: 100, protein: 2, carbs: 24, fat: 0, grams: 28,
                sugar: 3.0, fiber: 1.0, saturatedFat: 0, sodium: 199.9, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "us-jif-peanut-butter",
            channel: "Gallery/photo equivalent",
            input: "1 porcao Jif Creamy Peanut Butter",
            itemName: "Jif Creamy Peanut Butter",
            product: PackagedProductReference(
                code: "051500255162",
                productName: "Creamy Peanut Butter",
                brand: "Jif",
                market: "United States",
                servingGrams: 33,
                kcal: 575.757575757576,
                protein: 21.2121212121212,
                carbs: 24.2424242424242,
                fat: 48.4848484848485,
                sugar: 9.09090909090909,
                fiber: 6.06060606060606,
                saturatedFat: 10.6060606060606,
                sodiumG: 0.424242424242424
            ),
            expected: ExpectedFoodAnalysis(
                calories: 190, protein: 7, carbs: 8, fat: 16, grams: 33,
                sugar: 3.0, fiber: 2.0, saturatedFat: 3.5, sodium: 140.0, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "us-lays-classic",
            channel: "Camera/photo equivalent",
            input: "1 porcao Lay's Classic",
            itemName: "Lay's Classic",
            product: PackagedProductReference(
                code: "028400310413",
                productName: "Classic",
                brand: "Lay's",
                market: "United States",
                servingGrams: 28,
                kcal: 571.428571428572,
                protein: 7.14285714285714,
                carbs: 53.5714285714286,
                fat: 35.7142857142857,
                sugar: 3.57142857142857,
                fiber: 3.57142857142857,
                saturatedFat: 5.35714285714286,
                sodiumG: 0.607142857142857
            ),
            expected: ExpectedFoodAnalysis(
                calories: 160, protein: 2, carbs: 15, fat: 10, grams: 28,
                sugar: 1.0, fiber: 1.0, saturatedFat: 1.5, sodium: 170.0, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "br-moca-condensed-milk",
            channel: "Nutrition label",
            input: "1 porcao Leite Condensado Moca",
            itemName: "Leite Condensado Moca",
            product: PackagedProductReference(
                code: "7891000100103",
                productName: "Leite Condensado Integral Moca",
                brand: "Nestle Moca",
                market: "Brazil",
                servingGrams: 20,
                kcal: 325,
                protein: 7,
                carbs: 55,
                fat: 8,
                sugar: 55,
                fiber: 0,
                saturatedFat: 5,
                sodiumG: 0
            ),
            expected: ExpectedFoodAnalysis(
                calories: 65, protein: 1, carbs: 11, fat: 2, grams: 20,
                sugar: 11.0, fiber: 0, saturatedFat: 1.0, sodium: 0, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "br-nescau-2",
            channel: "Nutrition label",
            input: "1 porcao Nescau 2.0",
            itemName: "Nescau 2.0",
            product: PackagedProductReference(
                code: "7891000053508",
                productName: "2.0",
                brand: "Nestle Nescau",
                market: "Brazil",
                servingGrams: 20,
                kcal: 365,
                protein: 3,
                carbs: 85,
                fat: 0,
                sugar: 75,
                fiber: 4.5,
                saturatedFat: 0,
                sodiumG: 0.06
            ),
            expected: ExpectedFoodAnalysis(
                calories: 73, protein: 1, carbs: 17, fat: 0, grams: 20,
                sugar: 15.0, fiber: 0.9, saturatedFat: 0, sodium: 12.0, potassium: nil
            )
        ),
        PackagedProductCase(
            id: "br-soda-antarctica",
            channel: "Text",
            input: "1 lata Soda Antarctica",
            itemName: "Soda Antarctica",
            product: PackagedProductReference(
                code: "7891991000833",
                productName: "Refrigerante Soda Limonada Antartica",
                brand: "Soda Antarctica",
                market: "Brazil",
                servingGrams: 350,
                kcal: 20.5714285714286,
                protein: 0,
                carbs: 5.14285714285714,
                fat: 0,
                sugar: 1.42857142857143,
                fiber: nil,
                saturatedFat: 0,
                sodiumG: 0.00828571428571429
            ),
            expected: ExpectedFoodAnalysis(
                calories: 72, protein: 0, carbs: 18, fat: 0, grams: 350,
                sugar: 5.0, fiber: nil, saturatedFat: 0, sodium: 29.0, potassium: nil
            )
        )
    ]

    func testPackagedProductsFromUSAndBrazilMatchOpenFoodFactsLabels() async throws {
        var rows: [PackagedProductReport.Row] = []

        for testCase in cases {
            let service = makeService(for: testCase)
            let analysis = try await service.analyzeText(description: testCase.input)
            rows.append(PackagedProductReport.Row(testCase: testCase, actual: analysis))

            XCTContext.runActivity(named: testCase.id) { _ in
                XCTAssertEqual(analysis.calories, testCase.expected.calories)
                XCTAssertEqual(analysis.protein, testCase.expected.protein)
                XCTAssertEqual(analysis.carbs, testCase.expected.carbs)
                XCTAssertEqual(analysis.fat, testCase.expected.fat)
                XCTAssertEqual(analysis.servingSizeGrams, testCase.expected.grams, accuracy: 0.1)
                assertOptional(analysis.sugarG, testCase.expected.sugar, label: "sugar")
                assertOptional(analysis.fiberG, testCase.expected.fiber, label: "fiber")
                assertOptional(analysis.saturatedFatG, testCase.expected.saturatedFat, label: "sat fat")
                assertOptional(analysis.sodiumMg, testCase.expected.sodium, label: "sodium")
            }
        }

        add(XCTAttachment(string: PackagedProductReport.markdown(rows: rows)))
        XCTAssertEqual(rows.filter(\.passed).count, cases.count)
    }

    private func makeService(for testCase: PackagedProductCase) -> NutritionAIService {
        let item = NutritionItemParser.ParsedItem(name: testCase.itemName, quantity: 1, unit: nil)
        let parser = MockNutritionItemParser(itemsByDescription: [
            testCase.input: [item]
        ])
        let per100g = testCase.product.per100g(appName: testCase.itemName)
        return NutritionAIService(
            ai: MockNutritionAIClient(),
            usda: MockUSDANutritionLookup(foodsByName: [FoodCache.canonicalize(testCase.itemName): per100g]),
            exa: EmptyExaNutritionLookup(),
            parser: parser,
            cache: DisabledFoodCache()
        )
    }

    private func assertOptional(_ actual: Double?, _ expected: Double?, label: String) {
        switch (actual, expected) {
        case let (actual?, expected?):
            XCTAssertEqual(actual, expected, accuracy: 0.1, "\(label) mismatch")
        case (nil, nil):
            break
        default:
            XCTFail("\(label) optionality mismatch: actual=\(String(describing: actual)) expected=\(String(describing: expected))")
        }
    }
}

enum PackagedProductReport {
    struct Row {
        let testCase: PackagedProductCase
        let actual: FoodAnalysis

        var passed: Bool {
            actual.calories == testCase.expected.calories &&
            actual.protein == testCase.expected.protein &&
            actual.carbs == testCase.expected.carbs &&
            actual.fat == testCase.expected.fat
        }
    }

    static func markdown(rows: [Row]) -> String {
        let passed = rows.filter(\.passed).count
        let score = rows.isEmpty ? 0 : Double(passed) / Double(rows.count) * 100
        var lines = [
            "# Nutrition AI Packaged Products Report",
            "",
            "- Reference source: Open Food Facts product labels by barcode.",
            "- Deterministic cases: \(rows.count).",
            "- Reliability score: \(String(format: "%.1f", score))%.",
            "",
            "| Market | Product | Barcode | Expected kcal/P/C/F | Actual kcal/P/C/F | Serving | Status |",
            "| --- | --- | --- | --- | --- | ---: | --- |"
        ]

        for row in rows {
            let expected = row.testCase.expected
            let actual = row.actual
            lines.append("| \(row.testCase.product.market) | \(row.testCase.product.brand) \(row.testCase.product.productName) | \(row.testCase.product.code) | \(expected.calories)/\(expected.protein)/\(expected.carbs)/\(expected.fat) | \(actual.calories)/\(actual.protein)/\(actual.carbs)/\(actual.fat) | \(String(format: "%.1f", actual.servingSizeGrams))g/ml | \(row.passed ? "PASS" : "FAIL") |")
        }

        lines += [
            "",
            "## References",
            "",
            "| Product | URL |",
            "| --- | --- |"
        ]
        for row in rows {
            lines.append("| \(row.testCase.product.brand) \(row.testCase.product.productName) | \(row.testCase.product.citationURL) |")
        }
        return lines.joined(separator: "\n")
    }
}
