import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Expiry Input Helpers

enum ExpiryInputMode: String, CaseIterable {
    case date, duration
}

enum ExpiryDurationUnit: String, CaseIterable {
    case days, months
}

struct AddPantryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \PantryItem.sortOrder) private var allItems: [PantryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    var initialName: String = ""

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @State private var expiryMode: ExpiryInputMode = .date
    @State private var expiryDurationValue: Int = 7
    @State private var expiryDurationUnit: ExpiryDurationUnit = .days
    @State private var keepExpiryOnAcquire = false
    @State private var showIconPicker = false
    @State private var focusNameField = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false

    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
    private var isDetailed: Bool { settingsArray.first?.pantryDetailLevel == .detailed }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            itemSection
            detailsSection
            if isDetailed {
                quantitySection
            }
            expirySection
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 600)
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
                if let match = ItemDatabase.shared.exactMatch(for: initialName) {
                    iconName = match.nomeDoArquivo
                    if categories.contains(where: { $0.name == match.categoria }) {
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

    @ViewBuilder
    private var itemSection: some View {
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
    }

    @ViewBuilder
    private var detailsSection: some View {
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

    @ViewBuilder
    private var quantitySection: some View {
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

    @ViewBuilder
    private var expirySection: some View {
        Section("Validade") {
            Toggle("Possui validade", isOn: $hasExpirationDate.animation())

            if hasExpirationDate {
                Picker("Modo", selection: $expiryMode.animation()) {
                    Text("Duração").tag(ExpiryInputMode.duration)
                    Text("Data").tag(ExpiryInputMode.date)
                }
                .pickerStyle(.segmented)

                if expiryMode == .duration {
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
                    .onChange(of: expiryDurationValue) { _, _ in syncDateFromDuration() }
                    .onChange(of: expiryDurationUnit) { _, _ in syncDateFromDuration() }
                } else {
                    DatePicker("Validade", selection: $expirationDate, in: Date()..., displayedComponents: .date)
                        .onChange(of: expirationDate) { _, newDate in
                            syncDurationFromDate(newDate)
                        }
                }

                if expiryMode == .duration {
                    Toggle("Manter ao mover", isOn: $keepExpiryOnAcquire)
                        .toggleStyle(.switch)

                    Text("Manter ao mover de Mercado para Despensa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            descriptionText: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
            category: finalCategory,
            quantity: isDetailed ? quantity : nil,
            unit: isDetailed ? (unit.isEmpty ? nil : unit) : nil,
            iconName: finalIcon,
            isLinkedToGrocery: false,
            expirationDate: hasExpirationDate ? expirationDate : nil,
            defaultExpiryDays: hasExpirationDate && keepExpiryOnAcquire ? computeExpiryDays() : nil,
            sortOrder: (allItems.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(item)
        dismiss()
    }

    private func syncDurationFromDate(_ date: Date) {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days >= 30 && days % 30 <= 2 {
            expiryDurationUnit = .months
            expiryDurationValue = max(1, days / 30)
        } else {
            expiryDurationUnit = .days
            expiryDurationValue = max(1, days)
        }
    }

    private func syncDateFromDuration() {
        let component: Calendar.Component = expiryDurationUnit == .months ? .month : .day
        expirationDate = Calendar.current.date(byAdding: component, value: expiryDurationValue, to: Date()) ?? Date()
    }

    private func computeExpiryDays() -> Int {
        if expiryMode == .duration {
            return expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
        }
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: expirationDate)).day ?? 0)
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

struct EditPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]
    @Bindable var item: PantryItem
    @State private var showIconPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPreview = false
    @State private var expiryMode: ExpiryInputMode = .duration
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
    @State private var snapshotExpirationDate: Date?
    @State private var snapshotDefaultExpiryDays: Int?
    @State private var snapshotIsLinkedToGrocery = false
    #endif

    private let categories = CategoryDatabase.shared.allCategories

    private var categoryIconFileName: String? {
        CategoryDatabase.shared.entry(for: item.category)?.iconFileName
    }
    private var isDetailed: Bool { settingsArray.first?.pantryDetailLevel == .detailed }

    var body: some View {
        Form {
            itemSectionEdit
            detailsSectionEdit
            if isDetailed {
                quantitySectionEdit
            }
            expirySectionEdit
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
                fallbackSymbol: "leaf"
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
            if let date = item.expirationDate {
                editSyncDurationFromDate(date)
            }
            #if os(macOS)
            snapshotName = item.name
            snapshotDescription = item.descriptionText
            snapshotImageData = item.imageData
            snapshotCategory = item.category
            snapshotQuantity = item.quantity
            snapshotUnit = item.unit
            snapshotIconName = item.iconName
            snapshotExpirationDate = item.expirationDate
            snapshotDefaultExpiryDays = item.defaultExpiryDays
            snapshotIsLinkedToGrocery = item.isLinkedToGrocery
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
                item.expirationDate = snapshotExpirationDate
                item.defaultExpiryDays = snapshotDefaultExpiryDays
                item.isLinkedToGrocery = snapshotIsLinkedToGrocery
            }
        }
        #endif
    }

    @ViewBuilder
    private var itemSectionEdit: some View {
        Section("Item") {
            ItemSearchField(
                text: $item.name,
                iconFileName: item.iconName,
                placeholderIconFileName: categoryIconFileName,
                fallbackSymbol: "leaf",
                showsLeadingIcon: true,
                onIconTapped: { showIconPicker = true }
            ) { (entry: ItemEntry) in
                applySelectedEntry(entry)
            }

            CategorySelectionRow(
                title: "Categoria",
                categories: categories,
                selection: $item.category
            )
        }
    }

    @ViewBuilder
    private var detailsSectionEdit: some View {
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

    @ViewBuilder
    private var quantitySectionEdit: some View {
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

    @ViewBuilder
    private var expirySectionEdit: some View {
        Section("Validade") {
            Toggle("Possui validade", isOn: Binding(
                get: { item.expirationDate != nil },
                set: { hasDate in
                    withAnimation {
                        if hasDate {
                            item.expirationDate = item.expirationDate ?? Date()
                        } else {
                            item.expirationDate = nil
                        }
                    }
                }
            ))

            if item.expirationDate != nil {
                Picker("Modo", selection: $expiryMode.animation()) {
                    Text("Duração").tag(ExpiryInputMode.duration)
                    Text("Data").tag(ExpiryInputMode.date)
                }
                .pickerStyle(.segmented)

                if expiryMode == .duration {
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
                    .onChange(of: expiryDurationValue) { _, _ in editSyncDateFromDuration() }
                    .onChange(of: expiryDurationUnit) { _, _ in editSyncDateFromDuration() }
                } else {
                    DatePicker("Validade", selection: Binding(
                        get: { item.expirationDate ?? Date() },
                        set: { newDate in
                            item.expirationDate = newDate
                            editSyncDurationFromDate(newDate)
                        }
                    ), in: Date()..., displayedComponents: .date)
                }

                if expiryMode == .duration {
                    Toggle("Manter ao mover de Mercado para Despensa", isOn: Binding(
                        get: { item.defaultExpiryDays != nil },
                        set: { keep in
                            if keep {
                                item.defaultExpiryDays = editComputeExpiryDays()
                            } else {
                                item.defaultExpiryDays = nil
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }
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

    private func loadPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                item.imageData = data
            }
        }
    }

    private func editSyncDurationFromDate(_ date: Date) {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days >= 30 && days % 30 <= 2 {
            expiryDurationUnit = .months
            expiryDurationValue = max(1, days / 30)
        } else {
            expiryDurationUnit = .days
            expiryDurationValue = max(1, days)
        }
    }

    private func editSyncDateFromDuration() {
        let component: Calendar.Component = expiryDurationUnit == .months ? .month : .day
        item.expirationDate = Calendar.current.date(byAdding: component, value: expiryDurationValue, to: Date()) ?? Date()
    }

    private func editComputeExpiryDays() -> Int {
        if expiryMode == .duration {
            return expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
        }
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: item.expirationDate ?? Date())).day ?? 0)
    }
}
