import Foundation

/// Static, hand-curated catalog of universal items the user can pick from
/// during the onboarding capture step. Names use `String(localized:)` so the
/// xcstrings build phase picks them up; icons reference the bundled
/// `images-128/` directory through `IconResolver.image(forFilename:)`.
enum OnboardingCatalog {

    struct ItemTemplate: Identifiable, Hashable {
        /// Stable identifier (slug). Used as the selection key in
        /// `OnboardingState`.
        let id: String
        /// Localized display name shown on the card.
        let displayName: String
        /// Filename inside `icons/images-128/`.
        let iconFileName: String
        /// Category name matching the seeded `Category` definitions.
        let category: String
    }

    // MARK: - Pantry catalog

    static let pantryItems: [ItemTemplate] = [
        .init(id: "rice",       displayName: String(localized: "Arroz", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "rice.png",         category: "Grãos, Massas e Cereais"),
        .init(id: "oats",       displayName: String(localized: "Aveia", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "oats.png",         category: "Grãos, Massas e Cereais"),
        .init(id: "pasta",      displayName: String(localized: "Macarrão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "pasta.png",        category: "Grãos, Massas e Cereais"),
        .init(id: "olive-oil",  displayName: String(localized: "Azeite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "olive-oil.png",    category: "Temperos e Condimentos"),
        .init(id: "salt",       displayName: String(localized: "Sal", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "salt.png",         category: "Temperos e Condimentos"),
        .init(id: "sugar",      displayName: String(localized: "Açúcar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "sugar.png",        category: "Temperos e Condimentos"),
        .init(id: "coffee",     displayName: String(localized: "Café", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "coffee.png",       category: "Bebidas"),
        .init(id: "milk",       displayName: String(localized: "Leite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "milk.png",         category: "Laticínios e Ovos"),
        .init(id: "egg",        displayName: String(localized: "Ovos", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "egg.png",          category: "Laticínios e Ovos"),
        .init(id: "cheese",     displayName: String(localized: "Queijo", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "cheese.png",       category: "Laticínios e Ovos"),
        .init(id: "butter",     displayName: String(localized: "Manteiga", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "butter.png",       category: "Laticínios e Ovos"),
        .init(id: "flour",      displayName: String(localized: "Farinha", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),      iconFileName: "flour.png",        category: "Grãos, Massas e Cereais"),
        .init(id: "bread",      displayName: String(localized: "Pão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "bread-white.png",  category: "Padaria"),
        .init(id: "garlic",     displayName: String(localized: "Alho", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "garlic.png",       category: "Verduras e Legumes"),
        .init(id: "onion",      displayName: String(localized: "Cebola", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "onion.png",        category: "Verduras e Legumes"),
        .init(id: "potato",     displayName: String(localized: "Batata", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "potato.png",       category: "Verduras e Legumes"),
        .init(id: "honey",      displayName: String(localized: "Mel", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "honey.png",        category: "Doces e Sobremesas"),
        .init(id: "tea",        displayName: String(localized: "Chá", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "tea.png",          category: "Bebidas"),
        .init(id: "lentils",    displayName: String(localized: "Lentilha", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "lentils.png",      category: "Grãos, Massas e Cereais"),
        .init(id: "beans",      displayName: String(localized: "Feijão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "soya-beans.png",   category: "Grãos, Massas e Cereais"),
        .init(id: "quinoa",     displayName: String(localized: "Quinoa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "quinoa.png",       category: "Grãos, Massas e Cereais"),
        .init(id: "tofu",       displayName: String(localized: "Tofu", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "tofu.png",         category: "Outros"),
        .init(id: "ketchup",    displayName: String(localized: "Ketchup", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),      iconFileName: "ketchup.png",      category: "Temperos e Condimentos"),
        .init(id: "mustard",    displayName: String(localized: "Mostarda", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "mustard.png",      category: "Temperos e Condimentos"),
        .init(id: "mayonnaise", displayName: String(localized: "Maionese", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "mayonnaise.png",   category: "Temperos e Condimentos"),
    ]

    // MARK: - Grocery catalog (different staples for the first shopping list)

    static let groceryItems: [ItemTemplate] = [
        .init(id: "tomato",     displayName: String(localized: "Tomate", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "tomato.png",       category: "Verduras e Legumes"),
        .init(id: "lettuce",    displayName: String(localized: "Alface", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "lettuce.png",      category: "Verduras e Legumes"),
        .init(id: "carrot",     displayName: String(localized: "Cenoura", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),      iconFileName: "carrot.png",       category: "Verduras e Legumes"),
        .init(id: "broccoli",   displayName: String(localized: "Brócolis", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "broccoli.png",     category: "Verduras e Legumes"),
        .init(id: "bread",      displayName: String(localized: "Pão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "bread-white.png",  category: "Padaria"),
        .init(id: "banana",     displayName: String(localized: "Banana", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "banana.png",       category: "Frutas"),
        .init(id: "apple",      displayName: String(localized: "Maçã", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "apple.png",        category: "Frutas"),
        .init(id: "egg",        displayName: String(localized: "Ovos", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "egg.png",          category: "Laticínios e Ovos"),
        .init(id: "milk",       displayName: String(localized: "Leite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "milk.png",         category: "Laticínios e Ovos"),
        .init(id: "rice",       displayName: String(localized: "Arroz", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "rice.png",         category: "Grãos, Massas e Cereais"),
        .init(id: "chicken",    displayName: String(localized: "Frango", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "chicken-raw.png",  category: "Carnes e Aves"),
        .init(id: "beef",       displayName: String(localized: "Carne bovina", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), iconFileName: "beef.png",         category: "Carnes e Aves"),
        .init(id: "salmon",     displayName: String(localized: "Salmão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "salmon.png",       category: "Peixes e Frutos do Mar"),
        .init(id: "yogurt",     displayName: String(localized: "Iogurte", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),      iconFileName: "yogurt.png",       category: "Laticínios e Ovos"),
        .init(id: "water",      displayName: String(localized: "Água", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),         iconFileName: "water-bottle.png", category: "Bebidas"),
        .init(id: "chocolate",  displayName: String(localized: "Chocolate", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),    iconFileName: "chocolate.png",    category: "Doces e Sobremesas"),
        .init(id: "chips",      displayName: String(localized: "Salgadinho", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),   iconFileName: "chips.png",        category: "Snacks e Petiscos"),
        .init(id: "toothpaste", displayName: String(localized: "Pasta de dente", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), iconFileName: "toothpaste.png", category: "Limpeza e Higiene"),
        .init(id: "cucumber",   displayName: String(localized: "Pepino", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "cucumber.png",     category: "Verduras e Legumes"),
        .init(id: "pasta",      displayName: String(localized: "Macarrão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "pasta.png",        category: "Grãos, Massas e Cereais"),
        .init(id: "cheese",     displayName: String(localized: "Queijo", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "cheese.png",       category: "Laticínios e Ovos"),
        .init(id: "onion",      displayName: String(localized: "Cebola", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "onion.png",        category: "Verduras e Legumes"),
        .init(id: "potato",     displayName: String(localized: "Batata", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "potato.png",       category: "Verduras e Legumes"),
        .init(id: "grape",      displayName: String(localized: "Uva", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),          iconFileName: "grape.png",        category: "Frutas"),
        .init(id: "butter",     displayName: String(localized: "Manteiga", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "butter.png",       category: "Laticínios e Ovos"),
        .init(id: "beans",      displayName: String(localized: "Feijão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),       iconFileName: "soya-beans.png",   category: "Grãos, Massas e Cereais"),
        .init(id: "shrimp",     displayName: String(localized: "Camarão", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),      iconFileName: "shrimp.png",       category: "Peixes e Frutos do Mar"),
        .init(id: "sausage",    displayName: String(localized: "Linguiça", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "sausage.png",      category: "Carnes e Aves"),
        .init(id: "ham",        displayName: String(localized: "Presunto", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),     iconFileName: "ham.png",          category: "Carnes e Aves"),
        .init(id: "bacon",      displayName: String(localized: "Bacon", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),        iconFileName: "bacon.png",        category: "Carnes e Aves"),
    ]

    // MARK: - Recipe templates (full recipes inserted on commit)

    struct RecipeTemplate: Identifiable {
        let id: String
        let name: String
        let summary: String
        let category: String
        let prepMinutes: Int
        let cookMinutes: Int
        let servings: Int
        let calories: Int
        /// Two color hex strings for the placeholder cover gradient.
        let gradientColors: [UInt32]
        let photoFileName: String?
        /// Tuples of (name, qty, unit, iconFileName).
        let ingredients: [(String, Double?, String, String?)]
        /// Plain-text steps in order.
        let steps: [String]
        let tags: [String]
    }

    static let recipeTemplates: [RecipeTemplate] = [
        .init(
            id: "chicken-wrap-hummus",
            name: String(localized: "Wrap de frango com homus", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Wrap leve com frango grelhado e homus cremoso.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Lanche",
            prepMinutes: 10, cookMinutes: 5, servings: 2, calories: 410,
            gradientColors: [0xF28E52, 0xB55239],
            photoFileName: "onboarding-chicken-wrap-hummus.jpg",
            ingredients: [
                (String(localized: "Wrap integral", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, "", "bread-white.png"),
                (String(localized: "Peito de frango grelhado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 180, "g", "chicken-raw.png"),
                (String(localized: "Homus", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 4, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), nil),
                (String(localized: "Tomate", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, "", "tomato.png"),
                (String(localized: "Alface", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 4, String(localized: "folhas", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "lettuce.png"),
            ],
            steps: [
                String(localized: "Aqueça os wraps rapidamente na frigideira.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Espalhe o homus por toda a superfície.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Adicione frango, tomate e alface no centro.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Enrole firme e sirva em seguida.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Fácil", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "strawberry-oat-smoothie",
            name: String(localized: "Smoothie de morango e aveia", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Smoothie rápido e cremoso para manhãs corridas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Café da manhã",
            prepMinutes: 5, cookMinutes: 0, servings: 1, calories: 290,
            gradientColors: [0xD95D8A, 0x6A3DE8],
            photoFileName: "onboarding-strawberry-oat-smoothie.jpg",
            ingredients: [
                (String(localized: "Morango", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "strawberry.png"),
                (String(localized: "Aveia", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 3, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "oats.png"),
                (String(localized: "Iogurte natural", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 0.75, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "yogurt.png"),
                (String(localized: "Banana", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, "", "banana.png"),
            ],
            steps: [
                String(localized: "Adicione todos os ingredientes ao liquidificador.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Bata até ficar liso e cremoso.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Sirva gelado imediatamente.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "café da manhã", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Fácil", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "tuna-quinoa-bowl",
            name: String(localized: "Bowl de atum com quinoa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Bowl fresco com proteína, fibras e muita saciedade.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Almoço",
            prepMinutes: 12, cookMinutes: 0, servings: 2, calories: 430,
            gradientColors: [0x6A89CC, 0x3A4A72],
            photoFileName: "onboarding-tuna-quinoa-bowl.jpg",
            ingredients: [
                (String(localized: "Quinoa cozida", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1.5, String(localized: "xícaras", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "quinoa.png"),
                (String(localized: "Atum", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "lata", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "tuna.png"),
                (String(localized: "Pepino", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 0.5, "", "cucumber.png"),
                (String(localized: "Tomate", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, "", "tomato.png"),
                (String(localized: "Azeite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "colher de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "olive-oil.png"),
            ],
            steps: [
                String(localized: "Distribua a quinoa em duas tigelas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Cubra com atum, pepino e tomate.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Finalize com azeite, sal e pimenta.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "almoço", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "pancake",
            name: String(localized: "Panqueca Americana", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Café da manhã fofinho e dourado em 25 minutos.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Café da manhã",
            prepMinutes: 10, cookMinutes: 15, servings: 4, calories: 320,
            gradientColors: [0xFFC371, 0xFF5F6D],
            photoFileName: "onboarding-american-pancakes.jpg",
            ingredients: [
                (String(localized: "Farinha de trigo", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, String(localized: "xícaras", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "flour.png"),
                (String(localized: "Leite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1.5, String(localized: "xícaras", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "milk.png"),
                (String(localized: "Ovos", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, "", "egg.png"),
                (String(localized: "Açúcar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 3, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "sugar.png"),
                (String(localized: "Manteiga", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "butter.png"),
            ],
            steps: [
                String(localized: "Misture os ingredientes secos em uma tigela.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Em outra, bata os ovos com leite e manteiga derretida.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Junte tudo até a massa ficar homogênea.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Doure os dois lados em frigideira antiaderente.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Sirva com mel ou frutas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "doce", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "café da manhã", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "caesar-salad",
            name: String(localized: "Salada Caesar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Clássico crocante com molho cremoso.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Almoço",
            prepMinutes: 15, cookMinutes: 0, servings: 2, calories: 280,
            gradientColors: [0x7FB069, 0x2D6A4F],
            photoFileName: "onboarding-caesar-salad.jpg",
            ingredients: [
                (String(localized: "Alface romana", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "pé", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "lettuce.png"),
                (String(localized: "Croutons", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "bread-white.png"),
                (String(localized: "Parmesão ralado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 50, "g", "cheese.png"),
                (String(localized: "Peito de frango grelhado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 200, "g", "chicken-raw.png"),
            ],
            steps: [
                String(localized: "Lave e rasgue as folhas de alface.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Grelhe o frango temperado e fatie.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Combine alface, croutons e frango.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Regue com molho caesar e finalize com parmesão.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "salada", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "carbonara",
            name: String(localized: "Espaguete à Carbonara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Italiano cremoso, sem creme de leite, em 20 min.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Jantar",
            prepMinutes: 5, cookMinutes: 15, servings: 2, calories: 580,
            gradientColors: [0xF6C453, 0xC78400],
            photoFileName: "onboarding-spaghetti-carbonara.jpg",
            ingredients: [
                (String(localized: "Espaguete", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 200, "g", "pasta.png"),
                (String(localized: "Bacon", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 100, "g", "bacon.png"),
                (String(localized: "Ovos", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, "", "egg.png"),
                (String(localized: "Parmesão ralado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 60, "g", "cheese.png"),
            ],
            steps: [
                String(localized: "Cozinhe o espaguete al dente em água salgada.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Doure o bacon em fogo médio.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Bata as gemas com o parmesão.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Misture tudo fora do fogo, ajustando com a água da massa.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "italiano", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "jantar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "smoothie-bowl",
            name: String(localized: "Smoothie Bowl", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Tigela energética de frutas para começar o dia.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Café da manhã",
            prepMinutes: 10, cookMinutes: 0, servings: 1, calories: 380,
            gradientColors: [0xB983FF, 0x4361EE],
            photoFileName: "onboarding-smoothie-bowl.jpg",
            ingredients: [
                (String(localized: "Banana congelada", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, "", "banana.png"),
                (String(localized: "Frutas vermelhas", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "strawberry.png"),
                (String(localized: "Iogurte natural", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 0.5, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "yogurt.png"),
                (String(localized: "Granola", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 3, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "granola.png"),
            ],
            steps: [
                String(localized: "Bata banana, frutas e iogurte no liquidificador.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Despeje em uma tigela.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Decore com granola e frutas frescas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "café da manhã", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "grilled-chicken",
            name: String(localized: "Frango Grelhado com Legumes", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "Proteína magra e legumes na chapa.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Almoço",
            prepMinutes: 10, cookMinutes: 20, servings: 2, calories: 420,
            gradientColors: [0xFF7B54, 0xCC2936],
            photoFileName: "onboarding-grilled-chicken-veggies.jpg",
            ingredients: [
                (String(localized: "Peito de frango", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 400, "g", "chicken-raw.png"),
                (String(localized: "Brócolis", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "xícara", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "broccoli.png"),
                (String(localized: "Cenoura", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, "", "carrot.png"),
                (String(localized: "Azeite", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 2, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "olive-oil.png"),
                (String(localized: "Sal", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "pitada", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "salt.png"),
            ],
            steps: [
                String(localized: "Tempere o frango com sal, pimenta e alho.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Grelhe 6–8 minutos de cada lado.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Salteie os legumes no azeite.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Sirva o frango ao lado dos legumes.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "fitness", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
        .init(
            id: "brigadeiro",
            name: String(localized: "Brigadeiro", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            summary: String(localized: "O doce brasileiro que ninguém recusa.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            category: "Sobremesa",
            prepMinutes: 5, cookMinutes: 15, servings: 20, calories: 45,
            gradientColors: [0x6B4226, 0x2C0F0F],
            photoFileName: "onboarding-brigadeiro.jpg",
            ingredients: [
                (String(localized: "Leite condensado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "lata", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "milk.png"),
                (String(localized: "Chocolate em pó", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 3, String(localized: "colheres de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "chocolate-bar.png"),
                (String(localized: "Manteiga", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), 1, String(localized: "colher de sopa", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), "butter.png"),
            ],
            steps: [
                String(localized: "Misture todos os ingredientes em uma panela.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Cozinhe em fogo baixo mexendo até desgrudar do fundo.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                String(localized: "Espere esfriar, faça bolinhas e passe no granulado.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
            ],
            tags: [String(localized: "doce", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "brasileiro", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)]
        ),
    ]
}
