import SwiftUI
import SwiftData
import PhotosUI

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false

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

            Section("Detalhes") {
                TextField("Descrição (opcional)", text: $descriptionText, axis: .vertical)
                    .lineLimit(3...5)

                if let imageData, let image = PlatformImage(data: imageData) {
                    Button {
                        showPhotoPreview = true
                    } label: {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(imageData == nil ? "Adicionar Foto" : "Alterar Foto", systemImage: "photo")
                }

                if imageData != nil {
                    Button("Remover Foto", role: .destructive) {
                        imageData = nil
                        selectedPhoto = nil
                    }
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
                fallbackSymbol: "basket"
            ) { entry in
                iconName = entry.nomeDoArquivo
            }
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let imageData, let image = PlatformImage(data: imageData) {
                PhotoPreviewSheetView(image: image)
            }
        }
        .onChange(of: selectedPhoto) {
            loadPhoto()
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
            descriptionText: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
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

    private func loadPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                imageData = data
            }
        }
    }
}

// MARK: - Edit

struct EditGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allEditCategories: [Category]

    @Bindable var item: GroceryItem
    @State private var showCategoryManager = false
    @State private var showIconPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false

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

            Section("Detalhes") {
                TextField("Descrição (opcional)", text: $item.descriptionText, axis: .vertical)
                    .lineLimit(3...5)

                if let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                    Button {
                        showPhotoPreview = true
                    } label: {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(item.imageData == nil ? "Adicionar Foto" : "Alterar Foto", systemImage: "photo")
                }

                if item.imageData != nil {
                    Button("Remover Foto", role: .destructive) {
                        item.imageData = nil
                        selectedPhoto = nil
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
                fallbackSymbol: "basket"
            ) { entry in
                item.iconName = entry.nomeDoArquivo
            }
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                PhotoPreviewSheetView(image: image)
            }
        }
        .onChange(of: selectedPhoto) {
            loadPhoto()
        }
    }

    private func applySelectedEntry(_ entry: ItemEntry) {
        item.name = entry.preferredTitle(matching: item.name)
        item.iconName = entry.nomeDoArquivo
        if categories.contains(where: { $0.name == entry.categoria }) {
            item.category = entry.categoria
        }
    }

    private func loadPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                item.imageData = data
            }
        }
    }
}
