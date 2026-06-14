import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToItem) private var scrollToItem
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.grocerySortOrder) private var allItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var editingItem: UnifiedItemSelection?
    @State private var acquiredItem: UnifiedItemSelection?
    @State private var targetedItemID: UUID?
    @State private var targetedCategoryName: String?
    @State private var highlightedItemID: UUID?

    let searchText: String
    let sortOption: ListsSortOption
    let filterOption: GroceryListFilterOption
    var onAcquired: (() -> Void)?
    var onPullToAdd: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private struct GroceryListSnapshot {
        let groups: [(String, [UnifiedItem])]
        let hasAnyItems: Bool
        let groupingMode: ListGroupingMode
        let categoryIconByName: [String: String]
    }

    private var activeGroupingMode: ListGroupingMode {
        settingsArray.first?.groceryGroupingMode ?? .marketSection
    }

    private func makeSnapshot() -> GroceryListSnapshot {
        let groupingMode = activeGroupingMode
        let listCategories = allCategories.filter { $0.type == .pantry || $0.type == .grocery }
        let categoryOrder = allCategories.filter { $0.type == .pantry }.map(\.name)
        let categoryIconByName = Dictionary(
            listCategories.compactMap { category in
                category.iconName.map { (category.name, $0) }
            },
            uniquingKeysWith: { current, _ in current }
        )
        let filteredItems = searchText.isEmpty
            ? allItems
            : allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        let keyForItem: (UnifiedItem) -> String = groupingMode == .marketSection
            ? { ItemDatabase.marketSection(for: $0.category) }
            : { $0.category }
        let grouped = Dictionary(grouping: filteredItems, by: keyForItem)
        let groups = grouped
            .map { key, items in (key, sortedItems(items)) }
            .sorted { lhs, rhs in
                if groupingMode == .marketSection {
                    let leftIdx = ItemDatabase.marketSectionOrder.firstIndex(of: lhs.0) ?? .max
                    let rightIdx = ItemDatabase.marketSectionOrder.firstIndex(of: rhs.0) ?? .max
                    if leftIdx != rightIdx { return leftIdx < rightIdx }
                } else {
                    let leftIdx = categoryOrder.firstIndex(of: lhs.0) ?? .max
                    let rightIdx = categoryOrder.firstIndex(of: rhs.0) ?? .max
                    if leftIdx != rightIdx { return leftIdx < rightIdx }
                }
                return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }

        return GroceryListSnapshot(
            groups: groups,
            hasAnyItems: !allItems.isEmpty,
            groupingMode: groupingMode,
            categoryIconByName: categoryIconByName
        )
    }

    var body: some View {
        let snapshot = makeSnapshot()

        Group {
            if !snapshot.hasAnyItems {
                emptyState
            } else if snapshot.groups.isEmpty {
                searchEmptyState
            } else {
                itemList(snapshot: snapshot)
            }
        }
        .sheet(item: $editingItem, onDismiss: { editingItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id, removalContext: .grocery)
                .forceLightStatusBar()
        }
        .sheet(item: $acquiredItem, onDismiss: { acquiredItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id, removalContext: .pantry)
                .forceLightStatusBar()
        }
    }

    private func itemList(snapshot: GroceryListSnapshot) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(snapshot.groups.enumerated()), id: \.element.0) { categoryIndex, entry in
                    grocerySection(categoryIndex: categoryIndex, category: entry.0, items: entry.1, snapshot: snapshot)
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollIndicators)
            #endif
            .scrollContentBackground(.hidden)
            .listSectionSeparator(.hidden)
            .coordinateSpace(name: "lists_scroll")
            .onScrollOffsetChange(perform: onScrollOffsetChange)
            .onChange(of: scrollToItem, initial: true) { _, request in
                guard let request, request.type == "groceryItem" else { return }
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
    private func grocerySection(categoryIndex: Int, category: String, items: [UnifiedItem], snapshot: GroceryListSnapshot) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                groceryRow(categoryIndex: categoryIndex, itemIndex: itemIndex, category: category, item: item, snapshot: snapshot)
            }
        } header: {
            groceryHeader(for: category, groupingMode: snapshot.groupingMode)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private func groceryRow(categoryIndex: Int, itemIndex: Int, category: String, item: UnifiedItem, snapshot: GroceryListSnapshot) -> some View {
        Button {
            editingItem = UnifiedItemSelection(id: item.id)
        } label: {
            GroceryItemRow(item: item, categoryIconName: snapshot.categoryIconByName[item.category], isAlsoInPantry: item.isPantry, showsDivider: itemIndex > 0) {
                acquireItem(item)
            }
            .contentShape(Rectangle())
            .overlay {
                DropTargetHighlight(isActive: targetedItemID == item.id)
            }
            .background(alignment: .top) {
                if categoryIndex == 0, itemIndex == 0 {
                    ScrollOffsetReader(coordinateSpace: "lists_scroll")
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuContent(for: item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label("Excluir", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !item.isPantry {
                Button {
                    copyToPantry(item)
                } label: {
                    Label("Em Ambos", systemImage: "square.on.square")
                }
                .tint(Color(red: 37/255, green: 79/255, blue: 34/255))
            }

            Button {
                acquireItem(item)
            } label: {
                Label(item.isPantry ? "Remover" : "Mover", systemImage: item.isPantry ? "refrigerator.fill" : "checkmark")
            }
            .tint(item.isPantry ? Color(red: 37/255, green: 79/255, blue: 34/255) : Color(red: 160/255, green: 58/255, blue: 19/255))
        }
        .draggable(ListsDragPayload(itemID: item.id, sourceList: .grocery)) {
            DragLiftPreviewCard(
                title: item.name,
                subtitle: category,
                systemImage: "cart"
            )
        }
        .dropDestination(
            for: ListsDragPayload.self,
            action: { droppedItems, _ in
                guard let payload = droppedItems.first else { return false }
                return handleDrop(payload, targetCategory: category, targetItem: item)
            },
            isTargeted: { isTargeted in
                if isTargeted {
                    targetedItemID = item.id
                    targetedCategoryName = nil
                } else if targetedItemID == item.id {
                    targetedItemID = nil
                }
            }
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(highlightedItemID == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .id(item.id)
    }

    private func groceryHeader(for category: String, groupingMode: ListGroupingMode) -> some View {
        HStack(spacing: 6) {
            Text(displayName(for: category, groupingMode: groupingMode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
            Spacer()
        }
        .textCase(nil)
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .background {
            DropTargetHighlight(isActive: targetedCategoryName == category)
        }
            .dropDestination(
                for: ListsDragPayload.self,
                action: { droppedItems, _ in
                    guard let payload = droppedItems.first else { return false }
                    return handleDrop(payload, targetCategory: category, targetItem: nil)
                },
                isTargeted: { isTargeted in
                    if isTargeted {
                        targetedCategoryName = category
                        targetedItemID = nil
                    } else if targetedCategoryName == category {
                        targetedCategoryName = nil
                    }
                }
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func displayName(for category: String, groupingMode: ListGroupingMode) -> String {
        switch groupingMode {
        case .category, .validade:
            return CategoryMutationService.localizedDisplayName(for: category, type: .pantry)
        case .marketSection:
            return category
        }
    }

    @ViewBuilder
    private func contextMenuContent(for item: UnifiedItem) -> some View {
        Group {
            Button("Editar", systemImage: "pencil") {
                editingItem = UnifiedItemSelection(id: item.id)
            }
            Button("Mover à Despensa", systemImage: "checkmark.circle") {
                acquireItem(item)
            }
            if !item.isPantry {
                Button("Em Ambos", systemImage: "square.on.square") {
                    copyToPantry(item)
                }
            }
            Button("Adquirir e Editar", systemImage: "square.and.pencil") {
                acquireItem(item, shouldEdit: true)
            }
            if item.isPantry {
                Label("Também na Despensa", systemImage: "refrigerator")
            }
            Divider()
            Button("Excluir", systemImage: "trash", role: .destructive) {
                deleteItem(item)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Lista Vazia", systemImage: "cart")
        } description: {
            Text("Adicione itens à lista de mercado para suas próximas compras.")
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private func acquireItem(_ item: UnifiedItem, shouldEdit: Bool = false) {
        withAnimation {
            item.isPantry = true
            item.isGrocery = false
            if let days = item.defaultExpiryDays, days > 0 {
                item.expirationDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
        }
        if shouldEdit {
            acquiredItem = UnifiedItemSelection(id: item.id)
        }
        onAcquired?()
    }

    private func copyToPantry(_ item: UnifiedItem) {
        guard !item.isPantry else { return }
        withAnimation {
            item.isPantry = true
        }
        onAcquired?()
    }

    private func deleteItem(_ item: UnifiedItem) {
        withAnimation {
            if item.isPantry || item.isUtensil {
                item.isGrocery = false
            } else {
                modelContext.delete(item)
            }
        }
    }

    private func sortedItems(_ items: [UnifiedItem]) -> [UnifiedItem] {
        switch sortOption {
        case .custom:
            return items.sorted { $0.grocerySortOrder < $1.grocerySortOrder }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .addedAt:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .expirationDate:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func handleDrop(_ payload: ListsDragPayload, targetCategory: String, targetItem: UnifiedItem?) -> Bool {
        let resolvedCategory: (String) -> String = { original in
            activeGroupingMode == .marketSection ? original : targetCategory
        }

        switch payload.sourceList {
        case .grocery:
            guard let sourceItem = allItems.first(where: { $0.id == payload.itemID }) else { return false }
            let previousCategory = sourceItem.category
            let newCategory = resolvedCategory(sourceItem.category)
            sourceItem.category = newCategory
            reorderGroceryItem(sourceItem, in: newCategory, before: targetItem)
            normalizeGrocerySortOrder(in: previousCategory)
            return true
        case .pantry:
            // Find the unified item from pantry and flip flags
            let fd = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.isPantry })
            guard let pantryItems = try? modelContext.fetch(fd),
                  let item = pantryItems.first(where: { $0.id == payload.itemID }) else { return false }
            let newCategory = resolvedCategory(item.category)
            item.isGrocery = true
            item.isPantry = false
            item.category = newCategory
            reorderGroceryItem(item, in: newCategory, before: targetItem)
            return true
        case .utensils:
            return false
        }
    }

    private func reorderGroceryItem(_ movingItem: UnifiedItem, in category: String, before targetItem: UnifiedItem?) {
        var items = allItems
            .filter { $0.id != movingItem.id && $0.category == category }
            .sorted { $0.grocerySortOrder < $1.grocerySortOrder }

        let insertIndex = if let targetItem, let targetIndex = items.firstIndex(where: { $0.id == targetItem.id }) {
            targetIndex
        } else {
            items.count
        }

        items.insert(movingItem, at: insertIndex)
        for (index, item) in items.enumerated() {
            if item.grocerySortOrder != index { item.grocerySortOrder = index }
            if item.category != category { item.category = category }
        }
    }

    private func normalizeGrocerySortOrder(in category: String) {
        let items = allItems
            .filter { $0.category == category }
            .sorted { $0.grocerySortOrder < $1.grocerySortOrder }

        for (index, item) in items.enumerated() {
            if item.grocerySortOrder != index { item.grocerySortOrder = index }
        }
    }
}

struct GroceryItemRow: View {
    let item: UnifiedItem
    let categoryIconName: String?
    let isAlsoInPantry: Bool
    let showsDivider: Bool
    let onAcquire: () -> Void

    private var hasExtraData: Bool {
        item.imageData != nil
    }

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
                    fallbackSymbol: "basket",
                    size: 24,
                    showBalloon: true
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if hasExtraData {
                            Image(systemName: "camera")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        if isAlsoInPantry {
                            Image(systemName: "refrigerator")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(red: 37/255, green: 79/255, blue: 34/255).opacity(0.7))
                        }
                    }
                    subtitleLine
                }

                Spacer()

                AnimatedItemActionButton(
                    actionID: item.id.uuidString,
                    systemImage: "refrigerator",
                    initialSystemImage: "checkmark",
                    color: PageTheme.lists.accentColor,
                    action: onAcquire
                )
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var subtitleLine: some View {
        let description = item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuantity = item.quantity != nil
        let hasDescription = !description.isEmpty

        if hasQuantity || hasDescription {
            HStack(spacing: 0) {
                if hasDescription {
                    Text(description)
                        .lineLimit(1)
                }
                if hasDescription && hasQuantity {
                    Text("  ·  ")
                        .foregroundStyle(.quaternary)
                }
                if let qty = item.quantity {
                    let num = qty.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f", qty)
                        : String(format: "%.1f", qty)
                    let text = item.unit.map { u in u.isEmpty ? "\(num)x" : "\(num) \(u)" } ?? "\(num)x"
                    Text(text)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
