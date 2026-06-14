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
    var body: some View {
        #if os(iOS)
        DeferredTabPage(tab: .recipes, delay: .milliseconds(80)) {
            RecipesLoadedView()
        } placeholder: {
            RecipesSkeletonPage()
        }
        #else
        RecipesLoadedView()
        #endif
    }
}

#if os(iOS)
private struct RecipesSkeletonPage: View {
    var body: some View {
        ExpandedPageLayout(
            pageTheme: .recipes,
            header: { isInverted in
                PageHeader(title: String(localized: "Receitas"), isInverted: isInverted) {
                    HStack(spacing: 6) {
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "plus") {}
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "line.3.horizontal.decrease.circle") {}
                        }
                        GlassButtonGroup {
                            GlassGroupButton(systemImage: "books.vertical") {}
                        }
                        SettingsButton()
                    }
                    .disabled(true)
                }
            },
            content: {
                AppLaunchSkeletonPage(kind: .recipes, presentation: .contentOnly)
            },
            infoContent: {
                Color.clear.frame(height: ExpandedPageHeaderMetrics.iosEmptyInfoHeight)
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }
}
#endif

private struct NotebookLoadingSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.visiblePageTheme) private var visiblePageTheme

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                skeletonBlock(width: 138, height: 18, cornerRadius: 9, palette: .surface)
                skeletonBlock(width: 18, height: 18, cornerRadius: 9, palette: .surface)
                Spacer(minLength: 0)
                skeletonBlock(width: 42, height: 26, cornerRadius: 13, palette: .surface)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    notebookCard(index: index)
                }
            }
        }
        .appSkeletonShimmer()
        .allowsHitTesting(false)
    }

    private func notebookCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(panelFillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppSkeletonPalette.surface.strokeColor(for: colorScheme, pageTheme: skeletonPageTheme), lineWidth: 0.6)
                    }

                skeletonBlock(
                    width: index.isMultiple(of: 2) ? 76 : 88,
                    height: index.isMultiple(of: 2) ? 62 : 70,
                    cornerRadius: 20,
                    palette: .accent
                )
                .offset(x: 12, y: 10)

                VStack(alignment: .leading, spacing: 7) {
                    skeletonBlock(width: index.isMultiple(of: 2) ? 92 : 118, height: 14, cornerRadius: 7, palette: .surface)
                    skeletonBlock(width: 68, height: 10, cornerRadius: 5, palette: .surface)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 128)
            .clipShape(.rect(cornerRadius: 16))

            skeletonBlock(width: index.isMultiple(of: 2) ? 78 : 94, height: 11, cornerRadius: 5.5, palette: .surface)
                .padding(.leading, 6)
        }
    }

    private func skeletonBlock(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        palette: AppSkeletonPalette
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.baseColor(for: colorScheme, pageTheme: skeletonPageTheme))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.strokeColor(for: colorScheme, pageTheme: skeletonPageTheme), lineWidth: 0.6)
            }
            .frame(width: width, height: height)
    }

    private var skeletonPageTheme: PageTheme {
        visiblePageTheme ?? .recipes
    }

    private var panelFillColor: Color {
        colorScheme == .dark
            ? neutralSurfaceColor
            : Color(red: 0.94, green: 0.94, blue: 0.95)
    }
}

private struct RecipesLoadedView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.scrollToItem) private var scrollToItem
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var selectedCategory: String? = nil
    @State private var sortOption: RecipeSortOption = .dateAdded
    @State private var showAddRecipe = false
    @State private var showImportRecipe = false
    @State private var importInitialSource: RecipeImportSource? = nil
    @State private var importLaunchMode: RecipeImportLaunchMode = .picker
    @State private var pendingImportedRecipeID: UUID? = nil
    @State private var showsInlineTitle = false
    @State private var editingRecipe: RecipeSelection?
    @State private var showCompatibleOnly = false
    @State private var showFavoritesOnly = false
    @State private var isShowingCadernos = false
    @State private var showNotebookManager = false
    @State private var contentResetToken: Int = 0
    @State private var highlightedRecipeID: UUID?
    @State private var pendingRecipeScrollID: UUID?
    @State private var selectedRecipeID: UUID?
    @State private var categoryBarCenterToken: Int = 0
    @State private var isLocalSearchVisible = false
    @State private var localSearchText = ""
    #if os(macOS)
    @State private var macGalleryAvailableWidth: CGFloat = 0
    #endif

    // Cached expensive computations
    @State private var cachedPantryNames: [String] = []
    @State private var cachedCompatibilities: [UUID: RecipeCompatibility] = [:]
    @State private var cachedFilteredRecipes: [Recipe] = []
    @State private var cachedGroupedRecipes: [RecipeCategoryGroup] = []
    @State private var cachedNotebookSummaries: [RecipeNotebookSummary] = []
    @State private var cachedRecipePlaceholderIconSources: [UUID: [RecipePlaceholderIconSource]] = [:]

    // Tracks when inputs to `recomputeCompatibilities` actually changed so
    // the heavy recompute does not re-run on every SwiftData @Query refresh
    // (CloudKit remote changes, scroll-induced re-evaluations, etc.).
    @State private var lastCompatibilityInputsKey: String = ""
    @State private var pendingCompatibilityRecomputeWork: DispatchWorkItem?
    @State private var pendingGalleryPrefetchTask: Task<Void, Never>?
    @State private var pendingNotebookRefreshTask: Task<Void, Never>?
    @State private var lastRecipeProjectionInputsKey: Int = 0
    @State private var lastNotebookSummaryInputsKey: Int = 0
    @State private var didRunInitialAppearWork = false
    @State private var isNotebookLoading = false
    @State private var notebookSummariesNeedRefresh = true

    private var settings: AppSettings? { settingsArray.first }
    private var viewMode: RecipeViewMode { settings?.recipeViewMode ?? .gallery }
    private var compatibilityThreshold: Double {
        Double(settings?.recipeCompatibilityThresholdPercent ?? 80) / 100
    }

    private var recipeCategories: [Category] {
        allCategories.filter { $0.type == .recipe }
    }

    private var compatibilities: [UUID: RecipeCompatibility] { cachedCompatibilities }

    private var recipes: [Recipe] { cachedFilteredRecipes }

    private var groupedRecipes: [RecipeCategoryGroup] { cachedGroupedRecipes }

    private var notebookSummaries: [RecipeNotebookSummary] { cachedNotebookSummaries }

    private var recipeCategoryNamesSignature: String {
        recipeCategories.map(\.name).joined(separator: "|")
    }

    private var recipeCategoriesDisplaySignature: Int {
        var hasher = Hasher()
        hasher.combine(recipeCategories.count)
        for category in recipeCategories {
            hasher.combine(category.id)
            hasher.combine(category.name)
            hasher.combine(category.iconName ?? "")
            hasher.combine(category.sortOrder)
        }
        return hasher.finalize()
    }

    private var recipeProjectionInputsKey: Int {
        var hasher = Hasher()
        hasher.combine(allRecipes.count)
        for recipe in allRecipes {
            hasher.combine(recipe.id)
            hasher.combine(recipe.name)
            hasher.combine(recipe.category)
            hasher.combine(recipe.createdAt)
            hasher.combine(recipe.prepTime)
            hasher.combine(recipe.cookTime)
            hasher.combine(recipe.difficulty.rawValue)
            hasher.combine(recipe.isFavorite)
            hasher.combine(recipe.tags.count)
            for tag in recipe.tags {
                hasher.combine(tag)
            }
        }
        hasher.combine(localSearchText)
        hasher.combine(selectedCategory ?? "")
        hasher.combine(showCompatibleOnly)
        hasher.combine(showFavoritesOnly)
        hasher.combine(sortOption.rawValue)
        hasher.combine(lastCompatibilityInputsKey)
        hasher.combine(recipeCategoriesDisplaySignature)
        return hasher.finalize()
    }

    private var notebookSummaryInputsKey: Int {
        var hasher = Hasher()
        hasher.combine(allRecipes.count)
        for recipe in allRecipes {
            hasher.combine(recipe.id)
            hasher.combine(recipe.name)
            hasher.combine(recipe.category)
            hasher.combine(recipe.isFavorite)
            hasher.combine(recipe.updatedAt)
            hasher.combine(recipe.tags.count)
            for tag in recipe.tags {
                hasher.combine(tag)
            }
        }
        hasher.combine(localSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.combine(lastCompatibilityInputsKey)
        hasher.combine(recipeCategoriesDisplaySignature)
        return hasher.finalize()
    }

    private var notebookModeTransition: Animation {
        // Instant swap. We previously used a 0.14s opacity crossfade, but
        // both branches are non-trivial (LazyVGrid of notebook cards with
        // image-loading tiles vs. the recipe gallery). Keeping both alive
        // for the duration of the animation made the transition look like
        // it was running at very low fps on real devices. Cutting the
        // animation makes the toggle feel native — like switching tabs.
        .linear(duration: 0)
    }

    private var galleryColumnCount: Int {
        #if os(macOS)
        galleryColumnCount(forAvailableWidth: macGalleryAvailableWidth)
        #else
        settings?.recipeGalleryColumns ?? 3
        #endif
    }

    private var galleryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1), count: galleryColumnCount)
    }

    #if os(macOS)
    private func galleryColumnCount(forAvailableWidth availableWidth: CGFloat) -> Int {
        let pageHorizontalPadding: CGFloat = 32
        let contentWidth = max(availableWidth - pageHorizontalPadding, 0)
        let minimumColumns = 3
        let preferredCardWidth: CGFloat = 190
        let minimumReasonableCardWidth: CGFloat = 180
        let spacing: CGFloat = 1
        let maxColumns = 7

        guard contentWidth > 0 else { return minimumColumns }

        // macOS: 3 cards por linha como base. Conforme a janela cresce,
        // adicionamos colunas só quando a largura total ainda sustenta
        // cards visualmente confortáveis.
        let preferredCount = Int((contentWidth + spacing) / (preferredCardWidth + spacing))
        let maximumAllowedCount = Int((contentWidth + spacing) / (minimumReasonableCardWidth + spacing))
        let clampedMaximum = min(max(maximumAllowedCount, minimumColumns), maxColumns)

        return min(max(preferredCount, minimumColumns), clampedMaximum)
    }
    #endif

    private var galleryPrefetchColumnCount: Int {
        #if os(macOS)
        max(galleryColumnCount, 3)
        #else
        galleryColumnCount
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
                localSearchHeader
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            RecipeDetailContainer(recipeID: id)
        }
        #endif
        .tint(PageTheme.recipes.accentColor)
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                AddRecipeView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showImportRecipe, onDismiss: handleImportRecipeDismissed) {
            RecipeImportHostView(initialSource: importInitialSource, launchMode: importLaunchMode) { recipeID in
                highlightedRecipeID = recipeID
                selectedRecipeID = recipeID
                pendingImportedRecipeID = recipeID
                showImportRecipe = false
            }
            .modelContainer(CloudSyncService.shared.container)
            .forceLightStatusBar()
        }
        .sheet(item: $editingRecipe, onDismiss: { editingRecipe = nil }) { selection in
            NavigationStack {
                EditRecipeContainerView(recipeID: selection.id)
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
            let appearStart = Date()
            PerformanceLogger.event(
                .recipes,
                "RecipesLoadedView.onAppear begin",
                metadata: "trace=recipes-appear recipes=\(allRecipes.count) categories=\(recipeCategories.count)"
            )
            let isInitialAppear = !didRunInitialAppearWork
            didRunInitialAppearWork = true
            recomputeCompatibilities()
            refreshRecipeProjectionsIfNeeded(force: isInitialAppear)
            if isShowingCadernos {
                scheduleNotebookRefresh(showSkeleton: cachedNotebookSummaries.isEmpty, force: isInitialAppear)
            } else if isInitialAppear {
                notebookSummariesNeedRefresh = true
            }
            handleScrollToItemRequest(scrollToItem)
            scheduleGalleryPrefetchIfNeeded()
            PerformanceLogger.event(
                .recipes,
                "RecipesLoadedView.onAppear end",
                metadata: String(format: "trace=recipes-appear tookMs=%.1f recipes=%d visible=%d groups=%d", Date().timeIntervalSince(appearStart) * 1000, allRecipes.count, recipes.count, groupedRecipes.count)
            )
        }
        .onDisappear {
            pendingGalleryPrefetchTask?.cancel()
            pendingGalleryPrefetchTask = nil
            pendingNotebookRefreshTask?.cancel()
            pendingNotebookRefreshTask = nil
        }
        // PERF: previously these used `.onChange(of: pantryItems)` /
        // `.onChange(of: allRecipes)` which fire on EVERY SwiftData @Query
        // refresh — including no-op CloudKit remote changes and any save
        // that doesn't affect ingredients. Each call walks every recipe and
        // does string folding for every ingredient, which caused visible
        // jank during scroll on real devices. Switch to stable signatures
        // (item identities + names) so we only recompute when the inputs
        // that actually matter for compatibility have changed, and debounce
        // bursts that would otherwise trigger many recomputes back-to-back.
        .onChange(of: pantryCompatibilitySignature) { _, _ in
            scheduleCompatibilityRecompute()
        }
        .onChange(of: recipeCompatibilitySignature) { _, _ in
            scheduleCompatibilityRecompute()
        }
        .onChange(of: recipeCategoryNamesSignature) { _, _ in
            normalizeSelectedCategoryIfNeeded()
            refreshRecipeProjectionsIfNeeded(force: true)
            invalidateNotebookSummaries(force: true)
        }
        .onChange(of: recipeCategoriesDisplaySignature) { _, _ in
            refreshRecipeProjectionsIfNeeded(force: true)
            invalidateNotebookSummaries(force: true)
        }
        .onChange(of: allRecipes) { _, _ in
            refreshRecipeProjectionsIfNeeded()
            invalidateNotebookSummaries()
        }
        .onChange(of: localSearchText) { _, _ in
            refreshRecipeProjectionsIfNeeded()
            invalidateNotebookSummaries(showSkeleton: isShowingCadernos && cachedNotebookSummaries.isEmpty)
        }
        .onChange(of: selectedCategory) { _, _ in
            refreshRecipeProjectionsIfNeeded()
        }
        .onChange(of: showCompatibleOnly) { _, _ in
            refreshRecipeProjectionsIfNeeded()
        }
        .onChange(of: showFavoritesOnly) { _, _ in
            refreshRecipeProjectionsIfNeeded()
        }
        .onChange(of: sortOption) { _, _ in
            refreshRecipeProjectionsIfNeeded()
        }
        .onChange(of: viewMode) { _, _ in
            scheduleGalleryPrefetchIfNeeded()
        }
        .onChange(of: lastCompatibilityInputsKey) { _, _ in
            refreshRecipeProjectionsIfNeeded(force: true)
            invalidateNotebookSummaries(force: true)
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
        PageHeader(title: isShowingCadernos ? String(localized: "Cadernos") : String(localized: "Receitas"), isInverted: isInverted) {
            HStack(spacing: 6) {
                GlassButtonGroup {
                    GlassGroupMenu(systemImage: "plus") {
                        Section("Importar receita") {
                            Button {
                                openImport(.link)
                            } label: {
                                Label("Colar link", systemImage: "link")
                            }
                            Button {
                                openImport(.gallery)
                            } label: {
                                Label("Importar da galeria", systemImage: "photo.on.rectangle.angled")
                            }
                            Button {
                                openImport(.camera)
                            } label: {
                                Label("Ler com câmera", systemImage: "camera.viewfinder")
                            }
                            Button {
                                openImport(.text)
                            } label: {
                                Label("Colar texto", systemImage: "text.alignleft")
                            }
                            #if os(macOS)
                            Button {
                                openImport(.files)
                            } label: {
                                Label("Importar dos arquivos", systemImage: "folder.fill")
                            }
                            #endif
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
                    GlassGroupButton(systemImage: "magnifyingglass") {
                        toggleLocalSearch()
                    }
                    .accessibilityLabel(Text(isLocalSearchVisible ? "Fechar" : "Buscar"))
                }

                GlassButtonGroup {
                    GlassGroupButton(systemImage: isShowingCadernos ? "book.closed" : "books.vertical") {
                        toggleNotebookPage()
                    }
                }

                #if !os(macOS)
                SettingsButton()
                #endif
            }
        }
    }

    @ViewBuilder
    private var localSearchHeader: some View {
        if isLocalSearchVisible {
            LocalPageSearchBar(text: $localSearchText, placeholder: isShowingCadernos ? "Buscar cadernos" : "Buscar receitas")
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func toggleLocalSearch() {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            isLocalSearchVisible.toggle()
            if !isLocalSearchVisible {
                localSearchText = ""
            }
        }
    }

    private func handleImportRecipeDismissed() {
        let recipeID = pendingImportedRecipeID

        importInitialSource = nil
        importLaunchMode = .picker
        pendingImportedRecipeID = nil

        if let recipeID {
            openRecipeInRecipesTab(recipeID)
        }
    }

    private func openImport(_ mode: RecipeImportLaunchMode) {
        importInitialSource = nil
        importLaunchMode = mode
        showImportRecipe = true
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
                            editingRecipe = RecipeSelection(id: recipe.id)
                        }
                        Button(
                            recipe.isFavorite ? "Desfavoritar" : "Favoritar",
                            systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                        ) {
                            recipe.isFavorite.toggle()
                        }
                    }
                }

                // SettingsButton removed on macOS — Settings is reached via
                // the sidebar's dedicated "Configurações" item.
            }
        }
        .padding(.horizontal)
    }
    #endif

    // MARK: - List Content

    @ViewBuilder
    private var recipesListContent: some View {
        // Instant content swap. We do NOT animate this transition: the
        // alternative branches are both heavy (recipe gallery vs. notebook
        // grid) and any cross-fade ends up rendering both subtrees for the
        // duration of the animation, which makes the toggle feel like it
        // is running at a very low frame rate.
        Group {
            if isShowingCadernos {
                cadernosModeContent
            } else {
                recipesModeContent
            }
        }
    }

    @ViewBuilder
    private var recipesModeContent: some View {
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
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var cadernosModeContent: some View {
        cadernosContent
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func recomputeCompatibilities() {
        // Cancel any pending debounced recompute — we are doing it now.
        pendingCompatibilityRecomputeWork?.cancel()
        pendingCompatibilityRecomputeWork = nil

        let inputsKey = "\(pantryCompatibilitySignature)##\(recipeCompatibilitySignature)"
        // Skip if nothing relevant changed since last successful recompute.
        if inputsKey == lastCompatibilityInputsKey {
            return
        }

        PerformanceLogger.measure(
            .recipes,
            "Recipes.recomputeCompatibilities",
            metadata: "trace=recipes-compat recipes=\(allRecipes.count) pantry=\(pantryItems.count)"
        ) {
            let names = pantryItems.map {
                $0.name
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
            }

            var nextCompatibilities: [UUID: RecipeCompatibility] = [:]
            var nextPlaceholderSources: [UUID: [RecipePlaceholderIconSource]] = [:]
            nextCompatibilities.reserveCapacity(allRecipes.count)
            nextPlaceholderSources.reserveCapacity(allRecipes.count)

            for recipe in allRecipes {
                let ingredients = (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
                if !ingredients.isEmpty {
                    nextPlaceholderSources[recipe.id] = ingredients
                        .prefix(10)
                        .map(RecipePlaceholderIconSource.init)
                }

                guard let compatibility = compatibility(for: ingredients, pantryNames: names) else { continue }
                nextCompatibilities[recipe.id] = compatibility
            }

            cachedPantryNames = names
            cachedCompatibilities = nextCompatibilities
            cachedRecipePlaceholderIconSources = nextPlaceholderSources
            lastCompatibilityInputsKey = inputsKey
        }
    }

    private func refreshRecipeProjectionsIfNeeded(force: Bool = false) {
        let inputsKey = recipeProjectionInputsKey
        guard force || inputsKey != lastRecipeProjectionInputsKey else { return }

        PerformanceLogger.measure(
            .recipes,
            "Recipes.refreshRecipeProjections",
            metadata: "trace=recipes-projection recipes=\(allRecipes.count) visible=\(cachedFilteredRecipes.count) groups=\(cachedGroupedRecipes.count)"
        ) {
            var result = allRecipes

            if !localSearchText.isEmpty {
                let searchText = localSearchText
                result = result.filter {
                    $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                    $0.category.localizedCaseInsensitiveContains(searchText)
                }
            }

            if let cat = selectedCategory {
                result = result.filter { recipe in
                    recipe.categories.contains(where: { CategoryMutationService.matchesName($0, cat) })
                }
            }

            if showCompatibleOnly {
                result = result.filter { (compatibilities[$0.id]?.matchedIngredients ?? 0) > 0 }
            }

            if showFavoritesOnly {
                result = result.filter(\.isFavorite)
            }

            let sortedRecipes = sortRecipes(result)
            cachedFilteredRecipes = sortedRecipes

            var grouped: [String: [Recipe]] = [:]
            grouped.reserveCapacity(recipeCategories.count + 1)
            for recipe in sortedRecipes {
                let categories = recipe.categories
                if categories.isEmpty {
                    grouped["", default: []].append(recipe)
                } else {
                    for category in categories {
                        grouped[category, default: []].append(recipe)
                    }
                }
            }

            let categoryNames: [String]
            if let selectedCategory {
                categoryNames = [selectedCategory]
            } else {
                let configured = recipeCategories.map(\.name)
                let configuredKeys = Set(configured)
                let remaining = grouped.keys.filter { !configuredKeys.contains($0) }.sorted()
                categoryNames = configured + remaining
            }

            cachedGroupedRecipes = categoryNames.compactMap { categoryName in
                let recipes = grouped[categoryName, default: []]
                guard !recipes.isEmpty else { return nil }
                return RecipeCategoryGroup(category: categoryName, recipes: recipes)
            }

            lastRecipeProjectionInputsKey = inputsKey
        }
        scheduleGalleryPrefetchIfNeeded()
    }

    @discardableResult
    private func refreshNotebookSummariesIfNeeded(force: Bool = false) -> Bool {
        let inputsKey = notebookSummaryInputsKey
        guard force || inputsKey != lastNotebookSummaryInputsKey else {
            notebookSummariesNeedRefresh = false
            return false
        }

        PerformanceLogger.measure(
            .recipes,
            "Recipes.refreshNotebookSummaries",
            metadata: "trace=recipes-notebooks recipes=\(allRecipes.count) notebooks=\(cachedNotebookSummaries.count)"
        ) {
            let searchText = localSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            var accumulators: [String: RecipeNotebookAccumulator] = [:]
            accumulators.reserveCapacity(recipeCategories.count)

            for recipe in allRecipes {
                for category in recipe.categories {
                    accumulators[category, default: RecipeNotebookAccumulator()].add(
                        recipe,
                        compatibility: compatibilities[recipe.id],
                        searchText: searchText
                    )
                }
            }

            cachedNotebookSummaries = recipeCategories.compactMap { category in
                let accumulator = accumulators[category.name] ?? RecipeNotebookAccumulator()
                let summary = RecipeNotebookSummary(
                    category: category,
                    recipeCount: accumulator.recipeCount,
                    compatibleCount: accumulator.compatibleCount,
                    previewRecipes: accumulator.previewRecipes
                )

                guard !searchText.isEmpty else { return summary }

                let localizedCategoryName = category.localizedDisplayName
                let categoryMatches = category.name.localizedCaseInsensitiveContains(searchText)
                    || localizedCategoryName.localizedCaseInsensitiveContains(searchText)

                return (categoryMatches || accumulator.recipeMatchesSearch) ? summary : nil
            }

            lastNotebookSummaryInputsKey = inputsKey
            notebookSummariesNeedRefresh = false
        }
        return true
    }

    private func invalidateNotebookSummaries(showSkeleton: Bool = false, force: Bool = false) {
        notebookSummariesNeedRefresh = true
        guard isShowingCadernos else { return }
        scheduleNotebookRefresh(showSkeleton: showSkeleton, force: force)
    }

    private func scheduleNotebookRefresh(showSkeleton: Bool, force: Bool) {
        pendingNotebookRefreshTask?.cancel()

        if showSkeleton {
            isNotebookLoading = true
        }

        pendingNotebookRefreshTask = Task { @MainActor in
            // Let the skeleton commit before any summary walk/sort work runs.
            if showSkeleton {
                try? await Task.sleep(for: .milliseconds(90))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }

            let shouldForce = force || notebookSummariesNeedRefresh
            _ = refreshNotebookSummariesIfNeeded(force: shouldForce)
            prefetchNotebookPreviewThumbnails()
            isNotebookLoading = false
            pendingNotebookRefreshTask = nil
        }
    }

    private func compatibility(for ingredients: [RecipeIngredient], pantryNames: [String]) -> RecipeCompatibility? {
        let normalizedIngredients = ingredients
            .map(\.name)
            .map(Self.normalizedIngredient)

        guard !normalizedIngredients.isEmpty else { return nil }

        let matchedIngredients = normalizedIngredients.reduce(into: 0) { total, ingredient in
            if pantryNames.contains(where: { pantry in
                pantry == ingredient || pantry.contains(ingredient) || ingredient.contains(pantry)
            }) {
                total += 1
            }
        }

        return RecipeCompatibility(matchedIngredients: matchedIngredients, totalIngredients: normalizedIngredients.count)
    }

    private static func normalizedIngredient(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    /// Debounces `recomputeCompatibilities()` so a burst of SwiftData /
    /// CloudKit notifications does not run the full O(recipes × ingredients)
    /// pipeline multiple times in the same frame.
    private func scheduleCompatibilityRecompute() {
        pendingCompatibilityRecomputeWork?.cancel()
        let work = DispatchWorkItem { [weak modelContext] in
            _ = modelContext // keep view alive context-side; actual work uses captured @State
            recomputeCompatibilities()
        }
        pendingCompatibilityRecomputeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Stable signature of pantry ingredients that affect compatibility.
    /// Reads only stored attributes (id, name) so it does not trigger any
    /// SwiftData relationship fault. Cheap enough to evaluate on every
    /// body pass, which is what `.onChange(of:)` requires.
    private var pantryCompatibilitySignature: Int {
        var hasher = Hasher()
        hasher.combine(pantryItems.count)
        for item in pantryItems {
            hasher.combine(item.id)
            hasher.combine(item.name)
        }
        return hasher.finalize()
    }

    /// Stable signature of recipes that affect compatibility. Uses
    /// `updatedAt` (a stored attribute) as a proxy for "ingredients
    /// possibly changed" instead of walking the `ingredients`
    /// relationship — that would fault every recipe on every body pass.
    private var recipeCompatibilitySignature: Int {
        var hasher = Hasher()
        hasher.combine(allRecipes.count)
        for recipe in allRecipes {
            hasher.combine(recipe.id)
            hasher.combine(recipe.updatedAt)
        }
        return hasher.finalize()
    }

    // MARK: - Content

    @ViewBuilder
    private var recipeContent: some View {
        VStack(spacing: 0) {
            // Category filter chips
            categoryFilter

            ScrollViewReader { proxy in
                #if os(macOS)
                GeometryReader { geometry in
                    ScrollView {
                        if viewMode == .gallery {
                            galleryView
                                .frame(width: geometry.size.width, alignment: .leading)
                        } else {
                            listView
                                .frame(width: geometry.size.width, alignment: .leading)
                        }
                    }
                    .onAppear {
                        updateMacGalleryAvailableWidth(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        updateMacGalleryAvailableWidth(width)
                    }
                    .onAppear {
                        scrollToPendingRecipeIfNeeded(with: proxy)
                    }
                    .onChange(of: pendingRecipeScrollID) { _, _ in
                        scrollToPendingRecipeIfNeeded(with: proxy)
                    }
                }
                #else
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
                #endif
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
                            label: category.localizedDisplayName,
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
            .background(neutralSurfaceColor, in: .rect(cornerRadius: 12))
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
                        let cols = galleryColumnCount
                        ForEach(Array(group.recipes.enumerated()), id: \.element.id) { index, recipe in
                            recipeGalleryCard(recipe, cornerRadii: galleryCornerRadii(index: index, total: group.recipes.count, columns: cols))
                        }
                    }
                }
            }

            recipesModeSwitchButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(macOS)
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
        #endif
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    #if os(macOS)
    private func updateMacGalleryAvailableWidth(_ width: CGFloat) {
        guard width.isFinite, abs(width - macGalleryAvailableWidth) > 1 else { return }
        macGalleryAvailableWidth = width
    }
    #endif

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

            recipesModeSwitchButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func recipeGalleryCard(_ recipe: Recipe, cornerRadii: RectangleCornerRadii = .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16)) -> some View {
        let card = RecipeCardView(
            recipe: recipe,
            compatibility: compatibilities[recipe.id],
            placeholderIconSources: placeholderIconSources(for: recipe),
            columns: galleryColumnCount,
            cornerRadii: cornerRadii
        )
        .equatable()
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
        LazyVStack(spacing: 10) {
            ForEach(recipes) { recipe in
                let row = RecipeRowView(
                    recipe: recipe,
                    compatibility: compatibilities[recipe.id],
                    placeholderIconSources: placeholderIconSources(for: recipe)
                )
                .equatable()
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

    private func placeholderIconSources(for recipe: Recipe) -> [RecipePlaceholderIconSource] {
        cachedRecipePlaceholderIconSources[recipe.id] ?? []
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
            editingRecipe = RecipeSelection(id: recipe.id)
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

                Button {
                    showFavoritesOnly.toggle()
                } label: {
                    Label("Mostrar só favoritas", systemImage: showFavoritesOnly ? "checkmark.circle.fill" : "circle")
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

            ContentUnavailableView.search(text: localSearchText)
        }
    }

    private var cadernosContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                notebookManagerButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Group {
                    if isNotebookLoading {
                        NotebookLoadingSkeleton()
                            .padding(.horizontal, 16)
                    } else if notebookSummaries.isEmpty {
                        if localSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ContentUnavailableView {
                                Label("Sem Cadernos", systemImage: "books.vertical")
                            } description: {
                                Text("Crie seu primeiro caderno para organizar receitas por tema, refeição ou ocasião.")
                            }
                            .padding(.top, 36)
                        } else {
                            ContentUnavailableView.search(text: localSearchText)
                                .padding(.top, 36)
                        }
                    } else {
                        LazyVGrid(columns: notebookColumns, spacing: 12) {
                            ForEach(notebookSummaries) { summary in
                                RecipeNotebookCard(
                                    summary: summary,
                                    placeholderIconSources: cachedRecipePlaceholderIconSources
                                ) {
                                    openNotebook(named: summary.category.name)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                notebookModeSwitchButton
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .onScrollOffsetChange(perform: updateInlineTitle)
    }

    private var notebookManagerButton: some View {
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
    }

    private var recipesModeSwitchButton: some View {
        modeSwitchButton(title: "Ir para os cadernos", systemImage: "books.vertical") {
            toggleNotebookPage()
        }
    }

    private var notebookModeSwitchButton: some View {
        modeSwitchButton(title: "Ir para as receitas", systemImage: "book.closed") {
            toggleNotebookPage()
        }
    }

    private func modeSwitchButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.primary.opacity(0.68))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(neutralSurfaceColor.opacity(0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
        // PERF: do NOT store `offset` in @State — the scroll callback fires on
        // every frame during scrolling. Mutating any @State here would force
        // RecipesView's body to re-evaluate per frame, which dominates scroll
        // cost. We only flip `showsInlineTitle` when the threshold is crossed,
        // so the body invalidation is bounded to at most twice per scroll
        // gesture instead of once per frame.
        let shouldShow = offset < -24
        if showsInlineTitle != shouldShow {
            showsInlineTitle = shouldShow
        }
    }

    private func handleScrollToItemRequest(_ request: ScrollToItemRequest?) {
        guard let request, request.type == "recipe" else { return }

        selectedCategory = nil
        refreshRecipeProjectionsIfNeeded(force: true)

        // Instant — no animation; see `notebookModeTransition` for context.
        isShowingCadernos = false
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
            isShowingCadernos = false
        } else if isNearTop {
            isShowingCadernos = true
            selectedRecipeID = nil
            scheduleNotebookRefresh(
                showSkeleton: cachedNotebookSummaries.isEmpty || notebookSummariesNeedRefresh,
                force: notebookSummariesNeedRefresh
            )
        } else {
            contentResetToken += 1
        }
    }

    private var isNearTop: Bool {
        // Derived from `showsInlineTitle` (which flips at the same threshold)
        // so we don't have to track the live scroll offset in @State.
        !showsInlineTitle
    }

    private func toggleNotebookPage() {
        if !isShowingCadernos {
            isShowingCadernos = true
            selectedRecipeID = nil
            scheduleNotebookRefresh(
                showSkeleton: cachedNotebookSummaries.isEmpty || notebookSummariesNeedRefresh,
                force: notebookSummariesNeedRefresh
            )
            return
        }
        // Instant swap — no animation. Both branches are heavy; cross-fading
        // them visibly drops frames.
        isShowingCadernos = false
    }

    private func prefetchNotebookPreviewThumbnails() {
        // Warm only the cover image for the first cards. Mini previews load
        // at a much smaller target size on demand, which keeps the notebooks
        // page responsive even when a category has many recipes.
        let previews = cachedNotebookSummaries
            .prefix(10)
            .compactMap(\.coverRecipe)
        guard !previews.isEmpty else { return }
        let maxPixel: CGFloat = 420
        for recipe in previews {
            guard let data = recipe.imageData, !data.isEmpty else { continue }
            let key = RecipeImageCache.key(
                recipeID: recipe.id,
                dataCount: data.count,
                maxPixel: maxPixel
            )
            if RecipeImageCache.shared.cachedThumbnail(key: key) != nil { continue }
            // Fire-and-forget: the cache will populate before SwiftUI's
            // `.task(id:)` in `RecipeThumbnail` even runs.
            Task.detached(priority: .userInitiated) {
                _ = await RecipeImageCache.shared.thumbnail(
                    key: key, data: data, maxPixel: maxPixel
                )
            }
        }
    }

    /// Pre-warm the on-disk + in-memory thumbnail cache for the recipes
    /// that will appear in the gallery on first paint. Subsequent launches
    /// hit the persistent disk cache, so visible cards render instantly
    /// without the expensive original-image decode on a cold start.
    private func prefetchGalleryThumbnails() {
        let cols = galleryPrefetchColumnCount
        let maxPixel: CGFloat = {
            switch cols {
            case 1: return 960
            case 2: return 700
            case 3: return 420
            default: return 320
            }
        }()
        // Two screens worth of cards is plenty without flooding the queue.
        let visibleBatch = max(cols * 6, 12)
        let candidates = recipes.prefix(visibleBatch)
        for recipe in candidates {
            guard let data = recipe.imageData, !data.isEmpty else { continue }
            let key = RecipeImageCache.key(
                recipeID: recipe.id,
                dataCount: data.count,
                maxPixel: maxPixel
            )
            RecipeImageCache.shared.prewarm(key: key, data: data, maxPixel: maxPixel)
        }
    }

    private func scheduleGalleryPrefetchIfNeeded() {
        pendingGalleryPrefetchTask?.cancel()
        guard viewMode == .gallery else { return }

        pendingGalleryPrefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            prefetchGalleryThumbnails()
        }
    }

    private func openNotebook(named categoryName: String) {
        selectedCategory = categoryName
        refreshRecipeProjectionsIfNeeded(force: true)
        categoryBarCenterToken += 1
        isShowingCadernos = false
        selectedRecipeID = nil
        contentResetToken += 1
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

private struct RecipeCategoryGroup: Identifiable {
    let category: String
    let recipes: [Recipe]

    var id: String { category }
}

private struct RecipeNotebookSummary: Identifiable {
    static let previewLimit = 3

    let category: Category
    let recipeCount: Int
    let compatibleCount: Int
    let previewRecipes: [Recipe]

    var id: UUID { category.id }
    var coverRecipe: Recipe? { previewRecipes.first }
    var miniPreviewRecipes: [Recipe] { Array(previewRecipes.dropFirst().prefix(2)) }
    var recipeCountAbbreviation: String { "\(Self.compactCount(recipeCount)) rec." }
    var compatibilityAbbreviation: String { "\(Self.compactCount(compatibleCount)) comp." }
    var additionalRecipeCount: Int { max(recipeCount - 1, 0) }
    var additionalRecipeBadge: String? {
        guard additionalRecipeCount > 0 else { return nil }
        return "+\(Self.compactCount(additionalRecipeCount))"
    }

    static func previewSortPrecedes(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func compactCount(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 10_000 {
            let value = Double(count) / 1_000
            return String(format: "%.1fk", value)
        }
        return "9.9k+"
    }
}

private struct RecipeNotebookAccumulator {
    var recipeCount = 0
    var compatibleCount = 0
    var previewRecipes: [Recipe] = []
    var recipeMatchesSearch = false

    mutating func add(_ recipe: Recipe, compatibility: RecipeCompatibility?, searchText: String) {
        recipeCount += 1
        if (compatibility?.matchedIngredients ?? 0) > 0 {
            compatibleCount += 1
        }
        if !searchText.isEmpty,
           recipe.name.localizedCaseInsensitiveContains(searchText)
            || recipe.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) {
            recipeMatchesSearch = true
        }
        insertPreviewRecipe(recipe)
    }

    private mutating func insertPreviewRecipe(_ recipe: Recipe) {
        if let insertionIndex = previewRecipes.firstIndex(where: { RecipeNotebookSummary.previewSortPrecedes(recipe, $0) }) {
            previewRecipes.insert(recipe, at: insertionIndex)
        } else if previewRecipes.count < RecipeNotebookSummary.previewLimit {
            previewRecipes.append(recipe)
        }

        if previewRecipes.count > RecipeNotebookSummary.previewLimit {
            previewRecipes.removeLast()
        }
    }
}

private let notebookSuggestedCardBackgroundColor = neutralSurfaceColor
private let notebookCardHeight: CGFloat = 192
private let notebookCardInnerHeight: CGFloat = 168
private let notebookPreviewHeight: CGFloat = 118

private struct RecipeNotebookCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showIconPicker = false

    let summary: RecipeNotebookSummary
    let placeholderIconSources: [UUID: [RecipePlaceholderIconSource]]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RecipeNotebookPreviewStrip(
                    summary: summary,
                    placeholderIconSources: placeholderIconSources
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: notebookPreviewHeight)
                    .clipShape(.rect(cornerRadius: 16))
                    .clipped()

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.category.localizedDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(minHeight: 20, alignment: .topLeading)

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
                    .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: notebookCardInnerHeight, alignment: .top)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(height: notebookCardHeight, alignment: .top)
        .background(notebookSuggestedCardBackgroundColor, in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
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
    let placeholderIconSources: [UUID: [RecipePlaceholderIconSource]]

    var body: some View {
        Group {
            if let coverRecipe = summary.coverRecipe {
                RecipeNotebookCoverPreview(
                    recipe: coverRecipe,
                    miniRecipes: summary.miniPreviewRecipes,
                    additionalRecipeBadge: summary.additionalRecipeBadge,
                    placeholderIconSources: placeholderIconSources
                )
            } else {
                RecipeNotebookEmptyPreviewPlaceholder(category: summary.category)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct RecipeNotebookCoverPreview: View {
    let recipe: Recipe
    let miniRecipes: [Recipe]
    let additionalRecipeBadge: String?
    let placeholderIconSources: [UUID: [RecipePlaceholderIconSource]]

    var body: some View {
        RecipeNotebookPreviewTile(
            recipe: recipe,
            placeholderIconSources: placeholderIconSources[recipe.id] ?? [],
            maxPixel: 420
        )
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: -7) {
                ForEach(miniRecipes, id: \.id) { miniRecipe in
                    RecipeNotebookMiniPreviewTile(
                        recipe: miniRecipe,
                        placeholderIconSources: placeholderIconSources[miniRecipe.id] ?? []
                    )
                }

                if let additionalRecipeBadge {
                    Text(additionalRecipeBadge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 28)
                        .background(Color.black.opacity(0.68), in: .rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.72), lineWidth: 1)
                        )
                }
            }
            .padding(9)
        }
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
    let placeholderIconSources: [RecipePlaceholderIconSource]
    let maxPixel: CGFloat

    var body: some View {
        GeometryReader { proxy in
            RecipeThumbnail(recipe: recipe, maxPixel: maxPixel) {
                RecipeImagePlaceholderCompact(
                    iconSources: placeholderIconSources,
                    darkenOverlay: false
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
        .clipped()
    }
}

private struct RecipeNotebookMiniPreviewTile: View {
    let recipe: Recipe
    let placeholderIconSources: [RecipePlaceholderIconSource]

    var body: some View {
        GeometryReader { proxy in
            RecipeThumbnail(recipe: recipe, maxPixel: 160) {
                RecipeImagePlaceholderCompact(
                    iconSources: placeholderIconSources,
                    darkenOverlay: false
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(width: 34, height: 28)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
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
                            Text(category.localizedDisplayName)
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
        .modalNavigationTitle(String(localized: "Gerenciar cadernos"))
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
                                    Text(category.localizedDisplayName)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .modalNavigationTitle(String(localized: "Mover receitas"))
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
