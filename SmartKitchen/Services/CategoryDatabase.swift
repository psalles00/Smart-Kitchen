import Foundation

struct CategoryDatabaseEntry: Codable, Identifiable, Sendable {
    let name: String
    let iconFileName: String?
    let marketSection: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case iconFileName = "icon_file_name"
        case marketSection = "market_section"
    }
}

final class CategoryDatabase: Sendable {
    static let shared = CategoryDatabase()

    let allCategories: [CategoryDatabaseEntry]
    private let normalizedEntries: [String: CategoryDatabaseEntry]

    private init() {
        let entries = Self.loadEntries()
        self.allCategories = entries
        self.normalizedEntries = Dictionary(uniqueKeysWithValues: entries.map { (Self.normalize($0.name), $0) })
    }

    func entry(for name: String) -> CategoryDatabaseEntry? {
        normalizedEntries[Self.normalize(name)]
    }

    func marketSection(for category: String) -> String {
        entry(for: category)?.marketSection ?? "Outros"
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadEntries() -> [CategoryDatabaseEntry] {
        guard let url = Bundle.main.url(forResource: "category_database", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CategoryDatabaseEntry].self, from: data) else {
            return fallbackEntries
        }

        return entries
    }

    private static let fallbackEntries: [CategoryDatabaseEntry] = [
        .init(name: "Frutas", iconFileName: "apple.png", marketSection: "Hortifruti"),
        .init(name: "Verduras e Legumes", iconFileName: "broccoli.png", marketSection: "Hortifruti"),
        .init(name: "Carnes e Aves", iconFileName: "chicken-raw.png", marketSection: "Açougue"),
        .init(name: "Peixes e Frutos do Mar", iconFileName: "fish-raw.png", marketSection: "Peixaria"),
        .init(name: "Padaria", iconFileName: "bread-white.png", marketSection: "Padaria"),
        .init(name: "Laticínios e Ovos", iconFileName: "milk.png", marketSection: "Refrigerados"),
        .init(name: "Grãos, Massas e Cereais", iconFileName: "rice.png", marketSection: "Mercearia"),
        .init(name: "Bebidas", iconFileName: "water-bottle.png", marketSection: "Bebidas"),
        .init(name: "Temperos e Condimentos", iconFileName: "salt.png", marketSection: "Temperos"),
        .init(name: "Enlatados e Conservas", iconFileName: "canned-tuna.png", marketSection: "Enlatados"),
        .init(name: "Doces e Sobremesas", iconFileName: "cake.png", marketSection: "Doces"),
        .init(name: "Snacks e Petiscos", iconFileName: "chips.png", marketSection: "Salgadinhos"),
        .init(name: "Pratos Prontos", iconFileName: "lunch-box.png", marketSection: "Congelados"),
        .init(name: "Limpeza e Higiene", iconFileName: "dish-soap.png", marketSection: "Limpeza"),
        .init(name: "Utensílios de Cozinha", iconFileName: "frying-pan.png", marketSection: "Utilidades"),
        .init(name: "Eletrodomésticos", iconFileName: "blender.png", marketSection: "Eletro"),
        .init(name: "Saúde e Bem-estar", iconFileName: "healthy-food.png", marketSection: "Saúde"),
        .init(name: "Outros", iconFileName: nil, marketSection: "Outros"),
    ]
}
