import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Item Detail Mode

enum ItemListType: String, CaseIterable, Identifiable {
    case pantry
    case grocery
    case utensil

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pantry:  "Despensa"
        case .grocery: "Mercado"
        case .utensil: "Utensílio"
        }
    }

    var icon: String {
        switch self {
        case .pantry:  "cabinet"
        case .grocery: "cart"
        case .utensil: "fork.knife"
        }
    }

    var color: Color {
        switch self {
        case .pantry:  Color(red: 37/255, green: 79/255, blue: 34/255)
        case .grocery: Color(red: 160/255, green: 58/255, blue: 19/255)
        case .utensil: Color.purple
        }
    }
}

enum ItemDetailMode {
    case create(destinations: Set<ItemListType> = [.grocery])
    case edit(UnifiedItem)
}

// MARK: - View

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allUnifiedItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    let mode: ItemDetailMode

    // Create-mode initial data
    var initialName: String = ""
    var initialIconFileName: String? = nil
    var initialCategory: String? = nil
    var onCreated: ((UUID, ItemListType) -> Void)? = nil

    // MARK: - Shared State

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var imageData: Data?
    @State private var selectedCategory = "Outros"
    @State private var iconName: String?
    @State private var userChangedCategory = false
    @State private var selectedLists: Set<ItemListType> = [.grocery]

    @State private var quantity: Double?
    @State private var unit = ""
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @State private var expiryMode: ExpiryInputMode = .date
    @State private var expiryDurationValue: Int = 7
    @State private var expiryDurationUnit: ExpiryDurationUnit = .days
    @State private var keepExpiryOnAcquire = false

    @State private var suggestions: [ItemEntry] = []
    @State private var showSuggestions = false
    @State private var showIconPicker = false
    @State private var showPhotoPreview = false
    @State private var showCategorySelection = false
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var nameFieldFocused: Bool

    private var settings: AppSettings? { settingsArray.first }
    private var showUtensils: Bool { settings?.showUtensils == true }
    private var isDetailed: Bool { settings?.pantryDetailLevel == .detailed }
    private var categories: [Category] { allCategories.filter { $0.type == .pantry } }

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var isUtensil: Bool {
        if let item = editingItem { return item.isUtensil && !item.isPantry && !item.isGrocery }
        return selectedLists == [.utensil]
    }

    private var showUtensilOption: Bool {
        switch mode {
        case .create: return showUtensils
        case .edit: return false
        }
    }

    private var hasPantry: Bool { selectedLists.contains(.pantry) }
    private var hasGrocery: Bool { selectedLists.contains(.grocery) }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // Edit-mode binding
    private var editingItem: UnifiedItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Icon area
                iconHeader
                    .padding(.top, 20)

                // Name field
                nameSection
                    .padding(.top, 12)

                // Category
                categorySection
                    .padding(.top, 4)

                // Suggestion chips (below category)
                suggestionsSection

                // List toggle
                listToggleSection
                    .padding(.top, 20)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                // Description + Photo
                descriptionPhotoSection
                    .padding(.top, 16)

                // Expiry (conditional)
                if (hasPantry || hasGrocery) && !isUtensil {
                    expirySection
                        .padding(.top, 16)
                }

                // Quantity (always show when not utensil)
                if !isUtensil {
                    quantitySection
                        .padding(.top, 16)
                }

                // Save button (create mode only)
                if isCreateMode {
                    saveButton
                        .padding(.top, 28)
                        .padding(.bottom, 20)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.medium, .large])
        #endif
        .tint(PageTheme.lists.accentColor)
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                initialQuery: name,
                currentIconFileName: iconName,
                fallbackSymbol: "leaf"
            ) { entry in
                if isCreateMode {
                    iconName = entry.nomeDoArquivo
                } else {
                    editingItem?.iconName = entry.nomeDoArquivo
                    iconName = entry.nomeDoArquivo
                }
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let data = resolvedImageData, let image = PlatformImage(data: data) {
                PhotoPreviewSheetView(image: image)
            }
        }
        .sheet(isPresented: $showCategorySelection) {
            NavigationStack {
                CategorySelectionView(
                    title: "Categoria",
                    categories: CategoryDatabase.shared.allCategories,
                    selection: isCreateMode ? $selectedCategory : editCategoryBinding
                )
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedPhoto) {
            loadPhoto()
        }
        .onChange(of: selectedLists) { _, newLists in
            if let item = editingItem {
                item.isPantry = newLists.contains(.pantry)
                item.isGrocery = newLists.contains(.grocery)
                item.isUtensil = newLists.contains(.utensil)
            }
        }
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - Icon Header

    private var currentIconName: String? {
        iconName ?? editingItem?.iconName
    }

    private var currentName: String {
        name
    }

    private var resolvedImageData: Data? {
        if isCreateMode { return imageData }
        return editingItem?.imageData ?? imageData
    }

    @ViewBuilder
    private var iconHeader: some View {
        Button {
            showIconPicker = true
        } label: {
            ZStack {
                // Shadow icon (behind, stretched + blurred)
                IconImage(
                    name: currentName,
                    iconFileName: currentIconName,
                    fallbackSymbol: "leaf",
                    size: 97
                )
                .scaleEffect(x: 1.5, y: 0.5)
                .blur(radius: 10)
                .opacity(0.5)

                // Main icon (no balloon background)
                IconImage(
                    name: currentName,
                    iconFileName: currentIconName,
                    fallbackSymbol: "leaf",
                    size: 97
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name Section

    @ViewBuilder
    private var nameSection: some View {
        ZStack(alignment: .trailing) {
            // Centered title - takes full width, padded to avoid sparkle overlap
            TextField("Nome do item", text: isCreateMode ? $name : editNameBinding)
                .font(.pageTitle)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .padding(.horizontal, 40)
                .focused($nameFieldFocused)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .onChange(of: isCreateMode ? name : editNameBinding.wrappedValue) { _, newValue in
                    updateSuggestions(for: newValue)
                    if !isCreateMode {
                        name = newValue
                    }
                }

            // Sparkle button overlaid on the right
            Button {
                toggleSuggestions()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showSuggestions ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(neutralSurfaceColor, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if showSuggestions && !suggestions.isEmpty {
            VStack(spacing: 0) {
                ExpandingFlowLayout(spacing: 6) {
                    ForEach(suggestions.prefix(12)) { entry in
                        let matchedTitle = entry.preferredTitle(matching: name)
                        Button {
                            selectSuggestion(entry)
                        } label: {
                            HStack(spacing: 5) {
                                IconImage(
                                    name: matchedTitle,
                                    iconFileName: entry.nomeDoArquivo,
                                    fallbackSymbol: "leaf",
                                    size: 18
                                )
                                Text(matchedTitle)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(neutralSurfaceColor, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        }
    }

    // MARK: - Category

    @ViewBuilder
    private var categorySection: some View {
        Button {
            showCategorySelection = true
        } label: {
            CategoryLabelView(
                categoryName: isCreateMode ? selectedCategory : (editingItem?.category ?? selectedCategory),
                iconSize: 16,
                spacing: 6,
                font: .subheadline
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List Toggle

    @ViewBuilder
    private var listToggleSection: some View {
        VStack(spacing: 12) {
            // Pantry + Grocery joined toggle
            pantryGroceryToggle

            // Utensil (separate, only when applicable)
            if showUtensilOption {
                utensilToggle
            }
        }
    }

    @ViewBuilder
    private var pantryGroceryToggle: some View {
        let pantrySelected = selectedLists.contains(.pantry)
        let grocerySelected = selectedLists.contains(.grocery)
        let bothSelected = pantrySelected && grocerySelected

        HStack(spacing: 0) {
            // Pantry button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    togglePantryGrocery(.pantry)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ItemListType.pantry.icon)
                        .font(.system(size: 13, weight: .medium))
                    Text(ItemListType.pantry.label)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(pantrySelected ? ItemListType.pantry.color : Color(.tertiarySystemFill))
                .foregroundStyle(pantrySelected ? .white : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!isCreateMode && isUtensil)

            // Grocery button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    togglePantryGrocery(.grocery)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ItemListType.grocery.icon)
                        .font(.system(size: 13, weight: .medium))
                    Text(ItemListType.grocery.label)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(grocerySelected ? ItemListType.grocery.color : Color(.tertiarySystemFill))
                .foregroundStyle(grocerySelected ? .white : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!isCreateMode && isUtensil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        // "Add to both" hint when one is selected
        if !bothSelected && !isUtensil {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedLists = [.pantry, .grocery]
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("Adicionar em ambos")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var utensilToggle: some View {
        let isSelected = selectedLists.contains(.utensil)
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                toggleList(.utensil)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ItemListType.utensil.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(ItemListType.utensil.label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? ItemListType.utensil.color : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Description + Photo

    @ViewBuilder
    private var descriptionPhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalhes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                // Description field
                TextField("Descrição (opcional)", text: isCreateMode ? $descriptionText : editDescriptionBinding, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Photo area (right)
                if let data = resolvedImageData, let image = PlatformImage(data: data) {
                    Button {
                        showPhotoPreview = true
                    } label: {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remover Foto", systemImage: "trash", role: .destructive) {
                            removePhoto()
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Alterar Foto", systemImage: "photo")
                        }
                    }
                } else {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20))
                            Text("Foto")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.tertiarySystemFill), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Quantity

    @ViewBuilder
    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quantidade")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("Qtd", value: isCreateMode ? $quantity : editQuantityBinding, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(width: 80)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                TextField("Unidade (kg, L, un...)", text: isCreateMode ? $unit : editUnitBinding)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Expiry

    /// Whether we're in grocery-only mode (duration + auto-apply forced)
    private var isGroceryOnlyExpiry: Bool {
        if let item = editingItem {
            return item.isGrocery && !item.isPantry
        }
        return !hasPantry && hasGrocery
    }

    @ViewBuilder
    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Validade")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("Possui validade", isOn: isCreateMode ? $hasExpirationDate.animation() : editHasExpiryBinding)
                .tint(PageTheme.lists.accentColor)
                .onChange(of: hasExpirationDate) { _, newValue in
                    if newValue && isGroceryOnlyExpiry {
                        keepExpiryOnAcquire = true
                    }
                }

            if resolvedHasExpiry || (isGroceryOnlyExpiry && hasExpirationDate) {
                VStack(spacing: 12) {
                    if !isGroceryOnlyExpiry {
                        Picker("Modo", selection: $expiryMode.animation()) {
                            Text("Duração").tag(ExpiryInputMode.duration)
                            Text("Data").tag(ExpiryInputMode.date)
                        }
                        .pickerStyle(.segmented)
                    }

                    if expiryMode == .duration || isGroceryOnlyExpiry {
                        expiryDurationPicker

                        // Auto-apply expiry explanation
                        if hasPantry || hasGrocery || editingItem != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                if isGroceryOnlyExpiry {
                                    // Forced on, non-toggleable
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(PageTheme.lists.accentColor)
                                                .font(.subheadline)
                                            Text("Validade aplicada automaticamente")
                                                .font(.subheadline)
                                        }
                                        Text("Ao comprar e mover para a Despensa, a validade de \(formattedExpiryDuration) será aplicada.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Toggle(isOn: $keepExpiryOnAcquire) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Aplicar validade automaticamente")
                                                .font(.subheadline)
                                            Text("Ao comprar no Mercado e mover para a Despensa, a validade de \(formattedExpiryDuration) será aplicada automaticamente.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tint(PageTheme.lists.accentColor)
                                }
                            }
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        DatePicker(
                            "Validade",
                            selection: isCreateMode ? $expirationDate : editExpiryDateBinding,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .onChange(of: isCreateMode ? expirationDate : (editingItem?.expirationDate ?? Date())) { _, newDate in
                            syncDurationFromDate(newDate)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var expiryDurationPicker: some View {
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
    }

    private var formattedExpiryDuration: String {
        if expiryDurationUnit == .months {
            return expiryDurationValue == 1 ? "1 mês" : "\(expiryDurationValue) meses"
        } else {
            return expiryDurationValue == 1 ? "1 dia" : "\(expiryDurationValue) dias"
        }
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Salvar")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isValid ? Color.black : Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
    }

    // MARK: - State Helpers

    private var resolvedHasExpiry: Bool {
        if isCreateMode { return hasExpirationDate }
        return editingItem?.expirationDate != nil
    }

    // MARK: - Edit Bindings

    private var editNameBinding: Binding<String> {
        Binding(
            get: { editingItem?.name ?? name },
            set: { newValue in editingItem?.name = newValue }
        )
    }

    private var editCategoryBinding: Binding<String> {
        Binding(
            get: { editingItem?.category ?? selectedCategory },
            set: { newValue in editingItem?.category = newValue }
        )
    }

    private var editDescriptionBinding: Binding<String> {
        Binding(
            get: { editingItem?.descriptionText ?? descriptionText },
            set: { newValue in editingItem?.descriptionText = newValue }
        )
    }

    private var editQuantityBinding: Binding<Double?> {
        Binding(
            get: { editingItem?.quantity },
            set: { newValue in editingItem?.quantity = newValue }
        )
    }

    private var editUnitBinding: Binding<String> {
        Binding(
            get: { editingItem?.unit ?? "" },
            set: { newValue in editingItem?.unit = newValue.isEmpty ? nil : newValue }
        )
    }

    private var editHasExpiryBinding: Binding<Bool> {
        Binding(
            get: { editingItem?.expirationDate != nil },
            set: { hasDate in
                withAnimation {
                    if hasDate {
                        editingItem?.expirationDate = editingItem?.expirationDate ?? Date()
                    } else {
                        editingItem?.expirationDate = nil
                    }
                }
            }
        )
    }

    private var editExpiryDateBinding: Binding<Date> {
        Binding(
            get: { editingItem?.expirationDate ?? Date() },
            set: { newDate in
                editingItem?.expirationDate = newDate
                syncDurationFromDate(newDate)
            }
        )
    }

    // MARK: - Setup

    private func setupInitialState() {
        switch mode {
        case .create(let destinations):
            selectedLists = destinations

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
                if let match = ItemDatabase.shared.exactMatch(for: name) {
                    if iconName == nil { iconName = match.nomeDoArquivo }
                    if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
                        selectedCategory = match.categoria
                        userChangedCategory = true
                    }
                }
            }

            // Restore last destination preference
            if let raw = settings?.lastAddItemDestinationRaw,
               let saved = AddItemDestination(rawValue: raw) {
                switch saved {
                case .pantry:  selectedLists = [.pantry]
                case .grocery: selectedLists = [.grocery]
                case .utensil: if showUtensils { selectedLists = [.utensil] }
                }
            }

            DispatchQueue.main.async {
                nameFieldFocused = true
            }

        case .edit(let item):
            name = item.name
            iconName = item.iconName
            var lists = Set<ItemListType>()
            if item.isPantry { lists.insert(.pantry) }
            if item.isGrocery { lists.insert(.grocery) }
            if item.isUtensil { lists.insert(.utensil) }
            if lists.isEmpty { lists.insert(.pantry) }
            selectedLists = lists
            if let date = item.expirationDate {
                hasExpirationDate = true
                syncDurationFromDate(date)
            }
            if let days = item.defaultExpiryDays {
                expiryDurationValue = days
                expiryDurationUnit = .days
                keepExpiryOnAcquire = true
            }
        }
    }

    // MARK: - List Toggle Logic

    private func togglePantryGrocery(_ listType: ItemListType) {
        guard listType == .pantry || listType == .grocery else { return }

        if selectedLists.contains(.utensil) {
            // Switch from utensil to this list
            selectedLists = [listType]
            return
        }

        let other: ItemListType = listType == .pantry ? .grocery : .pantry

        if selectedLists.contains(listType) {
            // Already selected — if both are on, turn off the tapped one
            if selectedLists.contains(other) {
                selectedLists.remove(listType)
            }
            // If only this one is on, switch to the other
            else {
                selectedLists = [other]
            }
        } else {
            // Not selected — default exclusive: turn on this, turn off other
            selectedLists = [listType]
        }
    }

    private func toggleList(_ listType: ItemListType) {
        if listType == .utensil {
            if selectedLists.contains(.utensil) {
                if selectedLists.count > 1 {
                    selectedLists.remove(.utensil)
                }
            } else {
                selectedLists = [.utensil]
            }
        } else {
            togglePantryGrocery(listType)
        }
    }

    // MARK: - Suggestions

    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                suggestions = []
                showSuggestions = false
            }
            return
        }
        let results = ItemDatabase.shared.search(query: trimmed, fallbackToFeatured: false)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            suggestions = results
            showSuggestions = !results.isEmpty
        }
    }

    private func toggleSuggestions() {
        if showSuggestions {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSuggestions = false
            }
            return
        }
        let results = ItemDatabase.shared.search(query: name.trimmingCharacters(in: .whitespaces), fallbackToFeatured: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            suggestions = results
            showSuggestions = !results.isEmpty
        }
    }

    private func selectSuggestion(_ entry: ItemEntry) {
        let resolvedTitle = entry.preferredTitle(matching: name)

        if isCreateMode {
            name = resolvedTitle
            iconName = entry.nomeDoArquivo
            if !userChangedCategory, CategoryDatabase.shared.entry(for: entry.categoria) != nil {
                selectedCategory = entry.categoria
            }
            userChangedCategory = true
        } else {
            editNameBinding.wrappedValue = resolvedTitle
            editingItem?.iconName = entry.nomeDoArquivo
            iconName = entry.nomeDoArquivo
            if CategoryDatabase.shared.entry(for: entry.categoria) != nil {
                editCategoryBinding.wrappedValue = entry.categoria
            }
        }

        nameFieldFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showSuggestions = false
            suggestions = []
        }
    }

    // MARK: - Photo

    private func loadPhoto() {
        guard let selectedPhoto else { return }
        Task { @MainActor in
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            setImageData(data)
        }
    }

    private func setImageData(_ data: Data) {
        if isCreateMode {
            imageData = data
        } else {
            editingItem?.imageData = data
            imageData = data
        }
    }

    private func removePhoto() {
        if isCreateMode {
            imageData = nil
        } else {
            editingItem?.imageData = nil
            imageData = nil
        }
        selectedPhoto = nil
    }

    // MARK: - Expiry Helpers

    private func syncDurationFromDate(_ date: Date) {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
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
        let newDate = Calendar.current.date(byAdding: component, value: expiryDurationValue, to: Date()) ?? Date()
        if isCreateMode {
            expirationDate = newDate
        } else {
            editingItem?.expirationDate = newDate
        }
    }

    private func computeExpiryDays() -> Int {
        if expiryMode == .duration {
            return expiryDurationUnit == .months ? expiryDurationValue * 30 : expiryDurationValue
        }
        return max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: expirationDate)
        ).day ?? 0)
    }

    // MARK: - Save (Create Mode)

    private func save() {
        guard isCreateMode else { return }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalIcon = iconName
        var finalCategory = selectedCategory

        if finalIcon == nil, let match = ItemDatabase.shared.exactMatch(for: trimmed) {
            finalIcon = match.nomeDoArquivo
            if !userChangedCategory, CategoryDatabase.shared.entry(for: match.categoria) != nil {
                finalCategory = match.categoria
            }
        }

        var createdID: UUID?
        var createdType: ItemListType = .grocery

        let wantsPantry = selectedLists.contains(.pantry)
        let wantsGrocery = selectedLists.contains(.grocery)
        let wantsUtensil = selectedLists.contains(.utensil)

        let allPantry = allUnifiedItems.filter { $0.isPantry }
        let allGrocery = allUnifiedItems.filter { $0.isGrocery }
        let allUtensils = allUnifiedItems.filter { $0.isUtensil }

        let item = UnifiedItem(
            name: trimmed,
            category: finalCategory,
            iconName: finalIcon,
            isPantry: wantsPantry,
            isGrocery: wantsGrocery,
            isUtensil: wantsUtensil,
            pantrySortOrder: wantsPantry ? (allPantry.map(\.pantrySortOrder).max() ?? -1) + 1 : 0,
            grocerySortOrder: wantsGrocery ? (allGrocery.map(\.grocerySortOrder).max() ?? -1) + 1 : 0,
            utensilSortOrder: wantsUtensil ? (allUtensils.map(\.utensilSortOrder).max() ?? -1) + 1 : 0
        )
        item.descriptionText = trimmedDescription
        item.imageData = imageData
        item.quantity = quantity
        item.unit = unit.isEmpty ? nil : unit

        if hasExpirationDate && (wantsPantry || wantsGrocery) {
            item.expirationDate = expirationDate
        }
        if (hasExpirationDate && keepExpiryOnAcquire) || isGroceryOnlyExpiry {
            item.defaultExpiryDays = computeExpiryDays()
        }

        modelContext.insert(item)
        createdID = item.id
        createdType = wantsPantry ? .pantry : (wantsGrocery ? .grocery : .utensil)

        if wantsUtensil {
            settings?.lastAddItemDestinationRaw = "utensil"
        } else {
            settings?.lastAddItemDestinationRaw = wantsPantry ? "pantry" : "grocery"
        }

        if let id = createdID {
            onCreated?(id, createdType)
        }
        dismiss()
    }
}
