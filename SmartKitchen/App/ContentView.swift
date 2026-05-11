import SwiftUI
import SwiftData
import PhotosUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case lists
    case recipes
    case nutrients
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Savoria"
        case .lists: return String(localized: "Listas")
        case .recipes: return String(localized: "Receitas")
        case .nutrients: return String(localized: "Nutrição")
        case .settings: return String(localized: "Configurações")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .lists: return "list.bullet.clipboard"
        case .recipes: return "book"
        case .nutrients: return "fork.knife"
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
    @State private var showWeightTracker = false
    @State private var addItemPrefill = ""
    @State private var addItemIconFileName: String?
    @State private var addItemCategory: String?
    @State private var scrollToTopTrigger: Int = 0
    @State private var scrollToItemRequest: ScrollToItemRequest?
    @State private var recipeNavigationPath = NavigationPath()
    @State private var displayedBgTheme: PageTheme = .home
    @State private var searchDragOffset: CGFloat = 0
    @StateObject private var searchService = UniversalSearchService()
    @StateObject private var searchBarState = SearchBarState()

    // Navigation stack for the search/assistant tab. Owned here so that the
    // home view's "Perguntar à IA" / "Ideias de receitas" / "Assistente"
    // shortcuts can both switch to the search tab AND push the AI page.
    @State private var assistantTabPath: [AssistantTabAIDestination] = []
    /// Tracks whether the on-screen keyboard is visible so we can hide the tab
    /// bar only while the user is actively typing. Driven by UIKit keyboard
    /// notifications on iOS.
    @State private var isKeyboardVisible: Bool = false

    // Search-triggered edit sheets
    @State private var searchEditItem: UnifiedItemSelection?
    @State private var searchEditRecipe: RecipeSelection?

    /// When non-nil, the CommandBar tab will open inline chat with this query on next activation.
    @State private var pendingChatQuery: String? = nil
    @State private var pendingOpenChat = false
    @State private var pendingNewConversation = false
    @State private var pendingShowHistory = false
    // The shared-import (Share Extension) sheet is presented by
    // `sharedImportInboxHost()` at the scene root in `SmartKitchenApp`,
    // OUTSIDE the `.id(cloudSync.containerID)` rebuild boundary.
    // ContentView only listens for follow-up routing notifications.
    @State private var showQuickRecipeImport = false
    @State private var quickRecipeImportLaunchMode: RecipeImportLaunchMode = .picker
    @State private var pendingQuickImportedRecipeID: UUID? = nil

    // MARK: - Direct assistant-bar shortcuts (no intermediate host sheet)
    // Food capture direct (nutrição)
    @State private var directFoodCameraActive = false
    @State private var directFoodGalleryActive = false
    @State private var directFoodGalleryItem: PhotosPickerItem?
    @State private var directFoodAnalysisImage: PlatformImage? = nil
    @State private var directFoodAnalysisLogDate: Date = Date()
    // Recipe import direct (receitas)
    @State private var directRecipeLinkActive = false
    @State private var directRecipeTextActive = false
    @State private var directRecipeGalleryActive = false
    @State private var directRecipeGalleryItem: PhotosPickerItem?
    @State private var directRecipeCameraActive = false

    /// Controls the first-launch onboarding flow. Driven by
    /// `AppSettings.hasCompletedOnboarding` and presented as a non-dismissible
    /// fullscreen cover until the user finishes (or chooses the free plan).
    @State private var showOnboarding: Bool = false

    #if os(macOS)
    @Environment(\.openSettings) private var openSettingsScene

    private enum MacAssistantShortcutIntent: Equatable {
        case assistant
        case aiMode
        case recipeIdeas

        var title: String {
            switch self {
            case .assistant:
                return String(localized: "Assistente")
            case .aiMode:
                return String(localized: "Modo IA")
            case .recipeIdeas:
                return String(localized: "Ideias de receitas")
            }
        }

        var symbolName: String {
            switch self {
            case .assistant:
                return "sparkle.magnifyingglass"
            case .aiMode:
                return "sparkles"
            case .recipeIdeas:
                return "lightbulb"
            }
        }

        var prompt: String {
            switch self {
            case .assistant:
                return String(localized: "Adicione, busque, ou pergunte…")
            case .aiMode:
                return AIChatPreset.nutritionCoach.searchPlaceholder
            case .recipeIdeas:
                return AIChatPreset.recipeIdeas.searchPlaceholder
            }
        }
    }

    @State private var selectedSidebar: SidebarItem? = .home
    @State private var macAssistantShortcutIntent: MacAssistantShortcutIntent?
    @State private var macAssistantBarFrame: CGRect = .zero
    @FocusState private var macSearchFieldFocused: Bool

    private var resolvedSelectedSidebar: SidebarItem {
        selectedSidebar ?? .home
    }

    private var macActivePageTheme: PageTheme {
        pageTheme(for: resolvedSelectedSidebar)
    }

    private var macAssistantBarAnimation: Animation {
        .spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    }

    private var macAssistantSearchTextIsEmpty: Bool {
        searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var macAssistantBarIsCentered: Bool {
        macAssistantShortcutIntent != nil && macAssistantSearchTextIsEmpty
    }

    private var macAssistantBarPrompt: String {
        if let macAssistantShortcutIntent {
            return macAssistantShortcutIntent.prompt
        }

        return searchBarState.mode == .aiChat
            ? searchBarState.aiChatPreset.searchPlaceholder
            : String(localized: "Adicione, busque, ou pergunte…")
    }

    private var macAssistantDockIconName: String {
        searchBarState.mode == .aiChat ? "paperplane.fill" : "sparkle.magnifyingglass"
    }

    private var macAssistantHighlightIntent: MacAssistantShortcutIntent {
        if let macAssistantShortcutIntent {
            return macAssistantShortcutIntent
        }

        if searchBarState.mode == .aiChat {
            return searchBarState.aiChatPreset == .recipeIdeas ? .recipeIdeas : .aiMode
        }

        return .assistant
    }

    private var macAssistantCurrentPageContext: SearchPageContext {
        switch resolvedSelectedSidebar {
        case .home:
            .home
        case .lists:
            .lists
        case .recipes:
            .recipes
        case .nutrients:
            .nutrients
        case .settings:
            .home
        }
    }

    private func openNativeSettingsWindow() {
        openSettingsScene()
    }

    private func beginMacAssistantShortcut(_ intent: MacAssistantShortcutIntent) {
        pendingShowHistory = false
        pendingNewConversation = false
        pendingOpenChat = false
        pendingChatQuery = nil
        searchBarState.pendingChatMessage = nil
        searchBarState.searchText = ""
        searchBarState.mode = .idle
        searchBarState.pageContext = macAssistantCurrentPageContext

        withAnimation(macAssistantBarAnimation) {
            macAssistantShortcutIntent = intent
        }

        searchBarState.reveal()
    }

    private func focusMacAssistantDock() {
        searchBarState.pageContext = macAssistantCurrentPageContext

        withAnimation(macAssistantBarAnimation) {
            macAssistantShortcutIntent = nil
        }

        searchBarState.reveal()
    }

    private func applyMacAssistantShortcutIntentIfNeeded() {
        guard let macAssistantShortcutIntent else { return }

        searchBarState.pageContext = macAssistantCurrentPageContext

        switch macAssistantShortcutIntent {
        case .assistant:
            searchBarState.mode = .idle
            searchBarState.aiChatPreset = .nutritionCoach
        case .aiMode:
            searchBarState.mode = .aiChat
            searchBarState.aiChatPreset = .nutritionCoach
        case .recipeIdeas:
            searchBarState.mode = .aiChat
            searchBarState.aiChatPreset = .recipeIdeas
        }

        withAnimation(macAssistantBarAnimation) {
            self.macAssistantShortcutIntent = nil
        }
    }

    private func restoreMacAssistantDockIfNeeded() {
        guard macAssistantShortcutIntent != nil else { return }

        withAnimation(macAssistantBarAnimation) {
            macAssistantShortcutIntent = nil
        }
    }

    private func submitMacAssistantText() {
        let trimmed = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            restoreMacAssistantDockIfNeeded()
            return
        }

        applyMacAssistantShortcutIntentIfNeeded()

        if searchBarState.mode == .aiChat {
            searchBarState.pendingChatMessage = trimmed
            searchBarState.searchText = ""
        } else {
            submitSearchAction()
        }
    }

    private func dismissMacAssistantInteraction() {
        if macSearchFieldFocused {
            searchBarState.defocusTrigger += 1
        } else if macAssistantBarIsCentered {
            restoreMacAssistantDockIfNeeded()
        }
    }

    private func handleMacAssistantOutsideTap(at location: CGPoint) {
        guard macAssistantBarFrame != .zero else { return }
        guard !macAssistantBarFrame.contains(location) else { return }

        dismissMacAssistantInteraction()
    }

    private func handleMacAssistantEscape() {
        guard macAssistantBarIsCentered || macSearchFieldFocused else { return }
        dismissMacAssistantInteraction()
    }

    @ViewBuilder
    private var macSidebarDetailContent: some View {
        switch resolvedSelectedSidebar {
        case .home:
            NavigationStack {
                HomeView(
                    onSettingsTap: { openNativeSettingsWindow() },
                    onOpenChat: {
                        beginMacAssistantShortcut(.aiMode)
                    },
                    onOpenRecipeIdeas: {
                        beginMacAssistantShortcut(.recipeIdeas)
                    },
                    onOpenSearch: {
                        beginMacAssistantShortcut(.assistant)
                    },
                    onOpenRecipeImport: openQuickRecipeImport,
                    onOpenFoodCameraDirect: openDirectFoodCamera,
                    onOpenFoodGalleryDirect: openDirectFoodGallery
                )
            }
            .background(Color.clear)

        case .lists:
            NavigationStack { ListsTabView() }
                .background(Color.clear)

        case .recipes:
            NavigationStack { RecipesView() }
                .background(Color.clear)

        case .nutrients:
            NavigationStack { NutrientsView() }
                .background(Color.clear)

        case .settings:
            NavigationStack { SettingsView() }
                .background(Color.clear)
        }
    }
    #endif

    private var settings: AppSettings? { settingsArray.first }
    private var activePageTheme: PageTheme { selectedTab.pageTheme ?? lastContentTab.pageTheme ?? .home }

    /// Mirrors `AppSettings.hasCompletedOnboarding` into `showOnboarding` so
    /// the fullscreen cover binding stays in sync. Also runs the one-shot
    /// migration that auto-completes onboarding for installs that already
    /// have user data (so the new flow only shows up for fresh installs).
    private func syncOnboardingFlag() {
        guard let settings else {
            // No settings row yet (very fresh launch). Don't decide here —
            // wait until the seeder creates one and SwiftData re-feeds the
            // query, then this method runs again via `.onChange`.
            return
        }

        if !settings.hasCompletedOnboarding {
            // Existing-user migration: if there is any pre-existing data,
            // assume the user already onboarded in a previous app version
            // and just flip the flag silently.
            if hasExistingUserData {
                settings.hasCompletedOnboarding = true
                try? modelContext.save()
                showOnboarding = false
                return
            }
            showOnboarding = true
        } else {
            showOnboarding = false
        }
    }

    /// Returns true when the database already has any user-created content,
    /// indicating this isn't a brand-new install.
    private var hasExistingUserData: Bool {
        var fd = FetchDescriptor<UnifiedItem>()
        fd.fetchLimit = 1
        if let items = try? modelContext.fetch(fd), !items.isEmpty { return true }
        var rd = FetchDescriptor<Recipe>()
        rd.fetchLimit = 1
        if let recipes = try? modelContext.fetch(rd), !recipes.isEmpty { return true }
        return false
    }

    private var assistantOverlayTitle: String {
        searchBarState.mode == .aiChat ? String(localized: "Modo IA") : String(localized: "Assistente")
    }
    private var assistantOverlaySubtitle: String {
        String(localized: "Adicione itens, busque na despensa ou pergunte à IA.")
    }

    private var fullscreenNutritionEntrySheetBinding: Binding<NutritionEntrySheet?> {
        Binding(
            get: {
                guard let sheet = searchBarState.pendingNutritionSheet,
                      sheet.prefersFullScreenPresentation else {
                    return nil
                }

                return sheet
            },
            set: { searchBarState.pendingNutritionSheet = $0 }
        )
    }

    private var sheetNutritionEntrySheetBinding: Binding<NutritionEntrySheet?> {
        Binding(
            get: {
                guard let sheet = searchBarState.pendingNutritionSheet,
                      !sheet.prefersFullScreenPresentation else {
                    return nil
                }

                return sheet
            },
            set: { searchBarState.pendingNutritionSheet = $0 }
        )
    }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    let isResettingRecipeDetail = newValue == .recipes && !recipeNavigationPath.isEmpty

                    if newValue == .recipes {
                        recipeNavigationPath = NavigationPath()
                    }

                    if !isResettingRecipeDetail {
                        scrollToTopTrigger += 1
                    }
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            mainTabView
                #if os(macOS)
                .allowsHitTesting(!showOnboarding)
                #endif

            #if os(macOS)
            if showOnboarding {
                OnboardingFlowView {
                    showOnboarding = false
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(1)
            }
            #endif
        }
        .environmentObject(searchBarState)
        .environment(\.scrollToItem, scrollToItemRequest)
        .environment(\.openRecipeInRecipesTab, openRecipeInRecipesTab)
        .environment(\.backgroundTheme, displayedBgTheme)
        .environment(\.visiblePageTheme, activePageTheme)
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView {
                showOnboarding = false
            }
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(item: fullscreenNutritionEntrySheetBinding) { sheet in
            nutritionEntrySheetContent(for: sheet)
        }
        .sheet(item: sheetNutritionEntrySheetBinding) { sheet in
            nutritionEntrySheetContent(for: sheet)
        }
        #else
        .sheet(item: $searchBarState.pendingNutritionSheet) { sheet in
            nutritionEntrySheetContent(for: sheet)
        }
        #endif
        .onAppear { syncOnboardingFlag() }
        .onChange(of: settings?.hasCompletedOnboarding ?? true) { _, _ in
            syncOnboardingFlag()
        }
        .sheet(isPresented: $showQuickRecipeImport, onDismiss: handleQuickRecipeImportDismissed) {
            RecipeImportHostView(launchMode: quickRecipeImportLaunchMode) { recipeID in
                pendingQuickImportedRecipeID = recipeID
                showQuickRecipeImport = false
            }
            .modelContainer(CloudSyncService.shared.container)
            .forceLightStatusBar()
        }
        .modifier(DirectAssistantShortcutsModifier(
            directFoodCameraActive: $directFoodCameraActive,
            directFoodGalleryActive: $directFoodGalleryActive,
            directFoodGalleryItem: $directFoodGalleryItem,
            directFoodAnalysisImage: $directFoodAnalysisImage,
            directFoodAnalysisLogDate: $directFoodAnalysisLogDate,
            directRecipeLinkActive: $directRecipeLinkActive,
            directRecipeTextActive: $directRecipeTextActive,
            directRecipeGalleryActive: $directRecipeGalleryActive,
            directRecipeGalleryItem: $directRecipeGalleryItem,
            directRecipeCameraActive: $directRecipeCameraActive,
            onRecipeImportedFromDirect: { recipeID in
                pendingQuickImportedRecipeID = recipeID
            },
            onRecipeSourceReady: { source in
                // Direct shortcuts route through `RecipeImportInbox`, which
                // is hosted at the scene root by `recipeImportInboxHost()`.
                // This keeps the presenting sheet outside ContentView's
                // `.id(cloudSync.containerID)` rebuild boundary, matching
                // the share-extension flow.
                RecipeImportLogger.info("direct shortcut -> RecipeImportInbox source \(RecipeImportLogger.sourceSummary(source))")
                RecipeImportInbox.shared.pendingSource = source
            }
        ))
        .sheet(isPresented: $showAddPantry) {
            ItemDetailView(
                mode: .create(destinations: [.pantry]),
                initialName: addItemPrefill,
                onCreated: { id, _ in
                    scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "pantryItem")
                    selectedTab = .lists
                },
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
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
                },
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
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
            ItemDetailView(
                mode: .create(destinations: [.utensil]),
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
                }
            )
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
                },
                onExistingItemRequested: { item in
                    openExistingItemFromCreateFlow(item)
                }
            )
            .forceLightStatusBar()
            .onDisappear {
                addItemPrefill = ""
                addItemIconFileName = nil
                addItemCategory = nil
            }
        }
        .sheet(item: $searchEditItem, onDismiss: { searchEditItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id)
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showWeightTracker) {
            NavigationStack {
                WeightTrackerView(showsDismissButton: true)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $searchEditRecipe, onDismiss: { searchEditRecipe = nil }) { selection in
            NavigationStack {
                EditRecipeContainerView(recipeID: selection.id)
            }
            .forceLightStatusBar()
        }
        .environment(\.presentAppSettings, {
            #if os(macOS)
            openNativeSettingsWindow()
            #else
            showSettings = true
            #endif
        })
        .environment(\.scrollToTopTrigger, scrollToTopTrigger)
        .preferredColorScheme(settings?.appearanceMode.colorScheme)
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
            #if os(macOS)
            openNativeSettingsWindow()
            #else
            showSettings = true
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAssistantFromWidget)) { _ in
            #if os(iOS)
            openAssistantTab()
            #else
            searchBarState.reveal(mode: .idle)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAIChatFromWidget)) { _ in
            // Open AI chat mode (handles iOS tab switch + push internally).
            openAIMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNutritionAtDate)) { _ in
            // The date itself is consumed by `NutrientsView`; here we only need
            // to switch the active tab so that view comes into focus.
            if selectedTab != .nutrients { selectedTab = .nutrients }
        }
        #if os(iOS)
        .forceLightStatusBar()
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .shareImportRouteToNutrients)) { _ in
            #if os(macOS)
            selectedSidebar = .nutrients
            #else
            if selectedTab != .nutrients { selectedTab = .nutrients }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareImportOpenAssistant)) { note in
            let prefill = note.userInfo?["prefill"] as? String
            openAIMode(prefill: prefill)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareImportRecipeSaved)) { note in
            guard let recipeID = note.userInfo?["recipeID"] as? UUID else { return }
            // Defer to the next main-actor turn so navigation does not race
            // with the still-committing sheet-dismiss transaction.
            Task { @MainActor in
                openRecipeInRecipesTab(recipeID)
            }
        }
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
        ZStack {
            TabView(selection: tabSelectionBinding) {
                Tab(value: AppTab.assistant) {
                    NavigationStack {
                        HomeView(
                            onSettingsTap: { showSettings = true },
                            onOpenChat: {
                                openAIMode()
                            },
                            onOpenRecipeIdeas: {
                                openAIMode(preset: .recipeIdeas)
                            },
                            onOpenSearch: {
                                openAssistantTab()
                            },
                            onOpenRecipeImport: openQuickRecipeImport,
                            onOpenFoodCameraDirect: openDirectFoodCamera,
                            onOpenFoodGalleryDirect: openDirectFoodGallery
                        )
                    }
                } label: {
                    Label("Savoria", systemImage: AppTab.assistant.icon)
                }

                Tab(value: AppTab.lists) {
                    NavigationStack {
                        ListsTabView()
                    }
                } label: {
                    Label("Listas", systemImage: AppTab.lists.icon)
                }

                Tab(value: AppTab.recipes) {
                    NavigationStack(path: $recipeNavigationPath) {
                        RecipesView()
                    }
                } label: {
                    Label("Receitas", systemImage: AppTab.recipes.icon)
                }

                Tab(value: AppTab.nutrients) {
                    NavigationStack {
                        NutrientsView()
                    }
                } label: {
                    Label("Nutrição", systemImage: AppTab.nutrients.icon)
                }

                Tab(value: AppTab.commandBar, role: .search) {
                    AssistantSearchTabContent(
                        searchBarState: searchBarState,
                        searchService: searchService,
                        onAction: { handleCommandBarAction($0) },
                        onOpenFoodCameraDirect: openDirectFoodCamera,
                        onOpenFoodGalleryDirect: openDirectFoodGallery,
                        pendingChatQuery: $pendingChatQuery,
                        pendingOpenChat: $pendingOpenChat,
                        pendingNewConversation: $pendingNewConversation,
                        pendingShowHistory: $pendingShowHistory,
                        path: $assistantTabPath
                    )
                } label: {
                    Label("Buscar", systemImage: AppTab.commandBar.icon)
                }
            }
            #if os(iOS)
            // Hide the tab bar only while the keyboard is up; otherwise the
            // assistant bar always shows alongside the tab bar.
            .toolbar(isKeyboardVisible ? .hidden : .visible, for: .tabBar)
            #endif
            .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
                guard searchBarState.mode != .aiChat else { return }
                searchService.search(query: newValue, context: modelContext, showUtensils: settings?.showUtensils == true)
            }
            .environment(\.searchOverlay, searchOverlayView)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            persistentAssistantBar
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
        .onChange(of: searchBarState.isVisible) { _, newValue in
            // Tapping the persistent assistant bar from any tab focuses it; in
            // that case we always switch to the assistant (search) tab so the
            // user sees the assistant content above the bar.
            if newValue && selectedTab != .commandBar {
                selectedTab = .commandBar
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    searchBarState.focusTrigger += 1
                }
            }
        }
    }

    // MARK: - Persistent Search Bar

    private var persistentAssistantBar: some View {
        UnifiedSearchBar(
            state: searchBarState,
            onAction: handleCommandBarAction,
            onOpenRecipeImport: openQuickRecipeImport,
            onOpenFoodCameraDirect: openDirectFoodCamera,
            onOpenFoodGalleryDirect: openDirectFoodGallery
        )
            .padding(.vertical, 6)
            // Compensate for the floating tab bar only while it is visible.
            // When the keyboard opens, the tab bar hides and the safe area
            // already repositions this inset above the keyboard.
            .padding(.bottom, isKeyboardVisible ? 0 : 49)
    }

    private func openQuickRecipeImport(_ launchMode: RecipeImportLaunchMode) {
        switch launchMode {
        case .link:
            directRecipeLinkActive = true
        case .text:
            directRecipeTextActive = true
        case .gallery:
            directRecipeGalleryItem = nil
            directRecipeGalleryActive = true
        case .camera:
            directRecipeCameraActive = true
        case .picker, .files:
            quickRecipeImportLaunchMode = launchMode
            showQuickRecipeImport = true
        }
    }

    private func openDirectFoodCamera() {
        directFoodAnalysisLogDate = Date()
        directFoodCameraActive = true
    }

    private func openDirectFoodGallery() {
        directFoodAnalysisLogDate = Date()
        directFoodGalleryItem = nil
        directFoodGalleryActive = true
    }

    // MARK: - Nutrition entry sheet (disparado pelo menu "+" da barra global)

    @ViewBuilder
    private func nutritionEntrySheetContent(for sheet: NutritionEntrySheet) -> some View {
        let logDate = Date()
        switch sheet {
        case .manual(let prefillName, let prefillMealType):
            FoodEntryFormView(
                mode: .create(onDate: logDate),
                prefillName: prefillName,
                prefillMealType: prefillMealType
            )
        case .recents:
            RecentsView(logDate: logDate)
        case .capturePhotoCamera:
            // Direct shortcut is handled at the root via DirectAssistantShortcutsModifier.
            // If routed through this sheet for any reason, fall back to the host chooser.
            FoodCaptureHostView(mode: .photo, logDate: logDate)
        case .capturePhotoGallery:
            FoodCaptureHostView(mode: .photo, logDate: logDate)
        case .captureLabel:
            FoodCaptureHostView(mode: .nutritionLabel, logDate: logDate)
        case .captureText(let prefillText, let autoAnalyze):
            FoodCaptureHostView(
                mode: .text,
                logDate: logDate,
                initialText: prefillText ?? "",
                shouldAutoAnalyzeTextOnAppear: autoAnalyze
            )
        case .captureVoice:
            FoodCaptureHostView(mode: .voice, logDate: logDate)
        case .comingSoon:
            EmptyView()
        }
    }

    /// Whether the results panel should be shown (first letter typed, chat, etc.)
    private var hasSearchContent: Bool {
        guard searchBarState.isVisible else { return false }
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil
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
                        Text(assistantOverlayTitle)
                            .font(.pageTitle)
                        if searchBarState.mode != .aiChat {
                            Text(assistantOverlaySubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
                topPinnedInset: 0,
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
        ZStack {
            NavigationSplitView {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            macSidebarNavigationSection
                            macSidebarShortcutsSection
                            macSidebarPreferencesSection
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
                .background(MacDarkSidebarBackground().ignoresSafeArea())
                .navigationTitle("")
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
                .environment(\.colorScheme, .dark)
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: 60)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            focusMacAssistantDock()
                        } label: {
                            Label("Buscar", systemImage: "sparkle.magnifyingglass")
                        }
                        .keyboardShortcut("k", modifiers: .command)
                    }
                }
            } detail: {
                ZStack {
                    macSidebarDetailContent
                }
                .overlay(alignment: .top) {
                    if macHasSearchContent {
                        macSearchResultsOverlay
                            .transition(.opacity)
                    }
                }
            }
            macAssistantBarOverlay
                .zIndex(1)
        }
        .coordinateSpace(name: "MacAssistantRoot")
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleMacAssistantOutsideTap(at: value.location)
                }
        )
        .onExitCommand {
            handleMacAssistantEscape()
        }
        .onPreferenceChange(MacAssistantBarFramePreferenceKey.self) { frame in
            macAssistantBarFrame = frame
        }
        .onChange(of: searchBarState.searchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                applyMacAssistantShortcutIntentIfNeeded()
            }
        }
        .onChange(of: searchBarState.focusTrigger) { _, _ in
            macSearchFieldFocused = true
        }
        .onChange(of: searchBarState.defocusTrigger) { _, _ in
            macSearchFieldFocused = false
            if macAssistantSearchTextIsEmpty {
                restoreMacAssistantDockIfNeeded()
            }
        }
        .onChange(of: macSearchFieldFocused) { _, newValue in
            if !newValue && macAssistantSearchTextIsEmpty {
                restoreMacAssistantDockIfNeeded()
            }
        }
        .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
            guard searchBarState.mode != .aiChat else { return }
            searchService.search(query: newValue, context: modelContext, showUtensils: settings?.showUtensils == true)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .focusedSceneValue(\.openCommandBarAction, { focusMacAssistantDock() })
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
        }
    }

    private var macHasSearchContent: Bool {
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil
    }

    private var macAssistantBarOverlay: some View {
        GeometryReader { proxy in
            let isCentered = macAssistantBarIsCentered
            let dockWidth = min(max(proxy.size.width * 0.22, 252), 292)
            let centeredWidth = min(max(proxy.size.width * 0.50, 540), 760)
            let width = isCentered ? centeredWidth : dockWidth
            let height: CGFloat = isCentered ? 74 : 52
            let x = isCentered ? proxy.size.width / 2 : 16 + width / 2
            let y = isCentered
                ? proxy.size.height / 2
                : proxy.size.height - proxy.safeAreaInsets.bottom - 18 - height / 2

            macAssistantBarChrome(isCentered: isCentered)
                .frame(width: width)
                .position(x: x, y: y)
                .shadow(color: .black.opacity(isCentered ? 0.34 : 0.16), radius: isCentered ? 44 : 16, y: isCentered ? 18 : 10)
                .shadow(color: .black.opacity(isCentered ? 0.20 : 0.08), radius: isCentered ? 14 : 6, y: isCentered ? 6 : 3)
                .preference(
                    key: MacAssistantBarFramePreferenceKey.self,
                    value: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
                )
        }
        .allowsHitTesting(true)
    }

    private func macAssistantBarChrome(isCentered: Bool) -> some View {
        HStack(spacing: isCentered ? 14 : 8) {
            if isCentered {
                HStack(spacing: 8) {
                    Image(systemName: macAssistantHighlightIntent.symbolName)
                    Text(macAssistantHighlightIntent.title)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.10), in: Capsule())
            } else {
                Image(systemName: macAssistantDockIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            TextField(
                "",
                text: $searchBarState.searchText
            )
            .textFieldStyle(.plain)
            .font(isCentered ? .title3.weight(.medium) : .subheadline)
            .overlay(alignment: .leading) {
                if macAssistantSearchTextIsEmpty {
                    Text(macAssistantBarPrompt)
                        .foregroundStyle(.white.opacity(isCentered ? 0.74 : 1))
                        .allowsHitTesting(false)
                        .lineLimit(1)
                }
            }
            .focused($macSearchFieldFocused)
            .onSubmit {
                submitMacAssistantText()
            }

            if !macAssistantSearchTextIsEmpty {
                Button {
                    searchBarState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: isCentered ? 16 : 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .buttonStyle(.plain)
            } else if !isCentered {
                Text("⌘K")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .foregroundStyle(.white, .white.opacity(0.82), .white.opacity(0.58))
        .tint(.white)
        .padding(.horizontal, isCentered ? 18 : 14)
        .padding(.vertical, isCentered ? 16 : 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: isCentered ? 24 : 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.20, blue: 0.24).opacity(isCentered ? 0.97 : 0.95),
                            Color(red: 0.11, green: 0.12, blue: 0.15).opacity(isCentered ? 0.94 : 0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCentered ? 24 : 14, style: .continuous)
                .strokeBorder(.white.opacity(isCentered ? 0.18 : 0.10), lineWidth: 1)
        )
        .contentShape(.rect)
        .onTapGesture {
            searchBarState.isVisible = true
            macSearchFieldFocused = true
        }
        .animation(macAssistantBarAnimation, value: isCentered)
    }

    // MARK: - macOS sidebar row helpers

    private func pageTheme(for item: SidebarItem) -> PageTheme {
        switch item {
        case .home: return .home
        case .lists: return .lists
        case .recipes: return .recipes
        case .nutrients: return .nutrients
        case .settings: return .home
        }
    }

    @ViewBuilder
    private var macSidebarNavigationSection: some View {
        macSidebarSection(title: "Navegação") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                    macSidebarRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var macSidebarShortcutsSection: some View {
        macSidebarSection(title: "Atalhos") {
            VStack(alignment: .leading, spacing: 4) {
                macSidebarShortcutRow(title: String(localized: "Assistente"), systemImage: "sparkle.magnifyingglass") {
                    selectedSidebar = .home
                    beginMacAssistantShortcut(.assistant)
                }
                macSidebarShortcutRow(title: String(localized: "Modo IA"), systemImage: "sparkles") {
                    selectedSidebar = .home
                    beginMacAssistantShortcut(.aiMode)
                }
                macSidebarShortcutRow(title: String(localized: "Ideias de receitas"), systemImage: "lightbulb") {
                    selectedSidebar = .home
                    beginMacAssistantShortcut(.recipeIdeas)
                }
                macSidebarShortcutRow(title: String(localized: "Adicionar à Despensa"), systemImage: "cabinet") {
                    showAddPantry = true
                }
                macSidebarShortcutRow(title: String(localized: "Adicionar ao Mercado"), systemImage: "cart") {
                    showAddGrocery = true
                }
                Menu {
                    macSidebarRecipeMenu
                } label: {
                    macSidebarShortcutLabel(title: String(localized: "Adicionar Receita"), systemImage: "book")
                }
                .menuOrder(.fixed)
                .buttonStyle(.plain)

                Menu {
                    macSidebarFoodMenu
                } label: {
                    macSidebarShortcutLabel(title: String(localized: "Registrar Alimento"), systemImage: "fork.knife")
                }
                .menuOrder(.fixed)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var macSidebarPreferencesSection: some View {
        macSidebarSection(title: "Preferências") {
            VStack(alignment: .leading, spacing: 4) {
                macSidebarRow(item: .settings)
            }
        }
    }

    @ViewBuilder
    private func macSidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 10)

            content()
        }
    }

    @ViewBuilder
    private var macSidebarRecipeMenu: some View {
        Section("Receitas") {
            Button("Criar receita", systemImage: "square.and.pencil") {
                showAddRecipe = true
            }
        }
        Section("Importar receita") {
            Button("Colar link", systemImage: "link") {
                openQuickRecipeImport(.link)
            }
            Button("Importar da galeria", systemImage: "photo.on.rectangle.angled") {
                openQuickRecipeImport(.gallery)
            }
            Button("Ler com câmera", systemImage: "camera.viewfinder") {
                openQuickRecipeImport(.camera)
            }
            Button("Colar texto", systemImage: "text.alignleft") {
                openQuickRecipeImport(.text)
            }
            Button("Importar dos arquivos", systemImage: "folder.fill") {
                openQuickRecipeImport(.files)
            }
        }
    }

    @ViewBuilder
    private var macSidebarFoodMenu: some View {
        Section("Registros Salvos") {
            Button("Salvar alimento", systemImage: "fork.knife") {
                searchBarState.pendingNutritionSheet = .manual()
            }
            Button("Alimentos salvos", systemImage: "clock.arrow.circlepath") {
                searchBarState.pendingNutritionSheet = .recents
            }
        }
        Section("Registrar por…") {
            Button("Rótulo", systemImage: "doc.text.viewfinder") {
                searchBarState.pendingNutritionSheet = .captureLabel
            }
            Button("Galeria", systemImage: "photo") {
                openDirectFoodGallery()
            }
            Button("Voz", systemImage: "waveform") {
                searchBarState.pendingNutritionSheet = .captureVoice
            }
            Button("Texto", systemImage: "character.cursor.ibeam") {
                searchBarState.pendingNutritionSheet = .captureText(prefillText: nil, autoAnalyze: false)
            }
        }
    }

    /// Sidebar destination row with custom themed selection painting.
    /// Avoids macOS's system blue selection highlight by using a manual
    /// background tinted with the destination's page theme accent color.
    @ViewBuilder
    private func macSidebarRow(item: SidebarItem) -> some View {
        let isSelected = resolvedSelectedSidebar == item
        let accent = pageTheme(for: item).accentColor

        Button {
            if item == .settings {
                openNativeSettingsWindow()
            } else {
                selectedSidebar = item
            }
        } label: {
            macSidebarLabel(title: item.title, systemImage: item.systemImage, foregroundStyle: isSelected ? Color.white : Color.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(accent.opacity(0.85)) : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
    }

    /// Plain sidebar shortcut row (no selection state).
    @ViewBuilder
    private func macSidebarShortcutRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            macSidebarShortcutLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func macSidebarShortcutLabel(title: String, systemImage: String) -> some View {
        macSidebarLabel(title: title, systemImage: systemImage, foregroundStyle: Color.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func macSidebarLabel(title: String, systemImage: String, foregroundStyle: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22, alignment: .center)

            Text(title)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    @ViewBuilder
    private var macSearchResultsOverlay: some View {
        let topOverlap: CGFloat = 78

        VStack(spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assistantOverlayTitle)
                        .font(.pageTitle)
                    if searchBarState.mode != .aiChat {
                        Text(assistantOverlaySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(appPrimaryBackground.opacity(0.985))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .offset(y: -topOverlap)
    }

    #endif

    private func handleTabSelectionChange(_ newValue: AppTab) {
        lastContentTab = newValue

        // When leaving the assistant tab to a content tab, defocus the search
        // field (hides keyboard) but DO NOT call `searchBarState.dismiss()` —
        // the AI page navigation state inside the assistant tab must survive
        // tab switches so the user can come back to where they were.
        if newValue != .commandBar && searchBarState.isVisible {
            searchBarState.defocusTrigger += 1
            searchBarState.isVisible = false
        }

        // Animate background theme change with a fade, independently of content swap
        if let newTheme = newValue.pageTheme, newTheme != displayedBgTheme {
            displayedBgTheme = newTheme
        }

        // Ao entrar na aba Nutrição, sempre voltar para o dia de hoje.
        if newValue == .nutrients {
            NotificationCenter.default.post(
                name: .openNutritionAtDate,
                object: nil,
                userInfo: ["date": Calendar.current.startOfDay(for: .now)]
            )
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
            openRecipeInRecipesTab(id)
        case .openUtensil(let id):
            scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "utensil")
            selectedTab = .lists
        case .editPantryItem(let id), .editGroceryItem(let id), .editUtensil(let id):
            searchEditItem = UnifiedItemSelection(id: id)
        case .editRecipe(let id):
            searchEditRecipe = RecipeSelection(id: id)
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
        case .registerFood(let prefill):
            searchBarState.pendingNutritionSheet = .captureText(prefillText: prefill, autoAnalyze: true)
        case .openWeightTracker:
            showWeightTracker = true
        case .askAssistant(let prefill):
            openAIMode(prefill: prefill)
        case .openAssistant:
            openAIMode()
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

    private func openRecipeInRecipesTab(_ id: UUID) {
        #if os(macOS)
        scrollToItemRequest = ScrollToItemRequest(itemID: id, type: "recipe")
        selectedSidebar = .recipes
        #else
        // Always defer navigation mutations to the next main-actor turn so
        // they don't collide with an in-flight sheet dismissal transaction.
        // Mutating `recipeNavigationPath` synchronously from an `onDismiss`
        // handler produces the "NavigationRequestObserver tried to update
        // multiple times per frame" warning and can land the detail view in
        // the same tick as SwiftData autosave — which has been trapping.
        let navigateToRecipe = {
            var path = NavigationPath()
            path.append(id)
            recipeNavigationPath = path
        }

        if selectedTab != .recipes {
            selectedTab = .recipes
        }
        Task { @MainActor in
            navigateToRecipe()
        }
        #endif
    }

    private func openAssistantFromSharedImport(prefill: String) {
        openAIMode(prefill: prefill)
    }

    private func openAIMode(preset: AIChatPreset = .nutritionCoach, prefill: String? = nil) {
        pendingShowHistory = false
        pendingNewConversation = false
        // Switch to the assistant (search) tab and push the AI page. The page
        // itself sets `searchBarState.mode = .aiChat` and routes the prefill
        // through `pendingChatQuery` / `pendingOpenChat` on appear.
        openAssistantTab(push: AssistantTabAIDestination(preset: preset, prefill: prefill))
    }

    /// Switches the active tab to the assistant (search) tab. If `push` is
    /// provided, also pushes the corresponding AI page on top of the tab's
    /// navigation stack. Use `openAssistantTab()` (no argument) to land on
    /// the idle assistant page (action grid / search results).
    private func openAssistantTab(push destination: AssistantTabAIDestination? = nil) {
        if let destination {
            // Replace the stack with just this destination so repeated taps
            // don't accumulate duplicate pages.
            assistantTabPath = [destination]
        } else {
            assistantTabPath = []
        }
        if selectedTab != .commandBar {
            selectedTab = .commandBar
        }
        searchBarState.reveal(mode: destination == nil ? .idle : nil)
    }

    private func handleQuickRecipeImportDismissed() {
        quickRecipeImportLaunchMode = .picker

        guard let importedRecipeID = pendingQuickImportedRecipeID else { return }

        pendingQuickImportedRecipeID = nil
        searchBarState.dismiss()
        // Defer navigation: let the sheet-dismiss transaction fully commit
        // before mutating nav path, avoiding same-frame update warning / trap.
        Task { @MainActor in
            openRecipeInRecipesTab(importedRecipeID)
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

    private func openExistingItemFromCreateFlow(_ item: UnifiedItem) {
        showAddPantry = false
        showAddGrocery = false
        showAddUtensil = false
        showAddItem = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            searchEditItem = UnifiedItemSelection(id: item.id)
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

private struct MacAssistantBarFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
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

/// Forces the macOS NavigationSplitView sidebar to render with dark
/// `NSAppearance`, regardless of the window's effective appearance.
///
/// SwiftUI's `.environment(\.colorScheme, .dark)` only changes how SwiftUI
/// resolves dynamic colors in descendant views — it does NOT touch the
/// AppKit-rendered sidebar material (NSVisualEffectView with .sidebar
/// material), which always follows the window's `effectiveAppearance`.
///
/// To force the sidebar dark we install a transparent NSView as background
/// and walk up the responder chain to the enclosing sidebar host view
/// (the NSView that hosts the SwiftUI sidebar inside the NSSplitView).
/// We override its `appearance` to `.darkAqua`, which AppKit propagates to
/// the sidebar material and built-in selection highlights without affecting
/// the rest of the window.
struct MacDarkSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AppearanceForcingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AppearanceForcingView)?.applyDarkAppearance()
    }

    private final class AppearanceForcingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyDarkAppearance()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyDarkAppearance()
        }

        func applyDarkAppearance() {
            let dark = NSAppearance(named: .darkAqua)
            // Walk up to the nearest NSHostingView (or any ancestor that
            // sits at the root of the sidebar split item) and force dark
            // appearance there. This catches the SwiftUI hosting view that
            // contains the entire sidebar List, so the background material
            // and List selection highlight both render in dark mode while
            // the rest of the window stays in the user's chosen scheme.
            var current: NSView? = self.superview
            while let view = current {
                let className = NSStringFromClass(type(of: view))
                // Stop BEFORE we hit the NSSplitView or window — we only
                // want to dark the sidebar's host subtree, not the whole
                // split view (which would dark the divider/detail too).
                if className.contains("NSSplitView") || className.contains("Window") {
                    break
                }
                view.appearance = dark
                current = view.superview
            }
        }
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @EnvironmentObject private var searchBarState: SearchBarState
    // Corrigido ciclo do AttributeGraph separando dependências reativas de SwiftData em @State com atualização manual para evitar travamentos no macOS.

    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsArray: [AppSettings]

    @State private var showAddGrocery = false
    @State private var showAddPantry = false
    @State private var showAddRecipe = false
    @State private var showImportRecipe = false
    @State private var pendingImportedRecipeID: UUID? = nil
    @State private var showRecipeAddOptions = false
    @State private var selectedCompatibleCategory: String? = nil
    @State private var editingExpiringItem: UnifiedItemSelection?

    @State private var recipeCategoriesState: [Category] = []
    @State private var compatibleMatchesState: [HomeRecipeMatch] = []
    @State private var expiringItemsState: [UnifiedItem] = []
    @State private var contentResetToken: Int = 0
    @State private var shortcutDeckWidth: CGFloat = 0

    private var settings: AppSettings? { settingsArray.first }
    
    let onSettingsTap: () -> Void
    let onOpenChat: () -> Void
    let onOpenRecipeIdeas: () -> Void
    let onOpenSearch: () -> Void
    let onOpenRecipeImport: (RecipeImportLaunchMode) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .home,
            header: { isInverted in
                PageHeader(title: "Savoria", isInverted: isInverted) {
                    #if !os(macOS)
                    SettingsButton(onTap: onSettingsTap)
                    #else
                    EmptyView()
                    #endif
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        actionDeck
                        PendingNutritionDaysCard()
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
        .sheet(isPresented: $showImportRecipe, onDismiss: {
            guard let recipeID = pendingImportedRecipeID else { return }
            pendingImportedRecipeID = nil
            Task { @MainActor in
                openRecipeInRecipesTab(recipeID)
            }
        }) {
            RecipeImportHostView { recipeID in
                pendingImportedRecipeID = recipeID
                showImportRecipe = false
            }
                .modelContainer(CloudSyncService.shared.container)
                .forceLightStatusBar()
        }
        .confirmationDialog("Adicionar receita", isPresented: $showRecipeAddOptions, titleVisibility: .visible) {
            Button("Importar receita") {
                showImportRecipe = true
            }
            Button("Criar do zero") {
                showAddRecipe = true
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("De onde vem essa receita?")
        }
        .sheet(item: $editingExpiringItem, onDismiss: { editingExpiringItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id)
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

    @ViewBuilder
    private var actionDeck: some View {
        #if os(macOS)
        macActionDeck
        #else
        iosActionDeck
        #endif
    }

    #if os(macOS)
    private var macActionDeck: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let width = geo.size.width
            let trailingColumnWidth = min(max(width * 0.36, 250), 330)
            let featuredHeight: CGFloat = 232
            let stackedHeight: CGFloat = (featuredHeight - spacing) / 2
            let quickTileHeight: CGFloat = 76

            VStack(alignment: .leading, spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    homeShortcutButton(
                        title: String(localized: "Assistente"),
                        subtitle: String(localized: "Adicione, busque ou pergunte..."),
                        imageName: "assistente",
                        style: .featured,
                        imageSize: 222,
                        imageOffset: CGSize(width: -2, height: 28)
                    ) {
                        onOpenSearch()
                    }
                    .frame(maxWidth: .infinity, minHeight: featuredHeight, maxHeight: featuredHeight)

                    VStack(spacing: spacing) {
                        homeShortcutButton(
                            title: String(localized: "Modo IA"),
                            subtitle: String(localized: "Inteligência"),
                            imageName: "modo ia",
                            style: .wide,
                            imageSize: 144,
                            imageOffset: CGSize(width: -12, height: 18),
                            imageAlignment: .bottomTrailing
                        ) {
                            onOpenChat()
                        }
                        .frame(height: stackedHeight)

                        homeShortcutButton(
                            title: String(localized: "Ideias"),
                            subtitle: String(localized: "de receitas"),
                            imageName: "ideis",
                            style: .wide,
                            imageSize: 126,
                            imageOffset: CGSize(width: -14, height: 14),
                            imageAlignment: .bottomTrailing
                        ) {
                            onOpenRecipeIdeas()
                        }
                        .frame(height: stackedHeight)
                    }
                    .frame(width: trailingColumnWidth)
                }

                HStack(alignment: .top, spacing: spacing) {
                    macShortcutAddTile(title: String(localized: "Despensa"), imageName: "despensa", imageSize: 64, tileHeight: quickTileHeight) {
                        showAddPantry = true
                    }

                    macShortcutAddTile(title: String(localized: "Mercado"), imageName: "mercado", imageSize: 78, tileHeight: quickTileHeight) {
                        showAddGrocery = true
                    }

                    macShortcutAddTileMenu(title: String(localized: "Adicionar Receita"), imageName: "receitas", imageSize: 68, tileHeight: quickTileHeight) {
                        recipeShortcutMenuContent
                    }

                    macShortcutAddTileMenu(title: String(localized: "Registrar Alimento"), imageName: "nutrientes", imageSize: 68, tileHeight: quickTileHeight) {
                        foodShortcutMenuContent
                    }
                }
                .frame(height: quickTileHeight + 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 338)
        .padding(.bottom, 12)
    }

    private func macShortcutAddTile(
        title: String,
        imageName: String,
        imageSize: CGFloat? = nil,
        tileHeight: CGFloat = 76,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            homeShortcutAddTile(imageName: imageName, imageSize: imageSize, action: action)
                .frame(maxWidth: .infinity)
                .frame(height: tileHeight)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func macShortcutAddTileMenu<Content: View>(
        title: String,
        imageName: String,
        imageSize: CGFloat? = nil,
        tileHeight: CGFloat = 76,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            homeShortcutAddTileMenu(imageName: imageName, imageSize: imageSize, content: content)
                .frame(maxWidth: .infinity)
                .frame(height: tileHeight)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
    #else
    private var iosActionDeck: some View {
        VStack(alignment: .leading, spacing: 14) {

        GeometryReader { geo in
            let spacing = homeShortcutSpacing
            let smallSide = homeShortcutSmallSide(for: geo.size.width)
            let topSide = smallSide * 2 + spacing

            VStack(spacing: spacing) {
                // Linha superior: Assistente (featured) + Modo IA / Receitas (wide)
                HStack(spacing: spacing) {
                    homeShortcutButton(
                        title: String(localized: "Assistente"),
                        subtitle: String(localized: "Adicione, busque ou pergunte..."),
                        imageName: "assistente",
                        style: .featured,
                        imageSize: 152,
                        imageOffset: CGSize(width: 28, height: 28)
                    ) {
                        onOpenSearch()
                    }
                    .frame(width: topSide, height: topSide)

                    VStack(spacing: spacing) {
                        homeShortcutButton(
                            title: String(localized: "Modo IA"),
                            subtitle: String(localized: "Inteligência"),
                            imageName: "modo ia",
                            style: .wide,
                            imageSize: 126,
                            imageOffset: CGSize(width: 80, height: 38)
                        ) {
                            onOpenChat()
                        }
                        .frame(height: smallSide)

                        homeShortcutButton(
                            title: String(localized: "Ideias"),
                            subtitle: String(localized: "de receitas"),
                            imageName: "ideis",
                            style: .wide,
                            imageSize: 99,
                            imageOffset: CGSize(width: 95, height: 22)
                        ) {
                            onOpenRecipeIdeas()
                        }
                        .frame(height: smallSide)
                    }
                    .frame(width: topSide, height: topSide)
                }

                // Linha inferior: 4 tiles compactos com label abaixo
                HStack(spacing: spacing) {
                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "despensa", imageSize: 58) {
                            showAddPantry = true
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Despensa"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "mercado", imageSize: 71) {
                            showAddGrocery = true
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Mercado"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTileMenu(imageName: "receitas", imageSize: 65) {
                            recipeShortcutMenuContent
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Adicionar Receita"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTileMenu(imageName: "nutrientes", imageSize: 66) {
                            foodShortcutMenuContent
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Registrar Alimento"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
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
    #endif

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            expiringSectionHeader
            expiringSectionList
        }
    }

    private var expiringSectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Text("Validades próximas")
                    .font(.headline.weight(.semibold))
                SectionInfoButton(
                    title: "Validades próximas",
                    message: "Itens da despensa cuja data de validade está chegando. Toque em um item para editá-lo. Ajuste o intervalo de antecipáção nas configurações."
                )
            }

            Spacer()

            Text("\(expiringItemsState.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.14), in: .capsule)
        }
    }

    private var expiringSectionList: some View {
        let visibleItems = Array(expiringItemsState.prefix(5))

        return VStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                expiringSectionRow(for: item)

                if index < visibleItems.count - 1 {
                    ItemListDivider()
                        .padding(.horizontal, 14)
                }
            }
        }
        .background(homeShortcutBackgroundColor, in: .rect(cornerRadius: 18))
    }

    private func expiringSectionRow(for item: UnifiedItem) -> some View {
        Button {
            editingExpiringItem = UnifiedItemSelection(id: item.id)
        } label: {
            HStack(spacing: 12) {
                IconImage(
                    name: item.name,
                    iconFileName: item.iconName,
                    fallbackSymbol: "clock.badge.exclamationmark",
                    size: 28,
                    showBalloon: true,
                    balloonColor: expiringItemBalloonColor
                )

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
                editingExpiringItem = UnifiedItemSelection(id: item.id)
            }
            Divider()
            Button("Excluir", systemImage: "trash", role: .destructive) {
                withAnimation {
                    modelContext.delete(item)
                }
            }
        }
    }

    private var expiringItemBalloonColor: Color {
        colorScheme == .dark
            ? Color(red: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x1A / 255.0)
            : .white
    }

    private var dessertShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text("Receitas sugeridas")
                        .font(.headline.weight(.semibold))
                    SectionInfoButton(
                        title: "Receitas sugeridas",
                        message: "Receitas compatíveis com o que você tem na despensa, priorizando o horário do dia. Ajuste o nível de compatibilidade nas configurações ou filtre por categoria abaixo."
                    )
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
                    label: {
                        Text("Sem receitas sugeridas")
                    },
                    description: {
                        Text("Ajuste o nível de compatibilidade nas configurações ou adicione mais itens à despensa.")
                    }
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(compatibleMatchesState.prefix(8)) { match in
                            Button {
                                openRecipeInRecipesTab(match.recipe.id)
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
                filterChip(label: String(localized: "Sugestões"), isSelected: selectedCompatibleCategory == nil) {
                    selectedCompatibleCategory = nil
                }

                ForEach(recipeCategoriesState) { category in
                    filterChip(label: category.localizedDisplayName, isSelected: selectedCompatibleCategory == category.name) {
                        selectedCompatibleCategory = category.name
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let backgroundColor: Color = {
            if colorScheme == .dark {
                return isSelected ? PageTheme.home.accentColor.opacity(0.16) : Color(.tertiarySystemBackground)
            }

            return isSelected
                ? Color(red: 1.0, green: 0.93, blue: 0.84)
                : Color.white
        }()

        let foregroundColor: Color = {
            if colorScheme == .dark {
                return isSelected ? PageTheme.home.accentColor : .primary
            }

            return isSelected
                ? Color(red: 0.53, green: 0.31, blue: 0.03)
                : Color(red: 0.42, green: 0.27, blue: 0.06)
        }()

        let borderColor: Color = {
            guard colorScheme == .light else { return .clear }
            return isSelected
                ? Color(red: 0.92, green: 0.76, blue: 0.52)
                : Color.black.opacity(0.06)
        }()

        return Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(backgroundColor, in: .capsule)
                .overlay {
                    Capsule()
                        .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
                }
                .foregroundStyle(foregroundColor)
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
        imageAlignment: Alignment? = nil,
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
                customOffset: imageOffset,
                customAlignment: imageAlignment
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
        customOffset: CGSize? = nil,
        customAlignment: Alignment? = nil
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

            case .compact:
                Color.clear
            }
        }
        .overlay(alignment: customAlignment ?? homeShortcutImageAlignment(for: style)) {
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
            homeShortcutTileLabel(imageName: imageName, imageSize: imageSize)
        }
        .buttonStyle(HomeShortcutButtonStyle())
    }

    private func homeShortcutAddTileMenu<Content: View>(
        imageName: String,
        imageSize: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            homeShortcutTileLabel(imageName: imageName, imageSize: imageSize)
        }
        .menuOrder(.fixed)
        .buttonStyle(HomeShortcutButtonStyle())
    }

    @ViewBuilder
    private func homeShortcutTileLabel(imageName: String, imageSize: CGFloat?) -> some View {
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

    @ViewBuilder
    private var recipeShortcutMenuContent: some View {
        Section("Receitas") {
            Button("Procurar receitas", systemImage: "magnifyingglass") {
                searchBarState.pageContext = .recipes
                // Reveal triggers ContentView.onChange(isVisible) which
                // switches to the assistant tab.
                searchBarState.reveal(mode: .idle)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    searchBarState.mode = .searching
                }
            }
            Button("Criar receita", systemImage: "square.and.pencil") {
                showAddRecipe = true
            }
        }
        Section("Importar receita") {
            Button("Colar link", systemImage: "link") {
                onOpenRecipeImport(.link)
            }
            Button("Importar da galeria", systemImage: "photo.on.rectangle.angled") {
                onOpenRecipeImport(.gallery)
            }
            Button("Ler com câmera", systemImage: "camera.viewfinder") {
                onOpenRecipeImport(.camera)
            }
            Button("Colar texto", systemImage: "text.alignleft") {
                onOpenRecipeImport(.text)
            }
            #if os(macOS)
            Button("Importar dos arquivos", systemImage: "folder.fill") {
                onOpenRecipeImport(.files)
            }
            #endif
        }
    }

    @ViewBuilder
    private var foodShortcutMenuContent: some View {
        Section("Registros Salvos") {
            Button("Salvar alimento", systemImage: "fork.knife") {
                searchBarState.pendingNutritionSheet = .manual()
            }
            Button("Alimentos salvos", systemImage: "clock.arrow.circlepath") {
                searchBarState.pendingNutritionSheet = .recents
            }
        }
        Section("Registros Manuais") {
            Button("Registrar manualmente", systemImage: "square.and.pencil") {
                searchBarState.pendingNutritionSheet = .manual()
            }
        }
        Section("Registrar por…") {
            Button("Rótulo", systemImage: "doc.text.viewfinder") {
                searchBarState.pendingNutritionSheet = .captureLabel
            }
            Button("Galeria", systemImage: "photo") {
                onOpenFoodGalleryDirect()
            }
            #if os(iOS)
            Button("Câmera", systemImage: "camera") {
                onOpenFoodCameraDirect()
            }
            #endif
            Button("Voz", systemImage: "waveform") {
                searchBarState.pendingNutritionSheet = .captureVoice
            }
            Button("Texto", systemImage: "character.cursor.ibeam") {
                searchBarState.pendingNutritionSheet = .captureText(prefillText: nil, autoAnalyze: false)
            }
        }
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

private let homeShortcutBackgroundColor = neutralSurfaceColor

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
                    Label(match.recipe.difficulty.displayName, systemImage: match.recipe.difficulty.icon)
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
            .background(appPrimaryBackground)
            .presentationBackground(appPrimaryBackground)
    }
}
extension View {
    func forceLightStatusBar() -> some View {
        self.modifier(ForceLightSheetModifier())
    }
}
#endif

// MARK: - Direct assistant-bar shortcuts modifier
// Presents camera / photos picker / link / text sheets directly at the root,
// so no intermediate host sheet ever appears between the tap and the action.

private struct DirectAssistantShortcutsModifier: ViewModifier {
    @Binding var directFoodCameraActive: Bool
    @Binding var directFoodGalleryActive: Bool
    @Binding var directFoodGalleryItem: PhotosPickerItem?
    @Binding var directFoodAnalysisImage: PlatformImage?
    @Binding var directFoodAnalysisLogDate: Date

    @Binding var directRecipeLinkActive: Bool
    @Binding var directRecipeTextActive: Bool
    @Binding var directRecipeGalleryActive: Bool
    @Binding var directRecipeGalleryItem: PhotosPickerItem?
    @Binding var directRecipeCameraActive: Bool

    let onRecipeImportedFromDirect: (UUID) -> Void
    let onRecipeSourceReady: (RecipeImportSource) -> Void

    func body(content: Content) -> some View {
        content
            // --- Food: camera (direct) ---
            #if os(iOS)
            .fullScreenCover(isPresented: $directFoodCameraActive) {
                FoodCameraPicker { image in
                    directFoodAnalysisImage = image
                }
                .ignoresSafeArea()
            }
            #endif
            // --- Food: gallery (direct) ---
            .photosPicker(isPresented: $directFoodGalleryActive,
                          selection: $directFoodGalleryItem,
                          matching: .images)
            .onChange(of: directFoodGalleryItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = PlatformImage(data: data) {
                        directFoodAnalysisImage = img
                    }
                    directFoodGalleryItem = nil
                }
            }
            // --- Food: analysis sheet (shows only after we have an image) ---
            .sheet(isPresented: Binding(
                get: { directFoodAnalysisImage != nil },
                set: { if !$0 { directFoodAnalysisImage = nil } }
            )) {
                if let image = directFoodAnalysisImage {
                    FoodCaptureHostView(mode: .photo,
                                        logDate: directFoodAnalysisLogDate,
                                        preloadedImage: image)
                        .forceLightStatusBar()
                }
            }
            // --- Recipe import: link (direct) ---
            .sheet(isPresented: $directRecipeLinkActive) {
                RecipeLinkInputSheet { url in
                    directRecipeLinkActive = false
                    onRecipeSourceReady(.url(url))
                }
                .forceLightStatusBar()
            }
            // --- Recipe import: text (direct) ---
            .sheet(isPresented: $directRecipeTextActive) {
                RecipeTextInputSheet { text in
                    directRecipeTextActive = false
                    onRecipeSourceReady(.text(text))
                }
                .forceLightStatusBar()
            }
            // --- Recipe import: gallery (direct) ---
            .photosPicker(isPresented: $directRecipeGalleryActive,
                          selection: $directRecipeGalleryItem,
                          matching: .images)
            .onChange(of: directRecipeGalleryItem) { _, newItem in
                guard let newItem else { return }
                Task { @MainActor in
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        onRecipeSourceReady(.image(data))
                    }
                    directRecipeGalleryItem = nil
                }
            }
            // --- Recipe import: camera (direct) ---
            #if os(iOS)
            .fullScreenCover(isPresented: $directRecipeCameraActive) {
                FoodCameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        onRecipeSourceReady(.image(data))
                    }
                }
                .ignoresSafeArea()
            }
            #endif
    }
}

