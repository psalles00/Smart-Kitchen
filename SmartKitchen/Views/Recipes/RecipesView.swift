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

    // Cached expensive computations
    @State private var cachedPantryNames: [String] = []
    @State private var cachedCompatibilities: [UUID: RecipeCompatibility] = [:]

    private var settings: AppSettings? { settingsArray.first }
    private var viewMode: RecipeViewMode { settings?.recipeViewMode ?? .gallery }
    private var compatibilityThreshold: Double {
        Double(settings?.recipeCompatibilityThresholdPercent ?? 80) / 100
    }

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    private var compatibilities: [UUID: RecipeCompatibility] { cachedCompatibilities }

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
            result = result.filter { (compatibilities[$0.id]?.matchedIngredients ?? 0) > 0 }
        }

        return sortRecipes(result)
    }

    private var groupedRecipes: [(category: String, recipes: [Recipe])] {
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
            guard !categoryRecipes.isEmpty else { return nil }
            return (categoryName, categoryRecipes)
        }
    }

    private var galleryColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 12)]
        #else
        Array(repeating: GridItem(.flexible(), spacing: 12), count: settings?.recipeGalleryColumns ?? 2)
        #endif
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .recipes,
            header: { isInverted in
                PageHeader(title: "Receitas", isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "magnifyingglass") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    showSearch.toggle()
                                    if !showSearch { searchText = "" }
                                }
                            }
                        }

                        topControlsSeparator

                        GlassButtonGroup {
                            optionsMenu
                            GlassGroupDivider()
                            GlassGroupButton(systemImage: "slider.horizontal.3") {
                                showCategoryManager = true
                            }
                        }

                        topControlsSeparator

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
                EmptyView()
            },
            onRefresh: {
                showAddRecipe = true
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.recipes.accentColor)
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
        .onAppear { recomputeCompatibilities() }
        .onChange(of: pantryItems) { _, _ in recomputeCompatibilities() }
        .onChange(of: allRecipes) { _, _ in recomputeCompatibilities() }
    }

    private func recomputeCompatibilities() {
        let names = pantryItems.map {
            $0.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
        }
        cachedPantryNames = names
        cachedCompatibilities = Dictionary(
            uniqueKeysWithValues: allRecipes.compactMap { recipe in
                guard let compatibility = recipe.compatibility(against: names) else { return nil }
                return (recipe.id, compatibility)
            }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var recipeContent: some View {
        VStack(spacing: 0) {
            CollapsibleSearchBar(
                text: $searchText,
                isPresented: $showSearch,
                placeholder: "Buscar receitas"
            )

            // Category filter chips
            categoryFilter

            ScrollView {
                if viewMode == .gallery {
                    galleryView
                } else {
                    listView
                }
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                filterChip(label: "Todos", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(recipeCategories) { cat in
                    filterChip(label: cat.name, isSelected: selectedCategory == cat.name) {
                        selectedCategory = cat.name
                    }
                }
            }
            .padding(4)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color(.systemBackground) : .clear, in: .rect(cornerRadius: 10))
                .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 4, x: 0, y: 1)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var topControlsSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 1)
    }

    // MARK: - Gallery

    private var galleryView: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groupedRecipes, id: \.category) { group in
                VStack(alignment: .leading, spacing: 14) {
                    if selectedCategory == nil {
                        Text(group.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.72))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }

                    LazyVGrid(columns: galleryColumns, spacing: 12) {
                        ForEach(group.recipes) { recipe in
                            recipeGalleryCard(recipe)
                        }
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

    // MARK: - List

    private var listView: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groupedRecipes, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if selectedCategory == nil {
                        Text(group.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.72))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }

                    recipeRows(group.recipes)
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

                #if os(iOS)
                if viewMode == .gallery {
                    Divider()
                    Menu {
                        ForEach([2, 3, 4], id: \.self) { count in
                            Button {
                                settings?.recipeGalleryColumns = count
                            } label: {
                                Label("\(count) Colunas", systemImage: "square.grid.\(count == 2 ? "2x2" : count == 3 ? "3x2" : "4x3")")
                                if settings?.recipeGalleryColumns == count {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Label("Tamanho da Grade", systemImage: "circle.grid.2x2")
                    }
                }
                #endif
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

            // Primary: sort by pantry availability ratio (descending)
            let leftRatio = left?.ratio ?? 0
            let rightRatio = right?.ratio ?? 0
            if leftRatio != rightRatio { return leftRatio > rightRatio }

            // Secondary: sort by user-chosen option
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

    private func updateInlineTitle(_ offset: CGFloat) {
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
        }
    }
}
