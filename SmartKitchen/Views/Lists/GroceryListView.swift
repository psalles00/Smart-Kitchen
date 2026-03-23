import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryItem.sortOrder) private var allItems: [GroceryItem]
    @Query(sort: \PantryItem.sortOrder) private var pantryItems: [PantryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var editingItem: GroceryItem?
    @State private var acquiredPantryItem: PantryItem?
    @State private var targetedItemID: UUID?
    @State private var targetedCategoryName: String?

    let searchText: String
    let sortOption: ListsSortOption
    let filterOption: GroceryListFilterOption
    var onAcquired: (() -> Void)?
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var categoryOrder: [String] { allCategories.filter { $0.type == .pantry }.map(\.name) }

    private var filteredItems: [GroceryItem] {
        var items = searchText.isEmpty
            ? allItems
            : allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        switch filterOption {
        case .all:
            break
        case .fixedOnly:
            items = items.filter(\.isFixed)
        case .regularOnly:
            items = items.filter { !$0.isFixed }
        }

        return items
    }

    private var groupedItems: [(String, [GroceryItem])] {
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
                EditGroceryItemView(item: item)
            }
        }
        .sheet(item: $acquiredPantryItem) { item in
            NavigationStack {
                EditPantryItemView(item: item)
            }
        }
    }

    private var itemList: some View {
        List {
            ForEach(Array(groupedItems.enumerated()), id: \.element.0) { categoryIndex, entry in
                grocerySection(categoryIndex: categoryIndex, category: entry.0, items: entry.1)
            }
        }
        .listStyle(.plain)
        .coordinateSpace(name: "lists_scroll")
        .onScrollOffsetChange(perform: onScrollOffsetChange)
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
    }

    @ViewBuilder
    private func groceryRow(categoryIndex: Int, itemIndex: Int, category: String, item: GroceryItem) -> some View {
        GroceryItemRow(item: item) {
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
        .onTapGesture {
            editingItem = item
        }
        .contextMenu {
            contextMenuContent(for: item)
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
                acquireItem(item)
            } label: {
                Label("Adquirir", systemImage: "checkmark")
            }
            .tint(.gray)
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
    }

    private func groceryHeader(for category: String) -> some View {
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

    @ViewBuilder
    private func contextMenuContent(for item: GroceryItem) -> some View {
        Button("Editar", systemImage: "pencil") {
            editingItem = item
        }
        Button("Adquirir", systemImage: "checkmark.circle") {
            acquireItem(item)
        }
        Button("Adquirir e Editar", systemImage: "square.and.pencil") {
            acquireItem(item, shouldEdit: true)
        }
        Button(
            item.isFixed ? "Desafixar" : "Fixar",
            systemImage: item.isFixed ? "pin.slash" : "pin"
        ) {
            item.isFixed.toggle()
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
        let pantryItem = PantryItem(
            name: item.name,
            category: item.category,
            quantity: item.quantity,
            unit: item.unit,
            iconName: item.iconName,
            isLinkedToGrocery: item.isFixed,
            sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(pantryItem)

        withAnimation {
            if item.isFixed {
                item.sortOrder = (allItems.map(\.sortOrder).max() ?? -1) + 1
            } else {
                modelContext.delete(item)
            }
        }

        if shouldEdit {
            acquiredPantryItem = pantryItem
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
        switch payload.sourceList {
        case .grocery:
            guard let sourceItem = allItems.first(where: { $0.id == payload.itemID }) else { return false }
            let previousCategory = sourceItem.category
            sourceItem.category = targetCategory
            reorderGroceryItem(sourceItem, in: targetCategory, before: targetItem)
            normalizeGrocerySortOrder(in: previousCategory)
            return true
        case .pantry:
            guard let pantryItem = pantryItems.first(where: { $0.id == payload.itemID }) else { return false }
            let groceryItem = GroceryItem(
                name: pantryItem.name,
                category: targetCategory,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit,
                iconName: pantryItem.iconName,
                isFixed: pantryItem.isLinkedToGrocery,
                linkedPantryItemId: pantryItem.isLinkedToGrocery ? pantryItem.id : nil
            )
            modelContext.insert(groceryItem)
            modelContext.delete(pantryItem)
            reorderGroceryItem(groceryItem, in: targetCategory, before: targetItem)
            return true
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
            item.sortOrder = index
            item.category = category
        }
    }

    private func normalizeGrocerySortOrder(in category: String) {
        let items = allItems
            .filter { $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }
}

struct GroceryItemRow: View {
    let item: GroceryItem
    let onAcquire: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconImage(name: item.name, fallbackSymbol: "basket", size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)

                if let qty = item.quantity {
                    let num = qty.truncatingRemainder(dividingBy: 1) == 0
                        ? String(format: "%.0f", qty)
                        : String(format: "%.1f", qty)
                    let text = item.unit.map { u in u.isEmpty ? "\(num)x" : "\(num) \(u)" } ?? "\(num)x"
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if item.isFixed {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            NeutralItemActionButton(systemImage: "arrow.down.circle", action: onAcquire)
        }
        .padding(.vertical, 4)
    }
}
