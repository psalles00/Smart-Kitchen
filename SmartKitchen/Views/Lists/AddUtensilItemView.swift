import SwiftUI
import SwiftData
import PhotosUI

struct AddUtensilItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UtensilItem.sortOrder) private var allItems: [UtensilItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var showIconPicker = false
    @State private var focusNameField = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false

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
                    .padding(.vertical, 4)
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
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 450)
        #endif
        .navigationTitle("Novo Utensílio")
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
                fallbackSymbol: "fork.knife"
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
            descriptionText: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
            category: finalCategory,
            iconName: finalIcon,
            sortOrder: nextOrder
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

struct EditUtensilItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allEditCategories: [Category]

    @Bindable var item: UtensilItem
    @State private var showIconPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false

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
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 450)
        #endif
        .navigationTitle("Editar Utensílio")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.lists.accentColor)
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
