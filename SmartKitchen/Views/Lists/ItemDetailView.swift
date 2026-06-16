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
        case .pantry:  String(localized: "Despensa")
        case .grocery: String(localized: "Mercado")
        case .utensil: String(localized: "Utensílio")
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

    var listName: String {
        switch self {
        case .pantry:  String(localized: "Despensa")
        case .grocery: String(localized: "Mercado")
        case .utensil: String(localized: "Utensílios")
        }
    }

    var removalDestinationLabel: String {
        switch self {
        case .pantry:  "da Despensa"
        case .grocery: "do Mercado"
        case .utensil: "dos Utensílios"
        }
    }

    var removalButtonTitle: String {
        "Remover \(removalDestinationLabel)"
    }
}

enum ItemDetailMode {
    case create(destinations: Set<ItemListType> = [.grocery])
    case edit(UnifiedItem)
}

struct UnifiedItemSelection: Identifiable, Hashable {
    let id: UUID
}

// MARK: - View

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    let mode: ItemDetailMode

    // Create-mode initial data
    var initialName: String = ""
    var initialIconFileName: String? = nil
    var initialCategory: String? = nil
    var onCreated: ((UUID, ItemListType) -> Void)? = nil
    var onExistingItemRequested: ((UnifiedItem) -> Void)? = nil
    var removalContext: ItemListType? = nil

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
    @State private var showRemoveConfirmation = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var duplicateCheckItems: [UnifiedItem] = []
    @State private var duplicateNameItem: UnifiedItem?
    #if os(iOS)
    @State private var itemDetailDetent: PresentationDetent = .medium
    #endif
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
    private var canCreate: Bool { isValid && duplicateNameItem == nil }

    // Edit-mode binding
    private var editingItem: UnifiedItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            itemDetailBackground

            ScrollView {
                VStack(spacing: 0) {
                    closeButtonRow

                    // Icon area
                    iconHeader
                        .padding(.top, 32)

                    // Name field
                    nameSection
                        .padding(.top, 32)

                    // Category
                    categorySection
                        .padding(.top, 4)

                    // Suggestion chips (below category)
                    suggestionsSection

                    existingItemNoticeSection

                    // List toggle
                    listToggleSection
                        .padding(.top, 20)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Description + Photo
                    descriptionPhotoSection
                        .padding(.top, 14)

                    // Expiry (conditional)
                    if (hasPantry || hasGrocery) && !isUtensil {
                        expirySection
                            .padding(.top, 10)
                    }

                    // Quantity (always show when not utensil)
                    if !isUtensil {
                        quantitySection
                            .padding(.top, 10)
                    }

                    // Save button (create mode only)
                    if isCreateMode {
                        saveButton
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                    } else if showsRemoveButton {
                        removeButton
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.medium, .large], selection: $itemDetailDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(appPrimaryBackground)
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
        .alert(removeConfirmationTitle, isPresented: $showRemoveConfirmation) {
            Button(removeConfirmationActionTitle, role: .destructive) {
                removeEditedItem()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(removeConfirmationMessage)
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

    private var currentCategoryName: String {
        isCreateMode ? selectedCategory : (editingItem?.category ?? selectedCategory)
    }

    private var currentCategoryIconName: String? {
        allCategories.first { category in
            category.name == currentCategoryName && category.type == (isUtensil ? .utensil : .pantry)
        }?.iconName ?? CategoryDatabase.shared.entry(for: currentCategoryName)?.iconFileName
    }

    private var resolvedHeaderIconName: String? {
        currentIconName
            ?? IconResolver.resolve(currentNameValue)
            ?? currentCategoryIconName
    }

    private var currentName: String {
        name
    }

    private var currentNameBinding: Binding<String> {
        isCreateMode ? $name : editNameBinding
    }

    private var currentNameValue: String {
        currentNameBinding.wrappedValue
    }

    private var resolvedImageData: Data? {
        if isCreateMode { return imageData }
        return editingItem?.imageData ?? imageData
    }

    private var itemDetailBackground: some View {
        Color(PlatformColor.systemBackground)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var closeButtonRow: some View {
#if os(macOS)
        if !isCreateMode {
            HStack {
                Spacer()

                Button {
                    closeEditor()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(neutralSurfaceColor, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
#endif
    }

    @ViewBuilder
    private var iconHeader: some View {
        Button {
            showIconPicker = true
        } label: {
            ZStack {
                IconImage(
                    name: currentName,
                    iconFileName: resolvedHeaderIconName,
                    fallbackSymbol: "leaf",
                    size: 96
                )
                .scaleEffect(6.0)
                .blur(radius: 34)
                .offset(y: -108)
                .opacity(colorScheme == .dark ? 0.22 : 0.28)
                .allowsHitTesting(false)

                IconImage(
                    name: currentName,
                    iconFileName: resolvedHeaderIconName,
                    fallbackSymbol: "leaf",
                    size: 96
                )
            }
            .frame(width: 112, height: 106)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name Section

    @ViewBuilder
    private var nameSection: some View {
        ZStack(alignment: .trailing) {
            // Centered title - takes full width, padded to avoid sparkle overlap
            TextField("", text: currentNameBinding)
                .font(.pageTitle)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .padding(.horizontal, 40)
                .focused($nameFieldFocused)
                .overlay {
                    if currentNameValue.isEmpty {
                        Text("Nome do item")
                            .font(.pageTitle)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 40)
                    }
                }
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .onChange(of: currentNameValue) { _, newValue in
                    updateSuggestions(for: newValue)
                    refreshDuplicateNameItem(for: newValue)
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

    @ViewBuilder
    private var existingItemNoticeSection: some View {
        if let existingItem = duplicateNameItem {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Text("Já existe um item com esse nome")
                        .font(.subheadline.weight(.semibold))
                }

                Text("Esse item já está em \(existingItemLocationsText(for: existingItem)). Abra o item existente para editar as listas em vez de criar outro.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openExistingItem(existingItem)
                } label: {
                    Text("Abrir item existente")
                        .font(.subheadline.weight(.semibold))
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(PageTheme.lists.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 14)
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
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isCreateMode && isUtensil)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedLists = [.pantry, .grocery]
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 10)
                    .frame(width: 42)
                    .background(bothSelected ? PageTheme.lists.accentColor : Color(.tertiarySystemFill))
                    .foregroundStyle(bothSelected ? .white : .primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isCreateMode && isUtensil)
            .accessibilityLabel(Text("Despensa & Mercado"))

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
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isCreateMode && isUtensil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Detalhes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Observações, marca ou preparo", text: isCreateMode ? $descriptionText : editDescriptionBinding, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(resolvedImageData == nil ? "Adicionar Foto" : "Alterar Foto", systemImage: resolvedImageData == nil ? "photo.badge.plus" : "photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if resolvedImageData != nil {
                    Button("Ver Foto", systemImage: "photo") {
                        showPhotoPreview = true
                    }
                    Button("Remover Foto", systemImage: "trash", role: .destructive) {
                        removePhoto()
                    }
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
                .background(canCreate ? Color.black : Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
    }

    @ViewBuilder
    private var removeButton: some View {
        Button(role: .destructive) {
            showRemoveConfirmation = true
        } label: {
            Text(removeConfirmationActionTitle)
                .font(.headline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - State Helpers

    private var resolvedHasExpiry: Bool {
        if isCreateMode { return hasExpirationDate }
        return editingItem?.expirationDate != nil
    }

    private var resolvedRemovalContext: ItemListType? {
        guard let item = editingItem else { return nil }

        if let removalContext, item.activeFlags.contains(removalContext) {
            return removalContext
        }

        if item.activeFlags.count == 1 {
            return item.activeFlags.first
        }

        return nil
    }

    private var showsRemoveButton: Bool {
        !isCreateMode && resolvedRemovalContext != nil
    }

    private var removeConfirmationTitle: String {
        guard let context = resolvedRemovalContext else {
            return "Remover item?"
        }
        return "\(context.removalButtonTitle)?"
    }

    private var removeConfirmationActionTitle: String {
        resolvedRemovalContext?.removalButtonTitle ?? "Remover item"
    }

    private var removeConfirmationMessage: String {
        guard let item = editingItem, let context = resolvedRemovalContext else {
            return ""
        }

        let remainingLists = item.activeFlags.filter { $0 != context }
        if remainingLists.isEmpty {
            return "Esse item será excluído permanentemente."
        }

        let remainingLabels = remainingLists.map(\.listName).joined(separator: ", ")
        return "Esse item será removido \(context.removalDestinationLabel) e continuará em \(remainingLabels)."
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
                if let match = ItemDatabase.shared.preferredMatch(for: name) {
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
            refreshDuplicateNameItem(for: name)

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

        if finalIcon == nil, let match = ItemDatabase.shared.preferredMatch(for: trimmed) {
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

        let item = UnifiedItem(
            name: trimmed,
            category: finalCategory,
            iconName: finalIcon,
            isPantry: wantsPantry,
            isGrocery: wantsGrocery,
            isUtensil: wantsUtensil,
            pantrySortOrder: wantsPantry ? nextSortOrder(for: .pantry) : 0,
            grocerySortOrder: wantsGrocery ? nextSortOrder(for: .grocery) : 0,
            utensilSortOrder: wantsUtensil ? nextSortOrder(for: .utensil) : 0
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

        let savedItem = insertOrMerge(item)
        createdID = savedItem.id
        createdType = wantsPantry ? .pantry : (wantsGrocery ? .grocery : .utensil)

        if wantsUtensil {
            settings?.lastAddItemDestinationRaw = "utensil"
        } else {
            settings?.lastAddItemDestinationRaw = wantsPantry ? "pantry" : "grocery"
        }

        if let id = createdID {
            onCreated?(id, createdType)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        dismiss()
    }

    private func existingItemLocationsText(for item: UnifiedItem) -> String {
        let labels = item.activeFlags.map(\.label)
        if labels.isEmpty {
            return "uma das listas"
        }
        return labels.joined(separator: ", ")
    }

    private func openExistingItem(_ item: UnifiedItem) {
        onExistingItemRequested?(item)
        dismiss()
    }

    private func refreshDuplicateNameItem(for candidateName: String) {
        guard isCreateMode else {
            duplicateNameItem = nil
            return
        }
        duplicateNameItem = existingItemFromCachedCreateItems(named: candidateName)
    }

    private func existingItemFromCachedCreateItems(named candidateName: String) -> UnifiedItem? {
        let trimmed = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        loadDuplicateCheckItemsIfNeeded()
        return UnifiedItem.existingItem(named: trimmed, in: duplicateCheckItems)
    }

    private func loadDuplicateCheckItemsIfNeeded() {
        guard isCreateMode, duplicateCheckItems.isEmpty else { return }
        duplicateCheckItems = (try? modelContext.fetch(FetchDescriptor<UnifiedItem>())) ?? []
    }

    private func insertOrMerge(_ item: UnifiedItem) -> UnifiedItem {
        var descriptor = FetchDescriptor<UnifiedItem>()
        descriptor.includePendingChanges = true
        let items = (try? modelContext.fetch(descriptor)) ?? []
        duplicateCheckItems = items
        if let existing = UnifiedItem.mergedExistingItem(named: item.name, in: items, context: modelContext) {
            existing.mergeDetails(from: item)
            return existing
        }
        modelContext.insert(item)
        return item
    }

    private func nextSortOrder(for listType: ItemListType) -> Int {
        let items = fetchItems(for: listType)
        let maxSortOrder = items.map { item in
            switch listType {
            case .pantry: item.pantrySortOrder
            case .grocery: item.grocerySortOrder
            case .utensil: item.utensilSortOrder
            }
        }.max() ?? -1
        return maxSortOrder + 1
    }

    private func fetchItems(for listType: ItemListType) -> [UnifiedItem] {
        let descriptor: FetchDescriptor<UnifiedItem>
        switch listType {
        case .pantry:
            descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.isPantry })
        case .grocery:
            descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.isGrocery })
        case .utensil:
            descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.isUtensil })
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func closeEditor() {
        if !isCreateMode {
            try? modelContext.save()
        }
        dismiss()
    }

    private func removeEditedItem() {
        guard let item = editingItem, let context = resolvedRemovalContext else { return }

        withAnimation {
            switch context {
            case .pantry:
                if item.isGrocery || item.isUtensil {
                    item.isPantry = false
                } else {
                    modelContext.delete(item)
                }
            case .grocery:
                if item.isPantry || item.isUtensil {
                    item.isGrocery = false
                } else {
                    modelContext.delete(item)
                }
            case .utensil:
                if item.isPantry || item.isGrocery {
                    item.isUtensil = false
                } else {
                    modelContext.delete(item)
                }
            }
        }

        dismiss()
    }
}

struct ItemDetailContainerView: View {
    let itemID: UUID
    var removalContext: ItemListType? = nil

    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [UnifiedItem]
    @State private var didResolveOnce = false

    init(itemID: UUID, removalContext: ItemListType? = nil) {
        self.itemID = itemID
        self.removalContext = removalContext
        _matches = Query(filter: #Predicate<UnifiedItem> { $0.id == itemID })
    }

    var body: some View {
        Group {
            if let item = matches.first {
                ItemDetailView(mode: .edit(item), removalContext: removalContext)
                    .onAppear { didResolveOnce = true }
            } else if didResolveOnce {
                Color.clear
                    .onAppear {
                        Task { @MainActor in
                            dismiss()
                        }
                    }
            } else {
                Color.clear
            }
        }
    }
}
