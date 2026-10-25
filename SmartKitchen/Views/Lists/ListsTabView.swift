import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Transient UI selection. No persistent flags or extra item queries.
struct ListItemSelection {
    var isActive = false
    var selectedIDs: Set<UUID> = []
    var toggle: (UUID) -> Void = { _ in }
    var updateVisibleIDs: (Set<UUID>) -> Void = { _ in }
}

private struct ListItemSelectionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = ListItemSelection()
}

extension EnvironmentValues {
    var listItemSelection: ListItemSelection {
        get { self[ListItemSelectionKey.self] }
        set { self[ListItemSelectionKey.self] = newValue }
    }
}

struct ListSelectionActiveKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct ListSelectionIndicator: View {
    let id: UUID
    @Environment(\.listItemSelection) private var selection

    var body: some View {
        Image(systemName: selection.selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .foregroundStyle(PageTheme.lists.accentColor)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }
}

struct ListSelectionRow<Content: View>: View {
    let item: UnifiedItem
    @ViewBuilder var content: () -> Content
    @Environment(\.listItemSelection) private var selection

    var body: some View {
        Button { selection.toggle(item.id) } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(item.name))
            .accessibilityValue(Text(selection.selectedIDs.contains(item.id) ? LocalizedStringKey("Selecionado") : LocalizedStringKey("Não selecionado")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selection.selectedIDs.contains(item.id) ? .isSelected : [])
            .accessibilityIdentifier("savoria.item.select." + item.id.uuidString)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(selection.selectedIDs.contains(item.id) ? PageTheme.lists.accentColor.opacity(0.12) : Color.clear)
            .id(item.id)
    }
}

enum ListBulkAction {
    case move(ItemListType)
    case category(String)
}

@MainActor
enum ListBulkMutation {
    /// Fetch only selected IDs; stale selections never affect items in another list.
    static func apply(_ action: ListBulkAction, selectedIDs: Set<UUID>, source: ItemListType,
                      in context: ModelContext) throws {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { ids.contains($0.id) })
        let items = try context.fetch(descriptor).filter { $0.activeFlags.contains(source) }
        if case .move(let destination) = action {
            guard source != .utensil, destination != .utensil, destination != source else { return }
        }
        let previousValues = items.map { item in
            (item, item.isPantry, item.isGrocery, item.isUtensil, item.isReserveValue,
             item.isChecked, item.expirationDate, item.category)
        }
        do {
            try context.transaction {
                for item in items {
                    switch action {
                    case .move(let destination): item.move(to: destination)
                    case .category(let category): item.category = category
                    }
                }
            }
        } catch {
            // Undo only this failed operation's fields, never unrelated pending edits.
            for (item, pantry, grocery, utensil, reserve, checked, expiry, category) in previousValues {
                item.isPantry = pantry
                item.isGrocery = grocery
                item.isUtensil = utensil
                item.isReserveValue = reserve
                item.isChecked = checked
                item.expirationDate = expiry
                item.category = category
            }
            throw error
        }
    }
}

private struct ListBulkCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [Category]
    let type: CategoryType
    var onChoose: (String) -> Void

    init(type: CategoryType, onChoose: @escaping (String) -> Void) {
        self.type = type
        self.onChoose = onChoose
        _categories = Query(filter: #Predicate<Category> { $0.type == type }, sort: \Category.sortOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Category.uniqueForDisplay(categories)) { category in
                    Button(category.localizedDisplayName) { onChoose(category.name); dismiss() }
                }
                if !categories.contains(where: { $0.name == "Outros" }) {
                    Button("Outros") { onChoose("Outros"); dismiss() }
                }
            }
            .navigationTitle("Alterar categoria")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .savoriaModalBorder(theme: .lists)
    }
}

enum ListSubtab: String, CaseIterable, Codable {
    case pantry
    case reserve
    case grocery
    case utensils

    var title: LocalizedStringKey {
        switch self {
        case .pantry:  "Despensa"
        case .reserve: "Para depois"
        case .grocery: "Mercado"
        case .utensils: "Utensílios"
        }
    }

    var icon: String {
        switch self {
        case .pantry:  "refrigerator"
        case .reserve: "tray"
        case .grocery: "cart"
        case .utensils: "fork.knife"
        }
    }

    var newItemTitle: String {
        switch self {
        case .pantry: "Novo Item da Despensa"
        case .reserve: String(localized: "Novo item para depois")
        case .grocery: "Novo Item do Mercado"
        case .utensils: "Novo Utensílio"
        }
    }

    var removalContext: ItemListType {
        switch self {
        case .pantry: .pantry
        case .reserve: .reserve
        case .grocery: .grocery
        case .utensils: .utensil
        }
    }
}

enum PantryListFilterOption: String, CaseIterable, Identifiable {
    case all
    case withExpiration
    case expiringSoon

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "Todos"
        case .withExpiration: "Com validade"
        case .expiringSoon: "Próximos da validade"
        }
    }
}

enum GroceryListFilterOption: String, CaseIterable, Identifiable {
    case all

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "Todos"
        }
    }
}

struct ListsDragPayload: Codable, Transferable, Hashable {
    let itemID: UUID
    let sourceList: ListSubtab

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// Only presentation selection is shared; the original feature owns its actions.
struct ListWorkspaceSelection {
    var primary: ListSubtab
    var secondary: ListSubtab
    init(primary: ListSubtab = .pantry) {
        self.primary = primary
        secondary = primary == .grocery ? .pantry : .grocery
    }
    mutating func selectPrimary(_ value: ListSubtab) {
        if value == secondary { secondary = primary }
        primary = value
    }
    mutating func selectSecondary(_ value: ListSubtab) {
        if value == primary { primary = secondary }
        secondary = value
    }
    mutating func reconcile(available: [ListSubtab]) {
        if !available.contains(primary) { primary = available.first ?? .pantry }
        if !available.contains(secondary) || secondary == primary {
            secondary = available.first { $0 != primary } ?? primary
        }
    }
}

struct ListsTabView: View {
    let initialSubtab: ListSubtab
    let selection: Binding<ListSubtab>?

    init(initialSubtab: ListSubtab = .pantry, selection: Binding<ListSubtab>? = nil) {
        self.initialSubtab = initialSubtab
        self.selection = selection
    }

    var body: some View {
        #if os(iOS)
        DeferredTabPage(tab: .lists) {
            ListsLoadedTabView(initialSubtab: initialSubtab, selection: selection)
        } placeholder: {
            ListsSkeletonPage(initialSubtab: initialSubtab)
        }
        #else
        ListsLoadedTabView(initialSubtab: initialSubtab, selection: selection)
        #endif
    }
}

#if os(iOS)
private struct ListsSkeletonPage: View {
    init(initialSubtab: ListSubtab = .pantry) {
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .lists,
            header: { isInverted in
                PageHeader(title: String(localized: "Listas"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "plus") {}
                        }

                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "line.3.horizontal.decrease.circle") {}
                        }

                        SettingsButton()
                    }
                    .disabled(true)
                }
            },
            content: {
                AppLaunchSkeletonPage(kind: .lists, presentation: .contentOnly)
            },
            infoContent: {
                Color.clear.frame(height: ExpandedPageHeaderMetrics.iosEmptyInfoHeight)
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }
}
#endif

private struct ListsLoadedTabView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.scrollToItem) private var scrollToItem
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]

    private let externalSelection: Binding<ListSubtab>?
    @State private var workspaceSelection: ListWorkspaceSelection
    private var selectedSubtab: ListSubtab {
        get { externalSelection?.wrappedValue ?? workspaceSelection.primary }
        nonmutating set {
            if let externalSelection { externalSelection.wrappedValue = newValue }
            else { workspaceSelection.selectPrimary(newValue) }
        }
    }
    @State private var showAddPantry = false
    @State private var showAddGrocery = false
    @State private var showAddReserve = false
    @State private var showAddUtensil = false
    @State private var existingItemFromCreateFlow: UnifiedItemSelection?
    @State private var showsInlineTitle = false
    @State private var sortOption: ListsSortOption = .custom
    @State private var pantryFilter: PantryListFilterOption = .all
    @State private var groceryFilter: GroceryListFilterOption = .all
    @State private var targetedTab: ListSubtab?
    @State private var contentResetToken: Int = 0
    @State private var isLocalSearchVisible = false
    @State private var localSearchText = ""
    @State private var isSelectingItems = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var visibleItemIDs: Set<UUID> = []
    @State private var showsBulkCategories = false
    @State private var showsBulkSaveError = false

    @State private var pantryBadge: Int = 0
    @State private var groceryBadge: Int = 0

    private var settings: AppSettings? { settingsArray.first }

    private var visibleTabs: [ListSubtab] {
        var tabs: [ListSubtab] = [.pantry]
        if settings?.showReserve == true { tabs.append(.reserve) }
        tabs.append(.grocery)
        if settings?.showUtensils == true {
            tabs.append(.utensils)
        }
        return tabs
    }

    init(initialSubtab: ListSubtab = .pantry, selection: Binding<ListSubtab>? = nil) {
        externalSelection = selection
        _workspaceSelection = State(initialValue: ListWorkspaceSelection(primary: initialSubtab))
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .lists,
            companionPage: {
                AnyView(SavoriaOriginalListPane(initialSubtab: workspaceSelection.secondary, selection: Binding(
                    get: { workspaceSelection.secondary },
                    set: { workspaceSelection.selectSecondary($0) }
                )))
            },
            header: { isInverted in
                PageHeader(title: String(localized: "Listas"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "plus") {
                                if selectedSubtab == .pantry {
                                    showAddPantry = true
                                } else if selectedSubtab == .reserve {
                                    showAddReserve = true
                                } else if selectedSubtab == .utensils {
                                    showAddUtensil = true
                                } else {
                                    showAddGrocery = true
                                }
                            }
                            .accessibilityIdentifier("savoria.lists.add")
                        }

                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "magnifyingglass") {
                                toggleLocalSearch()
                            }
                            .accessibilityLabel(Text(isLocalSearchVisible ? "Fechar" : "Buscar"))
                        }

                        GlassButtonGroup {
                            optionsMenu
                        }

                        #if !os(macOS)
                        SettingsButton()
                        #endif
                    }
                }
            },
            content: {
                VStack(spacing: 0) {
                    subtabPicker
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    Group {
                        switch selectedSubtab {
                        case .pantry:
                            PantryView(
                                searchText: localSearchText,
                                sortOption: sortOption,
                                filterOption: pantryFilter,
                                expiringLeadDays: settings?.expiringItemsLeadDays ?? 30,
                                onSentToGrocery: {
                                    withAnimation(.spring(response: 0.35)) {
                                        groceryBadge += 1
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { groceryBadge = 0 }
                                    }
                                },
                                onPullToAdd: { showAddPantry = true },
                                onScrollOffsetChange: updateInlineTitle
                            )
                        case .reserve:
                            GroceryListView(searchText: localSearchText, sortOption: sortOption,
                                            filterOption: groceryFilter, listType: .reserve,
                                            onPullToAdd: { showAddReserve = true },
                                            onScrollOffsetChange: updateInlineTitle)
                        case .grocery:
                            GroceryListView(
                                searchText: localSearchText,
                                sortOption: sortOption,
                                filterOption: groceryFilter,
                                onAcquired: {
                                    withAnimation(.spring(response: 0.35)) {
                                        pantryBadge += 1
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { pantryBadge = 0 }
                                    }
                                },
                                onPullToAdd: { showAddGrocery = true },
                                onScrollOffsetChange: updateInlineTitle
                            )
                        case .utensils:
                            UtensilsView(
                                searchText: localSearchText,
                                sortOption: sortOption,
                                onPullToAdd: { showAddUtensil = true },
                                onScrollOffsetChange: updateInlineTitle
                            )
                        }
                    }
                    .clipped()
                    .id("\(selectedSubtab.rawValue)-\(contentResetToken)")
                }
            },
            infoContent: {
                localSearchHeader
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .environment(\.listItemSelection, ListItemSelection(
            isActive: isSelectingItems,
            selectedIDs: selectedItemIDs,
            toggle: toggleItemSelection,
            updateVisibleIDs: updateVisibleItemIDs
        ))
        .preference(key: ListSelectionActiveKey.self, value: isSelectingItems)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectingItems {
                selectionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showsBulkCategories) {
            ListBulkCategorySheet(type: selectedSubtab == .utensils ? .utensil : .pantry) { category in
                applyBulkAction(.category(category))
            }
        }
        .alert("Não foi possível salvar a ação. Tente novamente.", isPresented: $showsBulkSaveError) {
            Button("OK", role: .cancel) {}
        }
        .tint(PageTheme.lists.accentColor)
        .onChange(of: visibleTabs) { _, tabs in
            if externalSelection == nil { workspaceSelection.reconcile(available: tabs) }
        }
        .onChange(of: selectedSubtab) {
            finishItemSelection()
            localSearchText = ""
            showsInlineTitle = false
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            handleActiveTabRetap()
        }
        .onChange(of: scrollToItem, initial: true) { _, request in
            guard let request else { return }
            switch request.type {
            case "pantryItem":
                selectedSubtab = .pantry
            case "reserveItem":
                if settings?.showReserve == true { selectedSubtab = .reserve }
            case "groceryItem":
                selectedSubtab = .grocery
            case "utensil":
                selectedSubtab = .utensils
            default:
                break
            }
        }
        .sheet(isPresented: $showAddPantry) {
            ItemDetailView(
                mode: .create(destinations: [.pantry]),
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
                }
            )
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddReserve) {
            ItemDetailView(mode: .create(destinations: [.reserve]),
                           onExistingItemRequested: openExistingItemFromCreateFlow)
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddGrocery) {
            ItemDetailView(
                mode: .create(destinations: [.grocery]),
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
                }
            )
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddUtensil) {
            ItemDetailView(
                mode: .create(destinations: [.utensil]),
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
                }
            )
                .forceLightStatusBar()
        }
        .sheet(item: $existingItemFromCreateFlow, onDismiss: { existingItemFromCreateFlow = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id, removalContext: selectedSubtab.removalContext)
                .forceLightStatusBar()
        }
        #if os(macOS)
        .focusedSceneValue(
            \.newItemCommandAction,
            NewItemCommandAction(title: selectedSubtab.newItemTitle, perform: openNewItemSheet)
        )
        #endif
    }

    @ViewBuilder
    private var localSearchHeader: some View {
        if isLocalSearchVisible {
            LocalPageSearchBar(text: $localSearchText, placeholder: "Buscar nesta lista")
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func toggleLocalSearch() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            isLocalSearchVisible.toggle()
            if !isLocalSearchVisible {
                localSearchText = ""
            }
        }
    }

    private var optionsMenu: some View {
        GlassGroupMenu(systemImage: "line.3.horizontal.decrease.circle") {
            Button(isSelectingItems ? String(localized: "Cancelar") : String(localized: "Selecionar itens"), systemImage: "checkmark.circle") {
                if isSelectingItems { finishItemSelection() }
                else { isSelectingItems = true }
            }
            .accessibilityIdentifier("savoria.lists.select")
            Divider()
            Section("Ordenar por") {
                ForEach(ListsSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        Label(option.displayName, systemImage: sortIcon(for: option))
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Section("Agrupar por") {
                ForEach(availableGroupingModes) { mode in
                    Button {
                        setGroupingMode(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode.icon)
                        if currentGroupingMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Section("Filtrar") {
                if selectedSubtab == .pantry {
                    ForEach(PantryListFilterOption.allCases) { option in
                        Button {
                            pantryFilter = option
                        } label: {
                            Text(option.label)
                            if pantryFilter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } else {
                    ForEach(GroceryListFilterOption.allCases) { option in
                        Button {
                            groceryFilter = option
                        } label: {
                            Text(option.label)
                            if groceryFilter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("savoria.lists.options")
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text("Selecionados: \(selectedItemIDs.count)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityIdentifier("savoria.lists.selection.count")
            Spacer(minLength: 0)
            Button {
                selectedItemIDs = selectedItemIDs == visibleItemIDs ? [] : visibleItemIDs
            } label: {
                Image(systemName: selectedItemIDs == visibleItemIDs && !visibleItemIDs.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(visibleItemIDs.isEmpty)
            .accessibilityLabel(Text(selectedItemIDs == visibleItemIDs ? LocalizedStringKey("Limpar seleção") : LocalizedStringKey("Selecionar todos")))
            .accessibilityIdentifier("savoria.lists.selection.all")
            Menu {
                if selectedSubtab != .utensils {
                    if selectedSubtab != .pantry {
                        Button("Mover para Despensa", systemImage: "refrigerator") { applyBulkAction(.move(.pantry)) }
                    }
                    if settings?.showReserve == true && selectedSubtab != .reserve {
                        Button("Mover para depois", systemImage: "tray") { applyBulkAction(.move(.reserve)) }
                    }
                    if selectedSubtab != .grocery {
                        Button("Mover para Mercado", systemImage: "cart") { applyBulkAction(.move(.grocery)) }
                    }
                }
                Button("Alterar categoria", systemImage: "square.grid.2x2") { showsBulkCategories = true }
            } label: {
                Label("Ação", systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .disabled(selectedItemIDs.isEmpty)
            .accessibilityIdentifier("savoria.lists.selection.actions")
            Button(action: finishItemSelection) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Cancelar")
            .accessibilityIdentifier("savoria.lists.selection.cancel")
        }
        .padding(.horizontal, 12)
        #if os(macOS)
        .foregroundStyle(.white)
        .tint(.white)
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .environment(\.colorScheme, .dark)
        #else
        .foregroundStyle(PageTheme.lists.accentColor)
        .background {
            if #available(iOS 26, macOS 26, *) {
                Capsule().fill(.clear).glassEffect(.regular.interactive(), in: .capsule)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        #endif
    }

    private func toggleItemSelection(_ id: UUID) {
        guard isSelectingItems, visibleItemIDs.contains(id) else { return }
        if selectedItemIDs.contains(id) { selectedItemIDs.remove(id) }
        else { selectedItemIDs.insert(id) }
    }

    private func updateVisibleItemIDs(_ ids: Set<UUID>) {
        if visibleItemIDs != ids { visibleItemIDs = ids }
        selectedItemIDs.formIntersection(ids)
    }

    private func finishItemSelection() {
        isSelectingItems = false
        selectedItemIDs = []
        showsBulkCategories = false
    }

    private func applyBulkAction(_ action: ListBulkAction) {
        guard isSelectingItems, !selectedItemIDs.isEmpty else { return }
        do {
            try ListBulkMutation.apply(action, selectedIDs: selectedItemIDs,
                                       source: selectedSubtab.removalContext, in: modelContext)
            finishItemSelection()
        } catch {
            showsBulkSaveError = true
        }
    }

    private var availableGroupingModes: [ListGroupingMode] {
        switch selectedSubtab {
        case .pantry: ListGroupingMode.allCases
        case .reserve: [.category]
        case .grocery: ListGroupingMode.allCases.filter { $0 != .validade }
        case .utensils: [.category]
        }
    }

    private var currentGroupingMode: ListGroupingMode {
        switch selectedSubtab {
        case .pantry: settings?.pantryGroupingMode ?? .category
        case .reserve: .category
        case .grocery: settings?.groceryGroupingMode ?? .marketSection
        case .utensils: .category
        }
    }

    private func setGroupingMode(_ mode: ListGroupingMode) {
        guard let settings else { return }
        switch selectedSubtab {
        case .pantry: settings.pantryGroupingMode = mode
        case .reserve: break
        case .grocery: settings.groceryGroupingMode = mode
        case .utensils: break
        }
    }

    private var subtabPicker: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                ListsSubtabDropButton(
                    tab: tab,
                    isSelected: selectedSubtab == tab,
                    badgeText: badgeText(for: tab),
                    isDropTargeted: targetedTab == tab,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSubtab = tab
                        }
                    },
                    onDrop: { payload in
                        moveDraggedItem(payload, to: tab)
                    },
                    onTargetChange: { isTargeted in
                        targetedTab = isTargeted ? tab : (targetedTab == tab ? nil : targetedTab)
                    }
                )
            }
        }
        .padding(4)
        .background(neutralSurfaceColor, in: .rect(cornerRadius: 12))
    }

    private func badgeText(for tab: ListSubtab) -> String? {
        let badgeValue: Int
        switch tab {
        case .pantry:
            badgeValue = pantryBadge
        case .grocery:
            badgeValue = groceryBadge
        case .reserve, .utensils:
            badgeValue = 0
        }
        return badgeValue > 0 ? "+\(badgeValue)" : nil
    }
    private func moveDraggedItem(_ payload: ListsDragPayload, to destination: ListSubtab) {
        guard !isSelectingItems else { return }
        guard payload.sourceList != destination else { return }

        guard payload.sourceList != .utensils, destination != .utensils,
              let item = item(withID: payload.itemID) else { return }
        item.move(to: destination.removalContext)
        selectedSubtab = destination
        try? modelContext.save()
    }

    private func item(withID itemID: UUID) -> UnifiedItem? {
        var descriptor = FetchDescriptor<UnifiedItem>(
            predicate: #Predicate<UnifiedItem> { item in
                item.id == itemID
            }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            PerformanceLogger.error(
                .tabSwitch,
                "ListsTabView drag item fetch failed",
                metadata: "itemID=\(itemID.uuidString) error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    private func sortIcon(for option: ListsSortOption) -> String {
        switch option {
        case .custom: "line.3.horizontal"
        case .name: "textformat.abc"
        case .addedAt: "calendar"
        case .expirationDate: "clock.badge.exclamationmark"
        }
    }

    private func updateInlineTitle(_ offset: CGFloat) {
        // Only the threshold is consumed by the title and tab-retap behavior.
        // Persisting every pixel in @State rebuilt the entire list per frame.
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
        }
    }

    private func handleActiveTabRetap() {
        if isNearTop {
            advanceToNextVisibleSubtab()
        } else {
            contentResetToken += 1
        }
    }

    private var isNearTop: Bool {
        !showsInlineTitle
    }

    private func advanceToNextVisibleSubtab() {
        guard visibleTabs.count > 1,
              let currentIndex = visibleTabs.firstIndex(of: selectedSubtab) else { return }
        let nextIndex = visibleTabs.index(after: currentIndex)
        selectedSubtab = nextIndex < visibleTabs.endIndex ? visibleTabs[nextIndex] : visibleTabs[visibleTabs.startIndex]
    }

    private func openNewItemSheet() {
        switch selectedSubtab {
        case .pantry:
            showAddPantry = true
        case .reserve:
            showAddReserve = true
        case .grocery:
            showAddGrocery = true
        case .utensils:
            showAddUtensil = true
        }
    }

    private func openExistingItemFromCreateFlow(_ item: UnifiedItem) {
        showAddPantry = false
        showAddGrocery = false
        showAddReserve = false
        showAddUtensil = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            existingItemFromCreateFlow = UnifiedItemSelection(id: item.id)
        }
    }

}

private struct ListsSubtabDropButton: View {
    let tab: ListSubtab
    let isSelected: Bool
    let badgeText: String?
    let isDropTargeted: Bool
    let onTap: () -> Void
    let onDrop: (ListsDragPayload) -> Void
    let onTargetChange: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                    .symbolRenderingMode(.monochrome)

                Text(tab.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color(.systemBackground) : .clear, in: .rect(cornerRadius: 10))
            .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 4, x: 0, y: 1)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .overlay {
            DropTargetHighlight(isActive: isDropTargeted)
        }
        .dropDestination(
            for: ListsDragPayload.self,
            action: { items, _ in
                guard let payload = items.first else { return false }
                onDrop(payload)
                return true
            },
            isTargeted: onTargetChange
        )
    }
}

