import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scrollToItem) private var scrollToItem
    @Query(sort: \PantryItem.sortOrder) private var allItems: [PantryItem]
    @Query(sort: \GroceryItem.sortOrder) private var groceryItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var editingItem: PantryItem?
    @State private var targetedItemID: UUID?
    @State private var targetedCategoryName: String?
    @State private var highlightedItemID: UUID?

    let searchText: String
    let sortOption: ListsSortOption
    let filterOption: PantryListFilterOption
    let expiringLeadDays: Int
    var onSentToGrocery: (() -> Void)?
    var onPullToAdd: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var settings: AppSettings? { settingsArray.first }
    private var isDetailed: Bool { settings?.pantryDetailLevel == .detailed }
    private var groupingMode: ListGroupingMode { settings?.pantryGroupingMode ?? .category }
    private var categoryOrder: [String] { allCategories.filter { $0.type == .pantry }.map(\.name) }

    private var filteredItems: [PantryItem] {
        var items = searchText.isEmpty
            ? allItems
            : allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        switch filterOption {
        case .all:
            break
        case .withExpiration:
            items = items.filter { $0.expirationDate != nil }
        case .expiringSoon:
            let now = Calendar.current.startOfDay(for: .now)
            let limit = Calendar.current.date(byAdding: .day, value: expiringLeadDays, to: now) ?? now
            items = items.filter {
                guard let expirationDate = $0.expirationDate else { return false }
                let day = Calendar.current.startOfDay(for: expirationDate)
                return day >= now && day <= limit
            }
        }

        return items
    }

    private var groupedItems: [(String, [PantryItem])] {
        if groupingMode == .validade {
            return expirationGroupedItems
        }

        let keyForItem: (PantryItem) -> String = groupingMode == .marketSection
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

    private var expirationGroupedItems: [(String, [PantryItem])] {
        let now = Calendar.current.startOfDay(for: .now)
        let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        let twoWeeks = Calendar.current.date(byAdding: .day, value: 14, to: now)!

        let sectionOrder = [
            "Expirados",
            "Expira hoje",
            "Expira nos próximos dias",
            "Expira nas próximas semanas",
            "Dentro da validade",
            "Sem validade"
        ]

        func sectionKey(for item: PantryItem) -> String {
            guard let expDate = item.expirationDate else { return "Sem validade" }
            let day = Calendar.current.startOfDay(for: expDate)
            if day < now { return "Expirados" }
            if day == now { return "Expira hoje" }
            if day <= threeDays { return "Expira nos próximos dias" }
            if day <= twoWeeks { return "Expira nas próximas semanas" }
            return "Dentro da validade"
        }

        let grouped = Dictionary(grouping: filteredItems, by: sectionKey)

        return sectionOrder.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            let sorted = items.sorted { a, b in
                let aDate = a.expirationDate ?? .distantFuture
                let bDate = b.expirationDate ?? .distantFuture
                return aDate < bDate
            }
            return (key, sorted)
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
                EditPantryItemView(item: item)
            }
            .forceLightStatusBar()
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(groupedItems.enumerated()), id: \.element.0) { categoryIndex, entry in
                    pantrySection(categoryIndex: categoryIndex, category: entry.0, items: entry.1)
                }
            }
            .listRowInsets(EdgeInsets())
            .padding(.top, -16) // Remove o espaçamento do topo da primeira seção
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
                guard let request, request.type == "pantryItem" else { return }
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
    private func pantrySection(categoryIndex: Int, category: String, items: [PantryItem]) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                pantryRow(categoryIndex: categoryIndex, itemIndex: itemIndex, category: category, item: item)
            }
        } header: {
            pantryHeader(for: category)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private func pantryRow(categoryIndex: Int, itemIndex: Int, category: String, item: PantryItem) -> some View {
        Button {
            editingItem = item
        } label: {
            let categoryIconName = allCategories.first(where: { $0.name == category && $0.type == .pantry })?.iconName
            let inGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            PantryItemRow(
                item: item,
                categoryIconName: categoryIconName,
                isDetailed: isDetailed,
                isAlsoInGrocery: inGrocery,
                onSendToGrocery: { sendToGrocery(item) },
                showsDivider: itemIndex > 0
            )
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
            let inGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            Button("Editar", systemImage: "pencil") {
                editingItem = item
            }
            Button("Mover ao Mercado", systemImage: "cart.badge.plus") {
                sendToGrocery(item)
            }
            if !inGrocery {
                Button("Copiar ao Mercado", systemImage: "doc.on.doc") {
                    copyToGrocery(item)
                }
            }
            if inGrocery {
                Label("Também no Mercado", systemImage: "cart")
            }
            Divider()
            Button("Excluir", systemImage: "trash", role: .destructive) {
                deleteItem(item)
            }
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
            let inGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }

            if !inGrocery {
                Button {
                    copyToGrocery(item)
                } label: {
                    Label("Copiar", systemImage: "cart.badge.plus")
                }
                .tint(.blue)
            }

            Button {
                sendToGrocery(item)
            } label: {
                Label(inGrocery ? "Remover" : "Mover", systemImage: inGrocery ? "cart.badge.minus" : "cart.badge.plus")
            }
            .tint(inGrocery ? .orange : .green)
        }
        .draggable(ListsDragPayload(itemID: item.id, sourceList: .pantry)) {
            DragLiftPreviewCard(
                title: item.name,
                subtitle: category,
                systemImage: "refrigerator"
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

    private func pantryHeader(for category: String) -> some View {
        HStack(spacing: 6) {
            Text(category)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Despensa Vazia", systemImage: "refrigerator")
        } description: {
            Text("Adicione itens à sua despensa para acompanhar o que você tem em casa.")
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private func deleteItem(_ item: PantryItem) {
        withAnimation {
            if item.isLinkedToGrocery {
                let grocery = GroceryItem(
                    name: item.name,
                    category: item.category,
                    iconName: item.iconName,
                    isFixed: true,
                    linkedPantryItemId: item.id,
                    defaultExpiryDays: expiryDaysForGrocery(from: item),
                    sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
                )
                modelContext.insert(grocery)
            }
            modelContext.delete(item)
        }
    }

    private func sendToGrocery(_ item: PantryItem) {
        // If already exists in grocery, just remove from pantry
        let alreadyInGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        if !alreadyInGrocery {
            let grocery = GroceryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                iconName: item.iconName,
                isFixed: item.isLinkedToGrocery,
                linkedPantryItemId: item.isLinkedToGrocery ? item.id : nil,
                defaultExpiryDays: expiryDaysForGrocery(from: item),
                sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            withAnimation {
                modelContext.insert(grocery)
            }
        }
        withAnimation {
            modelContext.delete(item)
            onSentToGrocery?()
        }
    }

    private func copyToGrocery(_ item: PantryItem) {
        // Check if already in grocery
        let alreadyInGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        guard !alreadyInGrocery else { return }
        let grocery = GroceryItem(
            name: item.name,
            category: item.category,
            quantity: item.quantity,
            unit: item.unit,
            iconName: item.iconName,
            isFixed: item.isLinkedToGrocery,
            linkedPantryItemId: item.isLinkedToGrocery ? item.id : nil,
            defaultExpiryDays: expiryDaysForGrocery(from: item),
            sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
        )
        withAnimation {
            modelContext.insert(grocery)
            onSentToGrocery?()
        }
    }

    private func sortedItems(_ items: [PantryItem]) -> [PantryItem] {
        switch sortOption {
        case .custom:
            return items.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.addedAt > $1.addedAt
            }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .addedAt:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .expirationDate:
            return items.sorted {
                switch ($0.expirationDate, $1.expirationDate) {
                case let (lhs?, rhs?): return lhs < rhs
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        }
    }

    private func handleDrop(_ payload: ListsDragPayload, targetCategory: String, targetItem: PantryItem?) -> Bool {
        // When grouping by market section, the drop target is a section name, not a category.
        // Keep the item's original category; only reorder within the visual group.
        let resolvedCategory: (String) -> String = { original in
            groupingMode == .marketSection ? original : targetCategory
        }

        switch payload.sourceList {
        case .pantry:
            guard let sourceItem = allItems.first(where: { $0.id == payload.itemID }) else { return false }
            let previousCategory = sourceItem.category
            let newCategory = resolvedCategory(sourceItem.category)
            sourceItem.category = newCategory
            reorderPantryItem(sourceItem, in: newCategory, before: targetItem)
            normalizePantrySortOrder(in: previousCategory)
            return true
        case .grocery:
            guard let groceryItem = groceryItems.first(where: { $0.id == payload.itemID }) else { return false }
            let newCategory = resolvedCategory(groceryItem.category)
            let pantryItem = PantryItem(
                name: groceryItem.name,
                category: newCategory,
                quantity: groceryItem.quantity,
                unit: groceryItem.unit,
                iconName: groceryItem.iconName,
                isLinkedToGrocery: groceryItem.isFixed,
                expirationDate: expirationDateForPantry(from: groceryItem),
                defaultExpiryDays: groceryItem.defaultExpiryDays
            )
            modelContext.insert(pantryItem)
            modelContext.delete(groceryItem)
            reorderPantryItem(pantryItem, in: newCategory, before: targetItem)
            return true
        case .utensils:
            return false
        }
    }

    private func reorderPantryItem(_ movingItem: PantryItem, in category: String, before targetItem: PantryItem?) {
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

    private func normalizePantrySortOrder(in category: String) {
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

struct PantryItemRow: View {
    let item: PantryItem
    let categoryIconName: String?
    let isDetailed: Bool
    let isAlsoInGrocery: Bool
    let onSendToGrocery: () -> Void
    let showsDivider: Bool

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
                IconImage(name: item.name, iconFileName: item.iconName ?? categoryIconName, fallbackSymbol: "leaf", size: 24, showBalloon: true)

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
                        if isAlsoInGrocery {
                            Image(systemName: "cart")
                                .font(.system(size: 9))
                                .foregroundStyle(.green.opacity(0.7))
                        }
                    }
                    subtitleLine
                }

                Spacer()

                if item.isLinkedToGrocery {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                AnimatedItemActionButton(
                    actionID: item.id.uuidString,
                    systemImage: "cart",
                    initialSystemImage: "xmark",
                    color: PageTheme.lists.accentColor,
                    action: onSendToGrocery
                )
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var subtitleLine: some View {
        let description = item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuantity = isDetailed && !item.formattedQuantity.isEmpty
        let hasExpiry = item.formattedExpirationDate != nil
        let hasDescription = !description.isEmpty

        if hasQuantity || hasExpiry || hasDescription {
            HStack(spacing: 0) {
                if hasDescription {
                    Text(description)
                        .lineLimit(1)
                }
                if hasDescription && (hasQuantity || hasExpiry) {
                    Text("  ·  ")
                        .foregroundStyle(.quaternary)
                }
                if hasQuantity {
                    Text(item.formattedQuantity)
                }
                if hasQuantity && hasExpiry {
                    Text("  ·  ")
                        .foregroundStyle(.quaternary)
                }
                if let expiration = item.formattedExpirationDate {
                    Text("Validade \(expiration)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
