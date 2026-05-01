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
        .init(id: "rice",       displayName: String(localized: "Arroz"),        iconFileName: "rice.png",         category: "Grãos, Massas e Cereais"),
        .init(id: "oats",       displayName: String(localized: "Aveia"),        iconFileName: "oats.png",         category: "Grãos, Massas e Cereais"),
        .init(id: "pasta",      displayName: String(localized: "Macarrão"),     iconFileName: "pasta.png",        category: "Grãos, Massas e Cereais"),
        .init(id: "olive-oil",  displayName: String(localized: "Azeite"),       iconFileName: "olive-oil.png",    category: "Temperos e Condimentos"),
        .init(id: "salt",       displayName: String(localized: "Sal"),          iconFileName: "salt.png",         category: "Temperos e Condimentos"),
        .init(id: "sugar",      displayName: String(localized: "Açúcar"),       iconFileName: "sugar.png",        category: "Temperos e Condimentos"),
        .init(id: "coffee",     displayName: String(localized: "Café"),         iconFileName: "coffee.png",       category: "Bebidas"),
        .init(id: "milk",       displayName: String(localized: "Leite"),        iconFileName: "milk.png",         category: "Laticínios e Ovos"),
        .init(id: "egg",        displayName: String(localized: "Ovos"),         iconFileName: "egg.png",          category: "Laticínios e Ovos"),
        .init(id: "cheese",     displayName: String(localized: "Queijo"),       iconFileName: "cheese.png",       category: "Laticínios e Ovos"),
        .init(id: "butter",     displayName: String(localized: "Manteiga"),     iconFileName: "butter.png",       category: "Laticínios e Ovos"),
        .init(id: "flour",      displayName: String(localized: "Farinha"),      iconFileName: "flour.png",        category: "Grãos, Massas e Cereais"),
        .init(id: "bread",      displayName: String(localized: "Pão"),          iconFileName: "bread-white.png",  category: "Padaria"),
        .init(id: "garlic",     displayName: String(localized: "Alho"),         iconFileName: "garlic.png",       category: "Verduras e Legumes"),
        .init(id: "onion",      displayName: String(localized: "Cebola"),       iconFileName: "onion.png",        category: "Verduras e Legumes"),
        .init(id: "potato",     displayName: String(localized: "Batata"),       iconFileName: "potato.png",       category: "Verduras e Legumes"),
        .init(id: "honey",      displayName: String(localized: "Mel"),          iconFileName: "honey.png",        category: "Doces e Sobremesas"),
    ]

    // MARK: - Grocery catalog (different staples for the first shopping list)

    static let groceryItems: [ItemTemplate] = [
        .init(id: "tomato",     displayName: String(localized: "Tomate"),       iconFileName: "tomato.png",       category: "Verduras e Legumes"),
        .init(id: "lettuce",    displayName: String(localized: "Alface"),       iconFileName: "lettuce.png",      category: "Verduras e Legumes"),
        .init(id: "carrot",     displayName: String(localized: "Cenoura"),      iconFileName: "carrot.png",       category: "Verduras e Legumes"),
        .init(id: "broccoli",   displayName: String(localized: "Brócolis"),     iconFileName: "broccoli.png",     category: "Verduras e Legumes"),
        .init(id: "avocado",    displayName: String(localized: "Abacate"),      iconFileName: "avocado.png",      category: "Frutas"),
        .init(id: "banana",     displayName: String(localized: "Banana"),       iconFileName: "banana.png",       category: "Frutas"),
        .init(id: "apple",      displayName: String(localized: "Maçã"),         iconFileName: "apple.png",        category: "Frutas"),
        .init(id: "lemon",      displayName: String(localized: "Limão"),        iconFileName: "lemon.png",        category: "Frutas"),
        .init(id: "orange",     displayName: String(localized: "Laranja"),      iconFileName: "orange.png",       category: "Frutas"),
        .init(id: "strawberry", displayName: String(localized: "Morango"),      iconFileName: "strawberry.png",   category: "Frutas"),
        .init(id: "chicken",    displayName: String(localized: "Frango"),       iconFileName: "chicken-raw.png",  category: "Carnes e Aves"),
        .init(id: "beef",       displayName: String(localized: "Carne bovina"), iconFileName: "beef.png",         category: "Carnes e Aves"),
        .init(id: "salmon",     displayName: String(localized: "Salmão"),       iconFileName: "salmon.png",       category: "Peixes e Frutos do Mar"),
        .init(id: "yogurt",     displayName: String(localized: "Iogurte"),      iconFileName: "yogurt.png",       category: "Laticínios e Ovos"),
        .init(id: "water",      displayName: String(localized: "Água"),         iconFileName: "water-bottle.png", category: "Bebidas"),
        .init(id: "chocolate",  displayName: String(localized: "Chocolate"),    iconFileName: "chocolate.png",    category: "Doces e Sobremesas"),
        .init(id: "chips",      displayName: String(localized: "Salgadinho"),   iconFileName: "chips.png",        category: "Snacks e Petiscos"),
        .init(id: "toothpaste", displayName: String(localized: "Pasta de dente"), iconFileName: "toothpaste.png", category: "Limpeza e Higiene"),
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
        /// Tuples of (name, qty, unit, iconFileName).
        let ingredients: [(String, Double?, String, String?)]
        /// Plain-text steps in order.
        let steps: [String]
        let tags: [String]
    }

    static let recipeTemplates: [RecipeTemplate] = [
        .init(
            id: "pancake",
            name: String(localized: "Panqueca Americana"),
            summary: String(localized: "Café da manhã fofinho e dourado em 25 minutos."),
            category: "Café da manhã",
            prepMinutes: 10, cookMinutes: 15, servings: 4, calories: 320,
            gradientColors: [0xFFC371, 0xFF5F6D],
            ingredients: [
                (String(localized: "Farinha de trigo"), 2, String(localized: "xícaras"), "flour.png"),
                (String(localized: "Leite"), 1.5, String(localized: "xícaras"), "milk.png"),
                (String(localized: "Ovos"), 2, "", "egg.png"),
                (String(localized: "Açúcar"), 3, String(localized: "colheres de sopa"), "sugar.png"),
                (String(localized: "Manteiga"), 2, String(localized: "colheres de sopa"), "butter.png"),
            ],
            steps: [
                String(localized: "Misture os ingredientes secos em uma tigela."),
                String(localized: "Em outra, bata os ovos com leite e manteiga derretida."),
                String(localized: "Junte tudo até a massa ficar homogênea."),
                String(localized: "Doure os dois lados em frigideira antiaderente."),
                String(localized: "Sirva com mel ou frutas."),
            ],
            tags: [String(localized: "doce"), String(localized: "café da manhã")]
        ),
        .init(
            id: "caesar-salad",
            name: String(localized: "Salada Caesar"),
            summary: String(localized: "Clássico crocante com molho cremoso."),
            category: "Almoço",
            prepMinutes: 15, cookMinutes: 0, servings: 2, calories: 280,
            gradientColors: [0x7FB069, 0x2D6A4F],
            ingredients: [
                (String(localized: "Alface romana"), 1, String(localized: "pé"), "lettuce.png"),
                (String(localized: "Croutons"), 1, String(localized: "xícara"), "bread-white.png"),
                (String(localized: "Parmesão ralado"), 50, "g", "cheese.png"),
                (String(localized: "Peito de frango grelhado"), 200, "g", "chicken-raw.png"),
            ],
            steps: [
                String(localized: "Lave e rasgue as folhas de alface."),
                String(localized: "Grelhe o frango temperado e fatie."),
                String(localized: "Combine alface, croutons e frango."),
                String(localized: "Regue com molho caesar e finalize com parmesão."),
            ],
            tags: [String(localized: "saudável"), String(localized: "salada")]
        ),
        .init(
            id: "brigadeiro",
            name: String(localized: "Brigadeiro"),
            summary: String(localized: "O doce brasileiro que ninguém recusa."),
            category: "Sobremesa",
            prepMinutes: 5, cookMinutes: 15, servings: 20, calories: 45,
            gradientColors: [0x6B4226, 0x2C0F0F],
            ingredients: [
                (String(localized: "Leite condensado"), 1, String(localized: "lata"), "milk.png"),
                (String(localized: "Chocolate em pó"), 3, String(localized: "colheres de sopa"), "chocolate-bar.png"),
                (String(localized: "Manteiga"), 1, String(localized: "colher de sopa"), "butter.png"),
            ],
            steps: [
                String(localized: "Misture todos os ingredientes em uma panela."),
                String(localized: "Cozinhe em fogo baixo mexendo até desgrudar do fundo."),
                String(localized: "Espere esfriar, faça bolinhas e passe no granulado."),
            ],
            tags: [String(localized: "doce"), String(localized: "brasileiro")]
        ),
        .init(
            id: "carbonara",
            name: String(localized: "Espaguete à Carbonara"),
            summary: String(localized: "Italiano cremoso, sem creme de leite, em 20 min."),
            category: "Jantar",
            prepMinutes: 5, cookMinutes: 15, servings: 2, calories: 580,
            gradientColors: [0xF6C453, 0xC78400],
            ingredients: [
                (String(localized: "Espaguete"), 200, "g", "pasta.png"),
                (String(localized: "Bacon"), 100, "g", "bacon.png"),
                (String(localized: "Ovos"), 2, "", "egg.png"),
                (String(localized: "Parmesão ralado"), 60, "g", "cheese.png"),
            ],
            steps: [
                String(localized: "Cozinhe o espaguete al dente em água salgada."),
                String(localized: "Doure o bacon em fogo médio."),
                String(localized: "Bata as gemas com o parmesão."),
                String(localized: "Misture tudo fora do fogo, ajustando com a água da massa."),
            ],
            tags: [String(localized: "italiano"), String(localized: "jantar")]
        ),
        .init(
            id: "smoothie-bowl",
            name: String(localized: "Smoothie Bowl"),
            summary: String(localized: "Tigela energética de frutas para começar o dia."),
            category: "Café da manhã",
            prepMinutes: 10, cookMinutes: 0, servings: 1, calories: 380,
            gradientColors: [0xB983FF, 0x4361EE],
            ingredients: [
                (String(localized: "Banana congelada"), 1, "", "banana.png"),
                (String(localized: "Frutas vermelhas"), 1, String(localized: "xícara"), "strawberry.png"),
                (String(localized: "Iogurte natural"), 0.5, String(localized: "xícara"), "yogurt.png"),
                (String(localized: "Granola"), 3, String(localized: "colheres de sopa"), "granola.png"),
            ],
            steps: [
                String(localized: "Bata banana, frutas e iogurte no liquidificador."),
                String(localized: "Despeje em uma tigela."),
                String(localized: "Decore com granola e frutas frescas."),
            ],
            tags: [String(localized: "saudável"), String(localized: "café da manhã")]
        ),
        .init(
            id: "grilled-chicken",
            name: String(localized: "Frango Grelhado com Legumes"),
            summary: String(localized: "Proteína magra e legumes na chapa."),
            category: "Almoço",
            prepMinutes: 10, cookMinutes: 20, servings: 2, calories: 420,
            gradientColors: [0xFF7B54, 0xCC2936],
            ingredients: [
                (String(localized: "Peito de frango"), 400, "g", "chicken-raw.png"),
                (String(localized: "Brócolis"), 1, String(localized: "xícara"), "broccoli.png"),
                (String(localized: "Cenoura"), 2, "", "carrot.png"),
                (String(localized: "Azeite"), 2, String(localized: "colheres de sopa"), "olive-oil.png"),
                (String(localized: "Sal"), 1, String(localized: "pitada"), "salt.png"),
            ],
            steps: [
                String(localized: "Tempere o frango com sal, pimenta e alho."),
                String(localized: "Grelhe 6–8 minutos de cada lado."),
                String(localized: "Salteie os legumes no azeite."),
                String(localized: "Sirva o frango ao lado dos legumes."),
            ],
            tags: [String(localized: "saudável"), String(localized: "fitness")]
        ),
    ]
}
