import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToItem) private var scrollToItem
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \PantryItem.sortOrder) private var pantryItems: [PantryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var editingItem: GroceryItem?
    @State private var acquiredPantryItem: PantryItem?
    @State private var targetedItemID: UUID?
    @State private var targetedCategoryName: String?
    @State private var highlightedItemID: UUID?

    let searchText: String
    let sortOption: ListsSortOption
    let filterOption: GroceryListFilterOption
    var onAcquired: (() -> Void)?
    var onPullToAdd: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var groupingMode: ListGroupingMode { settingsArray.first?.groceryGroupingMode ?? .marketSection }
    private var categoryOrder: [String] { allCategories.filter { $0.type == .pantry }.map(\.name) }

    private var filteredItems: [GroceryItem] {
        let items = searchText.isEmpty
            ? allItems
            : allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return items
    }

    private var groupedItems: [(String, [GroceryItem])] {
        let keyForItem: (GroceryItem) -> String = groupingMode == .marketSection
            ? { ItemDatabase.marketSection(for: $0.category) }
            : { $0.category }

        let grouped = Dictionary(grouping: filteredItems, by: keyForItem)

        return grouped
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
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                emptyState
            } else if groupedItems.isEmpty {
                searchEmptyState
            } else {
                itemList
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                EditGroceryItemView(item: item)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $acquiredPantryItem) { item in
            NavigationStack {
                EditPantryItemView(item: item)
            }
            .forceLightStatusBar()
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(groupedItems.enumerated()), id: \.element.0) { categoryIndex, entry in
                    grocerySection(categoryIndex: categoryIndex, category: entry.0, items: entry.1)
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.plain)
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
    private func grocerySection(categoryIndex: Int, category: String, items: [GroceryItem]) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                groceryRow(categoryIndex: categoryIndex, itemIndex: itemIndex, category: category, item: item)
            }
        } header: {
            groceryHeader(for: category)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private func groceryRow(categoryIndex: Int, itemIndex: Int, category: String, item: GroceryItem) -> some View {
        Button {
            editingItem = item
        } label: {
            let categoryIconName = allCategories.first(where: { $0.name == category && $0.type == .grocery })?.iconName
            let inPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            GroceryItemRow(item: item, categoryIconName: categoryIconName, isAlsoInPantry: inPantry, showsDivider: itemIndex > 0) {
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
            let inPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }

            if !inPantry {
                Button {
                    copyToPantry(item)
                } label: {
                    Label("Copiar", systemImage: "checkmark")
                }
                .tint(.blue)
            }

            Button {
                acquireItem(item)
            } label: {
                Label(inPantry ? "Remover" : "Mover", systemImage: inPantry ? "refrigerator.fill" : "checkmark")
            }
            .tint(inPantry ? .orange : .green)
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

    private func groceryHeader(for category: String) -> some View {
        HStack(spacing: 6) {
            if let iconName = allCategories.first(where: { $0.name == category && ($0.type == .grocery || $0.type == .pantry) })?.iconName {
                IconImage(name: category, iconFileName: iconName, fallbackSymbol: "folder", size: 18)
            }
            Text(category)
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

    @ViewBuilder
    private func contextMenuContent(for item: GroceryItem) -> some View {
        let inPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        Button("Editar", systemImage: "pencil") {
            editingItem = item
        }
        Button("Mover à Despensa", systemImage: "checkmark.circle") {
            acquireItem(item)
        }
        if !inPantry {
            Button("Copiar à Despensa", systemImage: "doc.on.doc") {
                copyToPantry(item)
            }
        }
        Button("Adquirir e Editar", systemImage: "square.and.pencil") {
            acquireItem(item, shouldEdit: true)
        }
        if inPantry {
            Label("Também na Despensa", systemImage: "refrigerator")
        }
        Divider()
        Button("Excluir", systemImage: "trash", role: .destructive) {
            deleteItem(item)
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

    private func acquireItem(_ item: GroceryItem, shouldEdit: Bool = false) {
        // If already exists in pantry, just remove from grocery
        let alreadyInPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        var pantryItem: PantryItem?
        if !alreadyInPantry {
            let newPantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                iconName: item.iconName,
                isLinkedToGrocery: false,
                expirationDate: expirationDateForPantry(from: item),
                defaultExpiryDays: item.defaultExpiryDays,
                sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(newPantryItem)
            pantryItem = newPantryItem
        } else {
            pantryItem = pantryItems.first { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        }

        withAnimation {
            modelContext.delete(item)
        }

        if shouldEdit, let pantryItem {
            acquiredPantryItem = pantryItem
        }
        onAcquired?()
    }

    private func copyToPantry(_ item: GroceryItem) {
        // Check if already in pantry
        let alreadyInPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        guard !alreadyInPantry else { return }
        let pantryItem = PantryItem(
            name: item.name,
            category: item.category,
            quantity: item.quantity,
            unit: item.unit,
            iconName: item.iconName,
            isLinkedToGrocery: false,
            expirationDate: expirationDateForPantry(from: item),
            defaultExpiryDays: item.defaultExpiryDays,
            sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
        )
        withAnimation {
            modelContext.insert(pantryItem)
        }
        onAcquired?()
    }

    private func deleteItem(_ item: GroceryItem) {
        withAnimation {
            modelContext.delete(item)
        }
    }

    private func sortedItems(_ items: [GroceryItem]) -> [GroceryItem] {
        switch sortOption {
        case .custom:
            return items.sorted { $0.sortOrder < $1.sortOrder }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .addedAt:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .expirationDate:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func handleDrop(_ payload: ListsDragPayload, targetCategory: String, targetItem: GroceryItem?) -> Bool {
        let resolvedCategory: (String) -> String = { original in
            groupingMode == .marketSection ? original : targetCategory
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
            guard let pantryItem = pantryItems.first(where: { $0.id == payload.itemID }) else { return false }
            let newCategory = resolvedCategory(pantryItem.category)
            let groceryItem = GroceryItem(
                name: pantryItem.name,
                category: newCategory,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit,
                iconName: pantryItem.iconName,
                isFixed: pantryItem.isLinkedToGrocery,
                linkedPantryItemId: pantryItem.isLinkedToGrocery ? pantryItem.id : nil,
                defaultExpiryDays: expiryDaysForGrocery(from: pantryItem)
            )
            modelContext.insert(groceryItem)
            modelContext.delete(pantryItem)
            reorderGroceryItem(groceryItem, in: newCategory, before: targetItem)
            return true
        case .utensils:
            return false
        }
    }

    private func reorderGroceryItem(_ movingItem: GroceryItem, in category: String, before targetItem: GroceryItem?) {
        var items = allItems
            .filter { $0.id != movingItem.id && $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }

        let insertIndex = if let targetItem, let targetIndex = items.firstIndex(where: { $0.id == targetItem.id }) {
            targetIndex
        } else {
            items.count
        }

        items.insert(movingItem, at: insertIndex)
        for (index, item) in items.enumerated() {
            if item.sortOrder != index { item.sortOrder = index }
            if item.category != category { item.category = category }
        }
    }

    private func normalizeGrocerySortOrder(in category: String) {
        let items = allItems
            .filter { $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, item) in items.enumerated() {
            if item.sortOrder != index { item.sortOrder = index }
        }
    }

    private func expiryDaysForGrocery(from item: PantryItem) -> Int? {
        if let saved = item.defaultExpiryDays, saved > 0 { return saved }
        guard let expirationDate = item.expirationDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: expirationDate)
        ).day
        guard let days, days > 0 else { return nil }
        return days
    }

    private func expirationDateForPantry(from item: GroceryItem) -> Date? {
        guard let days = item.defaultExpiryDays, days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }
}

struct GroceryItemRow: View {
    let item: GroceryItem
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
                IconImage(name: item.name, iconFileName: item.iconName ?? categoryIconName, fallbackSymbol: "basket", size: 24, showBalloon: true)

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
                                .foregroundStyle(.orange.opacity(0.7))
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
