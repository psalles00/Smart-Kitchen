import Foundation

extension ItemEntry {
    func preferredTitle(matching query: String? = nil) -> String {
        let normalizedQuery = Self.normalize(query ?? "")

        if !normalizedQuery.isEmpty {
            let matches = titulos.filter { Self.normalize($0).hasPrefix(normalizedQuery) }
            if !matches.isEmpty {
                // Prefer the title that contains diacritics (e.g. "Limão" over "Limao")
                if let accented = matches.first(where: { $0.lowercased() != Self.normalize($0) }) {
                    return accented
                }
                return matches[0]
            }
        }

        return titulos.first ?? ""
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
