import SwiftUI
import SwiftData

struct AddUtensilItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UtensilItem.sortOrder) private var allItems: [UtensilItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var showIconPicker = false
    @State private var focusNameField = false

    private var categories: [Category] { allCategories.filter { $0.type == .utensil } }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Utensílio") {
                ItemSearchField(
                    text: $name,
                    iconFileName: iconName,
                    fallbackSymbol: "fork.knife",
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
        }
        .navigationTitle("Novo Utensílio")
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
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: name,
                currentIconFileName: iconName,
                fallbackSymbol: "fork.knife"
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
        guard !trimmed.isEmpty else { return }

        var finalIcon = iconName
        var finalCategory = selectedCategory

        if finalIcon == nil, let match = ItemDatabase.shared.exactMatch(for: trimmed) {
            finalIcon = match.nomeDoArquivo
            if !userChangedCategory,
               categories.contains(where: { $0.name == match.categoria }) {
                finalCategory = match.categoria
            }
        }

        let nextOrder = (allItems.map(\.sortOrder).max() ?? -1) + 1
        let item = UtensilItem(
            name: trimmed,
            category: finalCategory,
            iconName: finalIcon,
            sortOrder: nextOrder
        )
        modelContext.insert(item)
        dismiss()
    }
}

struct EditUtensilItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allEditCategories: [Category]

    @Bindable var item: UtensilItem
    @State private var showIconPicker = false

    private var categories: [Category] { allEditCategories.filter { $0.type == .utensil } }

    var body: some View {
        Form {
            Section("Utensílio") {
                ItemSearchField(
                    text: $item.name,
                    iconFileName: item.iconName,
                    fallbackSymbol: "fork.knife",
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
        }
        .navigationTitle("Editar Utensílio")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: item.name,
                currentIconFileName: item.iconName,
                fallbackSymbol: "fork.knife"
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
