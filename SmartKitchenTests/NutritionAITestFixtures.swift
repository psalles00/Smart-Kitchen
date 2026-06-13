import Foundation
@testable import Savoria

struct USDAReferenceFood {
    let key: String
    let fdcId: Int
    let dataType: String
    let description: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugar: Double?
    let fiber: Double?
    let saturatedFat: Double?
    let sodium: Double?
    let potassium: Double?

    var citationURL: String {
        "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\(fdcId)/nutrients"
    }

    @MainActor
    func per100g(appName: String, servingGrams: Double? = nil) -> Per100gNutrition {
        Per100gNutrition(
            canonicalName: FoodCache.canonicalize(appName),
            locale: "en_US",
            displayName: "\(description) (FDC \(fdcId))",
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
            sodium: sodium,
            potassium: potassium,
            emoji: nil,
            servingGrams: servingGrams,
            source: "usda",
            citationURL: citationURL,
            id: nil,
            upvotes: 0,
            downvotes: 0
        )
    }
}

struct ExpectedFoodAnalysis {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let grams: Double
    let sugar: Double?
    let fiber: Double?
    let saturatedFat: Double?
    let sodium: Double?
    let potassium: Double?
}

struct ReliabilityFoodInput {
    let item: NutritionItemParser.ParsedItem
    let reference: USDAReferenceFood
    let servingGrams: Double?

    init(
        name: String,
        quantity: Double?,
        unit: String?,
        reference: USDAReferenceFood,
        servingGrams: Double? = nil
    ) {
        self.item = NutritionItemParser.ParsedItem(name: name, quantity: quantity, unit: unit)
        self.reference = reference
        self.servingGrams = servingGrams
    }
}

struct NutritionReliabilityCase {
    let id: String
    let title: String
    let cuisine: String
    let channel: String
    let input: String
    let foods: [ReliabilityFoodInput]
    let expected: ExpectedFoodAnalysis
}

enum NutritionAITestFixtures {
    static let banana = USDAReferenceFood(
        key: "banana",
        fdcId: 2709224,
        dataType: "Survey (FNDDS)",
        description: "Banana, raw",
        kcal: 97,
        protein: 0.74,
        carbs: 22.71,
        fat: 0.28,
        sugar: 15.8,
        fiber: 1.7,
        saturatedFat: 0.112,
        sodium: 0,
        potassium: 326
    )

    static let egg = USDAReferenceFood(
        key: "egg",
        fdcId: 173424,
        dataType: "SR Legacy",
        description: "Egg, whole, cooked, hard-boiled",
        kcal: 155,
        protein: 12.6,
        carbs: 1.12,
        fat: 10.6,
        sugar: 1.12,
        fiber: 0,
        saturatedFat: 3.27,
        sodium: 124,
        potassium: 126
    )

    static let rice = USDAReferenceFood(
        key: "rice",
        fdcId: 168878,
        dataType: "SR Legacy",
        description: "Rice, white, long-grain, regular, enriched, cooked",
        kcal: 130,
        protein: 2.69,
        carbs: 28.2,
        fat: 0.28,
        sugar: 0.05,
        fiber: 0.4,
        saturatedFat: 0.077,
        sodium: 1,
        potassium: 35
    )

    static let blackBeans = USDAReferenceFood(
        key: "black-beans",
        fdcId: 173735,
        dataType: "SR Legacy",
        description: "Beans, black, mature seeds, cooked, boiled, without salt",
        kcal: 132,
        protein: 8.86,
        carbs: 23.7,
        fat: 0.54,
        sugar: 0.32,
        fiber: 8.7,
        saturatedFat: 0.139,
        sodium: 1,
        potassium: 355
    )

    static let roastedChicken = USDAReferenceFood(
        key: "roasted-chicken",
        fdcId: 171075,
        dataType: "SR Legacy",
        description: "Chicken, broilers or fryers, breast, meat and skin, cooked, roasted",
        kcal: 197,
        protein: 29.8,
        carbs: 0,
        fat: 7.78,
        sugar: 0,
        fiber: 0,
        saturatedFat: 2.19,
        sodium: 71,
        potassium: 245
    )

    static let pinkSalmon = USDAReferenceFood(
        key: "pink-salmon",
        fdcId: 172001,
        dataType: "SR Legacy",
        description: "Fish, salmon, pink, cooked, dry heat",
        kcal: 153,
        protein: 24.6,
        carbs: 0,
        fat: 5.28,
        sugar: 0,
        fiber: 0,
        saturatedFat: 0.971,
        sodium: 90,
        potassium: 439
    )

    static let tofu = USDAReferenceFood(
        key: "tofu",
        fdcId: 172475,
        dataType: "SR Legacy",
        description: "Tofu, raw, firm, prepared with calcium sulfate",
        kcal: 144,
        protein: 17.3,
        carbs: 2.78,
        fat: 8.72,
        sugar: nil,
        fiber: 2.3,
        saturatedFat: 1.26,
        sodium: 14,
        potassium: 237
    )

    static let lentils = USDAReferenceFood(
        key: "lentils",
        fdcId: 172421,
        dataType: "SR Legacy",
        description: "Lentils, mature seeds, cooked, boiled, without salt",
        kcal: 116,
        protein: 9.02,
        carbs: 20.1,
        fat: 0.38,
        sugar: 1.8,
        fiber: 7.9,
        saturatedFat: 0.053,
        sodium: 2,
        potassium: 369
    )

    static let cornTortilla = USDAReferenceFood(
        key: "corn-tortilla",
        fdcId: 2707823,
        dataType: "Survey (FNDDS)",
        description: "Tortilla, corn",
        kcal: 218,
        protein: 5.7,
        carbs: 44.64,
        fat: 2.85,
        sugar: 0.88,
        fiber: 6.3,
        saturatedFat: 0.453,
        sodium: 45,
        potassium: 186
    )

    static let referenceFoods: [USDAReferenceFood] = [
        banana, egg, rice, blackBeans, roastedChicken,
        pinkSalmon, tofu, lentils, cornTortilla
    ]

    static let reliabilityCases: [NutritionReliabilityCase] = [
        NutritionReliabilityCase(
            id: "single-banana",
            title: "Single banana",
            cuisine: "Whole food",
            channel: "Text",
            input: "1 banana",
            foods: [
                ReliabilityFoodInput(name: "banana", quantity: 1, unit: "un", reference: banana)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 116, protein: 1, carbs: 27, fat: 0, grams: 120,
                sugar: 19.0, fiber: 2.0, saturatedFat: 0.1, sodium: 0, potassium: 391.2
            )
        ),
        NutritionReliabilityCase(
            id: "two-eggs",
            title: "Two boiled eggs",
            cuisine: "Breakfast",
            channel: "Voice transcript",
            input: "2 ovos cozidos",
            foods: [
                ReliabilityFoodInput(name: "ovo", quantity: 2, unit: "un", reference: egg)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 155, protein: 13, carbs: 1, fat: 11, grams: 100,
                sugar: 1.1, fiber: 0, saturatedFat: 3.3, sodium: 124, potassium: 126
            )
        ),
        NutritionReliabilityCase(
            id: "rice-beans",
            title: "Rice and black beans",
            cuisine: "Brazilian",
            channel: "Text",
            input: "150g arroz branco cozido e 100g feijao preto",
            foods: [
                ReliabilityFoodInput(name: "arroz branco cozido", quantity: 150, unit: "g", reference: rice),
                ReliabilityFoodInput(name: "feijao preto", quantity: 100, unit: "g", reference: blackBeans)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 327, protein: 13, carbs: 66, fat: 1, grams: 250,
                sugar: 0.4, fiber: 9.3, saturatedFat: 0.3, sodium: 2.5, potassium: 407.5
            )
        ),
        NutritionReliabilityCase(
            id: "brazilian-plate",
            title: "Rice, beans, roasted chicken",
            cuisine: "Brazilian",
            channel: "Text",
            input: "150g arroz branco, 100g feijao preto e 120g frango assado",
            foods: [
                ReliabilityFoodInput(name: "arroz branco", quantity: 150, unit: "g", reference: rice),
                ReliabilityFoodInput(name: "feijao preto", quantity: 100, unit: "g", reference: blackBeans),
                ReliabilityFoodInput(name: "frango assado", quantity: 120, unit: "g", reference: roastedChicken)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 563, protein: 49, carbs: 66, fat: 10, grams: 370,
                sugar: 0.4, fiber: 9.3, saturatedFat: 2.9, sodium: 87.7, potassium: 701.5
            )
        ),
        NutritionReliabilityCase(
            id: "salmon-rice",
            title: "Salmon and rice",
            cuisine: "Japanese-style",
            channel: "Gallery/photo equivalent",
            input: "160g arroz branco e 100g salmao grelhado",
            foods: [
                ReliabilityFoodInput(name: "arroz branco", quantity: 160, unit: "g", reference: rice),
                ReliabilityFoodInput(name: "salmao grelhado", quantity: 100, unit: "g", reference: pinkSalmon)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 361, protein: 29, carbs: 45, fat: 6, grams: 260,
                sugar: 0.1, fiber: 0.6, saturatedFat: 1.1, sodium: 91.6, potassium: 495
            )
        ),
        NutritionReliabilityCase(
            id: "lentils-rice",
            title: "Lentils and rice",
            cuisine: "Indian-style",
            channel: "Text",
            input: "180g lentilhas cozidas e 120g arroz branco",
            foods: [
                ReliabilityFoodInput(name: "lentilhas cozidas", quantity: 180, unit: "g", reference: lentils),
                ReliabilityFoodInput(name: "arroz branco", quantity: 120, unit: "g", reference: rice)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 365, protein: 19, carbs: 70, fat: 1, grams: 300,
                sugar: 3.3, fiber: 14.7, saturatedFat: 0.2, sodium: 4.8, potassium: 706.2
            )
        ),
        NutritionReliabilityCase(
            id: "tacos",
            title: "Corn tortilla tacos",
            cuisine: "Mexican",
            channel: "Camera/photo equivalent",
            input: "90g tortilla de milho, 120g feijao preto e 100g frango assado",
            foods: [
                ReliabilityFoodInput(name: "tortilla de milho", quantity: 90, unit: "g", reference: cornTortilla),
                ReliabilityFoodInput(name: "feijao preto", quantity: 120, unit: "g", reference: blackBeans),
                ReliabilityFoodInput(name: "frango assado", quantity: 100, unit: "g", reference: roastedChicken)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 552, protein: 46, carbs: 69, fat: 11, grams: 310,
                sugar: 1.2, fiber: 16.1, saturatedFat: 2.8, sodium: 112.7, potassium: 838.4
            )
        ),
        NutritionReliabilityCase(
            id: "vegan-bowl",
            title: "Tofu, lentils, rice",
            cuisine: "Vegetarian",
            channel: "Text",
            input: "150g tofu, 150g lentilhas e 100g arroz branco",
            foods: [
                ReliabilityFoodInput(name: "tofu", quantity: 150, unit: "g", reference: tofu),
                ReliabilityFoodInput(name: "lentilhas", quantity: 150, unit: "g", reference: lentils),
                ReliabilityFoodInput(name: "arroz branco", quantity: 100, unit: "g", reference: rice)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 520, protein: 42, carbs: 63, fat: 14, grams: 400,
                sugar: 2.8, fiber: 15.7, saturatedFat: 2.0, sodium: 25, potassium: 944
            )
        ),
        NutritionReliabilityCase(
            id: "chicken-rice",
            title: "Chicken and rice",
            cuisine: "Fitness",
            channel: "Text",
            input: "200g arroz branco e 180g frango assado",
            foods: [
                ReliabilityFoodInput(name: "arroz branco", quantity: 200, unit: "g", reference: rice),
                ReliabilityFoodInput(name: "frango assado", quantity: 180, unit: "g", reference: roastedChicken)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 615, protein: 59, carbs: 56, fat: 15, grams: 380,
                sugar: 0.1, fiber: 0.8, saturatedFat: 4.1, sodium: 129.8, potassium: 511
            )
        ),
        NutritionReliabilityCase(
            id: "tofu-tortilla",
            title: "Tofu and corn tortilla",
            cuisine: "Vegetarian Mexican-style",
            channel: "Text",
            input: "120g tofu e 60g tortilla de milho",
            foods: [
                ReliabilityFoodInput(name: "tofu", quantity: 120, unit: "g", reference: tofu),
                ReliabilityFoodInput(name: "tortilla de milho", quantity: 60, unit: "g", reference: cornTortilla)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 304, protein: 24, carbs: 30, fat: 12, grams: 180,
                sugar: 0.5, fiber: 6.5, saturatedFat: 1.8, sodium: 43.8, potassium: 396
            )
        ),
        NutritionReliabilityCase(
            id: "eggs-banana",
            title: "Eggs and banana",
            cuisine: "Breakfast",
            channel: "Voice transcript",
            input: "2 ovos cozidos e 1 banana",
            foods: [
                ReliabilityFoodInput(name: "ovo", quantity: 2, unit: "un", reference: egg),
                ReliabilityFoodInput(name: "banana", quantity: 1, unit: "un", reference: banana)
            ],
            expected: ExpectedFoodAnalysis(
                calories: 271, protein: 13, carbs: 28, fat: 11, grams: 220,
                sugar: 20.1, fiber: 2.0, saturatedFat: 3.4, sodium: 124, potassium: 517.2
            )
        )
    ]
}
