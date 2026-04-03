import Foundation

extension ItemEntry {
    func preferredTitle(matching query: String? = nil) -> String {
        let normalizedQuery = Self.normalize(query ?? "")

        if !normalizedQuery.isEmpty,
           let match = titulos.first(where: { Self.normalize($0).hasPrefix(normalizedQuery) }) {
            return match
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
