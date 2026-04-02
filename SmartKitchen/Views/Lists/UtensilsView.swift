import SwiftUI
import SwiftData

struct UtensilsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UtensilItem.sortOrder) private var allItems: [UtensilItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    let searchText: String
    let sortOption: ListsSortOption
    var onScrollOffsetChange: (CGFloat) -> Void = { _ in }

    private var utensilCategories: [Category] {
        allCategories.filter { $0.type == .utensil }
    }

    private var filteredItems: [UtensilItem] {
        let items: [UtensilItem]
        if searchText.isEmpty {
            items = Array(allItems)
        } else {
            items = allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOption {
        case .custom:
            return items.sorted { $0.sortOrder < $1.sortOrder }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .addedAt:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .expirationDate:
            return items.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private var groupedItems: [(String, [UtensilItem])] {
        let cats = utensilCategories.map(\.name)
        var groups: [(String, [UtensilItem])] = []
        for catName in cats {
            let items = filteredItems.filter { $0.category == catName }
            if !items.isEmpty { groups.append((catName, items)) }
        }
        let knownCats = Set(cats)
        let uncategorized = filteredItems.filter { !knownCats.contains($0.category) }
        if !uncategorized.isEmpty { groups.append(("Outros", uncategorized)) }
        return groups
    }

    var body: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "Nenhum utensílio" : "Sem resultados",
                systemImage: searchText.isEmpty ? "fork.knife" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Adicione seus utensílios de cozinha" : "Nenhum utensílio encontrado para \"\(searchText)\"")
            )
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(groupedItems.enumerated()), id: \.1.0) { categoryIndex, group in
                    let (categoryName, items) = group
                    Section {
                        ForEach(Array(items.enumerated()), id: \.1.id) { itemIndex, item in
                            UtensilItemRow(item: item, showsDivider: itemIndex > 0)
                                .contentShape(Rectangle())
                                .background(alignment: .top) {
                                    if categoryIndex == 0, itemIndex == 0 {
                                        ScrollOffsetReader(coordinateSpace: "lists_scroll")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteItem(item)
                                    } label: {
                                        Label("Remover", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteItem(item)
                                    } label: {
                                        Label("Remover", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        if groupedItems.count > 1 {
                            HStack {
                                let catIcon = utensilCategories.first(where: { $0.name == categoryName })
                                if let iconName = catIcon?.iconName {
                                    IconImage(name: iconName, fallbackSymbol: "fork.knife", size: 18)
                                }
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
            }
            .padding(.top, 8)
        }
    }

    private func deleteItem(_ item: UtensilItem) {
        withAnimation {
            modelContext.delete(item)
        }
    }
}

struct UtensilItemRow: View {
    let item: UtensilItem
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                ItemListDivider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .center, spacing: 12) {
                IconImage(name: item.name, iconFileName: item.iconName, fallbackSymbol: "fork.knife", size: 28, showBalloon: true)

                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }
}
