import SwiftUI

struct ItemIconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let currentIconFileName: String?
    let fallbackSymbol: String
    let onItemSelected: (ItemEntry) -> Void

    @State private var searchText: String

    init(
        title: String = "Escolher Ícone",
        initialQuery: String,
        currentIconFileName: String? = nil,
        fallbackSymbol: String = "leaf",
        onItemSelected: @escaping (ItemEntry) -> Void
    ) {
        self.title = title
        self.currentIconFileName = currentIconFileName
        self.fallbackSymbol = fallbackSymbol
        self.onItemSelected = onItemSelected
        _searchText = State(initialValue: initialQuery)
    }

    private var results: [ItemEntry] {
        let matches = ItemDatabase.shared.search(
            query: searchText,
            limit: 60,
            fallbackToFeatured: true
        )

        guard let currentIconFileName,
              let currentEntry = ItemDatabase.shared.entry(forFilename: currentIconFileName),
              !matches.contains(where: { $0.nomeDoArquivo == currentEntry.nomeDoArquivo }) else {
            return matches
        }

        return [currentEntry] + matches
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView(
                        "Nenhum ícone encontrado",
                        systemImage: "magnifyingglass",
                        description: Text("Tente buscar com outro termo.")
                    )
                } else {
                    List(results, id: \.nomeDoArquivo) { entry in
                        Button {
                            onItemSelected(entry)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconImage(
                                    name: entry.preferredTitle(matching: searchText),
                                    iconFileName: entry.nomeDoArquivo,
                                    fallbackSymbol: fallbackSymbol,
                                    size: 28,
                                    showBalloon: true
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.preferredTitle(matching: searchText))
                                        .foregroundStyle(.primary)
                                    Text(entry.categoria)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if entry.nomeDoArquivo == currentIconFileName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Buscar item ou utensílio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
