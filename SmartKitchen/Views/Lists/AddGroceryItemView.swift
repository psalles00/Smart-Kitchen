import SwiftUI
import SwiftData

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var selectedCategory = "Outros"

    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var isFixed = false
    @State private var showCategoryManager = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Nome", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
            }

            Section("Quantidade") {
                HStack {
                    TextField("Qtd", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(!isValid)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
    }

    private func save() {
        let item = GroceryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            category: selectedCategory,
            quantity: quantity,
            unit: unit.isEmpty ? nil : unit,
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

    private var categories: [Category] { allEditCategories.filter { $0.type == .pantry } }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Nome", text: $item.name)
                    .textInputAutocapitalization(.words)

                Picker("Categoria", selection: $item.category) {
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
            }

            Section("Quantidade") {
                HStack {
                    TextField("Qtd", value: $item.quantity, format: .number)
                        .keyboardType(.decimalPad)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
    }
}
