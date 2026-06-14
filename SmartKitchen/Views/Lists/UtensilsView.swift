import SwiftUI
import SwiftData

struct UtensilsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToItem) private var scrollToItem
    @Query(filter: #Predicate<UnifiedItem> { $0.isUtensil }, sort: \UnifiedItem.utensilSortOrder) private var allItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @State private var editingItem: UnifiedItemSelection?
    @State private var highlightedItemID: UUID?

    let searchText: String
    let sortOption: ListsSortOption
    var onPullToAdd: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private struct UtensilsListSnapshot {
        let groups: [(String, [UnifiedItem])]
        let hasVisibleItems: Bool
        let categoryIconByName: [String: String]
    }

    private func makeSnapshot() -> UtensilsListSnapshot {
        let utensilCategories = allCategories.filter { $0.type == .utensil }
        let categoryIconByName = Dictionary(
            utensilCategories.compactMap { category in
                category.iconName.map { (category.name, $0) }
            },
            uniquingKeysWith: { current, _ in current }
        )
        let items: [UnifiedItem]
        if searchText.isEmpty {
            items = Array(allItems)
        } else {
            items = allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        let filteredItems: [UnifiedItem] = switch sortOption {
        case .custom:
            items.sorted { $0.utensilSortOrder < $1.utensilSortOrder }
        case .name:
            items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .addedAt:
            items.sorted { $0.addedAt > $1.addedAt }
        case .expirationDate:
            items.sorted { $0.utensilSortOrder < $1.utensilSortOrder }
        }

        let cats = utensilCategories.map(\.name)
        var groups: [(String, [UnifiedItem])] = []
        for catName in cats {
            let items = filteredItems.filter { $0.category == catName }
            if !items.isEmpty { groups.append((catName, items)) }
        }
        let knownCats = Set(cats)
        let uncategorized = filteredItems.filter { !knownCats.contains($0.category) }
        if !uncategorized.isEmpty { groups.append(("Outros", uncategorized)) }

        return UtensilsListSnapshot(
            groups: groups,
            hasVisibleItems: !filteredItems.isEmpty,
            categoryIconByName: categoryIconByName
        )
    }

    var body: some View {
        let snapshot = makeSnapshot()

        Group {
            if !snapshot.hasVisibleItems {
                ContentUnavailableView(
                    searchText.isEmpty ? "Nenhum utensílio" : "Sem resultados",
                    systemImage: searchText.isEmpty ? "fork.knife" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Adicione seus utensílios de cozinha" : "Nenhum utensílio encontrado para \"\(searchText)\"")
                )
                .padding(.top, 40)
            } else {
                itemList(snapshot: snapshot)
            }
        }
        .sheet(item: $editingItem, onDismiss: { editingItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id, removalContext: .utensil)
                .forceLightStatusBar()
        }
    }

    private func itemList(snapshot: UtensilsListSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Array(snapshot.groups.enumerated()), id: \.1.0) { categoryIndex, group in
                        utensilSection(
                            categoryIndex: categoryIndex,
                            categoryName: group.0,
                            items: group.1,
                            showsHeader: snapshot.groups.count > 1,
                            snapshot: snapshot
                        )
                    }
                }
                .padding(.top, 0)
            }
            #if os(iOS)
            .contentMargins(.top, 8, for: .scrollIndicators)
            #endif
            .coordinateSpace(name: "lists_scroll")
            .onScrollOffsetChange(perform: onScrollOffsetChange)
            .onChange(of: scrollToItem, initial: true) { _, request in
                guard let request, request.type == "utensil" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(request.itemID, anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            highlightedItemID = request.itemID
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                highlightedItemID = nil
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func utensilSection(
        categoryIndex: Int,
        categoryName: String,
        items: [UnifiedItem],
        showsHeader: Bool,
        snapshot: UtensilsListSnapshot
    ) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.1.id) { itemIndex, item in
                Button {
                    editingItem = UnifiedItemSelection(id: item.id)
                } label: {
                    UtensilItemRow(
                        item: item,
                        categoryIconName: snapshot.categoryIconByName[item.category],
                        showsDivider: itemIndex > 0
                    )
                        .contentShape(Rectangle())
                        .background(alignment: .top) {
                            if categoryIndex == 0, itemIndex == 0 {
                                ScrollOffsetReader(coordinateSpace: "lists_scroll")
                            }
                        }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Remover", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Editar", systemImage: "pencil") {
                        editingItem = UnifiedItemSelection(id: item.id)
                    }
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Remover", systemImage: "trash")
                    }
                }
                .id(item.id)
                .background(highlightedItemID == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
        } header: {
            if showsHeader {
                HStack {
                    Text(categoryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(.systemBackground))
            }
        }
    }

    private func deleteItem(_ item: UnifiedItem) {
        withAnimation {
            if item.isPantry || item.isGrocery {
                item.isUtensil = false
            } else {
                modelContext.delete(item)
            }
        }
    }
}

struct UtensilItemRow: View {
    let item: UnifiedItem
    let categoryIconName: String?
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                ItemListDivider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .center, spacing: 12) {
                IconImage(
                    name: item.name,
                    iconFileName: item.resolvedIconName(categoryIconName: categoryIconName),
                    fallbackSymbol: "fork.knife",
                    size: 24,
                    showBalloon: true
                )

                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }
}
