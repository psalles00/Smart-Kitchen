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
    @State private var showCommandBar = false
    @State private var searchQuery = ""
    @State private var showAssistant = false
    @State private var showSettings = false
    @State private var showAddPantry = false
    @State private var showAddGrocery = false
    @State private var showAddRecipe = false
    @State private var showAddUtensil = false
    @State private var showAddItem = false
    @State private var addItemPrefill = ""
    @State private var addItemIconFileName: String?
    @State private var addItemCategory: String?
    @State private var isBouncingBackFromCommandBar = false
    @State private var scrollToTopTrigger: Int = 0
    @State private var scrollToItemRequest: ScrollToItemRequest?
    @State private var isSearchActive = false
    @State private var displayedBgTheme: PageTheme = .home
    @StateObject private var searchService = UniversalSearchService()

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
                if newValue == selectedTab && newValue != .commandBar && !isBouncingBackFromCommandBar {
                    scrollToTopTrigger += 1
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        mainTabView
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
        .sheet(isPresented: $showCommandBar) {
            CommandBarView { action in
                handleCommandBarAction(action)
            }
            #if os(macOS)
            .frame(width: 560, height: 480)
            #endif
        }
        .onAppear {
            // TODO: Re-enable daily backup once BackupManager.swift is included in this target.
            // BackupManager.shared.performDailyBackupIfNeeded(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                AssistantView()
            }
            .forceLightStatusBar()
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
                    HomeView(onSettingsTap: { showSettings = true })
                }
            } label: {
                Label("Início", systemImage: AppTab.assistant.icon)
            }

            Tab(value: AppTab.lists) {
                NavigationStack {
                    ListsTabView()
                }
            } label: {
                Label("Listas", systemImage: AppTab.lists.icon)
            }

            Tab(value: AppTab.recipes) {
                NavigationStack {
                    RecipesView()
                }
            } label: {
                Label("Receitas", systemImage: AppTab.recipes.icon)
            }

            Tab(value: AppTab.nutrients) {
                NavigationStack {
                    NutrientsPlaceholderView()
                }
            } label: {
                Label("Nutrientes", systemImage: AppTab.nutrients.icon)
            }

            Tab(value: AppTab.commandBar, role: .search) {
                NavigationStack {
                    CommandBarSearchContent(
                        query: $searchQuery,
                        searchService: searchService,
                        onAction: { handleCommandBarAction($0) }
                    )
                    .navigationTitle("Assistente")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                }
                .searchable(text: $searchQuery, isPresented: $isSearchActive, placement: .automatic, prompt: "Adicione, busque, ou pergunte…")
                .onSubmit(of: .search) {
                    submitSearchAction()
                }
                .onChange(of: searchQuery) { _, newValue in
                    searchService.search(query: newValue, context: modelContext, showUtensils: settings?.showUtensils == true)
                }
                .onChange(of: isSearchActive) { _, isActive in
                    if !isActive {
                        searchQuery = ""
                        if selectedTab == .commandBar {
                            selectedTab = lastContentTab
                        }
                    }
                }
            } label: {
                Label("Buscar", systemImage: AppTab.commandBar.icon)
            }
        }
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
                    showCommandBar = true
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
                        showCommandBar = true
                    } label: {
                        Label("Buscar", systemImage: "sparkle.magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        } detail: {
            switch selectedSidebar ?? .home {
            case .home:
                NavigationStack { HomeView(onSettingsTap: { selectedSidebar = .settings }) }
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
        .focusedSceneValue(\.openCommandBarAction, { showCommandBar = true })
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
        if newValue == .commandBar {
            #if os(macOS)
            // macOS: bounce back and present as a sheet
            isBouncingBackFromCommandBar = true
            selectedTab = lastContentTab
            showCommandBar = true
            return
            #endif
            // iOS: activate search field natively via isPresented binding
            isSearchActive = true
            return
        }

        if isBouncingBackFromCommandBar {
            isBouncingBackFromCommandBar = false
            return
        }

        lastContentTab = newValue

        // Animate background theme change with a fade, independently of content swap
        if let newTheme = newValue.pageTheme, newTheme != displayedBgTheme {
            displayedBgTheme = newTheme
        }
    }

    private func handleCommandBarAction(_ action: CommandBarAction) {
        // Dismiss search/command bar before navigating
        isSearchActive = false
        searchQuery = ""
        showCommandBar = false

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
        case .askAssistant:
            clearChatMessages()
            showAssistant = true
        case .openAssistant:
            clearChatMessages()
            showAssistant = true
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
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
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
                case .pantryItem:  handleCommandBarAction(.openPantryItem(objectID))
                case .groceryItem: handleCommandBarAction(.openGroceryItem(objectID))
                case .recipe:      handleCommandBarAction(.openRecipe(objectID))
                case .utensil:     handleCommandBarAction(.openUtensil(objectID))
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

    private func clearChatMessages() {
        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = (try? modelContext.fetch(descriptor)) ?? []
        for message in messages {
            modelContext.delete(message)
        }
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
    // Corrigido ciclo do AttributeGraph separando dependências reativas de SwiftData em @State com atualização manual para evitar travamentos no macOS.

    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var showAssistant = false
    @State private var showAddGrocery = false
    @State private var showAddPantry = false
    @State private var selectedCompatibleCategory: String? = nil

    @State private var recipeCategoriesState: [Category] = []
    @State private var compatibleMatchesState: [HomeRecipeMatch] = []
    @State private var expiringItemsState: [PantryItem] = []
    @State private var contentResetToken: Int = 0

    private var settings: AppSettings? { settingsArray.first }
    
    let onSettingsTap: () -> Void

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
            },
            onRefresh: {
                CloudSyncService.shared.syncNow()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.home.accentColor)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    CloudSyncService.shared.syncNow()
                } label: {
                    Label("Sincronizar", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                AssistantView()
            }
            .forceLightStatusBar()
        }
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
            showAssistant = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seu centro de cozinha")
                            .font(.sectionTitle)
                            .foregroundStyle(.primary)

                        Text("Abra o assistente em modal, acesse listas rápido e veja combinações da despensa sem depender de IA.")
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
                    compactPill("Abrir assistente", systemImage: "bubble.left.and.text.bubble.right.fill")
                    compactPill("Chat em modal", systemImage: "uiwindow.split.2x1")
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
                    title: "Assistente",
                    subtitle: "Abrir chat",
                    systemImage: "sparkles",
                    tint: .blue
                ) {
                    showAssistant = true
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
