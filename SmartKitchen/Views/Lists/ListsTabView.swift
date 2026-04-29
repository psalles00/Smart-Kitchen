import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

enum ListSubtab: String, CaseIterable, Codable {
    case pantry
    case grocery
    case utensils

    var title: LocalizedStringKey {
        switch self {
        case .pantry:  "Despensa"
        case .grocery: "Mercado"
        case .utensils: "Utensílios"
        }
    }

    var icon: String {
        switch self {
        case .pantry:  "refrigerator"
        case .grocery: "cart"
        case .utensils: "fork.knife"
        }
    }

    var newItemTitle: String {
        switch self {
        case .pantry: "Novo Item da Despensa"
        case .grocery: "Novo Item do Mercado"
        case .utensils: "Novo Utensílio"
        }
    }

    var removalContext: ItemListType {
        switch self {
        case .pantry: .pantry
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

struct ListsTabView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.scrollToItem) private var scrollToItem
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.pantrySortOrder) private var pantryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.grocerySortOrder) private var groceryItems: [UnifiedItem]
    @Query private var settingsArray: [AppSettings]

    @State private var selectedSubtab: ListSubtab
    @State private var showAddPantry = false
    @State private var showAddGrocery = false
    @State private var showAddUtensil = false
    @State private var existingItemFromCreateFlow: UnifiedItemSelection?
    @EnvironmentObject private var searchBarState: SearchBarState
    @State private var showsInlineTitle = false
    @State private var sortOption: ListsSortOption = .custom
    @State private var pantryFilter: PantryListFilterOption = .all
    @State private var groceryFilter: GroceryListFilterOption = .all
    @State private var targetedTab: ListSubtab?
    @State private var currentScrollOffset: CGFloat = 0
    @State private var contentResetToken: Int = 0

    @State private var pantryBadge: Int = 0
    @State private var groceryBadge: Int = 0

    private var settings: AppSettings? { settingsArray.first }

    private var visibleTabs: [ListSubtab] {
        var tabs: [ListSubtab] = [.pantry, .grocery]
        if settings?.showUtensils == true {
            tabs.append(.utensils)
        }
        return tabs
    }

    init(initialSubtab: ListSubtab = .pantry) {
        _selectedSubtab = State(initialValue: initialSubtab)
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .lists,
            header: { isInverted in
                PageHeader(title: String(localized: "Listas"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "plus") {
                                if selectedSubtab == .pantry {
                                    showAddPantry = true
                                } else if selectedSubtab == .utensils {
                                    showAddUtensil = true
                                } else {
                                    showAddGrocery = true
                                }
                            }
                        }

                        GlassButtonGroup {
                            optionsMenu
                        }

                        SettingsButton()
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
                                searchText: searchBarState.debouncedSearchText,
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
                        case .grocery:
                            GroceryListView(
                                searchText: searchBarState.debouncedSearchText,
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
                                searchText: searchBarState.debouncedSearchText,
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
                EmptyView()
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.lists.accentColor)
        .onChange(of: selectedSubtab) {
            searchBarState.searchText = ""
            showsInlineTitle = false
            currentScrollOffset = 0
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            handleActiveTabRetap()
        }
        .onChange(of: scrollToItem, initial: true) { _, request in
            guard let request else { return }
            switch request.type {
            case "pantryItem":
                selectedSubtab = .pantry
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

    private var optionsMenu: some View {
        GlassGroupMenu(systemImage: "line.3.horizontal.decrease.circle") {
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
    }

    private var availableGroupingModes: [ListGroupingMode] {
        switch selectedSubtab {
        case .pantry: ListGroupingMode.allCases
        case .grocery: ListGroupingMode.allCases.filter { $0 != .validade }
        case .utensils: [.category]
        }
    }

    private var currentGroupingMode: ListGroupingMode {
        switch selectedSubtab {
        case .pantry: settings?.pantryGroupingMode ?? .category
        case .grocery: settings?.groceryGroupingMode ?? .marketSection
        case .utensils: .category
        }
    }

    private func setGroupingMode(_ mode: ListGroupingMode) {
        guard let settings else { return }
        switch selectedSubtab {
        case .pantry: settings.pantryGroupingMode = mode
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
        case .utensils:
            badgeValue = 0
        }
        return badgeValue > 0 ? "+\(badgeValue)" : nil
    }
    private func moveDraggedItem(_ payload: ListsDragPayload, to destination: ListSubtab) {
        guard payload.sourceList != destination else { return }

        switch (payload.sourceList, destination) {
        case (.pantry, .grocery):
            guard let item = pantryItems.first(where: { $0.id == payload.itemID }) else { return }
            item.isGrocery = true
            item.isPantry = false
            selectedSubtab = .grocery
        case (.grocery, .pantry):
            guard let item = groceryItems.first(where: { $0.id == payload.itemID }) else { return }
            item.isPantry = true
            item.isGrocery = false
            if let days = item.defaultExpiryDays, days > 0 {
                item.expirationDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
            selectedSubtab = .pantry
        default:
            break
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
        currentScrollOffset = offset
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
        currentScrollOffset >= -24
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
        case .grocery:
            showAddGrocery = true
        case .utensils:
            showAddUtensil = true
        }
    }

    private func openExistingItemFromCreateFlow(_ item: UnifiedItem) {
        showAddPantry = false
        showAddGrocery = false
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
