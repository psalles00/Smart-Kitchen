import SwiftUI
import SwiftData

/// Destination for a new item created from search suggestions.
enum AddItemDestination: String, CaseIterable {
    case pantry
    case grocery
    case utensil

    var label: String {
        switch self {
        case .pantry:   "Despensa"
        case .grocery:  "Mercado"
        case .utensil:  "Utensílios"
        }
    }
}

/// Unified "Novo Item" modal opened from suggestion chips.
struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PantryItem.sortOrder) private var pantryItems: [PantryItem]
    @Query(sort: \GroceryItem.sortOrder) private var groceryItems: [GroceryItem]
    @Query(sort: \UtensilItem.sortOrder) private var utensilItems: [UtensilItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    var initialName: String = ""
    var initialIconFileName: String? = nil
    var initialCategory: String? = nil

    @State private var name = ""
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var destination: AddItemDestination = .grocery
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var showIconPicker = false
    @State private var focusNameField = false

    private var settings: AppSettings? { settingsArray.first }
    private var showUtensils: Bool { settings?.showUtensils == true }
    private var availableDestinations: [AddItemDestination] {
        showUtensils ? AddItemDestination.allCases : [.pantry, .grocery]
    }
    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Item") {
                ItemSearchField(
                    text: $name,
                    iconFileName: iconName,
                    fallbackSymbol: "leaf",
                    isFocusedBinding: $focusNameField,
                    showsLeadingIcon: true,
                    onIconTapped: { showIconPicker = true }
                ) { (entry: ItemEntry) in
                    applySelectedEntry(entry)
                }

                CategorySelectionRow(
                    title: "Categoria",
                    categories: CategoryDatabase.shared.allCategories,
                    selection: $selectedCategory
                )
                .onChange(of: selectedCategory) { _, _ in
                    userChangedCategory = true
                }
            }

            Section("Destino") {
                Picker("Adicionar em", selection: $destination) {
                    ForEach(availableDestinations, id: \.self) { dest in
                        Text(dest.label).tag(dest)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Quantidade") {
                HStack {
                    TextField("Qtd", value: $quantity, format: .number)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(width: 80)
                    TextField("Unidade (kg, L, un...)", text: $unit)
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .navigationTitle("Novo Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.lists.accentColor)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(!isValid)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: name,
                currentIconFileName: iconName,
                fallbackSymbol: "leaf"
            ) { entry in
                iconName = entry.nomeDoArquivo
            }
            .forceLightStatusBar()
        }
        .onAppear {
            // Restore last used destination
            if let raw = settings?.lastAddItemDestinationRaw,
               let saved = AddItemDestination(rawValue: raw),
               availableDestinations.contains(saved) {
                destination = saved
            } else {
                destination = .grocery
            }

            if !initialName.isEmpty {
                name = initialName
            }
            if let fn = initialIconFileName {
                iconName = fn
            }
            if let cat = initialCategory, CategoryDatabase.shared.entry(for: cat) != nil {
                selectedCategory = cat
                userChangedCategory = true
            }
            if iconName == nil || selectedCategory == "Outros" {
                if let match = ItemDatabase.shared.exactMatch(for: initialName) {
                    if iconName == nil { iconName = match.nomeDoArquivo }
                    if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
                        selectedCategory = match.categoria
                        userChangedCategory = true
                    }
                }
            }
            DispatchQueue.main.async {
                focusNameField = true
            }
        }
    }

    private func applySelectedEntry(_ entry: ItemEntry) {
        name = entry.preferredTitle(matching: name)
        iconName = entry.nomeDoArquivo
        if CategoryDatabase.shared.entry(for: entry.categoria) != nil {
            selectedCategory = entry.categoria
        }
        userChangedCategory = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var finalIcon = iconName
        var finalCategory = selectedCategory

        if finalIcon == nil, let match = ItemDatabase.shared.exactMatch(for: trimmed) {
            finalIcon = match.nomeDoArquivo
            if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
                finalCategory = match.categoria
            }
        }

        // Persist chosen destination
        settings?.lastAddItemDestinationRaw = destination.rawValue

        switch destination {
        case .grocery:
            let item = GroceryItem(
                name: trimmed,
                category: finalCategory,
                quantity: quantity,
                unit: unit.isEmpty ? nil : unit,
                iconName: finalIcon,
                isFixed: false,
                sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        case .pantry:
            let item = PantryItem(
                name: trimmed,
                category: finalCategory,
                quantity: quantity,
                unit: unit.isEmpty ? nil : unit,
                iconName: finalIcon,
                sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        case .utensil:
            let item = UtensilItem(
                name: trimmed,
                category: finalCategory,
                iconName: finalIcon,
                sortOrder: (utensilItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        }

        dismiss()
    }
}
