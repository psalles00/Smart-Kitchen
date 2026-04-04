import Foundation

extension ItemEntry {
    func preferredTitle(matching query: String? = nil) -> String {
        let normalizedQuery = Self.normalize(query ?? "")

        let candidates: [String]
        if !normalizedQuery.isEmpty {
            let matches = titulos.filter { Self.normalize($0).hasPrefix(normalizedQuery) }
            candidates = matches.isEmpty ? titulos : matches
        } else {
            candidates = titulos
        }

        // Prefer a title that contains diacritics (e.g. "Limão" over "Limao")
        if let accented = candidates.first(where: { $0.lowercased() != Self.normalize($0) }) {
            return accented
        }
        return candidates.first ?? ""
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
