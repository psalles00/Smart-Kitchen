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
    @State private var selectedRecipeID: UUID?

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
            let summary = RecipeNotebookSummary(category: category, recipes: matchingRecipes)

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
        .onAppear { recomputeCompatibilities() }
        .onChange(of: pantryItems) { _, _ in recomputeCompatibilities() }
        .onChange(of: allRecipes) { _, _ in recomputeCompatibilities() }
        .onChange(of: recipeCategoryNamesSignature) { _, _ in
            normalizeSelectedCategoryIfNeeded()
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

                GlassButtonGroup {
                    GlassGroupButton(systemImage: isShowingCadernos ? "book.closed" : "books.vertical") {
                        toggleNotebookPage()
                    }
                }

                if !isShowingCadernos {
                    GlassButtonGroup {
                        optionsMenu
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
                .onChange(of: scrollToItem) { _, request in
                    guard let request, request.type == "recipe" else { return }
                    isShowingCadernos = false
                    // Clear category filter so item is visible
                    selectedCategory = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(request.itemID, anchor: .center)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                highlightedRecipeID = request.itemID
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    highlightedRecipeID = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            filterChip(label: "Todos", systemImage: "square.grid.2x2", isSelected: selectedCategory == nil) {
                selectedCategory = nil
            }
            ForEach(recipeCategories) { cat in
                filterChip(label: cat.name, systemImage: categorySymbol(for: cat.name), isSelected: selectedCategory == cat.name) {
                    selectedCategory = cat.name
                }
            }
        }
        .padding(4)
        .background(Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                filterChip(label: "Todos", systemImage: "square.grid.2x2", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(recipeCategories) { cat in
                    filterChip(label: cat.name, systemImage: categorySymbol(for: cat.name), isSelected: selectedCategory == cat.name) {
                        selectedCategory = cat.name
                    }
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
        #endif
    }

    private func categorySymbol(for name: String) -> String {
        recipeCategorySymbol(for: name)
    }

    private func filterChip(label: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11))
                        .symbolRenderingMode(.monochrome)
                }
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
        #if os(iOS)
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
        #endif
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
        #if os(iOS)
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
        #endif
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Abra um caderno para voltar à lista principal já filtrada naquela categoria.")
                        .font(.serifBody)
                        .foregroundStyle(.secondary)

                    Text("Os previews usam as receitas mais recentes de cada caderno.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
                    ForEach(notebookSummaries) { summary in
                        RecipeNotebookCard(summary: summary) {
                            openNotebook(named: summary.category.name)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    showNotebookManager = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline.weight(.semibold))
                        Text("Gerenciar cadernos")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(PageTheme.recipes.accentColor.opacity(0.14), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 6)
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

    var id: UUID { category.id }
    var previewRecipes: [Recipe] { Array(recipes.prefix(3)) }
    var countLabel: String { recipes.count == 1 ? "1 receita" : "\(recipes.count) receitas" }

    var supportingText: String {
        if let firstRecipe = recipes.first {
            return firstRecipe.name
        }

        return "Sem receitas neste caderno ainda."
    }
}

private struct RecipeNotebookCard: View {
    let summary: RecipeNotebookSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RecipeNotebookPreviewFan(summary: summary)
                    .frame(width: 126, height: 108)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: recipeCategorySymbol(for: summary.category.name))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PageTheme.recipes.accentColor)
                            .frame(width: 34, height: 34)
                            .background(PageTheme.recipes.accentColor.opacity(0.12), in: .circle)

                        Text(summary.category.name)
                            .font(.cardTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        Label(summary.countLabel, systemImage: "book.pages")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if summary.recipes.contains(where: { $0.isFavorite }) {
                            Label("Favoritos", systemImage: "heart.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.pink.opacity(0.88))
                        }
                    }

                    Text(summary.supportingText)
                        .font(.subheadline)
                        .foregroundStyle(summary.recipes.isEmpty ? .secondary : .primary)
                        .lineLimit(2)

                    if !summary.recipes.isEmpty {
                        Text("Toque para abrir em Receitas")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color(red: 250 / 255, green: 244 / 255, blue: 235 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(PageTheme.recipes.accentColor.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecipeNotebookPreviewFan: View {
    let summary: RecipeNotebookSummary

    private let offsets: [(x: CGFloat, y: CGFloat, angle: Double)] = [
        (-20, 8, -11),
        (0, -6, 0),
        (22, 10, 11)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PageTheme.recipes.accentColor.opacity(0.16),
                            Color.white.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if summary.previewRecipes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: recipeCategorySymbol(for: summary.category.name))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PageTheme.recipes.accentColor)

                    Text("Novo caderno")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(summary.previewRecipes.enumerated()), id: \.element.id) { index, recipe in
                    RecipeNotebookPreviewTile(recipe: recipe)
                        .frame(width: 72, height: 92)
                        .rotationEffect(.degrees(offsets[index].angle))
                        .offset(x: offsets[index].x, y: offsets[index].y)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
                }

                if summary.recipes.count > 3 {
                    Text("+\(summary.recipes.count - 3)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PageTheme.recipes.accentColor, in: .capsule)
                        .offset(x: 26, y: 34)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct RecipeNotebookPreviewTile: View {
    let recipe: Recipe

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewImage

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(recipe.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var previewImage: some View {
        if let data = recipe.imageData, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RecipeImagePlaceholderCompact(
                ingredients: (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder },
                darkenOverlay: true
            )
        }
    }
}

private struct RecipeNotebookManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]

    @State private var newNotebookName = ""
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
                        Image(systemName: recipeCategorySymbol(for: category.name))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(PageTheme.recipes.accentColor)
                            .frame(width: 34, height: 34)
                            .background(PageTheme.recipes.accentColor.opacity(0.12), in: .circle)

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
        .navigationTitle("Gerenciar cadernos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") {
                    dismiss()
                }
            }
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
                                    Image(systemName: recipeCategorySymbol(for: category.name))
                                        .foregroundStyle(PageTheme.recipes.accentColor)
                                    Text(category.name)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Mover receitas")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancelar") {
                            showMoveDestinationSheet = false
                        }
                    }
                }
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
    switch name {
    case "Café da manhã": return "sunrise"
    case "Almoço": return "fork.knife"
    case "Jantar": return "moon.stars"
    case "Lanche": return "takeoutbag.and.cup.and.straw"
    case "Sobremesa": return "birthday.cake"
    case "Bebida": return "cup.and.saucer"
    default: return "square.grid.2x2"
    }
}
