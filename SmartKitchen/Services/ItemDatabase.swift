import Foundation

/// Pre-loaded database of known items with icons and categories.
/// Provides fast prefix search and exact matching for autocomplete.
final class ItemDatabase: Sendable {

    static let shared = ItemDatabase()

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
        "a", "as", "com", "da", "das", "de", "do", "dos", "e", "em",
        "na", "nas", "no", "nos", "o", "os", "para", "por", "sem",
        "um", "uma", "uns", "umas"
    ]

    /// Flattened index: each title maps to its parent entry.
    private let index: [(normalized: String, entry: ItemEntry)]

    /// All entries keyed by filename for direct lookup.
    private let byFilename: [String: ItemEntry]
    private let entries: [ItemEntry]

    private init() {
        let entries = Self.loadEntries()
        var idx: [(String, ItemEntry)] = []
        idx.reserveCapacity(entries.count * 3)
        var byFile: [String: ItemEntry] = [:]
        byFile.reserveCapacity(entries.count)

        for entry in entries {
            byFile[entry.nomeDoArquivo] = entry
            for title in entry.titulos {
                idx.append((Self.normalize(title), entry))
            }
        }

        self.index = idx
        self.byFilename = byFile
        self.entries = entries.sorted {
            $0.preferredTitle().localizedCaseInsensitiveCompare($1.preferredTitle()) == .orderedAscending
        }
        self.allCategories = Array(Set(byFile.values.map(\.categoria))).sorted()
    }

    // MARK: - Public

    /// Search by prefix. Returns up to `limit` unique entries matching the query.
    func search(query: String, limit: Int = 12, fallbackToFeatured: Bool = false) -> [ItemEntry] {
        let q = Self.normalize(query)
        guard q.count >= 2 else {
            return fallbackToFeatured ? featuredEntries(limit: limit) : []
        }

        var seen = Set<String>()
        var results: [ItemEntry] = []

        // Gather candidates – always use word-prefix matching to avoid
        // noise (e.g. "Pera" matching "Paciente Pré-Operatório" via
        // substring "opera" containing "pera").
        for (normalized, entry) in index {
            let matches = normalized.hasPrefix(q)
                || normalized.split(whereSeparator: { $0 == " " || $0 == "-" })
                    .contains { $0.hasPrefix(q) }
            if matches {
                if seen.insert(entry.nomeDoArquivo).inserted {
                    results.append(entry)
                }
            }
        }
        
        // Sort by match quality
        let sorted = results.sorted { (a: ItemEntry, b: ItemEntry) -> Bool in
            let titleA = Self.normalize(a.preferredTitle(matching: query))
            let titleB = Self.normalize(b.preferredTitle(matching: query))
            
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
        Array(entries.prefix(limit))
    }

    /// Returns an entry if any of its titles match the given name exactly
    /// (case-insensitive, diacritics-insensitive).
    func exactMatch(for name: String) -> ItemEntry? {
        let q = Self.normalize(name)
        guard !q.isEmpty else { return nil }
        for (normalized, entry) in index where normalized == q {
            return entry
        }
        return nil
    }

    /// Returns the exact match for the full name, or the most specific
    /// database title contained as whole words in the name.
    func preferredMatch(for name: String) -> ItemEntry? {
        if let exact = exactMatch(for: name) {
            return exact
        }

        let normalizedQuery = Self.normalizeForInheritedMatching(name)
        guard !normalizedQuery.isEmpty else { return nil }

        var bestEntry: ItemEntry?
        var bestScore: InheritedMatchScore?

        for (normalized, entry) in index {
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
    static let marketSectionOrder: [String] = [
        "Hortifruti", "Açougue", "Peixaria", "Padaria", "Refrigerados",
        "Mercearia", "Bebidas", "Temperos", "Enlatados", "Doces",
        "Salgadinhos", "Congelados", "Limpeza", "Utilidades", "Eletro",
        "Saúde", "Outros"
    ]

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
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
