import Foundation

/// Pre-loaded database of known items with icons and categories.
/// Provides fast prefix search and exact matching for autocomplete.
final class ItemDatabase: Sendable {

    static let shared = ItemDatabase()

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

        // Prefix matches first
        for (normalized, entry) in index {
            guard normalized.hasPrefix(q) else { continue }
            guard seen.insert(entry.nomeDoArquivo).inserted else { continue }
            results.append(entry)
            if results.count >= limit { return results }
        }

        // Then contains matches
        for (normalized, entry) in index {
            guard normalized.contains(q) else { continue }
            guard seen.insert(entry.nomeDoArquivo).inserted else { continue }
            results.append(entry)
            if results.count >= limit { return results }
        }

        return results
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

    /// Look up an entry by its icon filename.
    func entry(forFilename filename: String) -> ItemEntry? {
        byFilename[filename]
    }

    /// All unique category names present in the database, sorted.
    let allCategories: [String]

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
