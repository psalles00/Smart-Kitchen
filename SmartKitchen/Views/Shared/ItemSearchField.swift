import SwiftUI

/// A text field with autocomplete suggestions from the item database.
/// When the user types ≥2 characters, matching items appear in a dropdown.
struct ItemSearchField: View {
    @Binding var text: String
    var placeholder: String = "Nome"
    var onItemSelected: ((ItemEntry) -> Void)?

    @State private var suggestions: [ItemEntry] = []
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    updateSuggestions(for: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        // Small delay so tap on suggestion can register
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if !isFocused { showSuggestions = false }
                        }
                    }
                }

            if showSuggestions && !suggestions.isEmpty {
                suggestionsList
            }
        }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.nomeDoArquivo) { entry in
                Button {
                    selectItem(entry)
                } label: {
                    HStack(spacing: 10) {
                        IconImage(
                            name: "",
                            iconFileName: entry.nomeDoArquivo,
                            fallbackSymbol: "leaf",
                            size: 28,
                            showBalloon: true
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            // Show the best matching title
                            Text(bestTitle(for: entry))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(entry.categoria)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if entry.nomeDoArquivo != suggestions.last?.nomeDoArquivo {
                    Divider()
                        .padding(.leading, 42)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 4)
    }

    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2 {
            suggestions = ItemDatabase.shared.search(query: trimmed)
            showSuggestions = !suggestions.isEmpty
        } else {
            suggestions = []
            showSuggestions = false
        }
    }

    private func selectItem(_ entry: ItemEntry) {
        text = bestTitle(for: entry)
        showSuggestions = false
        suggestions = []
        onItemSelected?(entry)
    }

    /// Find the best title to display — prefer the PT-BR one that starts with query.
    private func bestTitle(for entry: ItemEntry) -> String {
        let query = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        // Prefer titles that start with the query
        if let match = entry.titulos.first(where: {
            $0.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
                .hasPrefix(query)
        }) {
            return match
        }

        // Prefer non-ASCII titles (Portuguese) over English
        if let pt = entry.titulos.first(where: { $0.unicodeScalars.contains(where: { $0.value > 127 }) }) {
            return pt
        }

        return entry.titulos.first ?? ""
    }
}
