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

enum RecipeCustomOptionKind: String {
    case state
    case unit

    var placeholder: String {
        switch self {
        case .state: "Estado"
        case .unit: "Unidade"
        }
    }

    var customPromptTitle: String {
        switch self {
        case .state: "Novo estado"
        case .unit: "Nova unidade"
        }
    }

    var customPromptMessage: String {
        switch self {
        case .state: "Digite um estado personalizado"
        case .unit: "Digite uma unidade personalizada"
        }
    }

    var storageKey: String {
        "recipe.custom-options.\(rawValue)"
    }
}

enum RecipeCustomOptionsStore {
    static func customOptions(for kind: RecipeCustomOptionKind) -> [String] {
        guard let data = UserDefaults.standard.data(forKey: kind.storageKey),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    static func add(_ rawValue: String, for kind: RecipeCustomOptionKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let existingDefault = RecipeOptionCatalog.resolve(trimmed, for: kind) {
            return existingDefault.fullName
        }

        var values = customOptions(for: kind)
        if let existingCustom = values.first(where: {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existingCustom
        }

        values.append(trimmed)
        save(values, for: kind)
        return trimmed
    }

    static func remove(_ rawValue: String, for kind: RecipeCustomOptionKind) {
        let filtered = customOptions(for: kind).filter {
            $0.localizedCaseInsensitiveCompare(rawValue) != .orderedSame
        }
        save(filtered, for: kind)
    }

    private static func save(_ values: [String], for kind: RecipeCustomOptionKind) {
        let encoded = try? JSONEncoder().encode(values)
        UserDefaults.standard.set(encoded, forKey: kind.storageKey)
    }
}

struct RecipeOptionMenuField: View {
    let kind: RecipeCustomOptionKind
    @Binding var selection: String

    @State private var customOptions: [String] = []
    @State private var customValue = ""
    @State private var showCustomAlert = false

    var body: some View {
        Menu {
            Button {
                customValue = RecipeOptionCatalog.resolve(selection, for: kind)?.fullName ?? selection
                showCustomAlert = true
            } label: {
                Label("Personalizado", systemImage: "square.and.pencil")
            }

            Section("Sugestões") {
                ForEach(RecipeOptionCatalog.options(for: kind), id: \.fullName) { option in
                    optionButton(option.fullName, label: option.menuLabel)
                }
            }

            if !customOptions.isEmpty {
                Section("Personalizados") {
                    ForEach(customOptions, id: \.self) { option in
                        optionButton(option)
                    }

                    Menu("Apagar personalizados") {
                        ForEach(customOptions, id: \.self) { option in
                            Button(option, role: .destructive) {
                                if selection.localizedCaseInsensitiveCompare(option) == .orderedSame {
                                    selection = ""
                                }
                                RecipeCustomOptionsStore.remove(option, for: kind)
                                reloadCustomOptions()
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.isEmpty ? kind.placeholder : RecipeOptionCatalog.menuLabel(for: selection, kind: kind))
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: reloadCustomOptions)
        .alert(kind.customPromptTitle, isPresented: $showCustomAlert) {
            TextField(kind.customPromptMessage, text: $customValue)
            Button("Cancelar", role: .cancel) { }
            Button("Salvar") {
                let resolved = RecipeCustomOptionsStore.add(customValue, for: kind)
                if !resolved.isEmpty {
                    selection = resolved
                }
                reloadCustomOptions()
            }
        } message: {
            Text("Personalizado")
        }
    }

    private func optionButton(_ option: String, label: String? = nil) -> some View {
        Button {
            selection = option
        } label: {
            let displayLabel = label ?? option
            if isSelected(option) {
                Label(displayLabel, systemImage: "checkmark")
            } else {
                Text(displayLabel)
            }
        }
    }

    private func reloadCustomOptions() {
        customOptions = RecipeCustomOptionsStore.customOptions(for: kind)
    }

    private func isSelected(_ option: String) -> Bool {
        if selection.localizedCaseInsensitiveCompare(option) == .orderedSame {
            return true
        }

        return RecipeOptionCatalog.resolve(selection, for: kind)?.matches(option) == true
    }
}
