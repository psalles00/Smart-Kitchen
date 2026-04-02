import SwiftUI
import SwiftData

struct AddUtensilItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UtensilItem.sortOrder) private var allItems: [UtensilItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var selectedCategory = "Outros"

    private var categories: [Category] { allCategories.filter { $0.type == .utensil } }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Utensílio") {
                TextField("Nome", text: $name)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
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

        let nextOrder = (allItems.map(\.sortOrder).max() ?? -1) + 1
        let item = UtensilItem(
            name: trimmed,
            category: selectedCategory,
            sortOrder: nextOrder
        )
        modelContext.insert(item)
        dismiss()
    }
}
