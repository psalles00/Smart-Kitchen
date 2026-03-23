import SwiftUI
import SwiftData

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.sortOrder) private var allItems: [PantryItem]
    @Query(sort: \GroceryItem.sortOrder) private var groceryItems: [GroceryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var editingItem: PantryItem?
    @State private var targetedItemID: UUID?
    @State private var targetedCategoryName: String?

    let searchText: String
    let sortOption: ListsSortOption
    let filterOption: PantryListFilterOption
    let expiringLeadDays: Int
    var onSentToGrocery: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var settings: AppSettings? { settingsArray.first }
    private var isDetailed: Bool { settings?.pantryDetailLevel == .detailed }
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
        let grouped = Dictionary(grouping: filteredItems) { $0.category }
        return grouped
            .map { category, items in
                (category, sortedItems(items))
            }
            .sorted { lhs, rhs in
                let leftIndex = categoryOrder.firstIndex(of: lhs.0) ?? .max
                let rightIndex = categoryOrder.firstIndex(of: rhs.0) ?? .max
                if leftIndex != rightIndex { return leftIndex < rightIndex }
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
                EditPantryItemView(item: item)
            }
        }
    }

    private var itemList: some View {
        List {
            ForEach(Array(groupedItems.enumerated()), id: \.element.0) { categoryIndex, entry in
                pantrySection(categoryIndex: categoryIndex, category: entry.0, items: entry.1)
            }
        }
        .listStyle(.plain)
        .coordinateSpace(name: "lists_scroll")
        .onScrollOffsetChange(perform: onScrollOffsetChange)
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
    }

    @ViewBuilder
    private func pantryRow(categoryIndex: Int, itemIndex: Int, category: String, item: PantryItem) -> some View {
        PantryItemRow(
            item: item,
            isDetailed: isDetailed,
            onSendToGrocery: { sendToGrocery(item) },
            onRemove: { deleteItem(item) }
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
        .onTapGesture {
            editingItem = item
        }
        .contextMenu {
            Button("Editar", systemImage: "pencil") {
                editingItem = item
            }
            Button("Enviar ao Mercado", systemImage: "cart.badge.plus") {
                sendToGrocery(item)
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
            .tint(.gray)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                sendToGrocery(item)
            } label: {
                Label("Mercado", systemImage: "cart.badge.plus")
            }
            .tint(.gray)
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
    }

    private func pantryHeader(for category: String) -> some View {
        Text(category)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
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
                    sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
                )
                modelContext.insert(grocery)
            }
            modelContext.delete(item)
        }
    }

    private func sendToGrocery(_ item: PantryItem) {
        let grocery = GroceryItem(
            name: item.name,
            category: item.category,
            quantity: item.quantity,
            unit: item.unit,
            iconName: item.iconName,
            isFixed: item.isLinkedToGrocery,
            linkedPantryItemId: item.isLinkedToGrocery ? item.id : nil,
            sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
        )
        withAnimation {
            modelContext.insert(grocery)
            modelContext.delete(item)
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
        switch payload.sourceList {
        case .pantry:
            guard let sourceItem = allItems.first(where: { $0.id == payload.itemID }) else { return false }
            let previousCategory = sourceItem.category
            sourceItem.category = targetCategory
            reorderPantryItem(sourceItem, in: targetCategory, before: targetItem)
            normalizePantrySortOrder(in: previousCategory)
            return true
        case .grocery:
            guard let groceryItem = groceryItems.first(where: { $0.id == payload.itemID }) else { return false }
            let pantryItem = PantryItem(
                name: groceryItem.name,
                category: targetCategory,
                quantity: groceryItem.quantity,
                unit: groceryItem.unit,
                iconName: groceryItem.iconName,
                isLinkedToGrocery: groceryItem.isFixed
            )
            modelContext.insert(pantryItem)
            modelContext.delete(groceryItem)
            reorderPantryItem(pantryItem, in: targetCategory, before: targetItem)
            return true
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
            item.sortOrder = index
            item.category = category
        }
    }

    private func normalizePantrySortOrder(in category: String) {
        let items = allItems
            .filter { $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }
}

struct PantryItemRow: View {
    let item: PantryItem
    let isDetailed: Bool
    let onSendToGrocery: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconImage(name: item.name, fallbackSymbol: "leaf", size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                if isDetailed, !item.formattedQuantity.isEmpty {
                    Text(item.formattedQuantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let expiration = item.formattedExpirationDate {
                    Text("Validade \(expiration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if item.isLinkedToGrocery {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            NeutralItemActionButton(systemImage: "cart.badge.plus", action: onSendToGrocery)
            NeutralItemActionButton(systemImage: "trash", action: onRemove)
        }
        .padding(.vertical, 4)
    }
}
