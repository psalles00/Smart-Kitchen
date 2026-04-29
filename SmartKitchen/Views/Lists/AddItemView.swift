import SwiftUI
import SwiftData
import PhotosUI

/// Destination for a new item created from search suggestions.
enum AddItemDestination: String, CaseIterable {
    case pantry
    case grocery
    case utensil

    var label: String {
        switch self {
        case .pantry:   String(localized: "Despensa")
        case .grocery:  String(localized: "Mercado")
        case .utensil:  String(localized: "Utensílios")
        }
    }
}

/// Unified "Novo Item" modal opened from suggestion chips.
struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UnifiedItem.pantrySortOrder) private var pantryItems: [UnifiedItem]
    @Query(sort: \UnifiedItem.grocerySortOrder) private var groceryItems: [UnifiedItem]
    @Query(sort: \UnifiedItem.utensilSortOrder) private var utensilItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    var initialName: String = ""
    var initialIconFileName: String? = nil
    var initialCategory: String? = nil
    var onCreated: ((UUID, AddItemDestination) -> Void)? = nil

    @State private var name = ""
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var destination: AddItemDestination = .grocery
    @State private var quantity: Double?
    @State private var unit = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    #endif
    @State private var showPhotoPreview = false
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @State private var expiryMode: ExpiryInputMode = .date
    @State private var expiryDurationValue: Int = 7
    @State private var expiryDurationUnit: ExpiryDurationUnit = .days
    @State private var keepExpiryOnAcquire = false
    @State private var showIconPicker = false
    @State private var focusNameField = false

    private var settings: AppSettings? { settingsArray.first }
    private var showUtensils: Bool { settings?.showUtensils == true }
    private var availableDestinations: [AddItemDestination] {
        showUtensils ? AddItemDestination.allCases : [.pantry, .grocery]
    }
    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }
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

            Section("Destino") {
                Picker("Adicionar em", selection: $destination) {
                    ForEach(availableDestinations, id: \.self) { dest in
                        Text(dest.label).tag(dest)
                    }
                }
                .pickerStyle(.segmented)
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

                #if os(iOS)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(imageData == nil ? "Adicionar Foto" : "Alterar Foto", systemImage: "photo")
                }

                if imageData != nil {
                    Button("Remover Foto", role: .destructive) {
                        imageData = nil
                        selectedPhoto = nil
                    }
                }
                #endif
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

            if destination != .utensil {
                #if os(iOS)
                expirySection
                #endif
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .modalNavigationTitle(String(localized: "Novo Item"))
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
        #if os(iOS)
        .sheet(isPresented: $showPhotoPreview) {
            if let imageData, let image = PlatformImage(data: imageData) {
                PhotoPreviewSheetView(image: image)
            }
        }
        #endif
        #if os(iOS)
        .onChange(of: selectedPhoto) {
            loadPhoto()
        }
        #endif
        .onAppear {
            // Restore last used destination
            if let raw = settings?.lastAddItemDestinationRaw,
               let saved = AddItemDestination(rawValue: raw),
               availableDestinations.contains(saved) {
                destination = saved
            } else {
                destination = .grocery
            }

            if !initialName.isEmpty {
                name = initialName
            }
            if let fn = initialIconFileName {
                iconName = fn
            }
            if let cat = initialCategory, CategoryDatabase.shared.entry(for: cat) != nil {
                selectedCategory = cat
                userChangedCategory = true
            }
            if iconName == nil || selectedCategory == "Outros" {
                if let match = ItemDatabase.shared.preferredMatch(for: initialName) {
                    if iconName == nil { iconName = match.nomeDoArquivo }
                    if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
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

    private func applySelectedEntry(_ entry: ItemEntry) {
        name = entry.preferredTitle(matching: name)
        iconName = entry.nomeDoArquivo
        if CategoryDatabase.shared.entry(for: entry.categoria) != nil {
            selectedCategory = entry.categoria
        }
        userChangedCategory = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalIcon = iconName
        var finalCategory = selectedCategory

        if finalIcon == nil, let match = ItemDatabase.shared.preferredMatch(for: trimmed) {
            finalIcon = match.nomeDoArquivo
            if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
                finalCategory = match.categoria
            }
        }

        // Persist chosen destination
        settings?.lastAddItemDestinationRaw = destination.rawValue

        switch destination {
        case .grocery:
            let item = UnifiedItem(
                name: trimmed,
                descriptionText: trimmedDescription,
                imageData: imageData,
                category: finalCategory,
                quantity: quantity,
                unit: unit.isEmpty ? nil : unit,
                iconName: finalIcon,
                isPantry: false,
                isGrocery: true,
                isUtensil: false,
                grocerySortOrder: (groceryItems.filter(\.isGrocery).map(\.grocerySortOrder).max() ?? -1) + 1,
                defaultExpiryDays: hasExpirationDate ? computeExpiryDays() : nil,
                isFixed: false
            )
            modelContext.insert(item)
            onCreated?(item.id, .grocery)
        case .pantry:
            let item = UnifiedItem(
                name: trimmed,
                descriptionText: trimmedDescription,
                imageData: imageData,
                category: finalCategory,
                quantity: quantity,
                unit: unit.isEmpty ? nil : unit,
                iconName: finalIcon,
                isPantry: true,
                isGrocery: false,
                isUtensil: false,
                pantrySortOrder: (pantryItems.filter(\.isPantry).map(\.pantrySortOrder).max() ?? -1) + 1,
                expirationDate: hasExpirationDate ? expirationDate : nil,
                defaultExpiryDays: hasExpirationDate && keepExpiryOnAcquire ? computeExpiryDays() : nil
            )
            modelContext.insert(item)
            onCreated?(item.id, .pantry)
        case .utensil:
            let item = UnifiedItem(
                name: trimmed,
                category: finalCategory,
                iconName: finalIcon,
                isPantry: false,
                isGrocery: false,
                isUtensil: true,
                utensilSortOrder: (utensilItems.filter(\.isUtensil).map(\.utensilSortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
            onCreated?(item.id, .utensil)
        }

        dismiss()
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

                    Text(destination == .pantry
                         ? "Manter ao mover de Mercado para Despensa"
                         : "Validade aplicada ao mover para Despensa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

    #if os(iOS)
    private func loadPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                imageData = data
            }
        }
    }
    #endif
}
