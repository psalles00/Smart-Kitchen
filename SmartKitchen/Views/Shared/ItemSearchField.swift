import SwiftUI

/// A text field with autocomplete suggestions from the item database.
struct ItemSearchField: View {
    @Binding var text: String
    var placeholder: String = "Nome"
    var iconFileName: String? = nil
    var fallbackSymbol: String = "leaf"
    var isFocusedBinding: Binding<Bool>? = nil
    var showsLeadingIcon = false
    var onIconTapped: (() -> Void)? = nil
    var onItemSelected: ((ItemEntry) -> Void)?

    @State private var suggestions: [ItemEntry] = []
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if showsLeadingIcon {
                    iconView
                }

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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if !isFocused { showSuggestions = false }
                            }
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        isFocusedBinding?.wrappedValue = focused
                    }

                Button {
                    toggleSuggestions()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showSuggestions ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mostrar sugestões")
            }

            if showSuggestions && !suggestions.isEmpty {
                suggestionsList
            }
        }
        .onAppear {
            if isFocusedBinding?.wrappedValue == true {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
        }
        .onChange(of: isFocusedBinding?.wrappedValue ?? false) { _, shouldFocus in
            guard shouldFocus != isFocused else { return }
            isFocused = shouldFocus
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let onIconTapped {
            Button(action: onIconTapped) {
                itemIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Escolher ícone")
        } else {
            itemIcon
        }
    }

    private var itemIcon: some View {
        IconImage(
            name: text,
            iconFileName: iconFileName,
            fallbackSymbol: fallbackSymbol,
            size: 28,
            showBalloon: true
        )
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
                            fallbackSymbol: fallbackSymbol,
                            size: 28,
                            showBalloon: true
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.preferredTitle(matching: text))
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

    private func updateSuggestions(for query: String, fallbackToFeatured: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        suggestions = ItemDatabase.shared.search(
            query: trimmed,
            fallbackToFeatured: fallbackToFeatured
        )
        showSuggestions = !suggestions.isEmpty

        if trimmed.isEmpty && !fallbackToFeatured {
            suggestions = []
            showSuggestions = false
        }
    }

    private func selectItem(_ entry: ItemEntry) {
        let resolvedTitle = entry.preferredTitle(matching: text)
        isFocused = false
        showSuggestions = false
        suggestions = []

        if let onItemSelected {
            onItemSelected(entry)
        } else {
            text = resolvedTitle
        }
    }

    private func toggleSuggestions() {
        if showSuggestions {
            showSuggestions = false
            return
        }

        isFocused = true
        updateSuggestions(for: text, fallbackToFeatured: true)
    }
}
