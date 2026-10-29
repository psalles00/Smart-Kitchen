import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case ptBR = "pt-BR"
    case en = "en"
    case es = "es"
    case fr = "fr"
    case de = "de"
    case it = "it"
    case ja = "ja"

    static let fallback: AppLanguage = .en

    var bundleLocalizationIdentifier: String { rawValue }

    var foundationLocaleIdentifier: String {
        switch self {
        case .ptBR:
            return "pt-BR"
        case .en:
            return "en-US"
        case .es:
            return "es-ES"
        case .fr:
            return "fr-FR"
        case .de:
            return "de-DE"
        case .it:
            return "it-IT"
        case .ja:
            return "ja-JP"
        }
    }

    var baseLanguageCode: String {
        switch self {
        case .ptBR:
            return "pt"
        case .en:
            return "en"
        case .es:
            return "es"
        case .fr:
            return "fr"
        case .de:
            return "de"
        case .it:
            return "it"
        case .ja:
            return "ja"
        }
    }

    var locale: Locale {
        Locale(identifier: foundationLocaleIdentifier)
    }

    var itemMetadataResourceName: String {
        switch self {
        case .ptBR:
            return "meta-ptbr"
        case .en:
            return "meta-en"
        case .es:
            return "meta-es"
        case .fr:
            return "meta-fr"
        case .de:
            return "meta-de"
        case .it:
            return "meta-it"
        case .ja:
            return "meta-ja"
        }
    }

    var aiModelLanguageName: String {
        switch self {
        case .ptBR:
            return "Brazilian Portuguese"
        case .en:
            return "English"
        case .es:
            return "Spanish"
        case .fr:
            return "French"
        case .de:
            return "German"
        case .it:
            return "Italian"
        case .ja:
            return "Japanese"
        }
    }

    var recipeSearchKeyword: String {
        switch self {
        case .ptBR:
            return "receita"
        case .en:
            return "recipe"
        case .es:
            return "receta"
        case .fr:
            return "recette"
        case .de:
            return "rezept"
        case .it:
            return "ricetta"
        case .ja:
            return "レシピ"
        }
    }

    var recipeIngredientJoiner: String {
        switch self {
        case .ptBR:
            return "com"
        case .en:
            return "with"
        case .es:
            return "con"
        case .fr:
            return "avec"
        case .de:
            return "mit"
        case .it:
            return "con"
        case .ja:
            return "食材"
        }
    }

    var recipeSourcePageHint: String {
        switch self {
        case .ptBR: return "receita individual com ingredientes e modo de preparo, não listas de receitas"
        case .en: return "individual recipe with ingredients and directions, not recipe collections"
        case .es: return "receta individual con ingredientes e instrucciones, no listas de recetas"
        case .fr: return "recette individuelle avec ingrédients et préparation, pas de listes de recettes"
        case .de: return "einzelnes Rezept mit Zutaten und Zubereitung, keine Rezeptsammlungen"
        case .it: return "ricetta singola con ingredienti e preparazione, non raccolte di ricette"
        case .ja: return "材料と作り方がある個別のレシピ、レシピまとめを除く"
        }
    }

    func recipePantryConstraint(_ items: [String]) -> String {
        let names = items.joined(separator: ", ")
        switch self {
        case .ptBR: return "Use somente ingredientes dentre: \(names). Não é necessário usar todos."
        case .en: return "Use only ingredients from: \(names). You do not need to use them all."
        case .es: return "Usa solo ingredientes de esta lista: \(names). No es necesario usarlos todos."
        case .fr: return "Utilisez uniquement des ingrédients parmi : \(names). Il n’est pas nécessaire de tous les utiliser."
        case .de: return "Verwende nur Zutaten aus dieser Liste: \(names). Es müssen nicht alle verwendet werden."
        case .it: return "Usa solo ingredienti tra: \(names). Non è necessario usarli tutti."
        case .ja: return "使用できる材料：\(names)。この中の材料だけを使い、すべて使う必要はありません。"
        }
    }

    var recipeSearchVariations: [String] {
        switch self {
        case .ptBR: return ["combinações alternativas de ingredientes", "receitas regionais e internacionais", "técnicas de preparo diferentes"]
        case .en: return ["alternative ingredient combinations", "regional and international recipes", "different preparation techniques"]
        case .es: return ["combinaciones alternativas de ingredientes", "recetas regionales e internacionales", "técnicas de preparación diferentes"]
        case .fr: return ["autres associations d’ingrédients", "recettes régionales et internationales", "différentes techniques de préparation"]
        case .de: return ["alternative Zutatenkombinationen", "regionale und internationale Rezepte", "andere Zubereitungstechniken"]
        case .it: return ["combinazioni alternative di ingredienti", "ricette regionali e internazionali", "tecniche di preparazione diverse"]
        case .ja: return ["食材の別の組み合わせ", "郷土料理と世界の料理", "異なる調理方法"]
        }
    }

    var exaPreferredDomains: [String] {
        switch self {
        case .ptBR:
            return [
                "tudogostoso.com.br",
                "panelinha.com.br",
                "receitas.globo.com",
                "cybercook.com.br",
                "receiteria.com.br",
                "guiadacozinha.com.br",
                "comidasebebidas.uol.com.br",
                "anamariabraga.globo.com"
            ]
        case .en:
            return [
                "allrecipes.com",
                "simplyrecipes.com",
                "foodnetwork.com",
                "delish.com",
                "tasteofhome.com",
                "bbcgoodfood.com",
                "seriouseats.com",
                "thekitchn.com"
            ]
        case .es, .fr, .de, .it, .ja:
            return []
        }
    }

    var exaUserLocationCode: String? {
        locale.region?.identifier
    }

    static func resolve(identifier: String) -> AppLanguage? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("pt") { return .ptBR }
        if normalized.hasPrefix("en") { return .en }
        if normalized.hasPrefix("es") { return .es }
        if normalized.hasPrefix("fr") { return .fr }
        if normalized.hasPrefix("de") { return .de }
        if normalized.hasPrefix("it") { return .it }
        if normalized.hasPrefix("ja") { return .ja }
        return nil
    }
}

struct AppLocalization: Sendable {
    static let supportedLanguages = AppLanguage.allCases
    private static let languageBundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language in
            guard let path = Bundle.main.path(forResource: language.bundleLocalizationIdentifier, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        })

    let language: AppLanguage

    /// Resolves built-in labels for the selected language without changing
    /// persisted category identifiers or translating user-defined names.
    func builtInLabel(_ key: String) -> String {
        Self.languageBundles[language]?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    var locale: Locale {
        language.locale
    }

    var formattingLocale: Locale {
        locale
    }

    var foldingLocale: Locale {
        locale
    }

    var speechRecognizerLocale: Locale {
        locale
    }

    var fallbackSpeechRecognizerLocale: Locale {
        AppLanguage.en.locale
    }

    var nutritionCacheLocaleIdentifier: String {
        language.bundleLocalizationIdentifier
    }

    var preferredItemLanguages: [AppLanguage] {
        [language, .en].uniquePreservingOrder()
    }

    var visionRecognitionLanguages: [String] {
        preferredItemLanguages
            .map(\.foundationLocaleIdentifier)
            .uniquePreservingOrder()
    }

    var acceptLanguageHeader: String {
        let orderedTags = ([language.foundationLocaleIdentifier, language.baseLanguageCode] + preferredItemLanguages.flatMap {
            [$0.foundationLocaleIdentifier, $0.baseLanguageCode]
        }).uniquePreservingOrder()

        return orderedTags.enumerated().map { index, tag in
            if index == 0 {
                return tag
            }
            let quality = max(0.1, 1.0 - (Double(index) * 0.1))
            return String(format: "%@;q=%.1f", tag, quality)
        }.joined(separator: ",")
    }

    static func current(
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundlePreferredLanguages: [String] = Bundle.main.preferredLocalizations
    ) -> AppLocalization {
        let candidates = (bundlePreferredLanguages + preferredLanguages).uniquePreservingOrder()

        for identifier in candidates {
            if let language = AppLanguage.resolve(identifier: identifier) {
                return AppLocalization(language: language)
            }
        }

        return AppLocalization(language: .fallback)
    }
}

private extension Sequence where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
