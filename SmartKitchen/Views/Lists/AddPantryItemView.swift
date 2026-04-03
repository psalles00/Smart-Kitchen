import SwiftUI
import SwiftData

struct AddPantryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \PantryItem.sortOrder) private var allItems: [PantryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var isLinkedToGrocery = false
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @State private var showCategoryManager = false
    @State private var showIconPicker = false
    @State private var focusNameField = false

    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    private var isDetailed: Bool { settingsArray.first?.pantryDetailLevel == .detailed }
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
                ) { entry in
                    applySelectedEntry(entry)
                }

                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
                .onChange(of: selectedCategory) { _, _ in
                    userChangedCategory = true
                }
            }

            if isDetailed {
                Section("Quantidade") {
                    HStack {
                        TextField("Qtd", value: $quantity, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                        TextField("Unidade (kg, L, x...)", text: $unit)
                    }
                }
            }

            Section("Validade") {
                Toggle("Possui validade", isOn: $hasExpirationDate.animation())

                if hasExpirationDate {
                    DatePicker("Validade", selection: $expirationDate, displayedComponents: .date)
                }
            }

            Section {
                Toggle("Fixo no mercado", isOn: $isLinkedToGrocery)
            } footer: {
                Text("Quando ativado, o item aparece automaticamente na lista de mercado ao ser removido da despensa.")
            }
        }
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
            ToolbarItem(placement: .adaptiveTrailing) {
                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .pantry)
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: name,
                currentIconFileName: iconName,
                fallbackSymbol: "leaf"
            ) { entry in
                iconName = entry.nomeDoArquivo
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                focusNameField = true
            }
        }
    }

    private func applySelectedEntry(_ entry: ItemEntry) {
        name = entry.preferredTitle(matching: name)
        iconName = entry.nomeDoArquivo
        if categories.contains(where: { $0.name == entry.categoria }) {
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
            if !userChangedCategory,
               categories.contains(where: { $0.name == match.categoria }) {
                finalCategory = match.categoria
            }
        }

        let item = PantryItem(
            name: trimmed,
            category: finalCategory,
            quantity: isDetailed ? quantity : nil,
            unit: isDetailed ? (unit.isEmpty ? nil : unit) : nil,
            iconName: finalIcon,
            isLinkedToGrocery: isLinkedToGrocery,
            expirationDate: hasExpirationDate ? expirationDate : nil,
            sortOrder: (allItems.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(item)
        dismiss()
    }
}

// MARK: - Edit

struct EditPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Category.sortOrder) private var allEditCategories: [Category]

    @Bindable var item: PantryItem
    @State private var showCategoryManager = false
    @State private var showIconPicker = false

    private var categories: [Category] { allEditCategories.filter { $0.type == .pantry } }
    private var isDetailed: Bool { settingsArray.first?.pantryDetailLevel == .detailed }

    var body: some View {
        Form {
            Section("Item") {
                ItemSearchField(
                    text: $item.name,
                    iconFileName: item.iconName,
                    fallbackSymbol: "leaf",
                    showsLeadingIcon: true,
                    onIconTapped: { showIconPicker = true }
                ) { entry in
                    applySelectedEntry(entry)
                }

                Picker("Categoria", selection: $item.category) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
            }

            if isDetailed {
                Section("Quantidade") {
                    HStack {
                        TextField("Qtd", value: $item.quantity, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                        TextField("Unidade", text: Binding(
                            get: { item.unit ?? "" },
                            set: { item.unit = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }
            }

            Section("Validade") {
                Toggle("Possui validade", isOn: Binding(
                    get: { item.expirationDate != nil },
                    set: { hasDate in
                        if hasDate {
                            item.expirationDate = item.expirationDate ?? Date()
                        } else {
                            item.expirationDate = nil
                        }
                    }
                ))

                if item.expirationDate != nil {
                    DatePicker("Validade", selection: Binding(
                        get: { item.expirationDate ?? Date() },
                        set: { item.expirationDate = $0 }
                    ), displayedComponents: .date)
                }
            }

            Section {
                Toggle("Fixo no mercado", isOn: $item.isLinkedToGrocery)
            }
        }
        .navigationTitle("Editar Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.lists.accentColor)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
            ToolbarItem(placement: .adaptiveTrailing) {
                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .pantry)
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: item.name,
                currentIconFileName: item.iconName,
                fallbackSymbol: "leaf"
            ) { entry in
                item.iconName = entry.nomeDoArquivo
            }
        }
    }

    private func applySelectedEntry(_ entry: ItemEntry) {
        item.name = entry.preferredTitle(matching: item.name)
        item.iconName = entry.nomeDoArquivo
        if categories.contains(where: { $0.name == entry.categoria }) {
            item.category = entry.categoria
        }
    }
}
