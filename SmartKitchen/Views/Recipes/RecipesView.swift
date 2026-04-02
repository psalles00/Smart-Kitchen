import SwiftUI
import SwiftData

// MARK: - Sort Options

enum RecipeSortOption: String, CaseIterable {
    case name
    case dateAdded
    case prepTime
    case difficulty

    var label: LocalizedStringKey {
        switch self {
        case .name:       "Nome"
        case .dateAdded:  "Data"
        case .prepTime:   "Tempo de preparo"
        case .difficulty: "Dificuldade"
        }
    }

    var icon: String {
        switch self {
        case .name:       "textformat.abc"
        case .dateAdded:  "calendar"
        case .prepTime:   "clock"
        case .difficulty: "flame"
        }
    }
}

// MARK: - View

struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var sortOption: RecipeSortOption = .dateAdded
    @State private var showAddRecipe = false
    @State private var showSearch = false
    @State private var showsInlineTitle = false
    @State private var editingRecipe: Recipe?
    @State private var showCompatibleOnly = false
    @State private var showCategoryManager = false

    private var settings: AppSettings? { settingsArray.first }
    private var viewMode: RecipeViewMode { settings?.recipeViewMode ?? .gallery }
    private var compatibilityThreshold: Double {
        Double(settings?.recipeCompatibilityThresholdPercent ?? 80) / 100
    }

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    private var pantryNames: [String] {
        pantryItems.map {
            $0.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
        }
    }

    private var compatibilities: [UUID: RecipeCompatibility] {
        Dictionary(
            uniqueKeysWithValues: allRecipes.compactMap { recipe in
                guard let compatibility = recipe.compatibility(against: pantryNames) else { return nil }
                return (recipe.id, compatibility)
            }
        )
    }

    /// Filtered & sorted recipes.
    private var recipes: [Recipe] {
        var result = allRecipes

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by category
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if showCompatibleOnly {
            result = result.filter { compatibilityGroup(for: $0) != .incompatible }
        }

        return sortRecipes(result)
    }

    private var groupedRecipes: [(category: String, compatible: [Recipe], partial: [Recipe], other: [Recipe])] {
        let grouped = Dictionary(grouping: recipes) { $0.category }

        let categoryNames: [String]
        if let selectedCategory {
            categoryNames = [selectedCategory]
        } else {
            let configured = recipeCategories.map(\.name)
            let remaining = grouped.keys.filter { !configured.contains($0) }.sorted()
            categoryNames = configured + remaining
        }

        return categoryNames.compactMap { categoryName in
            let categoryRecipes = grouped[categoryName, default: []]
            let compatible = categoryRecipes.filter { compatibilityGroup(for: $0) == .compatible }
            let partial = categoryRecipes.filter { compatibilityGroup(for: $0) == .partial }
            let other = categoryRecipes.filter { compatibilityGroup(for: $0) == .incompatible }

            guard !compatible.isEmpty || !partial.isEmpty || !other.isEmpty else { return nil }
            return (categoryName, compatible, partial, other)
        }
    }

    private var galleryColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 12)]
        #else
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        #endif
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .recipes,
            header: { isInverted in
                PageHeader(title: "Receitas", isInverted: isInverted) {
                    HStack(spacing: 8) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "magnifyingglass") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    showSearch.toggle()
                                    if !showSearch { searchText = "" }
                                }
                            }
                        }

                        GlassButtonGroup {
                            optionsMenu
                            GlassGroupDivider()
                            GlassGroupButton(systemImage: "slider.horizontal.3") {
                                showCategoryManager = true
                            }
                        }

                        SettingsButton()
                    }
                }
            },
            content: {
                Group {
                    if allRecipes.isEmpty {
                        emptyState
                    } else if recipes.isEmpty {
                        searchEmptyState
                    } else {
                        recipeContent
                    }
                }
            },
            infoContent: {
                RecipesInfoContent()
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                AddRecipeView()
            }
        }
        .sheet(item: $editingRecipe) { recipe in
            NavigationStack {
                EditRecipeView(recipe: recipe)
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: .recipe)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var recipeContent: some View {
        VStack(spacing: 0) {
            ScrollOffsetReader(coordinateSpace: "expanded_scroll")

            CollapsibleSearchBar(
                text: $searchText,
                isPresented: $showSearch,
                placeholder: "Buscar receitas"
            )

            // Category filter chips
            categoryFilter

            if viewMode == .gallery {
                galleryView
            } else {
                listView
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "Todos", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(recipeCategories) { cat in
                    filterChip(label: cat.name, isSelected: selectedCategory == cat.name) {
                        selectedCategory = cat.name
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground), in: .capsule)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gallery

    private var galleryView: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groupedRecipes, id: \.category) { group in
                recipeGalleryCategorySection(group: group)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 20)
        .onScrollOffsetChange(perform: updateInlineTitle)
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groupedRecipes, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if selectedCategory == nil {
                        Text(group.category)
                            .font(.sectionTitle)
                            .padding(.horizontal, 2)
                    }

                    recipeListSubsection(title: "Compatíveis com a Despensa", recipes: group.compatible)
                    recipeListSubsection(title: "Parcialmente Compatíveis", recipes: group.partial)

                    if !showCompatibleOnly {
                        recipeListSubsection(title: "Outras Receitas", recipes: group.other)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 20)
        .onScrollOffsetChange(perform: updateInlineTitle)
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func recipeGalleryCategorySection(group: (category: String, compatible: [Recipe], partial: [Recipe], other: [Recipe])) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedCategory == nil {
                Text(group.category)
                    .font(.sectionTitle)
                    .padding(.horizontal, 2)
            }

            recipeGallerySubsection(title: "Compatíveis com a Despensa", recipes: group.compatible)
            recipeGallerySubsection(title: "Parcialmente Compatíveis", recipes: group.partial)

            if !showCompatibleOnly {
                recipeGallerySubsection(title: "Outras Receitas", recipes: group.other)
            }
        }
    }

    @ViewBuilder
    private func recipeGallerySubsection(title: String, recipes: [Recipe]) -> some View {
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                LazyVGrid(columns: galleryColumns, spacing: 12) {
                    ForEach(recipes) { recipe in
                        recipeGalleryCard(recipe)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recipeListSubsection(title: String, recipes: [Recipe]) -> some View {
        if !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(.secondary)

                recipeRows(recipes)
            }
        }
    }

    private func recipeGalleryCard(_ recipe: Recipe) -> some View {
        NavigationLink(value: recipe.id) {
            RecipeCardView(
                recipe: recipe,
                compatibility: compatibilities[recipe.id]
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            recipeContextMenu(for: recipe)
        }
    }

    @ViewBuilder
    private func recipeRows(_ recipes: [Recipe]) -> some View {
        VStack(spacing: 10) {
            ForEach(recipes) { recipe in
                NavigationLink(value: recipe.id) {
                    RecipeRowView(
                        recipe: recipe,
                        compatibility: compatibilities[recipe.id]
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    recipeContextMenu(for: recipe)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeContextMenu(for recipe: Recipe) -> some View {
        Button("Editar", systemImage: "pencil") {
            editingRecipe = recipe
        }
        Button(
            recipe.isFavorite ? "Desfavoritar" : "Favoritar",
            systemImage: recipe.isFavorite ? "heart.slash" : "heart"
        ) {
            recipe.isFavorite.toggle()
        }
        Divider()
        Button("Excluir", systemImage: "trash", role: .destructive) {
            deleteRecipe(recipe)
        }
    }

    // MARK: - Options Menu

    private var optionsMenu: some View {
        GlassGroupMenu(systemImage: "line.3.horizontal.decrease.circle") {
            Button("Categorias", systemImage: "slider.horizontal.3") {
                showCategoryManager = true
            }
            Section("Visualização") {
                ForEach(RecipeViewMode.allCases) { mode in
                    Button {
                        settings?.recipeViewMode = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.icon)
                        if viewMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section("Ordenar por") {
                ForEach(RecipeSortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        Label(option.label, systemImage: option.icon)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section("Filtros") {
                Button {
                    showCompatibleOnly.toggle()
                } label: {
                    Label("Mostrar só compatíveis", systemImage: showCompatibleOnly ? "checkmark.circle.fill" : "circle")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sem Receitas", systemImage: "book.closed")
        } description: {
            Text("Adicione suas receitas favoritas para tê-las sempre à mão.")
        } actions: {
            Button("Adicionar Receita") {
                showAddRecipe = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 0) {
            CollapsibleSearchBar(
                text: $searchText,
                isPresented: $showSearch,
                placeholder: "Buscar receitas"
            )

            categoryFilter

            ContentUnavailableView.search(text: searchText)
        }
    }

    // MARK: - Actions

    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
    }

    private func sortRecipes(_ recipes: [Recipe]) -> [Recipe] {
        var result = recipes

        result.sort { lhs, rhs in
            let left = compatibilities[lhs.id]
            let right = compatibilities[rhs.id]

            let leftGroup = compatibilityGroup(for: lhs).sortPriority
            let rightGroup = compatibilityGroup(for: rhs).sortPriority
            if leftGroup != rightGroup { return leftGroup < rightGroup }
            if left?.ratio != right?.ratio { return (left?.ratio ?? 0) > (right?.ratio ?? 0) }
            if left?.matchedIngredients != right?.matchedIngredients {
                return (left?.matchedIngredients ?? 0) > (right?.matchedIngredients ?? 0)
            }

            switch sortOption {
            case .name:
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            case .dateAdded:
                return lhs.createdAt > rhs.createdAt
            case .prepTime:
                return lhs.totalTime < rhs.totalTime
            case .difficulty:
                let order: [Difficulty] = [.easy, .medium, .hard]
                return (order.firstIndex(of: lhs.difficulty) ?? 0) < (order.firstIndex(of: rhs.difficulty) ?? 0)
            }
        }

        return result
    }

    private func compatibilityGroup(for recipe: Recipe) -> RecipeCompatibilityGroup {
        guard let compatibility = compatibilities[recipe.id] else { return .incompatible }
        if compatibility.ratio >= compatibilityThreshold {
            return .compatible
        }
        if compatibility.matchedIngredients > 0 {
            return .partial
        }
        return .incompatible
    }

    private func updateInlineTitle(_ offset: CGFloat) {
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
        }
    }
}

private enum RecipeCompatibilityGroup {
    case compatible
    case partial
    case incompatible

    var sortPriority: Int {
        switch self {
        case .compatible: 0
        case .partial: 1
        case .incompatible: 2
        }
    }
}
