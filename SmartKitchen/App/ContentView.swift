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
    @State private var searchEditItem: UnifiedItem?
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
    @FocusState private var macSearchFieldFocused: Bool

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
            ItemDetailView(
                mode: .create(destinations: [.pantry]),
                initialName: addItemPrefill,
                onCreated: { id, _ in
                    scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "pantryItem")
                    selectedTab = .lists
                }
            )
            .forceLightStatusBar()
            .onDisappear { addItemPrefill = "" }
        }
        .sheet(isPresented: $showAddGrocery) {
            ItemDetailView(
                mode: .create(destinations: [.grocery]),
                initialName: addItemPrefill,
                onCreated: { id, _ in
                    scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "groceryItem")
                    selectedTab = .lists
                }
            )
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
            ItemDetailView(mode: .create(destinations: [.utensil]))
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddItem) {
            ItemDetailView(
                mode: .create(),
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
            .forceLightStatusBar()
            .onDisappear {
                addItemPrefill = ""
                addItemIconFileName = nil
                addItemCategory = nil
            }
        }
        .sheet(item: $searchEditItem) { item in
            ItemDetailView(mode: .edit(item))
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
                        },
                        onOpenSearch: {
                            searchBarState.reveal()
                        }
                    )
                }
                .overlay { searchResultsOverlay }
                .overlay { searchBarDismissOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Início", systemImage: AppTab.assistant.icon)
            }

            Tab(value: AppTab.lists) {
                NavigationStack {
                    ListsTabView()
                }
                .overlay { searchResultsOverlay }
                .overlay { searchBarDismissOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Listas", systemImage: AppTab.lists.icon)
            }

            Tab(value: AppTab.recipes) {
                NavigationStack {
                    RecipesView()
                }
                .overlay { searchResultsOverlay }
                .overlay { searchBarDismissOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Receitas", systemImage: AppTab.recipes.icon)
            }

            Tab(value: AppTab.nutrients) {
                NavigationStack {
                    NutrientsPlaceholderView()
                }
                .overlay { searchResultsOverlay }
                .overlay { searchBarDismissOverlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomSearchBarArea }
            } label: {
                Label("Nutrientes", systemImage: AppTab.nutrients.icon)
            }
        }
        .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
            guard searchBarState.mode != .aiChat else { return }
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
            .padding(.vertical, 6)
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Invisible tap catcher: when the search bar is visible but has no content,
    /// tapping the background dismisses the search bar / keyboard.
    @ViewBuilder
    private var searchBarDismissOverlay: some View {
        if searchBarState.isVisible && !hasSearchContent {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    searchBarState.dismiss()
                }
        }
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
            // Header area — only this region dismisses the modal on drag
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Title + action buttons (aligned to bottom-right of subtitle)
                HStack(alignment: .bottom) {
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
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .contentShape(Rectangle())
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

            // Results area — scrollable, does NOT dismiss the modal
            if let overlay = searchOverlayView {
                overlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .offset(y: max(searchDragOffset, 0))
    }

    /// Search results view injected into ExpandedPageLayout's content panel via environment.
    private var searchOverlayView: AnyView? {
        #if os(macOS)
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showChat = searchBarState.mode == .aiChat
        guard hasText || showChat || pendingOpenChat || pendingChatQuery != nil else { return nil }
        #else
        guard searchBarState.isVisible else { return nil }
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showChat = searchBarState.mode == .aiChat

        guard hasText || showChat || pendingOpenChat || pendingChatQuery != nil else { return nil }
        #endif

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
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: searchBarState.mode == .aiChat ? "paperplane.fill" : "sparkle.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            searchBarState.mode == .aiChat ? "Converse com a IA…" : "Adicione, busque, ou pergunte…",
                            text: $searchBarState.searchText
                        )
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .focused($macSearchFieldFocused)
                        .onSubmit {
                            let trimmed = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            if searchBarState.mode == .aiChat {
                                searchBarState.pendingChatMessage = trimmed
                                searchBarState.searchText = ""
                            } else {
                                submitSearchAction()
                            }
                        }

                        if !searchBarState.searchText.isEmpty {
                            Button {
                                searchBarState.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("⌘K")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        macSearchFieldFocused = true
                    } label: {
                        Label("Buscar", systemImage: "sparkle.magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        } detail: {
            ZStack {
                NavigationStack {
                    HomeView(
                        onSettingsTap: { selectedSidebar = .settings },
                        onOpenChat: {
                            pendingOpenChat = true
                            macSearchFieldFocused = true
                        },
                        onOpenSearch: {
                            macSearchFieldFocused = true
                        }
                    )
                }
                .background(Color.clear)
                .environment(\.colorScheme, .light)
                .opacity(selectedSidebar == .home || selectedSidebar == nil ? 1 : 0)
                .allowsHitTesting(selectedSidebar == .home || selectedSidebar == nil)

                NavigationStack { ListsTabView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
                    .opacity(selectedSidebar == .lists ? 1 : 0)
                    .allowsHitTesting(selectedSidebar == .lists)

                NavigationStack { RecipesView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
                    .opacity(selectedSidebar == .recipes ? 1 : 0)
                    .allowsHitTesting(selectedSidebar == .recipes)

                NavigationStack { NutrientsPlaceholderView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
                    .opacity(selectedSidebar == .nutrients ? 1 : 0)
                    .allowsHitTesting(selectedSidebar == .nutrients)

                NavigationStack { SettingsView() }
                    .background(Color.clear)
                    .environment(\.colorScheme, .light)
                    .opacity(selectedSidebar == .settings ? 1 : 0)
                    .allowsHitTesting(selectedSidebar == .settings)
            }
            .overlay {
                if macHasSearchContent {
                    macSearchResultsOverlay
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
            guard searchBarState.mode != .aiChat else { return }
            searchService.search(query: newValue, context: modelContext, showUtensils: settings?.showUtensils == true)
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
                macBackgroundTransitionProgress = 1.0
            }
        }
    }

    private var macHasSearchContent: Bool {
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil
    }

    @ViewBuilder
    private var macSearchResultsOverlay: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
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
                        pendingNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingShowHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    searchBarState.searchText = ""
                    searchBarState.debouncedSearchText = ""
                    searchBarState.mode = .idle
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Results
            if let overlay = searchOverlayView {
                overlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .light)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(16)
        .environment(\.colorScheme, .light)
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
        case .editPantryItem(let id), .editGroceryItem(let id), .editUtensil(let id):
            let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditItem = item
            }
        case .editRecipe(let id):
            let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                searchEditRecipe = item
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
        let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        withAnimation {
            item.isGrocery = true
            item.isPantry = false
        }
    }

    private func moveGroceryItemToPantry(id: UUID) {
        let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        withAnimation {
            if let days = item.defaultExpiryDays, days > 0 {
                item.expirationDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
            item.isPantry = true
            item.isGrocery = false
        }
    }

    private func movePantryItemToGroceryByName(_ name: String) {
        let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate<UnifiedItem> { $0.isPantry })
        guard let items = try? modelContext.fetch(descriptor),
              let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        movePantryItemToGrocery(id: item.id)
    }

    private func moveGroceryItemToPantryByName(_ name: String) {
        let descriptor = FetchDescriptor<UnifiedItem>(predicate: #Predicate<UnifiedItem> { $0.isGrocery })
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

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(CloudSyncService.shared.container)
            .preferredColorScheme(.light)
            .previewDisplayName("ContentView — Canvas")
    }
}
#endif

private struct HomeView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.modelContext) private var modelContext
    // Corrigido ciclo do AttributeGraph separando dependências reativas de SwiftData em @State com atualização manual para evitar travamentos no macOS.

    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var showAddGrocery = false
    @State private var showAddPantry = false
    @State private var showAddRecipe = false
    @State private var selectedCompatibleCategory: String? = nil
    @State private var editingExpiringItem: UnifiedItem?

    @State private var recipeCategoriesState: [Category] = []
    @State private var compatibleMatchesState: [HomeRecipeMatch] = []
    @State private var expiringItemsState: [UnifiedItem] = []
    @State private var contentResetToken: Int = 0
    @State private var shortcutDeckWidth: CGFloat = 0

    private var settings: AppSettings? { settingsArray.first }
    
    let onSettingsTap: () -> Void
    let onOpenChat: () -> Void
    let onOpenSearch: () -> Void

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
                        actionDeck
                        if !expiringItemsState.isEmpty {
                            expiringSection
                        }
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
            ItemDetailView(mode: .create(destinations: [.grocery]))
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddPantry) {
            ItemDetailView(mode: .create(destinations: [.pantry]))
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddRecipe) {
            NavigationStack {
                AddRecipeView()
            }
            .forceLightStatusBar()
        }
        .sheet(item: $editingExpiringItem) { item in
            ItemDetailView(mode: .edit(item))
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
        let threshold = Double(settings?.recipeCompatibilityThresholdPercent ?? 80) / 100.0
        let applyTimeFilter = selectedCompatibleCategory == nil
        let mealKeywords = applyTimeFilter ? Self.mealKeywordsForCurrentTime() : []

        compatibleMatchesState = recipes
            .filter { recipe in
                guard let selectedCompatibleCategory = selectedCompatibleCategory else { return true }
                return recipe.categories.contains(selectedCompatibleCategory)
            }
            .compactMap { recipe -> HomeRecipeMatch? in
                guard let compatibility = recipe.compatibility(against: pantryNames) else { return nil }
                let match = HomeRecipeMatch(recipe: recipe, compatibilityInfo: compatibility)
                guard match.compatibility >= threshold else { return nil }
                return match
            }
            .sorted {
                // Boost recipes whose category/tags match current meal time (only for Sugestões)
                if applyTimeFilter {
                    let lhsMeal = Self.matchesMealTime($0.recipe, keywords: mealKeywords)
                    let rhsMeal = Self.matchesMealTime($1.recipe, keywords: mealKeywords)
                    if lhsMeal != rhsMeal { return lhsMeal }
                }
                if $0.compatibility != $1.compatibility { return $0.compatibility > $1.compatibility }
                if $0.compatibilityInfo.matchedIngredients != $1.compatibilityInfo.matchedIngredients {
                    return $0.compatibilityInfo.matchedIngredients > $1.compatibilityInfo.matchedIngredients
                }
                if $0.recipe.isFavorite != $1.recipe.isFavorite { return $0.recipe.isFavorite && !$1.recipe.isFavorite }
                return $0.recipe.name.localizedCaseInsensitiveCompare($1.recipe.name) == .orderedAscending
            }
    }

    /// Returns keywords that match the current time-of-day meal.
    private static func mealKeywordsForCurrentTime() -> [String] {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<10:
            return ["café da manhã", "café", "breakfast", "desjejum", "matinal"]
        case 10..<14:
            return ["almoço", "lunch", "prato principal", "refeição"]
        case 14..<17:
            return ["lanche", "snack", "sobremesa", "doce"]
        case 17..<21:
            return ["jantar", "dinner", "noturna", "prato principal", "refeição"]
        default:
            return ["lanche", "snack", "noturna"]
        }
    }

    /// Checks if a recipe's category or tags match meal-time keywords.
    private static func matchesMealTime(_ recipe: Recipe, keywords: [String]) -> Bool {
        let lower = recipe.category.lowercased()
        let tagSet = recipe.tags.map { $0.lowercased() }
        return keywords.contains { kw in
            lower.contains(kw) || tagSet.contains { $0.contains(kw) }
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

    private var actionDeck: some View {
        VStack(alignment: .leading, spacing: 14) {

        GeometryReader { geo in
            let spacing = homeShortcutSpacing
            let smallSide = homeShortcutSmallSide(for: geo.size.width)
            let topSide = smallSide * 2 + spacing

            VStack(spacing: spacing) {
                // Linha superior: Assistente (featured) + Modo IA / Receitas (wide)
                HStack(spacing: spacing) {
                    homeShortcutButton(
                        title: "Assistente",
                        subtitle: "Adicione, busque ou pergunte...",
                        imageName: "assistente",
                        style: .featured,
                        imageSize: 135,
                        imageOffset: CGSize(width: 28, height: 21)
                    ) {
                        onOpenSearch()
                    }
                    .frame(width: topSide, height: topSide)

                    VStack(spacing: spacing) {
                        homeShortcutButton(
                            title: "Modo IA",
                            subtitle: "",
                            imageName: "modo ia",
                            style: .wide,
                            imageSize: 126,
                            imageOffset: CGSize(width: 80, height: 36)
                        ) {
                            onOpenChat()
                        }
                        .frame(height: smallSide)

                        homeShortcutButton(
                            title: "Ideias",
                            subtitle: "",
                            imageName: "ideis",
                            style: .wide,
                            imageSize: 99,
                            imageOffset: CGSize(width: 95, height: 20)
                        ) {
                            onOpenChat()
                        }
                        .frame(height: smallSide)
                    }
                    .frame(width: topSide, height: topSide)
                }

                // Linha inferior: 4 tiles compactos com label abaixo
                HStack(spacing: spacing) {
                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "mercado", imageSize: 71) {
                            showAddGrocery = true
                        }
                        .frame(height: smallSide)
                        Text("Mercado")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "despensa", imageSize: 58) {
                            showAddPantry = true
                        }
                        .frame(height: smallSide)
                        Text("Despensa")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "receitas", imageSize: 65) {
                            showAddRecipe = true
                        }
                        .frame(height: smallSide)
                        Text("Receitas")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "nutrientes", imageSize: 58) {
                        }
                        .frame(height: smallSide)
                        Text("Nutrientes")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: homeShortcutDeckHeight(for: shortcutDeckWidth))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HomeShortcutDeckWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(HomeShortcutDeckWidthKey.self) { newWidth in
            shortcutDeckWidth = newWidth
        }
        .padding(.bottom, 40)
        } // end outer VStack
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

            VStack(spacing: 0) {
                ForEach(Array(expiringItemsState.prefix(5).enumerated()), id: \.element.id) { index, item in
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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

                    if index < min(expiringItemsState.count, 5) - 1 {
                        ItemListDivider()
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(homeShortcutBackgroundColor, in: .rect(cornerRadius: 18))
        }
    }

    private var dessertShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receitas sugeridas")
                        .font(.headline.weight(.semibold))
                    Text("Com base na sua despensa e horário do dia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !compatibleMatchesState.isEmpty {
                    Text("\(compatibleMatchesState.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(homeShortcutBackgroundColor, in: .capsule)
                }
            }

            compatibleCategoryFilter

            if compatibleMatchesState.isEmpty {
                ContentUnavailableView(
                    "Sem receitas sugeridas",
                    systemImage: "fork.knife",
                    description: Text("Ajuste o nível de compatibilidade nas configurações ou adicione mais itens à despensa.")
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
                filterChip(label: "Sugestões", isSelected: selectedCompatibleCategory == nil) {
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

    private var homeShortcutSpacing: CGFloat {
        8
    }

    private func homeShortcutSmallSide(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 72 }
        return max((width - homeShortcutSpacing * 3) / 4, 0)
    }

    private func homeShortcutDeckHeight(for width: CGFloat) -> CGFloat {
        let smallSide = homeShortcutSmallSide(for: width)
        return smallSide * 3 + homeShortcutSpacing * 2 + 22
    }

    private func homeShortcutButton(
        title: String,
        subtitle: String,
        imageName: String,
        style: HomeShortcutTileStyle,
        imageSize: CGFloat? = nil,
        imageOffset: CGSize? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            homeShortcutTileBody(
                title: title,
                subtitle: subtitle,
                imageName: imageName,
                style: style,
                customSize: imageSize,
                customOffset: imageOffset
            )
        }
        .buttonStyle(HomeShortcutButtonStyle())
    }

    private func homeShortcutLink<Destination: View>(
        title: String,
        subtitle: String,
        imageName: String,
        style: HomeShortcutTileStyle,
        imageSize: CGFloat? = nil,
        imageOffset: CGSize? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            homeShortcutTileBody(
                title: title,
                subtitle: subtitle,
                imageName: imageName,
                style: style,
                customSize: imageSize,
                customOffset: imageOffset
            )
        }
        .buttonStyle(HomeShortcutButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            HapticManager.impact(style: .light)
        })
    }

    private func homeShortcutTileBody(
        title: String,
        subtitle: String,
        imageName: String,
        style: HomeShortcutTileStyle,
        customSize: CGFloat? = nil,
        customOffset: CGSize? = nil
    ) -> some View {
        ZStack {
            homeShortcutBackgroundColor

            switch style {
            case .featured:
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(18)

            case .wide:
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(16)

            case .compact:
                Color.clear
            }
        }
        .overlay(alignment: homeShortcutImageAlignment(for: style)) {
            homeShortcutTileImage(
                imageName: imageName,
                style: style,
                customSize: customSize,
                customOffset: customOffset
            )
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    private func homeShortcutTileImage(
        imageName: String,
        style: HomeShortcutTileStyle,
        customSize: CGFloat?,
        customOffset: CGSize?
    ) -> some View {
        let defaultOffset: CGSize = switch style {
        case .featured:
            CGSize(width: 28, height: 28)
        case .wide:
            CGSize(width: 95, height: 25)
        case .compact:
            .zero
        }

        let finalOffset = customOffset ?? defaultOffset

        return Group {
            switch style {
            case .featured:
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: customSize ?? 150)
            case .wide:
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: customSize ?? 80)
            case .compact:
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: customSize ?? 76)
            }
        }
        .offset(finalOffset)
        .allowsHitTesting(false)
    }

    private func homeShortcutImageAlignment(for style: HomeShortcutTileStyle) -> Alignment {
        switch style {
        case .featured:
            .bottomTrailing
        case .wide:
            .bottomLeading
        case .compact:
            .center
        }
    }

    private func homeShortcutAddTile(
        imageName: String,
        imageSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            ZStack {
                homeShortcutBackgroundColor

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize ?? 76)
                    .allowsHitTesting(false)

                // "+" badge
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                    Spacer()
                }
            }
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(HomeShortcutButtonStyle())
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

private let homeShortcutBackgroundColor = Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)

private struct HomeShortcutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private enum HomeShortcutTileStyle {
    case featured
    case wide
    case compact

}

private struct HomeShortcutDeckWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label("\(match.compatibilityInfo.matchedIngredients)/\(match.compatibilityInfo.totalIngredients) ingr.", systemImage: "basket")
                    if match.recipe.totalTime > 0 {
                        Label("\(match.recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(match.recipe.difficulty.rawValue, systemImage: match.recipe.difficulty.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(12)
        .background(homeShortcutBackgroundColor, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var recipeImage: some View {
        if let data = match.recipe.imageData, let image = PlatformImage(data: data) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RecipeImagePlaceholderCompact(ingredients: (match.recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder })
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
private struct ForceLightSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .presentationBackground(.white)
    }
}
extension View {
    func forceLightStatusBar() -> some View {
        self.modifier(ForceLightSheetModifier())
    }
}
#endif
