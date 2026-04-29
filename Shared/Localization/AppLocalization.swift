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

    let language: AppLanguage

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

    static func current(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLocalization {
        for identifier in preferredLanguages {
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