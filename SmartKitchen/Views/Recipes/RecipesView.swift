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
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.scrollToItem) private var scrollToItem
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @EnvironmentObject private var searchBarState: SearchBarState

    @State private var selectedCategory: String? = nil
    @State private var sortOption: RecipeSortOption = .dateAdded
    @State private var showAddRecipe = false
    @State private var showImportRecipe = false
    @State private var importInitialSource: RecipeImportSource? = nil
    @State private var pendingImportedRecipeID: UUID? = nil
    @State private var showImportedRecipeDetail = false
    @State private var showsInlineTitle = false
    @State private var editingRecipe: Recipe?
    @State private var showCompatibleOnly = false
    @State private var isShowingCadernos = false
    @State private var showNotebookManager = false
    @State private var currentScrollOffset: CGFloat = 0
    @State private var contentResetToken: Int = 0
    @State private var highlightedRecipeID: UUID?
    @State private var pendingRecipeScrollID: UUID?
    @State private var selectedRecipeID: UUID?
    @State private var categoryBarCenterToken: Int = 0

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
        if !searchBarState.searchText.isEmpty {
            let searchText = searchBarState.searchText
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by category
        if let cat = selectedCategory {
            result = result.filter { recipe in
                recipe.categories.contains(where: { CategoryMutationService.matchesName($0, cat) })
            }
        }

        if showCompatibleOnly {
            result = result.filter { (compatibilities[$0.id]?.matchedIngredients ?? 0) > 0 }
        }

        return sortRecipes(result)
    }

    private var groupedRecipes: [(category: String, recipes: [Recipe])] {
        // Group recipes supporting multi-category (comma-separated)
        var grouped: [String: [Recipe]] = [:]
        for recipe in recipes {
            let cats = recipe.categories
            if cats.isEmpty {
                grouped["", default: []].append(recipe)
            } else {
                for cat in cats {
                    grouped[cat, default: []].append(recipe)
                }
            }
        }

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

    private var notebookSummaries: [RecipeNotebookSummary] {
        let searchText = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return recipeCategories.compactMap { category in
            let matchingRecipes = recipesForNotebook(named: category.name)
            
            // Collect all compatibilities for the matching recipes
            let matchedCompatibilities = matchingRecipes.compactMap { recipe in 
                compatibilities[recipe.id] 
            }

            let summary = RecipeNotebookSummary(
                category: category,
                recipes: matchingRecipes,
                compatibilities: matchedCompatibilities
            )

            guard !searchText.isEmpty else { return summary }

            let categoryMatches = category.name.localizedCaseInsensitiveContains(searchText)
            let recipeMatches = matchingRecipes.contains { recipe in
                recipe.name.localizedCaseInsensitiveContains(searchText) ||
                recipe.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }

            return (categoryMatches || recipeMatches) ? summary : nil
        }
    }

    private var recipeCategoryNamesSignature: String {
        recipeCategories.map(\.name).joined(separator: "|")
    }

    private var galleryColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 1)]
        #else
        Array(repeating: GridItem(.flexible(), spacing: 1), count: settings?.recipeGalleryColumns ?? 3)
        #endif
    }

    private var notebookColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .recipes,
            header: { isInverted in
                #if os(macOS)
                if !isShowingCadernos,
                   let recipeID = selectedRecipeID,
                   let recipe = allRecipes.first(where: { $0.id == recipeID }) {
                    macRecipeDetailHeader(recipe: recipe, isInverted: isInverted)
                } else {
                    recipesListHeader(isInverted: isInverted)
                }
                #else
                recipesListHeader(isInverted: isInverted)
                #endif
            },
            content: {
                #if os(macOS)
                if isShowingCadernos {
                    cadernosContent
                } else if let recipeID = selectedRecipeID,
                   let recipe = allRecipes.first(where: { $0.id == recipeID }) {
                    RecipeDetailView(recipe: recipe)
                } else {
                    recipesListContent
                }
                #else
                recipesListContent
                #endif
            },
            infoContent: {
                EmptyView()
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
        #endif
        .tint(PageTheme.recipes.accentColor)
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                AddRecipeView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showImportRecipe) {
            RecipeImportHostView(initialSource: importInitialSource) { recipeID in
                highlightedRecipeID = recipeID
                selectedRecipeID = recipeID
                pendingImportedRecipeID = recipeID
            }
            .modelContainer(CloudSyncService.shared.container)
            .forceLightStatusBar()
            .onDisappear {
                importInitialSource = nil
                if pendingImportedRecipeID != nil {
                    showImportedRecipeDetail = true
                }
            }
        }
        .sheet(isPresented: $showImportedRecipeDetail, onDismiss: {
            pendingImportedRecipeID = nil
        }) {
            if let recipeID = pendingImportedRecipeID,
               let recipe = allRecipes.first(where: { $0.id == recipeID }) {
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                }
                .forceLightStatusBar()
            } else {
                ContentUnavailableView(
                    "Receita salva",
                    systemImage: "checkmark.circle.fill",
                    description: Text("A receita foi criada, mas ainda não ficou disponível para visualização.")
                )
                .presentationBackground(.white)
            }
        }
        .sheet(item: $editingRecipe) { recipe in
            NavigationStack {
                EditRecipeView(recipe: recipe)
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showNotebookManager) {
            NavigationStack {
                RecipeNotebookManagerSheet()
            }
            .forceLightStatusBar()
        }
        #if os(macOS)
        .focusedSceneValue(
            \.newItemCommandAction,
            NewItemCommandAction(title: "Nova Receita", perform: { showAddRecipe = true })
        )
        .background(Color(.windowBackgroundColor).ignoresSafeArea())
        #endif
        .onAppear {
            recomputeCompatibilities()
            handleScrollToItemRequest(scrollToItem)
        }
        .onChange(of: pantryItems) { _, _ in recomputeCompatibilities() }
        .onChange(of: allRecipes) { _, _ in recomputeCompatibilities() }
        .onChange(of: recipeCategoryNamesSignature) { _, _ in
            normalizeSelectedCategoryIfNeeded()
        }
        .onChange(of: scrollToItem) { _, request in
            handleScrollToItemRequest(request)
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            handleActiveTabRetap()
        }
    }

    // MARK: - Headers

    @ViewBuilder
    private func recipesListHeader(isInverted: Bool) -> some View {
        PageHeader(title: isShowingCadernos ? "Cadernos" : "Receitas", isInverted: isInverted) {
            HStack(spacing: 6) {
                GlassButtonGroup {
                    GlassGroupMenu(systemImage: "plus") {
                        Button {
                            showImportRecipe = true
                        } label: {
                            Label("Importar receita", systemImage: "sparkles")
                        }
                        Divider()
                        Button {
                            showAddRecipe = true
                        } label: {
                            Label("Criar do zero", systemImage: "square.and.pencil")
                        }
                    }
                }

                if isShowingCadernos {
                    GlassButtonGroup {
                        GlassGroupButton(systemImage: "slider.horizontal.3") {
                            showNotebookManager = true
                        }
                    }
                }

                if !isShowingCadernos {
                    GlassButtonGroup {
                        optionsMenu
                    }
                }

                GlassButtonGroup {
                    GlassGroupButton(systemImage: isShowingCadernos ? "book.closed" : "books.vertical") {
                        toggleNotebookPage()
                    }
                }

                SettingsButton()
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func macRecipeDetailHeader(recipe: Recipe, isInverted: Bool) -> some View {
        HStack(alignment: .center) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedRecipeID = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Receitas")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PageTheme.recipes.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                GlassButtonGroup {
                    GlassGroupMenu(systemImage: "ellipsis.circle") {
                        Button("Editar", systemImage: "pencil") {
                            editingRecipe = recipe
                        }
                        Button(
                            recipe.isFavorite ? "Desfavoritar" : "Favoritar",
                            systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                        ) {
                            recipe.isFavorite.toggle()
                        }
                    }
                }

                SettingsButton()
            }
        }
        .padding(.horizontal)
    }
    #endif

    // MARK: - List Content

    @ViewBuilder
    private var recipesListContent: some View {
        if isShowingCadernos {
            cadernosContent
        } else {
            Group {
                if allRecipes.isEmpty {
                    emptyState
                } else if recipes.isEmpty {
                    searchEmptyState
                } else {
                    recipeContent
                }
            }
            .id(contentResetToken)
        }
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
            // Category filter chips
            categoryFilter

            ScrollViewReader { proxy in
                ScrollView {
                    if viewMode == .gallery {
                        galleryView
                    } else {
                        listView
                    }
                }
                .onAppear {
                    scrollToPendingRecipeIfNeeded(with: proxy)
                }
                .onChange(of: pendingRecipeScrollID) { _, _ in
                    scrollToPendingRecipeIfNeeded(with: proxy)
                }
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    filterChip(
                        label: "Todos",
                        iconFileName: "recipe.png",
                        fallbackSymbol: "square.grid.2x2",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                        categoryBarCenterToken += 1
                    }
                    .id(categoryFilterChipID(for: nil))

                    ForEach(recipeCategories) { category in
                        filterChip(
                            label: category.name,
                            iconFileName: category.iconName,
                            fallbackSymbol: recipeCategorySymbol(for: category.name),
                            isSelected: selectedCategory == category.name
                        ) {
                            selectedCategory = category.name
                            categoryBarCenterToken += 1
                        }
                        .id(categoryFilterChipID(for: category.name))
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255), in: .rect(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .onAppear {
                centerSelectedCategoryIfNeeded(using: proxy, animated: false)
            }
            .onChange(of: selectedCategory) { _, _ in
                centerSelectedCategoryIfNeeded(using: proxy)
            }
            .onChange(of: categoryBarCenterToken) { _, _ in
                centerSelectedCategoryIfNeeded(using: proxy)
            }
            .onChange(of: recipeCategoryNamesSignature) { _, _ in
                centerSelectedCategoryIfNeeded(using: proxy, animated: false)
            }
        }
    }

    private func filterChip(
        label: String,
        iconFileName: String? = nil,
        fallbackSymbol: String = "square.grid.2x2",
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IconImage(
                    name: label,
                    iconFileName: iconFileName,
                    fallbackSymbol: fallbackSymbol,
                    size: 18
                )
                .frame(width: 18, height: 18)

                Text(label)
                    .font(.footnote.weight(.medium))
            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isSelected ? Color(.systemBackground) : .clear, in: .rect(cornerRadius: 10))
                .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 4, x: 0, y: 1)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryFilterChipID(for categoryName: String?) -> String {
        "recipe-filter-" + (categoryName.map { CategoryMutationService.normalizedKey(for: $0) } ?? "all")
    }

    private func centerSelectedCategoryIfNeeded(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedCategory,
              recipeCategories.contains(where: { CategoryMutationService.matchesName($0.name, selectedCategory) }) else {
            return
        }

        let targetID = categoryFilterChipID(for: selectedCategory)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    // MARK: - Gallery

    private var galleryView: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(groupedRecipes, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if selectedCategory == nil {
                        recipeSectionHeader(group.category)
                    }

                    LazyVGrid(columns: galleryColumns, spacing: 1) {
                        let cols = settings?.recipeGalleryColumns ?? 3
                        ForEach(Array(group.recipes.enumerated()), id: \.element.id) { index, recipe in
                            recipeGalleryCard(recipe, cornerRadii: galleryCornerRadii(index: index, total: group.recipes.count, columns: cols))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 20)
        .gesture(
            MagnificationGesture()
                .onEnded { scale in
                    guard let settings = settings else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if scale < 0.8 {
                            // Pinch in -> smaller cards -> more columns
                            settings.recipeGalleryColumns = min(settings.recipeGalleryColumns + 1, 4)
                        } else if scale > 1.2 {
                            // Pinch out -> larger cards -> fewer columns
                            settings.recipeGalleryColumns = max(settings.recipeGalleryColumns - 1, 2)
                        }
                    }
                }
        )
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    // MARK: - List

    private var listView: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(groupedRecipes, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if selectedCategory == nil {
                        recipeSectionHeader(group.category)
                    }

                    recipeRows(group.recipes)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 20)
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func recipeGalleryCard(_ recipe: Recipe, cornerRadii: RectangleCornerRadii = .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16)) -> some View {
        let card = RecipeCardView(
            recipe: recipe,
            compatibility: compatibilities[recipe.id],
            columns: settings?.recipeGalleryColumns ?? 3,
            cornerRadii: cornerRadii
        )
        .overlay {
            if highlightedRecipeID == recipe.id {
                UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .shadow(color: .accentColor.opacity(0.4), radius: 8)
            }
        }

        #if os(macOS)
        card
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedRecipeID = recipe.id
                }
            }
            .contextMenu {
                recipeContextMenu(for: recipe)
            }
            .id(recipe.id)
        #else
        NavigationLink(value: recipe.id) {
            card
        }
        .buttonStyle(.plain)
        .contextMenu {
            recipeContextMenu(for: recipe)
        }
        .id(recipe.id)
        #endif
    }

    @ViewBuilder
    private func recipeRows(_ recipes: [Recipe]) -> some View {
        VStack(spacing: 10) {
            ForEach(recipes) { recipe in
                let row = RecipeRowView(
                    recipe: recipe,
                    compatibility: compatibilities[recipe.id]
                )
                .overlay {
                    if highlightedRecipeID == recipe.id {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .shadow(color: .accentColor.opacity(0.4), radius: 8)
                    }
                }

                #if os(macOS)
                row
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRecipeID = recipe.id
                        }
                    }
                    .contextMenu {
                        recipeContextMenu(for: recipe)
                    }
                    .id(recipe.id)
                #else
                NavigationLink(value: recipe.id) {
                    row
                }
                .buttonStyle(.plain)
                .contextMenu {
                    recipeContextMenu(for: recipe)
                }
                .id(recipe.id)
                #endif
            }
        }
    }

    private func recipeSectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.6))
            Spacer()
        }
        .textCase(nil)
        .padding(.vertical, 4)
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
                                Text("\(count) Colunas")
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
            categoryFilter

            ContentUnavailableView.search(text: searchBarState.searchText)
        }
    }

    private var cadernosContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Group {
                    if notebookSummaries.isEmpty {
                        if searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView {
                                Label("Sem Cadernos", systemImage: "books.vertical")
                            } description: {
                                Text("Crie seu primeiro caderno para organizar receitas por tema, refeição ou ocasião.")
                            }
                            .padding(.top, 36)
                        } else {
                            ContentUnavailableView.search(text: searchBarState.searchText)
                                .padding(.top, 36)
                        }
                    } else {
                        LazyVGrid(columns: notebookColumns, spacing: 12) {
                            ForEach(notebookSummaries) { summary in
                                RecipeNotebookCard(summary: summary) {
                                    openNotebook(named: summary.category.name)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)

                Button {
                    showNotebookManager = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.footnote.weight(.semibold))
                        Text("Gerenciar cadernos")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.94))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    // MARK: - Actions

    private func galleryCornerRadii(index: Int, total: Int, columns: Int) -> RectangleCornerRadii {
        let radius: CGFloat = 16
        let row = index / columns
        let col = index % columns
        let totalRows = (total + columns - 1) / columns
        let isFirstRow = row == 0
        let isLastRow = row == totalRows - 1
        let lastRowCount = total - (totalRows - 1) * columns
        let isFirstCol = col == 0
        let isLastCol = isLastRow ? (col == lastRowCount - 1) : (col == columns - 1)

        return RectangleCornerRadii(
            topLeading: (isFirstRow && isFirstCol) ? radius : 0,
            bottomLeading: (isLastRow && isFirstCol) ? radius : 0,
            bottomTrailing: (isLastRow && isLastCol) ? radius : 0,
            topTrailing: (isFirstRow && isLastCol) ? radius : 0
        )
    }

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
        currentScrollOffset = offset
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
        }
    }

    private func handleScrollToItemRequest(_ request: ScrollToItemRequest?) {
        guard let request, request.type == "recipe" else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isShowingCadernos = false
        }

        selectedCategory = nil
        highlightedRecipeID = request.itemID

        #if os(macOS)
        selectedRecipeID = request.itemID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                highlightedRecipeID = nil
            }
        }
        #else
        pendingRecipeScrollID = request.itemID
        #endif
    }

    private func scrollToPendingRecipeIfNeeded(with proxy: ScrollViewProxy) {
        guard let recipeID = pendingRecipeScrollID else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(recipeID, anchor: .center)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    highlightedRecipeID = recipeID
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        highlightedRecipeID = nil
                    }
                }
            }
            pendingRecipeScrollID = nil
        }
    }

    private func handleActiveTabRetap() {
        if isShowingCadernos {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                isShowingCadernos = false
            }
        } else if isNearTop {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                isShowingCadernos = true
                selectedRecipeID = nil
            }
        } else {
            contentResetToken += 1
        }
    }

    private var isNearTop: Bool {
        currentScrollOffset >= -24
    }

    private func recipesForNotebook(named categoryName: String) -> [Recipe] {
        allRecipes
            .filter { recipe in
                recipe.categories.contains(where: { CategoryMutationService.matchesName($0, categoryName) })
            }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite {
                    return lhs.isFavorite && !rhs.isFavorite
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func toggleNotebookPage() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isShowingCadernos.toggle()
            if isShowingCadernos {
                selectedRecipeID = nil
            }
        }
    }

    private func openNotebook(named categoryName: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            selectedCategory = categoryName
            categoryBarCenterToken += 1
            isShowingCadernos = false
            selectedRecipeID = nil
            contentResetToken += 1
        }
    }

    private func normalizeSelectedCategoryIfNeeded() {
        guard let selectedCategory else { return }

        if let canonicalName = CategoryMutationService.canonicalCategoryName(for: selectedCategory, type: .recipe, context: modelContext) {
            self.selectedCategory = canonicalName
        } else {
            self.selectedCategory = nil
        }
    }
}

private struct RecipeNotebookSummary: Identifiable {
    let category: Category
    let recipes: [Recipe]
    let compatibilities: [RecipeCompatibility]

    var id: UUID { category.id }
    var previewRecipes: [Recipe] { Array(recipes.prefix(3)) }
    var recipeCountAbbreviation: String { "\(recipes.count) rec." }
    var compatibilityAbbreviation: String {
        let compatibleCount = compatibilities.filter { $0.matchedIngredients > 0 }.count
        return "\(compatibleCount) comp."
    }
}

private let notebookSuggestedCardBackgroundColor = Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)

private struct RecipeNotebookCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showIconPicker = false

    let summary: RecipeNotebookSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RecipeNotebookPreviewStrip(summary: summary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 118)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Label {
                            Text(summary.recipeCountAbbreviation)
                        } icon: {
                            Image(systemName: "book.closed")
                                .font(.caption2)
                        }

                        Label {
                            Text(summary.compatibilityAbbreviation)
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(notebookSuggestedCardBackgroundColor, in: .rect(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            Button {
                showIconPicker = true
            } label: {
                HStack {
                    IconImage(
                        name: summary.category.name,
                        iconFileName: summary.category.iconName,
                        fallbackSymbol: recipeCategorySymbol(for: summary.category.name),
                        size: 18
                    )
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.72), in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(22)
        }
        .sheet(isPresented: $showIconPicker) {
            ItemIconPickerView(
                title: "Ícone do caderno",
                initialQuery: summary.category.name,
                currentIconFileName: summary.category.iconName,
                fallbackSymbol: recipeCategorySymbol(for: summary.category.name)
            ) { entry in
                summary.category.iconName = entry.nomeDoArquivo
                try? modelContext.save()
            }
            .forceLightStatusBar()
        }
    }
}

private struct RecipeNotebookPreviewStrip: View {
    let summary: RecipeNotebookSummary

    var body: some View {
        GeometryReader { geometry in
            if summary.previewRecipes.isEmpty {
                RecipeNotebookEmptyPreviewPlaceholder(category: summary.category)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                HStack(spacing: 1) {
                    ForEach(Array(summary.previewRecipes.enumerated()), id: \.element.id) { index, recipe in
                        RecipeNotebookPreviewTile(
                            recipe: recipe,
                            cornerRadii: previewCornerRadii(index: index, total: summary.previewRecipes.count)
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
        }
        .clipped()
    }

    private func previewCornerRadii(index: Int, total: Int) -> RectangleCornerRadii {
        let radius: CGFloat = 16

        if total == 1 {
            return .init(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
        }

        let isFirst = index == 0
        let isLast = index == total - 1

        return .init(
            topLeading: isFirst ? radius : 0,
            bottomLeading: isFirst ? radius : 0,
            bottomTrailing: isLast ? radius : 0,
            topTrailing: isLast ? radius : 0
        )
    }
}

private struct RecipeNotebookEmptyPreviewPlaceholder: View {
    let category: Category

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 244 / 255, green: 244 / 255, blue: 247 / 255),
                    Color(red: 236 / 255, green: 236 / 255, blue: 240 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: recipeCategorySymbol(for: category.name))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Sem receitas ainda.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct RecipeNotebookPreviewTile: View {
    let recipe: Recipe
    let cornerRadii: RectangleCornerRadii

    var body: some View {
        GeometryReader { geometry in
            previewImage(in: geometry.size)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadii: cornerRadii))
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func previewImage(in size: CGSize) -> some View {
        if let data = recipe.imageData, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            RecipeImagePlaceholderCompact(
                ingredients: (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder },
                darkenOverlay: false
            )
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

private struct RecipeNotebookManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]

    @State private var newNotebookName = ""
    @State private var iconEditingNotebook: Category?
    @State private var renamingNotebook: Category?
    @State private var renameDraft = ""
    @State private var notebookPendingDeletion: Category?
    @State private var showDeleteOptions = false
    @State private var showMoveDestinationSheet = false
    @State private var showDeleteRecipesConfirmation = false
    @State private var errorMessage: String?

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    var body: some View {
        List {
            Section("Novo caderno") {
                HStack(spacing: 12) {
                    TextField("Nome do caderno", text: $newNotebookName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    Button("Adicionar") {
                        addNotebook()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newNotebookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Cadernos") {
                ForEach(recipeCategories) { category in
                    HStack(spacing: 12) {
                        Button {
                            iconEditingNotebook = category
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                IconImage(
                                    name: category.name,
                                    iconFileName: category.iconName,
                                    fallbackSymbol: recipeCategorySymbol(for: category.name),
                                    size: 22
                                )
                                .frame(width: 34, height: 34)
                                .background(PageTheme.recipes.accentColor.opacity(0.12), in: .circle)

                                Image(systemName: "pencil.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PageTheme.recipes.accentColor)
                                    .background(Color(.systemBackground), in: .circle)
                                    .offset(x: 3, y: 3)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Alterar ícone de \(category.name)")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .font(.body.weight(.medium))

                            Text(recipeCountLabel(for: category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            renamingNotebook = category
                            renameDraft = category.name
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            notebookPendingDeletion = category
                            showDeleteOptions = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { source, destination in
                    CategoryMutationService.moveCategories(of: .recipe, from: source, to: destination, context: modelContext)
                    try? modelContext.save()
                }
            }

            Section {
                Text("Você pode renomear, reordenar ou remover qualquer caderno. Se um caderno tiver receitas, escolha antes se quer mover ou apagar essas receitas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .modalNavigationTitle("Gerenciar cadernos")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") {
                    dismiss()
                }
            }
            #else
            ToolbarItem {
                Button("Fechar") {
                    dismiss()
                }
            }
            #endif
        }
        .alert(
            "Renomear caderno",
            isPresented: Binding(
                get: { renamingNotebook != nil },
                set: { newValue in
                    if !newValue {
                        renamingNotebook = nil
                        renameDraft = ""
                    }
                }
            )
        ) {
            TextField("Nome", text: $renameDraft)
            Button("Cancelar", role: .cancel) {
                renamingNotebook = nil
                renameDraft = ""
            }
            Button("Salvar") {
                renameNotebook()
            }
        } message: {
            Text("Atualize o nome do caderno. As receitas ligadas a ele acompanham a mudança.")
        }
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Tente novamente.")
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: $showDeleteOptions,
            titleVisibility: .visible
        ) {
            if let notebookPendingDeletion {
                if recipeCount(for: notebookPendingDeletion) == 0 {
                    Button("Excluir caderno", role: .destructive) {
                        deleteNotebook(strategy: .reassign(toCategoryNamed: nil))
                    }
                } else {
                    if !CategoryMutationService.matchesName(notebookPendingDeletion.name, "Outros") {
                        Button("Mover receitas para Outros") {
                            deleteNotebook(strategy: .reassign(toCategoryNamed: "Outros"))
                        }
                    }

                    if otherRecipeCategories(excluding: notebookPendingDeletion).isEmpty == false {
                        Button("Mover receitas para outro caderno") {
                            showMoveDestinationSheet = true
                        }
                    }

                    Button("Apagar receitas deste caderno", role: .destructive) {
                        showDeleteRecipesConfirmation = true
                    }
                }
            }

            Button("Cancelar", role: .cancel) {
                resetDeletionFlow()
            }
        } message: {
            if let notebookPendingDeletion {
                Text("\(recipeCountLabel(for: notebookPendingDeletion)) serão afetadas por essa remoção.")
            }
        }
        .sheet(isPresented: $showMoveDestinationSheet, onDismiss: resetDeletionFlow) {
            NavigationStack {
                List {
                    if let notebookPendingDeletion {
                        ForEach(otherRecipeCategories(excluding: notebookPendingDeletion)) { category in
                            Button {
                                deleteNotebook(strategy: .reassign(toCategoryNamed: category.name))
                            } label: {
                                HStack(spacing: 12) {
                                    IconImage(
                                        name: category.name,
                                        iconFileName: category.iconName,
                                        fallbackSymbol: recipeCategorySymbol(for: category.name),
                                        size: 18
                                    )
                                    .frame(width: 22, height: 22)
                                    Text(category.name)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .modalNavigationTitle("Mover receitas")
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancelar") {
                            showMoveDestinationSheet = false
                        }
                    }
                    #else
                    ToolbarItem {
                        Button("Cancelar") {
                            showMoveDestinationSheet = false
                        }
                    }
                    #endif
                }
            }
            .forceLightStatusBar()
        }
        .sheet(item: $iconEditingNotebook) { category in
            ItemIconPickerView(
                title: "Ícone do caderno",
                initialQuery: category.name,
                currentIconFileName: category.iconName,
                fallbackSymbol: recipeCategorySymbol(for: category.name)
            ) { entry in
                category.iconName = entry.nomeDoArquivo
                try? modelContext.save()
            }
            .forceLightStatusBar()
        }
        .alert(
            "Apagar receitas deste caderno?",
            isPresented: $showDeleteRecipesConfirmation
        ) {
            Button("Cancelar", role: .cancel) {
                resetDeletionFlow()
            }
            Button("Apagar tudo", role: .destructive) {
                deleteNotebook(strategy: .deleteRecipes)
            }
        } message: {
            if let notebookPendingDeletion {
                Text("Essa ação remove o caderno e apaga definitivamente as receitas ligadas a \"\(notebookPendingDeletion.name)\".")
            }
        }
    }

    private var deletionDialogTitle: String {
        guard let notebookPendingDeletion else { return "Remover caderno" }
        return "Remover \"\(notebookPendingDeletion.name)\""
    }

    private func recipeCount(for category: Category) -> Int {
        allRecipes.filter { recipe in
            recipe.categories.contains(where: { CategoryMutationService.matchesName($0, category.name) })
        }.count
    }

    private func recipeCountLabel(for category: Category) -> String {
        let count = recipeCount(for: category)
        return count == 1 ? "1 receita" : "\(count) receitas"
    }

    private func otherRecipeCategories(excluding category: Category) -> [Category] {
        recipeCategories.filter { $0.id != category.id }
    }

    private func addNotebook() {
        let trimmed = newNotebookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try CategoryMutationService.createCategory(named: trimmed, type: .recipe, context: modelContext)
            try? modelContext.save()
            newNotebookName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameNotebook() {
        guard let renamingNotebook else { return }

        do {
            _ = try CategoryMutationService.renameCategory(renamingNotebook, to: renameDraft, context: modelContext)
            try? modelContext.save()
            self.renamingNotebook = nil
            renameDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNotebook(strategy: CategoryDeletionStrategy) {
        guard let notebookPendingDeletion else { return }

        do {
            _ = try CategoryMutationService.deleteCategory(notebookPendingDeletion, strategy: strategy, context: modelContext)
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }

        resetDeletionFlow()
    }

    private func resetDeletionFlow() {
        notebookPendingDeletion = nil
        showDeleteOptions = false
        showMoveDestinationSheet = false
        showDeleteRecipesConfirmation = false
    }
}

private func recipeCategorySymbol(for name: String) -> String {
    let normalizedName = name
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    switch normalizedName {
    case "Cafe da manha": return "sunrise"
    case "Almoco": return "fork.knife"
    case "Jantar": return "moon.stars"
    case "Lanche": return "takeoutbag.and.cup.and.straw"
    case "Sobremesa", "Doces e Sobremesas": return "birthday.cake"
    case "Bebida", "Bebidas": return "cup.and.saucer"
    default: return "square.grid.2x2"
    }
}

