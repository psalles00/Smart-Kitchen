import Foundation

/// Loads per-language alias dictionaries from the bundled `meta-*.json`
/// resources. Each file is ~550 KB and decoding all 7 of them at boot was
/// adding hundreds of ms to the first user interaction on a real device.
///
/// PERF: only the languages that are actually queried are loaded — and each
/// is loaded **at most once**, lazily. The current UI language (and English
/// as the universal fallback) get touched on the first call to
/// `rankedAliases`; other languages stay on disk until the user explicitly
/// switches locales mid-session.
private final class ItemLocalizationRegistry: @unchecked Sendable {
    static let shared = ItemLocalizationRegistry()

    private let lock = NSLock()
    private var aliasesByFilename: [String: [AppLanguage: [String]]] = [:]
    private var loadedLanguages: Set<AppLanguage> = []

    private init() {}

    func rankedAliases(for entry: ItemEntry, localization: AppLocalization = .current()) -> [(title: String, sourceRank: Int)] {
        ensureLoaded(language: localization.language)
        if localization.language != .en {
            ensureLoaded(language: .en)
        }

        lock.lock()
        let aliases = aliasesByFilename[entry.nomeDoArquivo] ?? [:]
        lock.unlock()

        var ranked: [(title: String, sourceRank: Int)] = []
        var seen = Set<String>()

        func append(_ titles: [String], rank: Int) {
            for title in titles {
                let normalized = ItemEntry.normalize(title, locale: localization.foldingLocale)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ranked.append((title: title, sourceRank: rank))
            }
        }

        append(aliases[localization.language] ?? [], rank: 0)

        if localization.language != .en {
            append(aliases[.en] ?? [], rank: 1)
        }

        append(entry.titulos, rank: 2)
        return ranked
    }

    /// Loads the alias file for `language` if it hasn't been loaded yet.
    /// Safe to call from any thread / actor; protected by an internal lock.
    func ensureLoaded(language: AppLanguage) {
        lock.lock()
        let alreadyLoaded = loadedLanguages.contains(language)
        if !alreadyLoaded {
            loadedLanguages.insert(language)
        }
        lock.unlock()

        guard !alreadyLoaded else { return }

        guard let url = Bundle.main.url(forResource: language.itemMetadataResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(BundledItemLocaleDocument.self, from: data) else {
            return
        }

        // Build the per-file delta outside the lock, then merge under the
        // lock to minimise contention.
        var delta: [String: [String]] = [:]
        for record in document.records {
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = record.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !filename.isEmpty else { continue }
            var titles = delta[filename] ?? []
            if !titles.contains(title) {
                titles.append(title)
            }
            delta[filename] = titles
        }

        lock.lock()
        for (filename, titles) in delta {
            var aliases = aliasesByFilename[filename] ?? [:]
            aliases[language] = titles
            aliasesByFilename[filename] = aliases
        }
        lock.unlock()
    }
}

private struct BundledItemLocaleDocument: Decodable {
    let records: [BundledItemLocaleRecord]

    private enum CodingKeys: String, CodingKey {
        case items
        case itens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try? container.decode([BundledItemLocaleRecord].self, forKey: .items) {
            self.records = items
        } else {
            self.records = try container.decode([BundledItemLocaleRecord].self, forKey: .itens)
        }
    }
}

private struct BundledItemLocaleRecord: Decodable {
    let title: String
    let fileName: String

    private enum CodingKeys: String, CodingKey {
        case title
        case titulo
        case fileName = "file_name"
        case nomeDoArquivo = "nome_do_arquivo"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = (try? container.decode(String.self, forKey: .title))
            ?? (try? container.decode(String.self, forKey: .titulo))
            ?? ""
        self.fileName = (try? container.decode(String.self, forKey: .fileName))
            ?? (try? container.decode(String.self, forKey: .nomeDoArquivo))
            ?? ""
    }
}

extension ItemEntry {
    func preferredTitle(matching query: String? = nil, localization: AppLocalization = .current()) -> String {
        let normalizedQuery = Self.normalize(query ?? "", locale: localization.foldingLocale)
        let rankedAliases = searchableTitles(localization: localization)

        let candidates: [(title: String, sourceRank: Int)]
        if !normalizedQuery.isEmpty {
            let matches = rankedAliases.filter {
                Self.normalize($0.title, locale: localization.foldingLocale).hasPrefix(normalizedQuery)
            }
            candidates = matches.isEmpty ? rankedAliases : matches
        } else {
            candidates = rankedAliases
        }

        // Prefer a title that contains diacritics (e.g. "Limão" over "Limao")
        if let accented = candidates.first(where: {
            $0.title.lowercased() != Self.normalize($0.title, locale: localization.foldingLocale)
        }) {
            return accented.title
        }
        return candidates.first?.title ?? titulos.first ?? ""
    }

    func searchableTitles(localization: AppLocalization = .current()) -> [(title: String, sourceRank: Int)] {
        ItemLocalizationRegistry.shared.rankedAliases(for: self, localization: localization)
    }

    static func normalize(_ text: String, locale: Locale = AppLocalization.current().foldingLocale) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
