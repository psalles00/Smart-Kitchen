import SwiftUI
import SwiftData
import PhotosUI

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    var initialName: String = ""

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false

    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var hasDefaultExpiry = false
    @State private var expiryDurationValue: Int = 7
    @State private var expiryDurationUnit: ExpiryDurationUnit = .days
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

                CategorySelectionRow(
                    title: "Categoria",
                    categories: CategoryDatabase.shared.allCategories,
                    selection: $selectedCategory
                )
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

            Section("Validade") {
                Toggle("Usar validade ao mover para despensa", isOn: $hasDefaultExpiry.animation())

                if hasDefaultExpiry {
                    HStack(spacing: 0) {
                        Picker("Quantidade", selection: $expiryDurationValue) {
                            ForEach(1...365, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                        .clipped()
                        #else
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        #endif

                        Picker("Unidade", selection: $expiryDurationUnit) {
                            Text("dias").tag(ExpiryDurationUnit.days)
                            Text("meses").tag(ExpiryDurationUnit.months)
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 120)
                        .clipped()
                        #else
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        #endif
                    }
                }
            }

        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .navigationTitle("Novo Item")
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
                fallbackSymbol: "basket"
            ) { entry in
                iconName = entry.nomeDoArquivo
            }
            .forceLightStatusBar()
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
            if !initialName.isEmpty {
                name = initialName
            }
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
            isFixed: false,
            defaultExpiryDays: hasDefaultExpiry ? computeGroceryExpiryDays() : nil,
            sortOrder: (allItems.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(item)
        dismiss()
    }

    private func computeGroceryExpiryDays() -> Int {
        expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
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
    @Bindable var item: GroceryItem
    @State private var showIconPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false
    @State private var expiryDurationValue: Int = 7
    @State private var expiryDurationUnit: ExpiryDurationUnit = .days

    #if os(macOS)
    @State private var didConfirm = false
    @State private var snapshotName = ""
    @State private var snapshotDescription = ""
    @State private var snapshotImageData: Data?
    @State private var snapshotCategory = ""
    @State private var snapshotQuantity: Double?
    @State private var snapshotUnit: String?
    @State private var snapshotIconName: String?
    @State private var snapshotDefaultExpiryDays: Int?
    #endif

    private let categories = CategoryDatabase.shared.allCategories

    private var categoryIconFileName: String? {
        CategoryDatabase.shared.entry(for: item.category)?.iconFileName
    }

    var body: some View {
        Form {
            Section("Item") {
                ItemSearchField(
                    text: $item.name,
                    iconFileName: item.iconName,
                    placeholderIconFileName: categoryIconFileName,
                    fallbackSymbol: "basket",
                    showsLeadingIcon: true,
                    onIconTapped: { showIconPicker = true }
                ) { entry in
                    applySelectedEntry(entry)
                }

                CategorySelectionRow(
                    title: "Categoria",
                    categories: categories,
                    selection: $item.category
                )
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

            Section("Validade") {
                Toggle("Usar validade ao mover para despensa", isOn: Binding(
                    get: { item.defaultExpiryDays != nil },
                    set: { hasExpiry in
                        withAnimation {
                            if hasExpiry {
                                item.defaultExpiryDays = expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
                            } else {
                                item.defaultExpiryDays = nil
                            }
                        }
                    }
                ))

                if item.defaultExpiryDays != nil {
                    HStack(spacing: 0) {
                        Picker("Quantidade", selection: $expiryDurationValue) {
                            ForEach(1...365, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                        .clipped()
                        #else
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        #endif

                        Picker("Unidade", selection: $expiryDurationUnit) {
                            Text("dias").tag(ExpiryDurationUnit.days)
                            Text("meses").tag(ExpiryDurationUnit.months)
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 120)
                        .clipped()
                        #else
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        #endif
                    }
                    .onChange(of: expiryDurationValue) { _, _ in
                        item.defaultExpiryDays = expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
                    }
                    .onChange(of: expiryDurationUnit) { _, _ in
                        item.defaultExpiryDays = expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
                    }
                }
            }

        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .navigationTitle("Editar Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(PageTheme.lists.accentColor)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") {
                    #if os(macOS)
                    didConfirm = true
                    #endif
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: item.name,
                currentIconFileName: item.iconName,
                fallbackSymbol: "basket"
            ) { entry in
                item.iconName = entry.nomeDoArquivo
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                PhotoPreviewSheetView(image: image)
            }
        }
        .onChange(of: selectedPhoto) {
            loadPhoto()
        }
        .onAppear {
            if let days = item.defaultExpiryDays, days > 0 {
                if days >= 30 && days % 30 == 0 {
                    expiryDurationUnit = .months
                    expiryDurationValue = max(1, days / 30)
                } else {
                    expiryDurationUnit = .days
                    expiryDurationValue = days
                }
            }
            #if os(macOS)
            snapshotName = item.name
            snapshotDescription = item.descriptionText
            snapshotImageData = item.imageData
            snapshotCategory = item.category
            snapshotQuantity = item.quantity
            snapshotUnit = item.unit
            snapshotIconName = item.iconName
            snapshotDefaultExpiryDays = item.defaultExpiryDays
            #endif
        }
        #if os(macOS)
        .onDisappear {
            if !didConfirm {
                item.name = snapshotName
                item.descriptionText = snapshotDescription
                item.imageData = snapshotImageData
                item.category = snapshotCategory
                item.quantity = snapshotQuantity
                item.unit = snapshotUnit
                item.iconName = snapshotIconName
                item.defaultExpiryDays = snapshotDefaultExpiryDays
            }
        }
        #endif
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
