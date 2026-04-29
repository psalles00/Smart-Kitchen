import Foundation

struct CategoryDatabaseEntry: Codable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let iconFileName: String?
    let marketSection: String
    let localizedNames: [String: String]
    let localizedMarketSections: [String: String]
    let aliases: [String: [String]]

    var id: String { identifier }

    init(
        identifier: String,
        name: String,
        iconFileName: String?,
        marketSection: String,
        localizedNames: [String: String] = [:],
        localizedMarketSections: [String: String] = [:],
        aliases: [String: [String]] = [:]
    ) {
        self.identifier = identifier
        self.name = name
        self.iconFileName = iconFileName
        self.marketSection = marketSection
        self.localizedNames = localizedNames
        self.localizedMarketSections = localizedMarketSections
        self.aliases = aliases
    }

    private static func defaultIdentifier(for name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
            .lowercased()
            .replacingOccurrences(of: "&", with: " e ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: "-")
    }

    var displayName: String {
        let localization = AppLocalization.current()
        return localizedNames[localization.language.bundleLocalizationIdentifier]
            ?? localizedNames[localization.language.baseLanguageCode]
            ?? name
    }

    var displayMarketSection: String {
        let localization = AppLocalization.current()
        return localizedMarketSections[localization.language.bundleLocalizationIdentifier]
            ?? localizedMarketSections[localization.language.baseLanguageCode]
            ?? marketSection
    }

    var searchableTokens: [String] {
        var tokens = [identifier, name]
        tokens.append(contentsOf: localizedNames.values)
        tokens.append(contentsOf: aliases.values.flatMap { $0 })
        return tokens
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case name
        case iconFileName = "icon_file_name"
        case marketSection = "market_section"
        case localizedNames = "localized_names"
        case localizedMarketSections = "localized_market_sections"
        case aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? Self.defaultIdentifier(for: name)

        self.init(
            identifier: identifier,
            name: name,
            iconFileName: try container.decodeIfPresent(String.self, forKey: .iconFileName),
            marketSection: try container.decode(String.self, forKey: .marketSection),
            localizedNames: try container.decodeIfPresent([String: String].self, forKey: .localizedNames) ?? [:],
            localizedMarketSections: try container.decodeIfPresent([String: String].self, forKey: .localizedMarketSections) ?? [:],
            aliases: try container.decodeIfPresent([String: [String]].self, forKey: .aliases) ?? [:]
        )
    }
}

final class CategoryDatabase: Sendable {
    static let shared = CategoryDatabase()

    let allCategories: [CategoryDatabaseEntry]
    private let normalizedEntries: [String: CategoryDatabaseEntry]

    private init() {
        let entries = Self.loadEntries()
        self.allCategories = entries
        var normalizedEntries: [String: CategoryDatabaseEntry] = [:]
        for entry in entries {
            for token in entry.searchableTokens {
                normalizedEntries[Self.normalize(token)] = entry
            }
        }
        self.normalizedEntries = normalizedEntries
    }

    func entry(for name: String) -> CategoryDatabaseEntry? {
        normalizedEntries[Self.normalize(name)]
    }

    func displayName(for category: String) -> String {
        entry(for: category)?.displayName ?? category
    }

    func marketSection(for category: String) -> String {
        entry(for: category)?.displayMarketSection ?? Self.fallbackEntries.last?.marketSection ?? "Outros"
    }

    var marketSectionsInDisplayOrder: [String] {
        var seen = Set<String>()
        return allCategories.compactMap { entry in
            let section = entry.displayMarketSection
            guard seen.insert(section).inserted else { return nil }
            return section
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
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
        .init(identifier: "fruits", name: "Frutas", iconFileName: "apple.png", marketSection: "Hortifruti", localizedNames: ["en": "Fruits"], localizedMarketSections: ["en": "Produce"]),
        .init(identifier: "vegetables", name: "Verduras e Legumes", iconFileName: "broccoli.png", marketSection: "Hortifruti", localizedNames: ["en": "Vegetables & Greens"], localizedMarketSections: ["en": "Produce"]),
        .init(identifier: "meats", name: "Carnes e Aves", iconFileName: "chicken-raw.png", marketSection: "Açougue", localizedNames: ["en": "Meat & Poultry"], localizedMarketSections: ["en": "Butcher"]),
        .init(identifier: "seafood", name: "Peixes e Frutos do Mar", iconFileName: "fish-raw.png", marketSection: "Peixaria", localizedNames: ["en": "Fish & Seafood"], localizedMarketSections: ["en": "Seafood"]),
        .init(identifier: "bakery", name: "Padaria", iconFileName: "bread-white.png", marketSection: "Padaria", localizedNames: ["en": "Bakery"], localizedMarketSections: ["en": "Bakery"]),
        .init(identifier: "dairy", name: "Laticínios e Ovos", iconFileName: "milk.png", marketSection: "Refrigerados", localizedNames: ["en": "Dairy & Eggs"], localizedMarketSections: ["en": "Refrigerated"]),
        .init(identifier: "grains", name: "Grãos, Massas e Cereais", iconFileName: "rice.png", marketSection: "Mercearia", localizedNames: ["en": "Grains, Pasta & Cereals"], localizedMarketSections: ["en": "Grocery"]),
        .init(identifier: "beverages", name: "Bebidas", iconFileName: "water-bottle.png", marketSection: "Bebidas", localizedNames: ["en": "Beverages"], localizedMarketSections: ["en": "Beverages"]),
        .init(identifier: "seasonings", name: "Temperos e Condimentos", iconFileName: "salt.png", marketSection: "Temperos", localizedNames: ["en": "Seasonings & Condiments"], localizedMarketSections: ["en": "Seasonings"]),
        .init(identifier: "canned", name: "Enlatados e Conservas", iconFileName: "canned-tuna.png", marketSection: "Enlatados", localizedNames: ["en": "Canned & Preserved Goods"], localizedMarketSections: ["en": "Canned Goods"]),
        .init(identifier: "desserts", name: "Doces e Sobremesas", iconFileName: "cake.png", marketSection: "Doces", localizedNames: ["en": "Desserts & Sweets"], localizedMarketSections: ["en": "Sweets"]),
        .init(identifier: "snacks", name: "Snacks e Petiscos", iconFileName: "chips.png", marketSection: "Salgadinhos", localizedNames: ["en": "Snacks & Bites"], localizedMarketSections: ["en": "Snacks"]),
        .init(identifier: "prepared-meals", name: "Pratos Prontos", iconFileName: "lunch-box.png", marketSection: "Congelados", localizedNames: ["en": "Ready Meals"], localizedMarketSections: ["en": "Frozen"]),
        .init(identifier: "cleaning", name: "Limpeza e Higiene", iconFileName: "dish-soap.png", marketSection: "Limpeza", localizedNames: ["en": "Cleaning & Hygiene"], localizedMarketSections: ["en": "Cleaning"]),
        .init(identifier: "kitchen-tools", name: "Utensílios de Cozinha", iconFileName: "frying-pan.png", marketSection: "Utilidades", localizedNames: ["en": "Kitchen Tools"], localizedMarketSections: ["en": "Housewares"]),
        .init(identifier: "appliances", name: "Eletrodomésticos", iconFileName: "blender.png", marketSection: "Eletro", localizedNames: ["en": "Appliances"], localizedMarketSections: ["en": "Appliances"]),
        .init(identifier: "wellness", name: "Saúde e Bem-estar", iconFileName: "healthy-food.png", marketSection: "Saúde", localizedNames: ["en": "Health & Wellness"], localizedMarketSections: ["en": "Health"]),
        .init(identifier: "other", name: "Outros", iconFileName: nil, marketSection: "Outros", localizedNames: ["en": "Other"], localizedMarketSections: ["en": "Other"]),
    ]
}
