import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

enum ListSubtab: String, CaseIterable, Codable {
    case pantry
    case grocery

    var title: LocalizedStringKey {
        switch self {
        case .pantry:  "Despensa"
        case .grocery: "Mercado"
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
    case fixedOnly
    case regularOnly

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .all: "Todos"
        case .fixedOnly: "Fixos"
        case .regularOnly: "Não fixos"
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.sortOrder) private var pantryItems: [PantryItem]
    @Query(sort: \GroceryItem.sortOrder) private var groceryItems: [GroceryItem]
    @Query private var settingsArray: [AppSettings]

    @State private var selectedSubtab: ListSubtab
    @State private var showAddPantry = false
    @State private var showAddGrocery = false
    @State private var showCategoryManager = false
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showsInlineTitle = false
    @State private var sortOption: ListsSortOption = .custom
    @State private var pantryFilter: PantryListFilterOption = .all
    @State private var groceryFilter: GroceryListFilterOption = .all
    @State private var targetedTab: ListSubtab?

    @State private var pantryBadge: Int = 0
    @State private var groceryBadge: Int = 0

    private var settings: AppSettings? { settingsArray.first }

    init(initialSubtab: ListSubtab = .pantry) {
        _selectedSubtab = State(initialValue: initialSubtab)
    }

    var body: some View {
        VStack(spacing: 0) {
            CollapsibleSearchBar(
                text: $searchText,
                isPresented: $showSearch,
                placeholder: selectedSubtab == .pantry ? "Buscar na despensa" : "Buscar no mercado"
            )

            subtabPicker
                .padding(.horizontal)
                .padding(.top, 8)

            switch selectedSubtab {
            case .pantry:
                PantryView(
                    searchText: searchText,
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
                    onScrollOffsetChange: updateInlineTitle
                )
            case .grocery:
                GroceryListView(
                    searchText: searchText,
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
                    onScrollOffsetChange: updateInlineTitle
                )
            }
        }
        .navigationTitle("Listas")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Listas")
                    .font(.headline.weight(.semibold))
                    .opacity(showsInlineTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: showsInlineTitle)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        showSearch.toggle()
                        if !showSearch {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                optionsMenu

                Button {
                    if selectedSubtab == .pantry {
                        showAddPantry = true
                    } else {
                        showAddGrocery = true
                    }
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                SettingsButton()
            }
        }
        .onChange(of: selectedSubtab) {
            searchText = ""
            showsInlineTitle = false
        }
        .sheet(isPresented: $showAddPantry) {
            NavigationStack {
                AddPantryItemView()
            }
        }
        .sheet(isPresented: $showAddGrocery) {
            NavigationStack {
                AddGroceryItemView()
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .pantry, allowedTypes: [.pantry])
        }
    }

    private var optionsMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private var subtabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ListSubtab.allCases, id: \.self) { tab in
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
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func badgeText(for tab: ListSubtab) -> String? {
        let badgeValue = tab == .pantry ? pantryBadge : groceryBadge
        return badgeValue > 0 ? "+\(badgeValue)" : nil
    }
    private func moveDraggedItem(_ payload: ListsDragPayload, to destination: ListSubtab) {
        guard payload.sourceList != destination else { return }

        switch (payload.sourceList, destination) {
        case (.pantry, .grocery):
            guard let pantryItem = pantryItems.first(where: { $0.id == payload.itemID }) else { return }
            let groceryItem = GroceryItem(
                name: pantryItem.name,
                category: pantryItem.category,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit,
                iconName: pantryItem.iconName,
                isFixed: pantryItem.isLinkedToGrocery,
                linkedPantryItemId: pantryItem.isLinkedToGrocery ? pantryItem.id : nil,
                sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(groceryItem)
            modelContext.delete(pantryItem)
            selectedSubtab = .grocery
        case (.grocery, .pantry):
            guard let groceryItem = groceryItems.first(where: { $0.id == payload.itemID }) else { return }
            let pantryItem = PantryItem(
                name: groceryItem.name,
                category: groceryItem.category,
                quantity: groceryItem.quantity,
                unit: groceryItem.unit,
                iconName: groceryItem.iconName,
                isLinkedToGrocery: groceryItem.isFixed,
                sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(pantryItem)
            modelContext.delete(groceryItem)
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
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
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
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.subheadline.weight(.medium))

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
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
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
