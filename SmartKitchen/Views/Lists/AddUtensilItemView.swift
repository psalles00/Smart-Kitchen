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

    private var categories: [Category] { allCategories.filter { $0.type == .utensil } }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Utensílio") {
                ItemSearchField(text: $name) { entry in
                    iconName = entry.nomeDoArquivo
                    if categories.contains(where: { $0.name == entry.categoria }) {
                        selectedCategory = entry.categoria
                    }
                    userChangedCategory = true
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
