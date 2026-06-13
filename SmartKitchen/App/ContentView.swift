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
    case assistant
    case aiMode
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Savoria"
        case .lists: return String(localized: "Listas")
        case .recipes: return String(localized: "Receitas")
        case .nutrients: return String(localized: "Nutrição")
        case .assistant: return String(localized: "Assistente")
        case .aiMode: return String(localized: "SavorIA")
        case .settings: return String(localized: "Configurações")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .lists: return "list.bullet.clipboard"
        case .recipes: return "book"
        case .nutrients: return "fork.knife"
        case .assistant: return "sparkle.magnifyingglass"
        case .aiMode: return "sparkles"
        case .settings: return "gearshape"
        }
    }

}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
    // home view's "Pergunte à SavorIA" / "Ideias de receitas" / "Assistente"
    // shortcuts can both switch to the search tab AND push the AI page.
    @State private var assistantTabPath: [AssistantTabAIDestination] = []
    /// Tracks whether the on-screen keyboard is visible so we can hide the tab
    /// bar only while the user is actively typing. Driven by UIKit keyboard
    /// notifications on iOS.
    @State private var isKeyboardVisible: Bool = false
    @State private var suspendOffscreenTabs = false
    @State private var pendingOffscreenTabsResumeWork: DispatchWorkItem?
    @State private var didScheduleInitialOffscreenTabSuspension = false
    @State private var stagedTabPrewarmTask: Task<Void, Never>?
    @State private var didScheduleInitialTabPrewarm = false
    @State private var nextTabSwitchTraceID = 0
    @State private var pendingTabSwitchTrace: TabSwitchTrace?
    #if DEBUG
    @State private var didRunPerfAutoTabSwitch = false
    #endif
    /// Set of tabs that have ever been selected. We mount a tab on its first
    /// selection and keep it mounted afterwards. This avoids remounting all
    /// 4 offscreen tabs at once when the foreground-burst suspension window
    /// ends, which was causing a ~250ms main-thread hang from concurrent
    /// `@Query` subscriber setup. Permanent lazy-mount keeps the resume path
    /// cheap (only the active tab pays initial-fetch cost).
    @State private var mountedTabs: Set<AppTab> = [.assistant, .lists, .recipes, .nutrients]

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
    @State private var settingsSnapshot = ContentSettingsSnapshot()

    private let offscreenTabSuspensionDuration: TimeInterval = 8.0

    #if os(macOS)
    @State private var selectedSidebar: SidebarItem? = .home
    @State private var macBackgroundFromTheme: PageTheme = .home
    @State private var macBackgroundToTheme: PageTheme = .home
    @State private var macBackgroundTransitionProgress: Double = 1.0
    @FocusState private var macSearchFieldFocused: Bool
    @State private var macAssistantBarExpanded: Bool = false

    private var macActivePageTheme: PageTheme {
        switch selectedSidebar ?? .home {
        case .home: return .home
        case .lists: return .lists
        case .recipes: return .recipes
        case .nutrients: return .nutrients
        case .assistant, .aiMode: return .assistant
        case .settings: return .settings
        }
    }

    @ViewBuilder
    private var macSidebarDetailContent: some View {
        switch selectedSidebar ?? .home {
        case .home:
            NavigationStack {
                HomeView(
                    onSettingsTap: { selectedSidebar = .settings },
                    onOpenChat: {
                        openAIMode()
                        macSearchFieldFocused = true
                    },
                    onOpenRecipeIdeas: {
                        openAIMode(preset: .recipeIdeas)
                        macSearchFieldFocused = true
                    },
                    onOpenSearch: {
                        macSearchFieldFocused = true
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

        case .assistant:
            NavigationStack {
                MacAssistantExpandedPage(
                    mode: .assistant,
                    searchBarState: searchBarState,
                    searchService: searchService,
                    onAction: { handleCommandBarAction($0) },
                    onOpenFoodCameraDirect: openDirectFoodCamera,
                    onOpenFoodGalleryDirect: openDirectFoodGallery,
                    onRequestAIMode: { preset, prefill in
                        openAIMode(preset: preset, prefill: prefill)
                    },
                    pendingChatQuery: $pendingChatQuery,
                    pendingOpenChat: $pendingOpenChat,
                    pendingNewConversation: $pendingNewConversation,
                    pendingShowHistory: $pendingShowHistory
                )
            }
            .background(Color.clear)

        case .aiMode:
            NavigationStack {
                MacAssistantExpandedPage(
                    mode: .aiMode,
                    searchBarState: searchBarState,
                    searchService: searchService,
                    onAction: { handleCommandBarAction($0) },
                    onOpenFoodCameraDirect: openDirectFoodCamera,
                    onOpenFoodGalleryDirect: openDirectFoodGallery,
                    onRequestAIMode: nil,
                    pendingChatQuery: $pendingChatQuery,
                    pendingOpenChat: $pendingOpenChat,
                    pendingNewConversation: $pendingNewConversation,
                    pendingShowHistory: $pendingShowHistory
                )
            }
            .background(Color.clear)

        case .settings:
            NavigationStack { MacSettingsExpandedPage() }
                .background(Color.clear)
        }
    }
    #endif

    private var activePageTheme: PageTheme { selectedTab.pageTheme ?? lastContentTab.pageTheme ?? .home }

    /// Mirrors `AppSettings.hasCompletedOnboarding` into `showOnboarding` so
    /// the fullscreen cover binding stays in sync. Also runs the one-shot
    /// migration that auto-completes onboarding for installs that already
    /// have user data (so the new flow only shows up for fresh installs).
    private func syncOnboardingFlag() {
        guard let settings = fetchSettingsModel() else {
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

    private func fetchSettingsModel() -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func syncSettingsSnapshot() {
        let newSnapshot = ContentSettingsSnapshot(settings: fetchSettingsModel())
        guard settingsSnapshot != newSnapshot else { return }
        settingsSnapshot = newSnapshot
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
        searchBarState.mode == .aiChat ? String(localized: "SavorIA") : String(localized: "Assistente")
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
                    setSelectedTabWithoutAnimation(newValue)
                    return
                }

                if TabSwitchDiagnostics.isEnabled {
                    beginTabSwitch(to: newValue, source: "tabBar")
                }
                setSelectedTabWithoutAnimation(newValue)
            }
        )
    }

    private func setSelectedTabWithoutAnimation(_ tab: AppTab) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
    }

    var body: some View {
        let staged1 = applyBodyEnvironment(to: baseBodyView)
        let staged2 = applyPlatformNutritionPresentation(to: staged1)
        let staged3 = applyEditorAndImportSheets(to: staged2)
        return applyLifecycleAndGlobalPresentation(to: staged3)
    }

    private var baseBodyView: AnyView {
        AnyView(
            ZStack {
                bodyMainTabView

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
        )
    }

    private func applyBodyEnvironment(to content: AnyView) -> AnyView {
        AnyView(
            content
                .environmentObject(searchBarState)
                .environment(\.scrollToItem, scrollToItemRequest)
                .environment(\.openRecipeInRecipesTab, openRecipeInRecipesTab)
                .environment(\.backgroundTheme, displayedBgTheme)
                .environment(\.visiblePageTheme, activePageTheme)
                .environment(\.activeAppTab, selectedTab)
        )
    }

    private func applyPlatformNutritionPresentation(to content: AnyView) -> AnyView {
        #if os(iOS)
        return AnyView(
            content
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingFlowView {
                        showOnboarding = false
                    }
                    .interactiveDismissDisabled(true)
                }
                .fullScreenCover(item: fullscreenNutritionEntrySheetBinding, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) { sheet in
                    nutritionEntrySheetContent(for: sheet)
                }
                .sheet(item: sheetNutritionEntrySheetBinding, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) { sheet in
                    nutritionEntrySheetContent(for: sheet)
                }
        )
        #else
        return AnyView(
            content
                .sheet(item: $searchBarState.pendingNutritionSheet, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) { sheet in
                    nutritionEntrySheetContent(for: sheet)
                }
        )
        #endif
    }

    private func applyEditorAndImportSheets(to content: AnyView) -> AnyView {
        AnyView(
            content
                .sheet(isPresented: $showQuickRecipeImport, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                    handleQuickRecipeImportDismissed()
                }) {
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
                        RecipeImportLogger.info("direct shortcut -> RecipeImportInbox source \(RecipeImportLogger.sourceSummary(source))")
                        RecipeImportInbox.shared.pendingSource = source
                    }
                ))
                .sheet(isPresented: $showAddPantry, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
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
                .sheet(isPresented: $showAddGrocery, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
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
                .sheet(isPresented: $showAddRecipe, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
                    NavigationStack {
                        AddRecipeView()
                    }
                    .forceLightStatusBar()
                }
                .sheet(isPresented: $showAddUtensil, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
                    ItemDetailView(
                        mode: .create(destinations: [.utensil]),
                        onExistingItemRequested: { item in
                            openExistingItemFromCreateFlow(item)
                        }
                    )
                    .forceLightStatusBar()
                }
                .sheet(isPresented: $showAddItem, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
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
                .sheet(item: $searchEditItem, onDismiss: {
                    searchEditItem = nil
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) { selection in
                    ItemDetailContainerView(itemID: selection.id)
                        .forceLightStatusBar()
                }
                .sheet(isPresented: $showWeightTracker) {
                    NavigationStack {
                        WeightTrackerView()
                    }
                    .forceLightStatusBar()
                }
                .sheet(item: $searchEditRecipe, onDismiss: {
                    searchEditRecipe = nil
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) { selection in
                    NavigationStack {
                        EditRecipeContainerView(recipeID: selection.id)
                    }
                    .forceLightStatusBar()
                }
        )
    }

    private func applyLifecycleAndGlobalPresentation(to content: AnyView) -> AnyView {
        let tintedContent: AnyView = {
            #if os(macOS)
            return AnyView(content.tint(macActivePageTheme.accentColor))
            #else
            return AnyView(content.tint(activePageTheme.accentColor))
            #endif
        }()

        let base = AnyView(
            tintedContent
                .background(alignment: .topLeading) {
                    ContentSettingsObserver(snapshot: $settingsSnapshot)
                        .allowsHitTesting(false)
                }
                .environment(\.scrollToTopTrigger, scrollToTopTrigger)
                .environment(\.suspendActiveTabDataSubscriptions, suspendOffscreenTabs)
                .environment(\.presentAppSettings) {
                    showSettings = true
                }
                .preferredColorScheme(settingsSnapshot.appearanceMode.colorScheme)
                .sheet(isPresented: $showSettings, onDismiss: {
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                }) {
                    NavigationStack {
                        SettingsView()
                    }
                    .forceLightStatusBar()
                }
                .onAppear {
                    syncOnboardingFlag()
                    scheduleInitialTabPrewarmIfNeeded()
                }
                .onDisappear {
                    stagedTabPrewarmTask?.cancel()
                    stagedTabPrewarmTask = nil
                }
                .onChange(of: settingsSnapshot.hasCompletedOnboarding) { _, _ in
                    syncOnboardingFlag()
                }
                .onReceive(NotificationCenter.default.publisher(for: .appearanceModeChanged)) { _ in
                    #if os(iOS)
                    syncSettingsSnapshot()
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .openAssistantFromWidget)) { _ in
                    #if os(iOS)
                    openAssistantTab()
                    #else
                    searchBarState.reveal(mode: .idle)
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: .openAIChatFromWidget)) { _ in
                    openAIMode()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openNutritionAtDate)) { _ in
                    if selectedTab != .nutrients { selectedTab = .nutrients }
                }
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
                    NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                    Task { @MainActor in
                        openRecipeInRecipesTab(recipeID)
                    }
                }
                .onChange(of: selectedTab) { _, newValue in
                    handleTabSelectionChange(newValue)
                }
                #if DEBUG
                .task {
                    await runPerfAutoTabSwitchIfRequested()
                }
                #endif
        )

        #if os(iOS)
        return AnyView(base.forceLightStatusBar())
        #else
        return base
        #endif
    }

    private var bodyMainTabView: AnyView {
        #if os(macOS)
        AnyView(
            mainTabView
                .allowsHitTesting(!showOnboarding)
        )
        #else
        AnyView(mainTabView)
        #endif
    }

    private var mainTabView: AnyView {
        #if os(macOS)
        AnyView(macSidebarView)
        #else
        AnyView(nativeTabView)
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var iosAppBackground: some View {
        // Same strategy as macOS: keep the heavy SceneKit-backed shader
        // surfaces mounted and switch by opacity. Recreating these views on
        // each tab selection was showing up as main-thread hitches.
        ZStack {
            Color.black
            ForEach([PageTheme.home, .lists, .recipes, .nutrients], id: \.self) { theme in
                ThemedBackgroundView(
                    theme: theme,
                    selection: BackgroundManager.shared.background(for: theme),
                    progress: 1.0
                )
                .opacity(theme == displayedBgTheme ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
    #endif

    private var nativeTabView: some View {
        ZStack {
            iosAppBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)

            TabView(selection: tabSelectionBinding) {
                Tab(value: AppTab.assistant) {
                    Group {
                        if shouldMountTab(.assistant) {
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
                            .toolbar(.hidden, for: .navigationBar)
                        } else {
                            inactiveTabPlaceholder
                        }
                    }
                    .background {
                        TabActivationProbe(
                            tab: .assistant,
                            selectedTab: selectedTab,
                            trace: pendingTabSwitchTrace
                        )
                    }
                } label: {
                    Label("Savoria", systemImage: AppTab.assistant.icon)
                }

                Tab(value: AppTab.lists) {
                    Group {
                        if shouldMountTab(.lists) {
                            NavigationStack {
                                ListsTabView()
                            }
                            .toolbar(.hidden, for: .navigationBar)
                        } else {
                            inactiveTabPlaceholder
                        }
                    }
                    .background {
                        TabActivationProbe(
                            tab: .lists,
                            selectedTab: selectedTab,
                            trace: pendingTabSwitchTrace
                        )
                    }
                } label: {
                    Label("Listas", systemImage: AppTab.lists.icon)
                }

                Tab(value: AppTab.recipes) {
                    Group {
                        if shouldMountTab(.recipes) {
                            NavigationStack(path: $recipeNavigationPath) {
                                RecipesView()
                            }
                            .toolbar(.hidden, for: .navigationBar)
                        } else {
                            inactiveTabPlaceholder
                        }
                    }
                    .background {
                        TabActivationProbe(
                            tab: .recipes,
                            selectedTab: selectedTab,
                            trace: pendingTabSwitchTrace
                        )
                    }
                } label: {
                    Label("Receitas", systemImage: AppTab.recipes.icon)
                }

                Tab(value: AppTab.nutrients) {
                    Group {
                        if shouldMountTab(.nutrients) {
                            NavigationStack {
                                NutrientsView()
                            }
                            .toolbar(.hidden, for: .navigationBar)
                        } else {
                            inactiveTabPlaceholder
                        }
                    }
                    .background {
                        TabActivationProbe(
                            tab: .nutrients,
                            selectedTab: selectedTab,
                            trace: pendingTabSwitchTrace
                        )
                    }
                } label: {
                    Label("Nutrição", systemImage: AppTab.nutrients.icon)
                }

                Tab(value: AppTab.commandBar, role: .search) {
                    Group {
                        if shouldMountTab(.commandBar) {
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
                        } else {
                            inactiveTabPlaceholder
                        }
                    }
                    .background {
                        TabActivationProbe(
                            tab: .commandBar,
                            selectedTab: selectedTab,
                            trace: pendingTabSwitchTrace
                        )
                    }
                } label: {
                    Label("Buscar", systemImage: AppTab.commandBar.icon)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .environment(\.usesGlobalPageBackground, true)
            #if os(iOS)
            // Hide the tab bar only while the keyboard is up; otherwise the
            // assistant bar always shows alongside the tab bar.
            .toolbar(isKeyboardVisible ? .hidden : .visible, for: .tabBar)
            #endif
            .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
                guard searchBarState.mode != .aiChat else { return }
                searchService.search(query: newValue, context: modelContext, showUtensils: settingsSnapshot.showUtensils)
            }
            .environment(\.searchOverlay, searchOverlayView)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            persistentAssistantBar
        }
        #if os(iOS)
        .task {
            guard !didScheduleInitialOffscreenTabSuspension else { return }
            didScheduleInitialOffscreenTabSuspension = true
            suspendOffscreenTabsTemporarily(reason: "initialLaunch")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            suspendOffscreenTabsTemporarily(reason: "willEnterForeground")
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }
        #endif
        .onChange(of: searchBarState.isVisible) { _, newValue in
            // Tapping the persistent assistant bar from any tab focuses it; in
            // that case we always switch to the assistant (search) tab so the
            // user sees the assistant content above the bar.
            if newValue && selectedTab != .commandBar {
                selectedTab = .commandBar
            }
        }
    }

    // MARK: - Persistent Search Bar

    @ViewBuilder
    private var inactiveTabPlaceholder: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shouldMountTab(_ tab: AppTab) -> Bool {
        // Permanent lazy mount: a tab is mounted only on its first selection
        // and stays mounted afterwards. We deliberately do NOT unmount on
        // foreground-burst suspension, because mass-remount when the window
        // ends produced a ~250ms main-thread hang from concurrent `@Query`
        // subscriber setup. Per-view heavy observers are quieted via the
        // `suspendActiveTabDataSubscriptions` environment instead.
        mountedTabs.contains(tab) || selectedTab == tab
    }

    private func suspendOffscreenTabsTemporarily(reason: String) {
        pendingOffscreenTabsResumeWork?.cancel()

        if !suspendOffscreenTabs {
            suspendOffscreenTabs = true
            PerformanceLogger.event(
                .scenePhase,
                "offscreen tab suspension enabled",
                metadata: "reason=\(reason), durationMs=\(Int(offscreenTabSuspensionDuration * 1_000.0))"
            )
        } else {
            PerformanceLogger.event(
                .scenePhase,
                "offscreen tab suspension extended",
                metadata: "reason=\(reason), durationMs=\(Int(offscreenTabSuspensionDuration * 1_000.0))"
            )
        }

        let workItem = DispatchWorkItem {
            suspendOffscreenTabs = false
            pendingOffscreenTabsResumeWork = nil
            PerformanceLogger.event(.scenePhase, "offscreen tab suspension ended")
        }
        pendingOffscreenTabsResumeWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + offscreenTabSuspensionDuration, execute: workItem)
    }

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
            .padding(.bottom, isKeyboardVisible ? 0 : 45)
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
        // When the dedicated assistant/search tab is active, that tab already
        // hosts its own InlineSearchResultsView. Returning a second overlay
        // here mounts a hidden duplicate listener that can consume AI send
        // events before the visible chat receives them.
        guard selectedTab != .commandBar else { return nil }
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
        searchBarState.requestAINewConversation(source: "ContentView.startNewConversation")
    }

    private func showConversationHistory() {
        searchBarState.requestAIHistory(source: "ContentView.showConversationHistory")
    }

    #if os(macOS)
    /// Returns the `PageTheme` whose pre-defined accent colors should drive
    /// the selection pill for a given sidebar item. These constants live in
    /// `PageTheme.accentColor` / `PageTheme.secondaryAccentColor` and were
    /// chosen to match the per-page shader tints — they are NOT sampled from
    /// the shader at runtime.
    private func macSidebarTheme(for item: SidebarItem) -> PageTheme? {
        switch item {
        case .home: return .home
        case .lists: return .lists
        case .recipes: return .recipes
        case .nutrients: return .nutrients
        case .assistant, .aiMode: return .assistant
        case .settings: return .settings
        }
    }

    @ViewBuilder
    private func macSidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = (selectedSidebar ?? .home) == item
        let theme = macSidebarTheme(for: item)
        Button {
            if selectedSidebar != item {
                selectedSidebar = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.86))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(macSidebarSelectionFill(for: theme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                        .shadow(color: (theme?.accentColor ?? Color.white).opacity(0.28), radius: 6, x: 0, y: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Pre-computed selection fill per page. Uses `PageTheme.accentColor` /
    /// `secondaryAccentColor` so the active row visually matches the page's
    /// shader without sampling the shader.
    private func macSidebarSelectionFill(for theme: PageTheme?) -> LinearGradient {
        guard let theme else {
            return LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                theme.secondaryAccentColor.opacity(0.88),
                theme.accentColor.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func macSidebarSection(_ title: LocalizedStringKey, items: [SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            ForEach(items) { item in
                macSidebarRow(item)
            }
        }
    }

    /// A non-selectable row used for assistant shortcuts that fire a
    /// `CommandBarAction` / open a sheet, rather than navigating to a page.
    /// Visual style matches `macSidebarRow` (transparent background, white
    /// label) with a small colored dot on the right indicating the page the
    /// action belongs to.
    @ViewBuilder
    private func macSidebarActionRow(
        title: String,
        systemImage: String,
        tint: PageTheme,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.white.opacity(0.86))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(tint.accentColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var macSidebarAssistantShortcuts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Atalhos")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // IA — accent .home
            macSidebarActionRow(title: String(localized: "Pergunte à SavorIA"),
                                systemImage: "sparkles", tint: .home) {
                openAIMode(preset: .nutritionCoach)
            }
            macSidebarActionRow(title: String(localized: "Ideias de receitas"),
                                systemImage: "fork.knife.circle.fill", tint: .home) {
                openAIMode(preset: .recipeIdeas)
            }

            // Listas — accent .lists
            macSidebarActionRow(title: String(localized: "Adicionar à Despensa"),
                                systemImage: "shippingbox.fill", tint: .lists) {
                handleCommandBarAction(.addPantryItem(prefill: ""))
            }
            macSidebarActionRow(title: String(localized: "Adicionar ao Mercado"),
                                systemImage: "cart.badge.plus", tint: .lists) {
                handleCommandBarAction(.addGroceryItem(prefill: ""))
            }
            if settingsSnapshot.showUtensils {
                macSidebarActionRow(title: String(localized: "Adicionar Utensílio"),
                                    systemImage: "fork.knife", tint: .lists) {
                    handleCommandBarAction(.addUtensil(prefill: ""))
                }
            }

            // Receitas — accent .recipes
            macSidebarActionRow(title: String(localized: "Criar Receita"),
                                systemImage: "book.badge.plus", tint: .recipes) {
                handleCommandBarAction(.addRecipe(prefill: ""))
            }
            macSidebarActionRow(title: String(localized: "Importar da Galeria"),
                                systemImage: "photo.on.rectangle.angled", tint: .recipes) {
                openQuickRecipeImport(.gallery)
            }
            macSidebarActionRow(title: String(localized: "Ler Receita"),
                                systemImage: "camera.viewfinder", tint: .recipes) {
                openQuickRecipeImport(.camera)
            }
            macSidebarActionRow(title: String(localized: "Importar dos Arquivos"),
                                systemImage: "folder.fill", tint: .recipes) {
                openQuickRecipeImport(.files)
            }

            // Nutrição — accent .nutrients
            macSidebarActionRow(title: String(localized: "Registrar Alimento"),
                                systemImage: "fork.knife.circle.fill", tint: .nutrients) {
                searchBarState.pendingNutritionSheet = .captureText(prefillText: nil, autoAnalyze: false)
            }
            macSidebarActionRow(title: String(localized: "Registrar com Áudio"),
                                systemImage: "mic.fill", tint: .nutrients) {
                searchBarState.pendingNutritionSheet = .captureVoice
            }
            macSidebarActionRow(title: String(localized: "Registrar com Galeria"),
                                systemImage: "photo.on.rectangle.angled", tint: .nutrients) {
                openDirectFoodGallery()
            }
            macSidebarActionRow(title: String(localized: "Rastreio de Peso"),
                                systemImage: "scalemass.fill", tint: .nutrients) {
                handleCommandBarAction(.openWeightTracker)
            }
        }
    }

    private var macSidebarView: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    macSidebarSection("Navegação", items: [.home, .lists, .recipes, .nutrients])
                    macSidebarSection("Assistente", items: [.assistant, .aiMode])
                    macSidebarAssistantShortcuts
                    macSidebarSection("Preferências", items: [.settings])
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(MacDarkSidebarBackground().ignoresSafeArea())
            .navigationTitle("")
            .environment(\.colorScheme, .dark)
            .safeAreaInset(edge: .bottom) {
                // Sidebar shows a button-styled trigger that looks like a
                // search bar. The real TextField lives in the floating bar
                // mounted in the detail pane (single instance) so that
                // typing never causes the TextField to be re-created / lose
                // first responder.
                Group {
                    if macAssistantBarFloating {
                        Color.clear.frame(height: 0)
                    } else {
                        macAssistantBarTrigger
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        expandAssistantBar()
                    } label: {
                        Label("Buscar", systemImage: "sparkle.magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        } detail: {
            ZStack(alignment: .bottom) {
                macSidebarDetailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating assistant bar — always mounted so the TextField
                // keeps its identity (and focus) across docked ↔ floating
                // transitions. Visibility / position is animated via opacity
                // and an offset so SwiftUI never tears down the field.
                macAssistantBar(floating: true)
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .opacity(macAssistantBarFloating ? 1 : 0)
                    .offset(y: macAssistantBarFloating ? 0 : 30)
                    .allowsHitTesting(macAssistantBarFloating)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: macAssistantBarFloating)
        }
        .onChange(of: searchBarState.debouncedSearchText) { _, newValue in
            guard searchBarState.mode != .aiChat else { return }
            searchService.search(query: newValue, context: modelContext, showUtensils: settingsSnapshot.showUtensils)
        }
        // When the user starts typing in the floating assistant bar, route
        // them to the dedicated Assistente sidebar page (or SavorIA when in
        // AI chat mode) instead of stacking the legacy modal overlay on top
        // of whatever page they were on.
        .onChange(of: searchBarState.searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let target: SidebarItem = searchBarState.mode == .aiChat ? .aiMode : .assistant
            if selectedSidebar != target {
                // Mark the bar as expanded so navigating doesn't collapse it,
                // then move to the assistant page. Focus stays on the
                // (always-mounted) floating TextField.
                macAssistantBarExpanded = true
                selectedSidebar = target
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .focusedSceneValue(\.openCommandBarAction, { searchBarState.reveal(mode: .idle) })
        .background {
            macAppBackground
                .ignoresSafeArea()
        }
        .onAppear {
            // All themed backgrounds are mounted simultaneously in
            // `macAppBackground` and gated by opacity — there is no longer a
            // from/to crossfade, so we just sync the published theme.
            macBackgroundFromTheme = macActivePageTheme
            macBackgroundToTheme = macActivePageTheme
            macBackgroundTransitionProgress = 1.0
            displayedBgTheme = macActivePageTheme
        }
        .onChange(of: selectedSidebar) { _, newValue in
            let newTheme: PageTheme = {
                switch newValue ?? .home {
                case .home: return .home
                case .lists: return .lists
                case .recipes: return .recipes
                case .nutrients: return .nutrients
                case .assistant, .aiMode: return .assistant
                case .settings: return .settings
                }
            }()
            // Instant page switch: just publish the new active theme. The
            // background ZStack toggles opacity between pre-mounted shader
            // layers, so there is no SCNView re-instantiation flash.
            if newTheme != displayedBgTheme {
                displayedBgTheme = newTheme
            }
            macBackgroundToTheme = newTheme
            macBackgroundFromTheme = newTheme

            // When the user navigates away from the SavorIA page, collapse
            // the legacy assistant bar back into idle so the previous chat
            // doesn't keep showing as a floating modal over the new page.
            // The AI conversation itself is preserved by the dedicated
            // `SavorIA` page and resumes when the user returns to it.
            if newValue != .aiMode && newValue != .assistant {
                if searchBarState.mode == .aiChat {
                    searchBarState.mode = .idle
                }
                searchBarState.searchText = ""
                searchBarState.debouncedSearchText = ""
                macAssistantBarExpanded = false
                macSearchFieldFocused = false
            } else if newValue == .aiMode {
                if searchBarState.mode != .aiChat {
                    searchBarState.mode = .aiChat
                }
            } else if newValue == .assistant {
                if searchBarState.mode == .aiChat {
                    searchBarState.mode = .idle
                }
            }

            if (newValue ?? .home) == .home {
                NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
            }
        }
    }

    private var macHasSearchContent: Bool {
        // Retained as a no-op to avoid touching unrelated call sites — the
        // legacy modal search overlay was removed from the macOS layout; the
        // dedicated Assistente / SavorIA sidebar pages now host the assistant
        // chrome and search results directly.
        false
    }

    /// Whether the assistant bar should render as a floating panel anchored
    /// over the detail pane (rather than docked at the bottom of the sidebar).
    /// Expansion is driven by an explicit user gesture (tap to expand /
    /// chevron to collapse) so that clicking the bar always expands it,
    /// even before the user starts typing.
    private var macAssistantBarFloating: Bool {
        if macAssistantBarExpanded { return true }
        if macSearchFieldFocused { return true }
        if !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    /// Expand the floating assistant bar and put focus into the (always
    /// mounted) TextField. Used by the docked trigger, ⌘K toolbar button, and
    /// programmatic call sites.
    private func expandAssistantBar() {
        macAssistantBarExpanded = true
        // Run on the next runloop tick so the floating bar's opacity / offset
        // state has settled before we ask AppKit to make its TextField the
        // first responder.
        DispatchQueue.main.async {
            macSearchFieldFocused = true
        }
    }

    /// The "docked" representation in the sidebar. It is a plain button
    /// styled like a search field — it does NOT contain a TextField, so the
    /// real TextField (in the floating bar) keeps its first-responder state
    /// when the user starts typing.
    @ViewBuilder
    private var macAssistantBarTrigger: some View {
        Button {
            expandAssistantBar()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("Adicione, busque, ou pergunte…")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("⌘K")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func macAssistantBar(floating: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: searchBarState.mode == .aiChat ? "paperplane.fill" : "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
            ZStack(alignment: .leading) {
                // Manual placeholder — SwiftUI's `TextField(prompt:)` does
                // not honor a custom foreground color on macOS, so we paint
                // the placeholder ourselves while the field is empty.
                if searchBarState.searchText.isEmpty {
                    Text(
                        searchBarState.mode == .aiChat
                            ? searchBarState.aiChatPreset.searchPlaceholder
                            : String(localized: "Adicione, busque, ou pergunte…")
                    )
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .allowsHitTesting(false)
                }
                TextField("", text: $searchBarState.searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Color.white)
                    .tint(Color.white)
                    .focused($macSearchFieldFocused)
                    .onSubmit {
                        let trimmed = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if searchBarState.mode == .aiChat {
                            searchBarState.requestAIChatSend(trimmed, source: "ContentView.macSidebarSubmit")
                            searchBarState.searchText = ""
                        } else {
                            submitSearchAction()
                        }
                    }
            }

            if !searchBarState.searchText.isEmpty {
                Button {
                    searchBarState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Button {
                // Snap back into the sidebar: defocus, clear text, and
                // collapse. (SavorIA conversation state lives in the
                // dedicated `SavorIA` page and is unaffected.)
                macSearchFieldFocused = false
                searchBarState.searchText = ""
                searchBarState.debouncedSearchText = ""
                if searchBarState.mode == .aiChat {
                    searchBarState.mode = .idle
                }
                macAssistantBarExpanded = false
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
                .environment(\.colorScheme, .dark)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var macSearchResultsOverlay: some View {
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
                            searchBarState.requestAINewConversation(source: "legacy iOS search overlay")
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                            searchBarState.requestAIHistory(source: "legacy iOS search overlay")
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
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(16)
    }

    @ViewBuilder
    private var macAppBackground: some View {
        // Mount one themed background per page simultaneously and gate them
        // by opacity. Each `ThemedBackgroundView` owns its own SCNView; by
        // keeping all four mounted we never re-instantiate the Metal/SceneKit
        // view on page switch, which previously caused a visible flash on the
        // first frame after a sidebar selection change.
        ZStack {
            Color.black
            ForEach(PageTheme.allCases, id: \.self) { theme in
                macThemedBackground(for: theme)
                    .opacity(theme == macActivePageTheme ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func macThemedBackground(for theme: PageTheme) -> some View {
        ThemedBackgroundView(
            theme: theme,
            selection: BackgroundManager.shared.background(for: theme),
            progress: 1.0
        )
    }

    #endif

    private func handleTabSelectionChange(_ newValue: AppTab) {
        lastContentTab = newValue
        mountedTabs.insert(newValue)

        if TabSwitchDiagnostics.isEnabled,
           let trace = pendingTabSwitchTrace,
           trace.target == newValue {
            let elapsed = PerformanceLogger.monotonicMillisSinceLaunch() - trace.startedAtMs
            PerformanceLogger.event(
                .tabSwitch,
                "state committed",
                metadata: String(format: "trace=%d from=%@ target=%@ mountedBefore=%@ elapsedMs=%.1f",
                                 trace.id,
                                 trace.from.rawValue,
                                 trace.target.rawValue,
                                 trace.wasMounted.description,
                                 elapsed)
            )
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if pendingTabSwitchTrace?.id == trace.id {
                    pendingTabSwitchTrace = nil
                }
            }
        }

        // When leaving the assistant tab to a content tab, defocus the search
        // field (hides keyboard) but DO NOT call `searchBarState.dismiss()` —
        // the AI page navigation state inside the assistant tab must survive
        // tab switches so the user can come back to where they were.
        if newValue != .commandBar && searchBarState.isVisible {
            searchBarState.resignFocus()
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

        if newValue == .assistant {
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }
    }

    private func beginTabSwitch(to newValue: AppTab, source: String) {
        guard newValue != selectedTab else { return }

        nextTabSwitchTraceID += 1
        let trace = TabSwitchTrace(
            id: nextTabSwitchTraceID,
            from: selectedTab,
            target: newValue,
            startedAtMs: PerformanceLogger.monotonicMillisSinceLaunch(),
            wasMounted: mountedTabs.contains(newValue)
        )
        pendingTabSwitchTrace = trace
        PerformanceLogger.event(
            .tabSwitch,
            "begin",
            metadata: "trace=\(trace.id) source=\(source) from=\(trace.from.rawValue) target=\(trace.target.rawValue) mountedBefore=\(trace.wasMounted)"
        )
    }

    private func scheduleInitialTabPrewarmIfNeeded() {
        guard !didScheduleInitialTabPrewarm else { return }
        didScheduleInitialTabPrewarm = true
        scheduleStagedTabPrewarm(reason: "initialContentView")
    }

    private func scheduleStagedTabPrewarm(reason: String) {
        #if os(iOS)
        stagedTabPrewarmTask?.cancel()
        let tabs: [AppTab] = [.lists, .recipes, .nutrients, .commandBar]
        stagedTabPrewarmTask = Task { @MainActor in
            if TabSwitchDiagnostics.isEnabled {
                PerformanceLogger.event(
                    .tabSwitch,
                    "prewarm scheduled",
                    metadata: "reason=\(reason) tabs=\(tabs.map(\.rawValue).joined(separator: ","))"
                )
            }
            try? await Task.sleep(for: .milliseconds(1800))

            for tab in tabs {
                guard !Task.isCancelled else { return }
                if !mountedTabs.contains(tab) {
                    let start = PerformanceLogger.monotonicMillisSinceLaunch()
                    mountedTabs.insert(tab)
                    if TabSwitchDiagnostics.isEnabled {
                        PerformanceLogger.event(
                            .tabSwitch,
                            "prewarm mount requested",
                            metadata: "reason=\(reason) tab=\(tab.rawValue)"
                        )
                        DispatchQueue.main.async {
                            let elapsed = PerformanceLogger.monotonicMillisSinceLaunch() - start
                            PerformanceLogger.event(
                                .tabSwitch,
                                "prewarm mount next runloop",
                                metadata: String(format: "reason=%@ tab=%@ elapsedMs=%.1f",
                                                 reason,
                                                 tab.rawValue,
                                                 elapsed)
                            )
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(350))
            }

            if TabSwitchDiagnostics.isEnabled {
                PerformanceLogger.event(.tabSwitch, "prewarm finished", metadata: "reason=\(reason)")
            }
            stagedTabPrewarmTask = nil
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private func runPerfAutoTabSwitchIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-PerfAutoTabSwitch"),
              !didRunPerfAutoTabSwitch else {
            return
        }

        didRunPerfAutoTabSwitch = true
        let sequence: [AppTab] = [
            .lists,
            .recipes,
            .nutrients,
            .commandBar,
            .assistant,
            .lists,
            .recipes,
            .nutrients,
            .commandBar,
            .assistant
        ]

        PerformanceLogger.event(.tabSwitch, "auto sequence scheduled", metadata: "count=\(sequence.count)")
        try? await Task.sleep(for: .milliseconds(3800))

        for tab in sequence {
            guard !Task.isCancelled else { return }
            if tab != selectedTab {
                beginTabSwitch(to: tab, source: "autorun")
                selectedTab = tab
            }
            try? await Task.sleep(for: .milliseconds(700))
        }

        PerformanceLogger.event(.tabSwitch, "auto sequence finished")
    }
    #endif

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
        case .addCatalogItemToGrocery(let name, let iconFileName, let category):
            addCatalogItemToGrocery(name: name, iconFileName: iconFileName, category: category)
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
        #if os(macOS)
        // On macOS the assistant lives as a dedicated sidebar page now —
        // jump to it directly and bypass the legacy floating overlay.
        searchBarState.searchText = ""
        searchBarState.debouncedSearchText = ""
        searchBarState.mode = .aiChat
        if let prefill, !prefill.isEmpty {
            pendingChatQuery = prefill
            pendingOpenChat = true
        }
        if selectedSidebar != .aiMode {
            selectedSidebar = .aiMode
        }
        #else
        // Switch to the assistant (search) tab and push the AI page. The page
        // itself sets `searchBarState.mode = .aiChat` and routes the prefill
        // through `pendingChatQuery` / `pendingOpenChat` on appear.
        openAssistantTab(push: AssistantTabAIDestination(preset: preset, prefill: prefill))
        #endif
    }

    /// Switches the active tab to the assistant (search) tab. If `push` is
    /// provided, also pushes the corresponding AI page on top of the tab's
    /// navigation stack. Use `openAssistantTab()` (no argument) to land on
    /// the idle assistant page (action grid / search results).
    private func openAssistantTab(push destination: AssistantTabAIDestination? = nil) {
        #if os(macOS)
        if let destination, destination.preset != .nutritionCoach || destination.prefill != nil {
            searchBarState.mode = .aiChat
            if let prefill = destination.prefill, !prefill.isEmpty {
                pendingChatQuery = prefill
                pendingOpenChat = true
            }
            if selectedSidebar != .aiMode {
                selectedSidebar = .aiMode
            }
        } else {
            searchBarState.mode = .idle
            if selectedSidebar != .assistant {
                selectedSidebar = .assistant
            }
        }
        #else
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
        #endif
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
            if let suggestion = searchService.suggestions.first ?? ItemDatabase.shared.search(query: trimmedQuery, limit: 1).first {
                handleCommandBarAction(.addCatalogItemToGrocery(
                    name: suggestion.preferredTitle(matching: trimmedQuery),
                    iconFileName: suggestion.nomeDoArquivo,
                    category: suggestion.categoria
                ))
                return
            }

            // Default: open AddItemView with destination picker
            handleCommandBarAction(.addItem(prefill: trimmedQuery, iconFileName: nil, category: nil))
        }
    }

    private func addCatalogItemToGrocery(name: String, iconFileName: String?, category: String?) {
        let traceID = UUID().uuidString
        let start = DispatchTime.now()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var descriptor = FetchDescriptor<UnifiedItem>()
        descriptor.includePendingChanges = true
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        let nextGrocerySortOrder = ((allItems.filter { $0.isGrocery }.map(\.grocerySortOrder).max()) ?? -1) + 1
        let resolvedCategory = category.flatMap { CategoryDatabase.shared.entry(for: $0) == nil ? nil : $0 } ?? "Outros"

        let item: UnifiedItem
        let didCreate: Bool
        if let existing = UnifiedItem.existingItem(named: trimmed, in: allItems) {
            item = existing
            didCreate = false
            if !item.isGrocery {
                item.isGrocery = true
                item.isChecked = false
                item.grocerySortOrder = nextGrocerySortOrder
            }
            if item.iconName == nil {
                item.iconName = iconFileName
            }
            if item.category == "Outros", resolvedCategory != "Outros" {
                item.category = resolvedCategory
            }
        } else {
            item = UnifiedItem(
                name: trimmed,
                category: resolvedCategory,
                iconName: iconFileName,
                isGrocery: true,
                grocerySortOrder: nextGrocerySortOrder
            )
            modelContext.insert(item)
            didCreate = true
        }

        scrollToItemRequest = ScrollToItemRequest(itemID: item.id, type: "groceryItem")
        selectedTab = .lists
        searchService.clear()
        NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000.0
        PerformanceLogger.event(
            .assistant,
            "catalog item added to grocery",
            metadata: "flow=assistantAdd traceID=\(traceID) itemID=\(item.id) created=\(didCreate) tookMs=\(String(format: "%.1f", elapsedMs))"
        )
    }

    private func refreshSearchAfterMove() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            searchService.search(query: searchBarState.searchText, context: modelContext, showUtensils: settingsSnapshot.showUtensils)
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

private struct ContentSettingsSnapshot: Equatable {
    var appearanceMode: AppearanceMode = .system
    var hasCompletedOnboarding = true
    var showUtensils = false

    init(settings: AppSettings? = nil) {
        appearanceMode = settings?.appearanceMode ?? .system
        hasCompletedOnboarding = settings?.hasCompletedOnboarding ?? true
        showUtensils = settings?.showUtensils == true
    }
}

private struct TabSwitchTrace: Equatable {
    let id: Int
    let from: AppTab
    let target: AppTab
    let startedAtMs: Double
    let wasMounted: Bool
}

private enum TabSwitchDiagnostics {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-PerfAutoTabSwitch")
}

private struct TabActivationProbe: View {
    let tab: AppTab
    let selectedTab: AppTab
    let trace: TabSwitchTrace?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                logActivation(stage: "appear")
            }
            .onChange(of: selectedTab) { _, newValue in
                guard newValue == tab else { return }
                logActivation(stage: "selectionChange")
            }
    }

    private func logActivation(stage: String) {
        guard TabSwitchDiagnostics.isEnabled,
              selectedTab == tab,
              let trace,
              trace.target == tab else {
            return
        }

        let elapsed = PerformanceLogger.monotonicMillisSinceLaunch() - trace.startedAtMs
        PerformanceLogger.event(
            .tabSwitch,
            "content active",
            metadata: String(format: "trace=%d stage=%@ target=%@ mountedBefore=%@ elapsedMs=%.1f",
                             trace.id,
                             stage,
                             trace.target.rawValue,
                             trace.wasMounted.description,
                             elapsed)
        )

        let startedAtMs = trace.startedAtMs
        let traceID = trace.id
        let target = trace.target.rawValue
        let wasMounted = trace.wasMounted.description
        DispatchQueue.main.async {
            let nextRunloopElapsed = PerformanceLogger.monotonicMillisSinceLaunch() - startedAtMs
            PerformanceLogger.event(
                .tabSwitch,
                "content active next runloop",
                metadata: String(format: "trace=%d target=%@ mountedBefore=%@ elapsedMs=%.1f",
                                 traceID,
                                 target,
                                 wasMounted,
                                 nextRunloopElapsed)
            )
        }
    }
}

private struct ContentSettingsObserver: View {
    @Query private var settingsArray: [AppSettings]

    @Binding var snapshot: ContentSettingsSnapshot

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { syncSnapshot() }
            .onChange(of: settingsArray) { _, _ in
                syncSnapshot()
            }
    }

    private func syncSnapshot() {
        let newSnapshot = ContentSettingsSnapshot(settings: settingsArray.first)
        guard snapshot != newSnapshot else { return }
        snapshot = newSnapshot
    }
}

private final class HomeLiveInputsStore: ObservableObject {
    var pantryItems: [UnifiedItem] = []
    var recipes: [Recipe] = []
    var categories: [Category] = []
    var foodEntries: [FoodEntry] = []
    var dayLogs: [NutritionDayLog] = []
}

private struct HomeSettingsSnapshot: Equatable {
    var recipeCompatibilityThresholdPercent = 80
    var expiringItemsLeadDays = 30

    init(settings: AppSettings? = nil) {
        recipeCompatibilityThresholdPercent = settings?.recipeCompatibilityThresholdPercent ?? 80
        expiringItemsLeadDays = settings?.expiringItemsLeadDays ?? 30
    }
}

private struct HomeLiveInputsObserver: View {
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var foodEntries: [FoodEntry]
    @Query(sort: \NutritionDayLog.dayStart, order: .reverse) private var dayLogs: [NutritionDayLog]
    @Query private var settingsArray: [AppSettings]

    let store: HomeLiveInputsStore
    @Binding var settingsSnapshot: HomeSettingsSnapshot
    let onInitialInputsReady: () -> Void
    let onDebouncedInputsChanged: () -> Void

    @State private var didDeliverInitialInputs = false
    @State private var pendingDebouncedRefreshWork: DispatchWorkItem?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                syncLiveInputs(triggerDebouncedRefresh: false)
            }
            .onChange(of: pantryItems) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onChange(of: recipes) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onChange(of: categories) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onChange(of: foodEntries) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onChange(of: dayLogs) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onChange(of: settingsArray) { _, _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeDataShouldRefresh)) { _ in
                syncLiveInputs(triggerDebouncedRefresh: true)
            }
    }

    private func syncLiveInputs(triggerDebouncedRefresh: Bool) {
        store.pantryItems = pantryItems
        store.recipes = recipes
        store.categories = categories
        store.foodEntries = foodEntries
        store.dayLogs = dayLogs

        let newSettingsSnapshot = HomeSettingsSnapshot(settings: settingsArray.first)
        if settingsSnapshot != newSettingsSnapshot {
            settingsSnapshot = newSettingsSnapshot
        }

        if !didDeliverInitialInputs {
            didDeliverInitialInputs = true
            onInitialInputsReady()
            return
        }

        guard triggerDebouncedRefresh else { return }

        pendingDebouncedRefreshWork?.cancel()
        let workItem = DispatchWorkItem {
            onDebouncedInputsChanged()
        }
        pendingDebouncedRefreshWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}

private struct HomeView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @Environment(\.activeAppTab) private var activeAppTab
    @EnvironmentObject private var searchBarState: SearchBarState
    // Corrigido ciclo do AttributeGraph separando dependências reativas de SwiftData em @State com atualização manual para evitar travamentos no macOS.

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
    @State private var hasPendingNutritionDays = false
    @State private var contentResetToken: Int = 0
    @State private var shortcutDeckWidth: CGFloat = 0
    @State private var settingsSnapshot = HomeSettingsSnapshot()
    @StateObject private var liveInputs = HomeLiveInputsStore()
    @State private var hasLoadedInitialInputs = false
    
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
                    #endif
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: homeContentSpacing) {
                        actionDeck
                        if hasPendingNutritionDays {
                            PendingNutritionDaysCard()
                        }
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
        .background(alignment: .topLeading) {
            HomeLiveInputsObserver(
                store: liveInputs,
                settingsSnapshot: $settingsSnapshot,
                onInitialInputsReady: {
                    hasLoadedInitialInputs = true
                    refreshHomeDerivedState(logEvent: false)
                },
                onDebouncedInputsChanged: {
                    refreshHomeDerivedState(logEvent: true)
                }
            )
            .allowsHitTesting(false)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.home.accentColor)
        .sheet(isPresented: $showAddGrocery, onDismiss: {
            refreshHomeFromCurrentInputs(logEvent: true)
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }) {
            ItemDetailView(mode: .create(destinations: [.grocery]))
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddPantry, onDismiss: {
            refreshHomeFromCurrentInputs(logEvent: true)
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }) {
            ItemDetailView(mode: .create(destinations: [.pantry]))
                .forceLightStatusBar()
        }
        .sheet(isPresented: $showAddRecipe, onDismiss: {
            refreshHomeFromCurrentInputs(logEvent: true)
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }) {
            NavigationStack {
                AddRecipeView()
            }
            .forceLightStatusBar()
        }
        .sheet(isPresented: $showImportRecipe, onDismiss: {
            refreshHomeFromCurrentInputs(logEvent: true)
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
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
        .sheet(item: $editingExpiringItem, onDismiss: {
            editingExpiringItem = nil
            refreshHomeFromCurrentInputs(logEvent: true)
            NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
        }) { selection in
            ItemDetailContainerView(itemID: selection.id)
                .forceLightStatusBar()
        }
        .onChange(of: selectedCompatibleCategory) { _, _ in
            // User-driven changes feel best with no perceptible delay.
            updateCompatibleMatches()
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            contentResetToken += 1
        }
        .onAppear {
            refreshHomeFromCurrentInputs(logEvent: false)
        }
        .onChange(of: activeAppTab) { _, newValue in
            guard newValue == .assistant else { return }
            refreshHomeFromCurrentInputs(logEvent: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeDataShouldRefresh)) { _ in
            refreshHomeFromCurrentInputs(logEvent: true)
        }
    }

    private func refreshHomeFromCurrentInputs(logEvent: Bool) {
        guard hasLoadedInitialInputs else { return }
        refreshHomeDerivedState(logEvent: logEvent)
    }

    private func refreshHomeDerivedState(logEvent: Bool) {
        if logEvent {
            PerformanceLogger.event(.cloudSync, "HomeView debounced refresh")
        }
        updateRecipeCategories()
        updateCompatibleMatches()
        updateExpiringItems()
        updatePendingNutritionDays()
    }

    private func updateRecipeCategories() {
        recipeCategoriesState = liveInputs.categories.filter { $0.type == .recipe }
    }
    private func updateCompatibleMatches() {
        let pantryNames = liveInputs.pantryItems.map { normalized($0.name) }
        let threshold = Double(settingsSnapshot.recipeCompatibilityThresholdPercent) / 100.0
        let applyTimeFilter = selectedCompatibleCategory == nil
        let mealKeywords = applyTimeFilter ? Self.mealKeywordsForCurrentTime() : []

        compatibleMatchesState = liveInputs.recipes
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
        let leadDays = settingsSnapshot.expiringItemsLeadDays
        let now = Calendar.current.startOfDay(for: .now)
        let limit = Calendar.current.date(byAdding: .day, value: leadDays, to: now) ?? now
        expiringItemsState = liveInputs.pantryItems
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

    private func updatePendingNutritionDays() {
        let today = Calendar.current.startOfDay(for: .now)
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: today) else {
            hasPendingNutritionDays = false
            return
        }

        var cursor = today
        while cursor >= cutoff {
            let state = NutritionDayLogStore.state(
                for: cursor,
                entries: liveInputs.foodEntries,
                logs: liveInputs.dayLogs,
                calendar: .current
            )
            if state == .todayInProgress || state == .pastInProgress {
                hasPendingNutritionDays = true
                return
            }
            guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        hasPendingNutritionDays = false
    }

    private var hasHomeStatusSections: Bool {
        hasPendingNutritionDays || !expiringItemsState.isEmpty
    }

    private var homeContentSpacing: CGFloat {
        32
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
                        imageSize: 600,
                        imageOffset: CGSize(width: 110, height: 30)
                    ) {
                        onOpenSearch()
                    }
                    .frame(maxWidth: .infinity, minHeight: featuredHeight, maxHeight: featuredHeight)

                    VStack(spacing: spacing) {
                        homeShortcutButton(
                            title: String(localized: "SavorIA"),
                            subtitle: String(localized: "AI Mode"),
                            imageName: "savorai",
                            style: .wide,
                            imageSize: 150,
                            imageOffset: CGSize(width: 22, height: 26),
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
                            imageSize: 135,
                            imageOffset: CGSize(width: 14, height: 22),
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

                    macShortcutAddTile(title: String(localized: "Mercado"), imageName: "mercado", imageSize: 72, tileHeight: quickTileHeight) {
                        showAddGrocery = true
                    }

                    macShortcutAddTileMenu(title: String(localized: "Receitas"), imageName: "receitas", imageSize: 68, tileHeight: quickTileHeight) {
                        recipeShortcutMenuContent
                    }

                    macShortcutAddTileMenu(title: String(localized: "Alimento"), imageName: "nutrientes", imageSize: 64, tileHeight: quickTileHeight) {
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
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
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
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
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
                // Linha superior: Assistente (featured) + SavorIA / Receitas (wide)
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
                            title: String(localized: "SavorIA"),
                            subtitle: String(localized: "AI Mode"),
                            imageName: "savorai",
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
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTile(imageName: "mercado", imageSize: 71) {
                            showAddGrocery = true
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Mercado"))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTileMenu(imageName: "receitas", imageSize: 65) {
                            recipeShortcutMenuContent
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Receitas"))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    VStack(spacing: 6) {
                        homeShortcutAddTileMenu(imageName: "nutrientes", imageSize: 66) {
                            foodShortcutMenuContent
                        }
                        .frame(height: smallSide)
                        Text(String(localized: "Alimento"))
                            .font(.caption)
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

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    expiringSectionCard(for: item)
                        .frame(width: 104, height: 100)
                        .offset(y: -5)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, -4)
        }
    }

    private func expiringSectionCard(for item: UnifiedItem) -> some View {
        Button {
            editingExpiringItem = UnifiedItemSelection(id: item.id)
        } label: {
            ZStack(alignment: .bottom) {
                expiringCardSurface(for: item.expirationDate)

                VStack(spacing: 0) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)

                    if let expirationDate = item.expirationDate {
                        Text(relativeExpirationText(for: expirationDate))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(expirationHighlightColor(for: expirationDate))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.75)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    expiringCardTextPanelColor(for: item.expirationDate)
                        .clipShape(
                            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                        )
                )
            }
            .overlay(alignment: .top) {
                IconImage(
                    name: item.name,
                    iconFileName: item.resolvedIconName(),
                    fallbackSymbol: "clock.badge.exclamationmark",
                    size: 68,
                    showBalloon: false
                )
                .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 5)
                .offset(y: -20)
                .allowsHitTesting(false)
            }
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

    private var expiringCardSurfaceColor: Color {
        colorScheme == .dark ? Color(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0) : neutralSurfaceColor
    }

    private func expiringCardTextPanelColor(for date: Date?) -> Color {
        let isExpired = date.map { expirationDaysUntil($0) < 0 } ?? false
        if isExpired {
            return .clear
        }
        return expiringCardSurfaceColor.opacity(colorScheme == .dark ? 0.60 : 0.48)
    }

    private func expiringCardSurface(for date: Date?) -> some View {
        let isExpired = date.map { expirationDaysUntil($0) < 0 } ?? false
        let accent = isExpired
            ? Color.red
            : Color.primary.opacity(colorScheme == .dark ? 0.58 : 0.42)

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(expiringCardSurfaceColor)
            .overlay {
                expiringCardSurfaceGradient(isExpired: isExpired)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .expiringGlassReflectionBorder(cornerRadius: 16, accentColor: accent, isColored: true)
            .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 4)
    }

    private func expiringCardSurfaceGradient(isExpired: Bool) -> LinearGradient {
        if isExpired {
            return LinearGradient(
                stops: [
                    .init(color: Color.red.opacity(colorScheme == .dark ? 0.46 : 0.28), location: 0.00),
                    .init(color: Color.red.opacity(colorScheme == .dark ? 0.26 : 0.16), location: 0.24),
                    .init(color: Color.red.opacity(colorScheme == .dark ? 0.13 : 0.08), location: 0.58),
                    .init(color: Color.red.opacity(colorScheme == .dark ? 0.04 : 0.025), location: 0.82),
                    .init(color: Color.red.opacity(0.00), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            stops: [
                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.055), location: 0.00),
                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.028), location: 0.48),
                .init(color: Color.primary.opacity(0.00), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? PageTheme.home.accentColor.opacity(0.16) : neutralSurfaceColor,
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

    private func expirationDaysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    private func relativeExpirationText(for date: Date) -> String {
        let days = expirationDaysUntil(date)
        if days < -1 {
            return String.localizedStringWithFormat(String(localized: "Expirou há %lld dias"), abs(days))
        }
        if days == -1 { return String(localized: "Expirou há 1 dia") }
        if days == 0 { return String(localized: "Expira hoje") }
        if days == 1 { return String(localized: "Expira amanhã") }
        return String.localizedStringWithFormat(String(localized: "Expira em %lld dias"), days)
    }

    private func expirationHighlightColor(for date: Date) -> Color {
        let days = expirationDaysUntil(date)
        if days < 0 { return .red }
        return .secondary
    }
}

private let homeShortcutBackgroundColor = neutralSurfaceColor

private struct ExpiringGlassReflectionBorderModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isColored: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(continuousEdgeReflection, lineWidth: colorScheme == .dark ? 1.25 : 1.15)
                        .mask(continuousEdgeOpacityMask)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(topReflection, lineWidth: colorScheme == .dark ? 0.95 : 1.05)
                        .mask(topReflectionMask)
                        .blendMode(colorScheme == .dark ? .screen : .normal)
                }
                .allowsHitTesting(false)
            }
    }

    private var continuousEdgeOpacityMask: some View {
        GeometryReader { geometry in
            let midCornerLocation = min(max((cornerRadius / 2) / max(geometry.size.height, 1), 0), 1)

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.05), location: midCornerLocation),
                    .init(color: .white.opacity(0.35), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var topReflectionMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white, location: 0.18),
                    .init(color: .white.opacity(0.56), location: 0.54),
                    .init(color: .white.opacity(0.18), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cornerRadius + 8)

            Rectangle()
                .fill(.white.opacity(0.18))
        }
    }

    private var topReflection: some ShapeStyle {
        AngularGradient(
            stops: [
                .init(color: accentColor.opacity(0.00), location: 0.00),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.18 : 0.12) : 0.06), location: 0.08),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.36 : 0.24) : 0.10), location: 0.18),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.58 : 0.38) : 0.14), location: 0.25),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.36 : 0.24) : 0.10), location: 0.32),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.18 : 0.12) : 0.06), location: 0.42),
                .init(color: accentColor.opacity(0.00), location: 0.50),
                .init(color: accentColor.opacity(0.00), location: 1.00)
            ],
            center: .center,
            startAngle: .degrees(-180),
            endAngle: .degrees(180)
        )
    }

    private var continuousEdgeReflection: some ShapeStyle {
        accentColor.opacity(isColored ? (colorScheme == .dark ? 0.28 : 0.18) : (colorScheme == .dark ? 0.16 : 0.10))
    }
}

private extension View {
    func expiringGlassReflectionBorder(cornerRadius: CGFloat, accentColor: Color, isColored: Bool) -> some View {
        modifier(ExpiringGlassReflectionBorderModifier(cornerRadius: cornerRadius, accentColor: accentColor, isColored: isColored))
    }
}

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
    // On macOS we honor the user's selected appearance — never force a hard
    // white background on sheets, which previously made dark mode unreadable.
    // The modifier still gives sheets a clean adaptive background so they
    // don't fall through to the desktop / window chrome.
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
