import SwiftUI
import SwiftData

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false

    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var isFixed = false
    @State private var showCategoryManager = false
    @State private var showIconPicker = false
    @State private var focusNameField = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Item") {
                ItemSearchField(
                    text: $name,
                    iconFileName: iconName,
                    fallbackSymbol: "basket",
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

            Section {
                Toggle("Item fixo", isOn: $isFixed)
            } footer: {
                Text("Itens fixos reaparecem automaticamente na lista ao serem marcados como concluídos.")
            }
        }
        .navigationTitle("Novo Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                fallbackSymbol: "basket"
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

        // Auto-match: if user typed a name but didn't pick from autocomplete
        if finalIcon == nil, let match = ItemDatabase.shared.exactMatch(for: trimmed) {
            finalIcon = match.nomeDoArquivo
            if !userChangedCategory,
               categories.contains(where: { $0.name == match.categoria }) {
                finalCategory = match.categoria
            }
        }

        let item = GroceryItem(
            name: trimmed,
            category: finalCategory,
            quantity: quantity,
            unit: unit.isEmpty ? nil : unit,
            iconName: finalIcon,
            isFixed: isFixed,
            sortOrder: (allItems.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(item)
        dismiss()
    }
}

// MARK: - Edit

struct EditGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allEditCategories: [Category]

    @Bindable var item: GroceryItem
    @State private var showCategoryManager = false
    @State private var showIconPicker = false

    private var categories: [Category] { allEditCategories.filter { $0.type == .pantry } }

    var body: some View {
        Form {
            Section("Item") {
                ItemSearchField(
                    text: $item.name,
                    iconFileName: item.iconName,
                    fallbackSymbol: "basket",
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

            Section {
                Toggle("Item fixo", isOn: $item.isFixed)
            }
        }
        .navigationTitle("Editar Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                fallbackSymbol: "basket"
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
