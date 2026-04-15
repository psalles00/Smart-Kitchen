import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case lists
    case recipes
    case nutrients
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Início"
        case .lists: return "Listas"
        case .recipes: return "Receitas"
        case .nutrients: return "Nutrientes"
        case .settings: return "Configurações"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .lists: return "list.bullet.clipboard"
        case .recipes: return "book"
        case .nutrients: return "leaf"
        case .settings: return "gearshape"
        }
    }

}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]
    @State private var selectedTab: AppTab = .assistant
    @State private var lastContentTab: AppTab = .assistant
    @State private var showSettings = false
    @State private var showAddPantry = false
    @State private var showAddGrocery = false
    @State private var showAddRecipe = false
    @State private var showAddUtensil = false
    @State private var showAddItem = false
    @State private var addItemPrefill = ""
    @State private var addItemIconFileName: String?
    @State private var addItemCategory: String?
    @State private var scrollToTopTrigger: Int = 0
    @State private var scrollToItemRequest: ScrollToItemRequest?
    @State private var displayedBgTheme: PageTheme = .home
    @State private var searchDragOffset: CGFloat = 0
    @StateObject private var searchService = UniversalSearchService()
    @StateObject private var searchBarState = SearchBarState()

    // Search-triggered edit sheets
    @State private var searchEditPantryItem: PantryItem?
    @State private var searchEditGroceryItem: GroceryItem?
    @State private var searchEditUtensilItem: UtensilItem?
    @State private var searchEditRecipe: Recipe?

    /// When non-nil, the CommandBar tab will open inline chat with this query on next activation.
    @State private var pendingChatQuery: String? = nil
    @State private var pendingOpenChat = false
    @State private var pendingNewConversation = false
    @State private var pendingShowHistory = false

    #if os(macOS)
    @State private var selectedSidebar: SidebarItem? = .home
    @State private var macBackgroundFromTheme: PageTheme = .home
    @State private var macBackgroundToTheme: PageTheme = .home
    @State private var macBackgroundTransitionProgress: Double = 1.0

    private var macActivePageTheme: PageTheme {
        switch selectedSidebar ?? .home {
        case .home: return .home
        case .lists: return .lists
        case .recipes: return .recipes
        case .nutrients: return .nutrients
        case .settings: return .home
        }
    }
    #endif

    private var settings: AppSettings? { settingsArray.first }
    private var activePageTheme: PageTheme { selectedTab.pageTheme ?? lastContentTab.pageTheme ?? .home }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    scrollToTopTrigger += 1
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        mainTabView
        .environmentObject(searchBarState)
        .environment(\.scrollToItem, scrollToItemRequest)
        .environment(\.backgroundTheme, displayedBgTheme)
        .sheet(isPresented: $showAddPantry) {
            NavigationStack {
                AddPantryItemView(initialName: addItemPrefill, onCreated: { id in
                    scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "pantryItem")
                    selectedTab = .lists
                })
            }
            .forceLightStatusBar()
            .onDisappear { addItemPrefill = "" }
        }
        .sheet(isPresented: $showAddGrocery) {
            NavigationStack {
                AddGroceryItemView(initialName: addItemPrefill, onCreated: { id in
                    scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "groceryItem")
                    selectedTab = .lists
                })
            }
            .forceLightStatusBar()
            .onDisappear { addItemPrefill = "" }
        }
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                AddRecipeView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddUtensil) {
            NavigationStack {
                AddUtensilItemView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                AddItemView(
                    initialName: addItemPrefill,
                    initialIconFileName: addItemIconFileName,
                    initialCategory: addItemCategory,
                    onCreated: { id, destination in
                        switch destination {
                        case .pantry:
                            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "pantryItem")
                            selectedTab = .lists
                        case .grocery:
                            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "groceryItem")
                            selectedTab = .lists
                        case .utensil:
                            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "utensil")
                            selectedTab = .lists
                        }
                    }
                )
            }
            .forceLightStatusBar()
            .onDisappear {
                addItemPrefill = ""
                addItemIconFileName = nil
                addItemCategory = nil
            }
        }
        .sheet(item: $searchEditPantryItem) { (item: PantryItem) in
            NavigationStack {
                EditPantryItemView(item: item)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $searchEditGroceryItem) { (item: GroceryItem) in
            NavigationStack {
                EditGroceryItemView(item: item)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $searchEditUtensilItem) { (item: UtensilItem) in
            NavigationStack {
                EditUtensilItemView(item: item)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $searchEditRecipe) { (recipe: Recipe) in
            NavigationStack {
                EditRecipeView(recipe: recipe)
            }
            .forceLightStatusBar()
        }
        .environment(\.openSettings, {
            #if os(macOS)
            selectedSidebar = .settings
            #else
            showSettings = true
            #endif
        })
        .environment(\.scrollToTopTrigger, scrollToTopTrigger)
        #if os(macOS)
        .preferredColorScheme(.dark)
        #else
        .preferredColorScheme(settings?.appearanceMode.colorScheme)
        #endif
        #if os(macOS)
        .tint(macActivePageTheme.accentColor)
        #else
        .tint(activePageTheme.accentColor)
        #endif
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .forceLightStatusBar()
        }
        .onAppear {
            // TODO: Re-enable daily backup once BackupManager.swift is included in this target.
            // BackupManager.shared.performDailyBackupIfNeeded(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        #if os(iOS)
        .forceLightStatusBar()
        #endif
        .onChange(of: selectedTab) { _, newValue in
            handleTabSelectionChange(newValue)
        }
    }

    private var mainTabView: some View {
        #if os(macOS)
        macSidebarView
        #else
        nativeTabView
        #endif
    }

    private var nativeTabView: some View {
        TabView(selection: tabSelectionBinding) {
            Tab(value: AppTab.assistant) {
                NavigationStack {
                    HomeView(
                        onSettingsTap: { showSettings = true },
                        onOpenChat: {
                            pendingOpenChat = true
                            searchBarState.reveal()
                        }
                    )
                }
                .overlay { searchResultsOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Início", systemImage: AppTab.assistant.icon)
            }

            Tab(value: AppTab.lists) {
                NavigationStack {
                    ListsTabView()
                }
                .overlay { searchResultsOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Listas", systemImage: AppTab.lists.icon)
            }

            Tab(value: AppTab.recipes) {
                NavigationStack {
                    RecipesView()
                }
                .overlay { searchResultsOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Receitas", systemImage: AppTab.recipes.icon)
            }

            Tab(value: AppTab.nutrients) {
                NavigationStack {
                    NutrientsPlaceholderView()
                }
                .overlay { searchResultsOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Nutrientes", systemImage: AppTab.nutrients.icon)
            }
        }
        .onChange(of: searchBarState.searchText) { _, newValue in
            searchService.search(query: newValue, context: modelContext, showUtensils: settings?.showUtensils == true)
        }
        .environment(\.searchOverlay, searchOverlayView)
    }

    // MARK: - Bottom Search Bar

    /// Whether the results panel should be shown (first letter typed, chat, etc.)
    private var hasSearchContent: Bool {
        guard searchBarState.isVisible else { return false }
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil
    }

    @ViewBuilder
    private var bottomSearchBarArea: some View {
        UnifiedSearchBar(state: searchBarState) { _ in }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var searchResultsOverlay: some View {
        if hasSearchContent {
            searchResultsPanel
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Search Results Panel

    @ViewBuilder
    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Header: title + close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(searchBarState.mode == .aiChat ? "Modo IA" : "Assistente")
                        .font(.pageTitle)
                    Text(searchBarState.mode == .aiChat
                         ? "Converse com a IA sobre sua cozinha."
                         : "Adicione itens, busque na despensa ou pergunte à IA.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if searchBarState.mode == .aiChat {
                    Button {
                        startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showConversationHistory()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    searchBarState.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Results area
            if let overlay = searchOverlayView {
                overlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .offset(y: max(searchDragOffset, 0))
        .gesture(
            DragGesture(minimumDistance: 30)
                .onChanged { value in
                    searchDragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 200 {
                        searchBarState.dismiss()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        searchDragOffset = 0
                    }
                }
        )
        .ignoresSafeArea(edges: .bottom)
    }

    /// Search results view injected into ExpandedPageLayout's content panel via environment.
    private var searchOverlayView: AnyView? {
        guard searchBarState.isVisible else { return nil }
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showChat = searchBarState.mode == .aiChat

        guard hasText || showChat || pendingOpenChat || pendingChatQuery != nil else { return nil }

        return AnyView(
            InlineSearchResultsView(
                searchBarState: searchBarState,
                searchService: searchService,
                onAction: { handleCommandBarAction($0) },
                pendingChatQuery: $pendingChatQuery,
                pendingOpenChat: $pendingOpenChat,
                pendingNewConversation: $pendingNewConversation,
                pendingShowHistory: $pendingShowHistory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private func startNewConversation() {
        pendingNewConversation = true
    }

    private func showConversationHistory() {
        pendingShowHistory = true
    }

    #if os(macOS)
    private var macSidebarView: some View {
        NavigationSplitView {
            List(selection: $selectedSidebar) {
                Section("Navegação") {
                    ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                Section("Preferências") {
                    Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.systemImage)
                        .tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("")
            .tint(macActivePageTheme.accentColor)
            .safeAreaInset(edge: .bottom) {
                Button {
                    searchBarState.reveal()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Buscar e Adicionar")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("⌘K")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        searchBarState.reveal()
                    } label: {
                        Label("Buscar", systemImage: "sparkle.magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        } detail: {
            switch selectedSidebar ?? .home {
            case .home:
                NavigationStack {
                    HomeView(
                        onSettingsTap: { selectedSidebar = .settings },
                        onOpenChat: {
                            pendingOpenChat = true
                            searchBarState.reveal()
                        }
                    )
                }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
            case .lists:
                NavigationStack { ListsTabView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
            case .recipes:
                NavigationStack { RecipesView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
            case .nutrients:
                NavigationStack { NutrientsPlaceholderView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
            case .settings:
                NavigationStack { SettingsView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .focusedSceneValue(\.openCommandBarAction, { searchBarState.reveal() })
        .background {
            macAppBackground
                .ignoresSafeArea()
        }
        .onAppear {
            macBackgroundFromTheme = macActivePageTheme
            macBackgroundToTheme = macActivePageTheme
            macBackgroundTransitionProgress = 1.0
        }
        .onChange(of: selectedSidebar) { _, newValue in
            let newTheme: PageTheme = {
                switch newValue ?? .home {
                case .home: return .home
                case .lists: return .lists
                case .recipes: return .recipes
                case .nutrients: return .nutrients
                case .settings: return .home
                }
            }()
            if newTheme != displayedBgTheme {
                displayedBgTheme = newTheme
            }
            if newTheme != macBackgroundToTheme {
                macBackgroundFromTheme = macBackgroundToTheme
                macBackgroundToTheme = newTheme
                macBackgroundTransitionProgress = 0.0
                withAnimation(.easeInOut(duration: 0.35)) {
                    macBackgroundTransitionProgress = 1.0
                }
            }
        }
    }

    @ViewBuilder
    private var macAppBackground: some View {
        ZStack {
            Color.black
            macThemedBackground(for: macBackgroundFromTheme)
                .opacity(1.0 - macBackgroundTransitionProgress)
            macThemedBackground(for: macBackgroundToTheme)
                .opacity(macBackgroundTransitionProgress)
        }
    }

    @ViewBuilder
    private func macThemedBackground(for theme: PageTheme) -> some View {
        let selection = BackgroundManager.shared.background(for: theme)

        switch selection.type {
        case .texturedGradient:
            if let preset = selection.texturedPreset {
                TexturedGradientView(preset: preset, progress: 1.0)
            } else {
                macOriginalBackground(for: theme)
            }
        case .original:
            macOriginalBackground(for: theme)
        case .waves:
            WavesShaderView(progress: 1.0)
        }
    }

    @ViewBuilder
    private func macOriginalBackground(for theme: PageTheme) -> some View {
        switch theme {
        case .home:
            NebulaShaderView(theme: .home, progress: 1.0)
        case .lists:
            NebulaShaderView(theme: .lists, progress: 1.0)
        case .recipes:
            NebulaShaderView(theme: .recipes, progress: 1.0)
        case .nutrients:
            NebulaShaderView(theme: .nutrients, progress: 1.0)
        }
    }

    #endif

    private func handleTabSelectionChange(_ newValue: AppTab) {
        lastContentTab = newValue

        // Dismiss assistant/AI mode when switching tabs
        if searchBarState.isVisible {
            searchBarState.dismiss()
        }

        // Animate background theme change with a fade, independently of content swap
        if let newTheme = newValue.pageTheme, newTheme != displayedBgTheme {
            displayedBgTheme = newTheme
        }
    }

    private func handleCommandBarAction(_ action: CommandBarAction) {
        // For move actions triggered from search quick-action, keep search open
        let keepSearchOpen: Bool
        switch action {
        case .movePantryToGrocery, .moveGroceryToPantry,
             .movePantryToGroceryByName, .moveGroceryToPantryByName:
            keepSearchOpen = true
        default:
            keepSearchOpen = false
        }

        if !keepSearchOpen {
            searchBarState.selectResult()
        }

        switch action {
        case .openPantryItem(let id):
            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "pantryItem")
            selectedTab = .lists
        case .openGroceryItem(let id):
            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "groceryItem")
            selectedTab = .lists
        case .openRecipe(let id):
            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "recipe")
            selectedTab = .recipes
        case .openUtensil(let id):
            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "utensil")
            selectedTab = .lists
        case .editPantryItem(let id):
            let descriptor = FetchDescriptor<PantryItem>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditPantryItem = item
            }
        case .editGroceryItem(let id):
            let descriptor = FetchDescriptor<GroceryItem>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditGroceryItem = item
            }
        case .editRecipe(let id):
            let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditRecipe = item
            }
        case .editUtensil(let id):
            let descriptor = FetchDescriptor<UtensilItem>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditUtensilItem = item
            }
        case .addPantryItem(let prefill):
            addItemPrefill = prefill
            showAddPantry = true
        case .addGroceryItem(let prefill):
            addItemPrefill = prefill
            showAddGrocery = true
        case .addItem(let prefill, let iconFileName, let category):
            addItemPrefill = prefill
            addItemIconFileName = iconFileName
            addItemCategory = category
            showAddItem = true
        case .addRecipe:
            showAddRecipe = true
        case .addUtensil:
            showAddUtensil = true
        case .askAssistant(let prefill):
            pendingChatQuery = prefill
            searchBarState.reveal()
        case .openAssistant:
            pendingOpenChat = true
            searchBarState.reveal()
        case .movePantryToGrocery(let id):
            movePantryItemToGrocery(id: id)
            refreshSearchAfterMove()
        case .moveGroceryToPantry(let id):
            moveGroceryItemToPantry(id: id)
            refreshSearchAfterMove()
        case .movePantryToGroceryByName(let name):
            movePantryItemToGroceryByName(name)
            refreshSearchAfterMove()
        case .moveGroceryToPantryByName(let name):
            moveGroceryItemToPantryByName(name)
            refreshSearchAfterMove()
        }

        // Clear scroll request after views have consumed it
        if scrollToItemRequest != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                scrollToItemRequest = nil
            }
        }
    }

    /// Called when the user presses Enter/Search on the keyboard.
    private func submitSearchAction() {
        let trimmedQuery = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let isQuestion = trimmedQuery.contains("?") ||
            trimmedQuery.split(separator: " ").count >= 4

        // If there are search results and it's not a question, navigate to the first result
        if !searchService.results.isEmpty && !isQuestion {
            let first = searchService.results[0]
            if let objectID = first.objectID {
                RecentActionsStore.shared.record(RecentAction(
                    title: first.title,
                    type: first.type,
                    objectID: first.objectID,
                    iconName: first.iconFilename
                ))
                switch first.type {
                case .pantryItem:  handleCommandBarAction(.editPantryItem(objectID))
                case .groceryItem: handleCommandBarAction(.editGroceryItem(objectID))
                case .recipe:      handleCommandBarAction(.editRecipe(objectID))
                case .utensil:     handleCommandBarAction(.editUtensil(objectID))
                default:           handleCommandBarAction(.addItem(prefill: trimmedQuery, iconFileName: nil, category: nil))
                }
                return
            }
        }

        // If it looks like a question, ask assistant
        if isQuestion {
            handleCommandBarAction(.askAssistant(prefill: trimmedQuery))
        } else {
            // Default: open AddItemView with destination picker
            handleCommandBarAction(.addItem(prefill: trimmedQuery, iconFileName: nil, category: nil))
        }
    }

    private func refreshSearchAfterMove() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            searchService.search(query: searchBarState.searchText, context: modelContext, showUtensils: settings?.showUtensils == true)
        }
    }

    private func movePantryItemToGrocery(id: UUID) {
        let descriptor = FetchDescriptor<PantryItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        let groceryDescriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\GroceryItem.sortOrder)])
        let groceryItems = (try? modelContext.fetch(groceryDescriptor)) ?? []
        // Check if already exists in grocery
        let alreadyInGrocery = groceryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        if alreadyInGrocery {
            withAnimation { modelContext.delete(item) }
        } else {
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
            }
        }
    }

    private func moveGroceryItemToPantry(id: UUID) {
        let descriptor = FetchDescriptor<GroceryItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        let pantryDescriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\PantryItem.sortOrder)])
        let pantryItems = (try? modelContext.fetch(pantryDescriptor)) ?? []
        // Check if already exists in pantry
        let alreadyInPantry = pantryItems.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
        if alreadyInPantry {
            withAnimation { modelContext.delete(item) }
        } else {
            var expirationDate: Date?
            if let days = item.defaultExpiryDays, days > 0 {
                expirationDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
            let pantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                iconName: item.iconName,
                isLinkedToGrocery: false,
                expirationDate: expirationDate,
                defaultExpiryDays: item.defaultExpiryDays,
                sortOrder: (pantryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            withAnimation {
                modelContext.insert(pantryItem)
                modelContext.delete(item)
            }
        }
    }

    private func movePantryItemToGroceryByName(_ name: String) {
        let descriptor = FetchDescriptor<PantryItem>()
        guard let items = try? modelContext.fetch(descriptor),
              let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        movePantryItemToGrocery(id: item.id)
    }

    private func moveGroceryItemToPantryByName(_ name: String) {
        let descriptor = FetchDescriptor<GroceryItem>()
        guard let items = try? modelContext.fetch(descriptor),
              let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        moveGroceryItemToPantry(id: item.id)
    }

}

#if os(macOS)
private struct MacDetailCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif

private struct HomeView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.modelContext) private var modelContext
    // Corrigido ciclo do AttributeGraph separando dependências reativas de SwiftData em @State com atualização manual para evitar travamentos no macOS.

    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var showAddGrocery = false
    @State private var showAddPantry = false
    @State private var selectedCompatibleCategory: String? = nil
    @State private var editingExpiringItem: PantryItem?

    @State private var recipeCategoriesState: [Category] = []
    @State private var compatibleMatchesState: [HomeRecipeMatch] = []
    @State private var expiringItemsState: [PantryItem] = []
    @State private var contentResetToken: Int = 0

    private var settings: AppSettings? { settingsArray.first }
    
    let onSettingsTap: () -> Void
    let onOpenChat: () -> Void

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .home,
            header: { isInverted in
                PageHeader(title: "Início", isInverted: isInverted) {
                    SettingsButton(onTap: onSettingsTap)
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        assistantLauncher
                        if !expiringItemsState.isEmpty {
                            expiringSection
                        }
                        actionDeck
                        dessertShelf
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .id(contentResetToken)
            },
            infoContent: {
                HomeInfoContent()
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.home.accentColor)
        .sheet(isPresented: $showAddGrocery) {
            NavigationStack {
                AddGroceryItemView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddPantry) {
            NavigationStack {
                AddPantryItemView()
            }
            .forceLightStatusBar()
        }
        .sheet(item: $editingExpiringItem) { item in
            NavigationStack {
                EditPantryItemView(item: item)
            }
            .forceLightStatusBar()
        }
        .onAppear {
            updateRecipeCategories()
            updateCompatibleMatches()
            updateExpiringItems()
        }
        .onChange(of: pantryItems) { _, _ in
            updateCompatibleMatches()
            updateExpiringItems()
        }
        .onChange(of: recipes) { _, _ in
            updateCompatibleMatches()
            updateRecipeCategories()
        }
        .onChange(of: categories) { _, _ in
            updateRecipeCategories()
        }
        .onChange(of: selectedCompatibleCategory) { _, _ in
            updateCompatibleMatches()
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            contentResetToken += 1
        }
    }

    private func updateRecipeCategories() {
        recipeCategoriesState = categories.filter { $0.type == .recipe }
    }
    private func updateCompatibleMatches() {
        let pantryNames = pantryItems.map { normalized($0.name) }
        compatibleMatchesState = recipes
            .filter { recipe in
                guard let selectedCompatibleCategory = selectedCompatibleCategory else { return true }
                return recipe.category == selectedCompatibleCategory
            }
            .compactMap { recipe -> HomeRecipeMatch? in
                guard let compatibility = recipe.compatibility(against: pantryNames) else { return nil }
                return HomeRecipeMatch(recipe: recipe, compatibilityInfo: compatibility)
            }
            .sorted {
                if $0.compatibility != $1.compatibility { return $0.compatibility > $1.compatibility }
                if $0.compatibilityInfo.matchedIngredients != $1.compatibilityInfo.matchedIngredients {
                    return $0.compatibilityInfo.matchedIngredients > $1.compatibilityInfo.matchedIngredients
                }
                if $0.recipe.isFavorite != $1.recipe.isFavorite { return $0.recipe.isFavorite && !$1.recipe.isFavorite }
                return $0.recipe.name.localizedCaseInsensitiveCompare($1.recipe.name) == .orderedAscending
            }
    }
    private func updateExpiringItems() {
        let leadDays = settings?.expiringItemsLeadDays ?? 30
        let now = Calendar.current.startOfDay(for: .now)
        let limit = Calendar.current.date(byAdding: .day, value: leadDays, to: now) ?? now
        expiringItemsState = pantryItems
            .filter {
                guard let expirationDate = $0.expirationDate else { return false }
                let day = Calendar.current.startOfDay(for: expirationDate)
                return day <= limit
            }
            .sorted {
                guard let lhs = $0.expirationDate, let rhs = $1.expirationDate else { return false }
                return lhs < rhs
            }
    }

    private var assistantLauncher: some View {
        Button {
            onOpenChat()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seu centro de cozinha")
                            .font(.sectionTitle)
                            .foregroundStyle(.primary)

                        Text("Converse com a IA, acesse listas rápido e veja combinações da despensa.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "sparkles")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PageTheme.home.accentColor)
                        .frame(width: 46, height: 46)
                        .background(PageTheme.home.accentColor.opacity(0.14), in: .circle)
                }

                HStack(spacing: 8) {
                    compactPill("Conversar com IA", systemImage: "bubble.left.and.text.bubble.right.fill")
                    compactPill("Descubra receitas", systemImage: "fork.knife")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PageTheme.home.cardGradient,
                in: .rect(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var actionDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atalhos")
                .font(.headline.weight(.semibold))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                homeActionTile(
                    title: "IA",
                    subtitle: "Conversar",
                    systemImage: "sparkles",
                    tint: .blue
                ) {
                    onOpenChat()
                }

                homeActionTile(
                    title: "Mercado",
                    subtitle: "Adicionar item",
                    systemImage: "cart.badge.plus",
                    tint: .green
                ) {
                    showAddGrocery = true
                }

                homeActionTile(
                    title: "Despensa",
                    subtitle: "Modificar itens",
                    systemImage: "square.and.pencil",
                    tint: .orange
                ) {
                    showAddPantry = true
                }

                NavigationLink {
                    ListsTabView(initialSubtab: .pantry)
                } label: {
                    homeActionTileBody(
                        title: "Listas",
                        subtitle: "Abrir despensa",
                        systemImage: "list.bullet.clipboard",
                        tint: .indigo
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Validades próximas")
                        .font(.headline.weight(.semibold))
                    Text("Itens da despensa que vencem em breve")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(expiringItemsState.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14), in: .capsule)
            }

            VStack(spacing: 10) {
                ForEach(expiringItemsState.prefix(5)) { item in
                    Button {
                        editingExpiringItem = item
                    } label: {
                        HStack(spacing: 12) {
                            IconImage(name: item.name, iconFileName: item.iconName, fallbackSymbol: "clock.badge.exclamationmark", size: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                if let expiration = item.formattedExpirationDate {
                                    Text("Validade \(expiration)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if let expirationDate = item.expirationDate {
                                Text(relativeExpirationText(for: expirationDate))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(expirationHighlightColor(for: expirationDate))
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Editar", systemImage: "pencil") {
                            editingExpiringItem = item
                        }
                        Divider()
                        Button("Excluir", systemImage: "trash", role: .destructive) {
                            withAnimation {
                                modelContext.delete(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dessertShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receitas compatíveis")
                        .font(.headline.weight(.semibold))
                    Text("Ordenadas por compatibilidade com a sua despensa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !compatibleMatchesState.isEmpty {
                    Text("\(compatibleMatchesState.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PageTheme.home.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PageTheme.home.accentColor.opacity(0.12), in: .capsule)
                }
            }

            compatibleCategoryFilter

            if compatibleMatchesState.isEmpty {
                ContentUnavailableView(
                    "Sem receitas compatíveis",
                    systemImage: "fork.knife",
                    description: Text("Ajuste o grupo de receitas ou atualize a despensa para ver combinações aqui.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(compatibleMatchesState.prefix(8)) { match in
                            NavigationLink {
                                RecipeDetailView(recipe: match.recipe)
                            } label: {
                                HomeRecipeMatchCard(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var compatibleCategoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "Todos", isSelected: selectedCompatibleCategory == nil) {
                    selectedCompatibleCategory = nil
                }

                ForEach(recipeCategoriesState) { category in
                    filterChip(label: category.name, isSelected: selectedCompatibleCategory == category.name) {
                        selectedCompatibleCategory = category.name
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? PageTheme.home.accentColor.opacity(0.16) : Color(.tertiarySystemBackground),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? PageTheme.home.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private func compactPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: .capsule)
    }

    private func homeActionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            homeActionTileBody(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint
            )
        }
        .buttonStyle(.plain)
    }

    private func homeActionTileBody(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
    }

    private func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func relativeExpirationText(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days < 0 { return "Expirado" }
        if days == 0 { return "Hoje" }
        if days == 1 { return "1 dia" }
        return "\(days) dias"
    }

    private func expirationHighlightColor(for date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days < 0 { return .red }
        if days <= 7 { return .yellow }
        return .orange
    }
}

private struct HomeRecipeMatch: Identifiable {
    let recipe: Recipe
    let compatibilityInfo: RecipeCompatibility

    var id: UUID { recipe.id }
    var compatibility: Double { compatibilityInfo.ratio }
    var compactCompatibilityText: String { compatibilityInfo.compactText }
}

private struct HomeRecipeMatchCard: View {
    let match: HomeRecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                recipeImage
                    .frame(width: 210, height: 118)
                    .clipShape(.rect(cornerRadius: 16))

                Text(match.compactCompatibilityText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.72), in: .capsule)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(match.recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if match.recipe.totalTime > 0 {
                        Label("\(match.recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(match.recipe.difficulty.rawValue, systemImage: match.recipe.difficulty.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(match.compatibilityInfo.longText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PageTheme.home.accentColor)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var recipeImage: some View {
        if let data = match.recipe.imageData, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(.tertiarySystemFill), Color(.secondarySystemFill)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "birthday.cake")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}


#if os(iOS)
private struct ForceLightStatusBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                StatusBarStyleView(style: .lightContent)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}
extension View {
    func forceLightStatusBar() -> some View {
        self.modifier(ForceLightStatusBarModifier())
    }
}
#else
extension View {
    func forceLightStatusBar() -> some View {
        self.environment(\.colorScheme, .light)
    }
}
#endif
