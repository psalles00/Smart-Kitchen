import Foundation

/// Pre-loaded database of known items with icons and categories.
/// Provides fast prefix search and exact matching for autocomplete.
///
/// PERF: locale-keyed search indexes are built lazily, one language at a
/// time. The original implementation built indexes for all 7 supported
/// languages eagerly inside `init`, which decoded ~340 KB of JSON and
/// iterated 16k+ entries × 7 locales on the main thread the first time
/// any caller touched `ItemDatabase.shared`. That was the single biggest
/// contributor to the "app feels stuck for a few seconds after launch /
/// foreground" report.
///
/// Thread-safety: the mutable language cache is guarded by `indexLock`,
/// so this class is safe to call from any actor or background queue.
final class ItemDatabase: @unchecked Sendable {

    static let shared = ItemDatabase()

    private struct IndexedTitle {
        let normalized: String
        let entry: ItemEntry
        let sourceRank: Int
    }

    private struct InheritedMatchScore: Comparable {
        let wordCount: Int
        let characterCount: Int

        static func < (lhs: InheritedMatchScore, rhs: InheritedMatchScore) -> Bool {
            if lhs.wordCount != rhs.wordCount {
                return lhs.wordCount < rhs.wordCount
            }
            return lhs.characterCount < rhs.characterCount
        }
    }

    private static let ignoredInheritanceWords: Set<String> = [
        "a", "an", "and", "as", "com", "con", "da", "das", "de", "des",
        "di", "do", "dos", "e", "el", "em", "et", "for", "la", "las",
        "le", "les", "mit", "na", "nas", "no", "nos", "o", "of", "os",
        "para", "por", "sem", "the", "um", "uma", "unas", "und", "uns",
        "with", "y"
    ]

    /// Lock guarding `localizedIndexes`. Indexes are built lazily on first
    /// access per language and reused thereafter.
    private let indexLock = NSLock()
    private var localizedIndexes: [AppLanguage: [IndexedTitle]] = [:]

    /// All entries keyed by filename for direct lookup.
    private let byFilename: [String: ItemEntry]
    private let entries: [ItemEntry]

    private init() {
        let entries = Self.loadEntries()
        var byFile: [String: ItemEntry] = [:]
        byFile.reserveCapacity(entries.count)
        for entry in entries {
            byFile[entry.nomeDoArquivo] = entry
        }

        self.byFilename = byFile
        self.entries = entries
        self.allCategories = Array(Set(byFile.values.map(\.categoria))).sorted()

        // Eagerly build the index for the current UI language only — that's
        // the one users will actually search against immediately. Other
        // languages remain on disk until requested.
        _ = index(for: AppLocalization.current().language)
    }

    /// Pre-builds search indexes for the current language. Cheap to call
    /// multiple times; subsequent calls are no-ops. Intended to be invoked
    /// from a background task during app bootstrap so the first user
    /// interaction never pays the index-building cost.
    func prewarm() {
        _ = index(for: AppLocalization.current().language)
    }

    private func index(for language: AppLanguage) -> [IndexedTitle] {
        indexLock.lock()
        if let cached = localizedIndexes[language] {
            indexLock.unlock()
            return cached
        }
        indexLock.unlock()

        // Build outside the lock — `searchableTitles` itself acquires
        // a different lock (in `ItemLocalizationRegistry`) and we want to
        // avoid holding two locks at once.
        let localization = AppLocalization(language: language)
        var built: [IndexedTitle] = []
        built.reserveCapacity(entries.count * 2)
        for entry in entries {
            let titles = entry.searchableTitles(localization: localization)
            for title in titles {
                built.append(
                    IndexedTitle(
                        normalized: Self.normalize(title.title),
                        entry: entry,
                        sourceRank: title.sourceRank
                    )
                )
            }
        }

        indexLock.lock()
        // Another caller might have populated it while we were building;
        // last write wins — the result is identical regardless.
        localizedIndexes[language] = built
        indexLock.unlock()
        return built
    }

    // MARK: - Public

    /// Search by prefix. Returns up to `limit` unique entries matching the query.
    func search(query: String, limit: Int = 12, fallbackToFeatured: Bool = false) -> [ItemEntry] {
        let localization = AppLocalization.current()
        let q = Self.normalize(query)
        guard q.count >= 2 else {
            return fallbackToFeatured ? featuredEntries(limit: limit) : []
        }

        var seen = Set<String>()
        var results: [ItemEntry] = []
        var bestSourceRanks: [String: Int] = [:]
        let index = index(for: localization.language)

        // Gather candidates – always use word-prefix matching to avoid
        // noise (e.g. "Pera" matching "Paciente Pré-Operatório" via
        // substring "opera" containing "pera").
        for candidate in index {
            let normalized = candidate.normalized
            let entry = candidate.entry
            let matches = normalized.hasPrefix(q)
                || normalized.split(whereSeparator: { $0 == " " || $0 == "-" })
                    .contains { $0.hasPrefix(q) }
            if matches {
                bestSourceRanks[entry.nomeDoArquivo] = min(bestSourceRanks[entry.nomeDoArquivo] ?? Int.max, candidate.sourceRank)
                if seen.insert(entry.nomeDoArquivo).inserted {
                    results.append(entry)
                }
            }
        }
        
        // Sort by match quality
        let sorted = results.sorted { (a: ItemEntry, b: ItemEntry) -> Bool in
            let sourceRankA = bestSourceRanks[a.nomeDoArquivo] ?? Int.max
            let sourceRankB = bestSourceRanks[b.nomeDoArquivo] ?? Int.max
            if sourceRankA != sourceRankB {
                return sourceRankA < sourceRankB
            }

            let titleA = Self.normalize(a.preferredTitle(matching: query, localization: localization))
            let titleB = Self.normalize(b.preferredTitle(matching: query, localization: localization))
            
            let aExact = titleA == q
            let bExact = titleB == q
            if aExact != bExact { return aExact }
            
            let aPrefix = titleA.hasPrefix(q)
            let bPrefix = titleB.hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            
            // Prefer shorter titles
            if titleA.count != titleB.count {
                return titleA.count < titleB.count
            }
            
            // Fallback to alphabetical
            return a.nomeDoArquivo < b.nomeDoArquivo
        }
        
        return Array(sorted.prefix(limit))
    }

    func featuredEntries(limit: Int = 12) -> [ItemEntry] {
        let localization = AppLocalization.current()
        let sortedEntries = entries.sorted {
            $0.preferredTitle(localization: localization)
                .localizedCaseInsensitiveCompare($1.preferredTitle(localization: localization)) == .orderedAscending
        }
        return Array(sortedEntries.prefix(limit))
    }

    /// Returns an entry if any of its titles match the given name exactly
    /// (case-insensitive, diacritics-insensitive).
    func exactMatch(for name: String) -> ItemEntry? {
        let index = index(for: AppLocalization.current().language)
        let q = Self.normalize(name)
        guard !q.isEmpty else { return nil }
        for candidate in index where candidate.normalized == q {
            return candidate.entry
        }
        return nil
    }

    /// Returns the exact match for the full name, or the most specific
    /// database title contained as whole words in the name.
    func preferredMatch(for name: String) -> ItemEntry? {
        if let exact = exactMatch(for: name) {
            return exact
        }

        let index = index(for: AppLocalization.current().language)
        let normalizedQuery = Self.normalizeForInheritedMatching(name)
        guard !normalizedQuery.isEmpty else { return nil }

        var bestEntry: ItemEntry?
        var bestScore: InheritedMatchScore?

        for candidate in index {
            let normalized = candidate.normalized
            let entry = candidate.entry
            let normalizedTitle = Self.normalizeForInheritedMatching(normalized)
            guard normalizedTitle != normalizedQuery,
                  Self.isEligibleInheritedTitle(normalizedTitle),
                  Self.containsWholePhrase(normalizedTitle, in: normalizedQuery) else {
                continue
            }

            let score = InheritedMatchScore(
                wordCount: normalizedTitle.split(separator: " ").count,
                characterCount: normalizedTitle.count
            )

            if let currentBestScore = bestScore {
                if currentBestScore < score {
                    bestEntry = entry
                    bestScore = score
                }
            } else {
                bestEntry = entry
                bestScore = score
            }
        }

        return bestEntry
    }

    /// Look up an entry by its icon filename.
    func entry(forFilename filename: String) -> ItemEntry? {
        byFilename[filename]
    }

    /// All unique category names present in the database, sorted.
    let allCategories: [String]

    // MARK: - Market Section Mapping

    /// Maps a category name to its supermarket section.
    static func marketSection(for category: String) -> String {
        CategoryDatabase.shared.marketSection(for: category)
    }

    /// Ordered list of market sections for sorting.
    static var marketSectionOrder: [String] {
        CategoryDatabase.shared.marketSectionsInDisplayOrder
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: AppLocalization.current().foldingLocale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeForInheritedMatching(_ text: String) -> String {
        normalize(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: " ")
    }

    private static func isEligibleInheritedTitle(_ title: String) -> Bool {
        title.split(separator: " ").contains { token in
            let word = String(token)
            return word.count >= 3 && !ignoredInheritanceWords.contains(word)
        }
    }

    private static func containsWholePhrase(_ phrase: String, in query: String) -> Bool {
        query == phrase
            || query.hasPrefix(phrase + " ")
            || query.hasSuffix(" " + phrase)
            || query.contains(" " + phrase + " ")
    }

    private static func loadEntries() -> [ItemEntry] {
        guard let url = Bundle.main.url(forResource: "items_database", withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([ItemEntry].self, from: data)) ?? []
    }
}
