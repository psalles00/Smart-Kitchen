import SwiftUI
import SwiftData

enum AssistantScrollMetrics {
    static func topThreshold(forTopPadding topPadding: CGFloat) -> CGFloat {
        topPadding - 10
    }
}

// MARK: - Fullscreen Assistant View

/// Full-screen page that hosts both the "Assistente" (search) and the
/// "Modo IA" (chat) experiences on iOS.
///
/// Presented as a ZStack overlay in ContentView so the persistent search bar
/// remains mounted and focused while the assistant expands.
///
/// Background: LiquidGlass on iOS 26+, solid white/black on older iOS.
/// Dismiss: tap empty area, drag down, or close button.
struct FullscreenAssistantView: View {
    /// How this view is being presented.
    /// - `.overlay` (default): legacy floating overlay over the app, dismissable
    ///   via background tap, drag-down, or the close button.
    /// - `.tab`: hosted as a permanent tab page. All dismiss affordances are
    ///   suppressed (tap, drag, close button) and the AI chat mode is reached
    ///   through a navigation push instead of a global mode toggle.
    enum Presentation { case overlay, tab }
    enum ChromeStyle { case fullscreen, embeddedPanel }

    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @Environment(\.colorScheme) private var colorScheme
    @Query private var settingsArray: [AppSettings]
    @Query private var nutritionProfiles: [NutritionProfile]

    let onAction: (CommandBarAction) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    var presentation: Presentation = .overlay
    var chromeStyle: ChromeStyle = .fullscreen
    var usesDarkShaderBackground: Bool = false
    /// When set, the idle "Perguntar à IA" / "Ideias de receitas" buttons call
    /// this closure (with the desired preset) instead of mutating the global
    /// `searchBarState.mode`. Used by the search-tab to push the AI page.
    var onRequestAIMode: ((AIChatPreset, String?) -> Void)? = nil
    /// When true, render a native back button at the left of the title and use
    /// the SwiftUI `\.dismiss` environment to pop. Used only by the pushed AI
    /// page inside the search-tab navigation stack.
    var showsBackButton: Bool = false

    @Environment(\.dismiss) private var environmentDismiss

    // Drag-to-dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0.88
    @State private var isScrollableContentAtTop: Bool = true
    // Snapshot of scroll-at-top status captured at the moment a drag begins.
    // nil means the current drag hasn't started yet.
    @State private var dragStartedAtTop: Bool? = nil
    @State private var showImportRecipe = false
    @State private var recipeImportLaunchMode: RecipeImportLaunchMode = .picker
    @State private var pendingImportedRecipeID: UUID? = nil
    private let fullscreenTopPinnedInset: CGFloat = 72
    private let embeddedPanelTopInset: CGFloat = 16

    private var settings: AppSettings? { settingsArray.first }
    private var topPinnedInset: CGFloat {
        chromeStyle == .fullscreen ? fullscreenTopPinnedInset : embeddedPanelTopInset
    }
    private var showsPinnedHeader: Bool {
        chromeStyle == .fullscreen
    }
    private var idleScrollTopThreshold: CGFloat {
        AssistantScrollMetrics.topThreshold(forTopPadding: topPinnedInset)
    }
    private var assistantIAAccent: Color { PageTheme.home.accentColor }
    private var assistantListsAccent: Color { PageTheme.lists.accentColor }
    private var assistantRecipesAccent: Color { PageTheme.recipes.accentColor }
    private var assistantNutrientsAccent: Color { PageTheme.nutrients.accentColor }
    private var assistantActionButtonBaseHeight: CGFloat { 62 }
    private var assistantHeaderTitleFont: Font {
        if searchBarState.mode == .aiChat {
            return .custom("Bricolage Grotesque", size: 31, relativeTo: .title).bold()
        }

        return .pageTitle
    }
    private var assistantActionColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }
    private var headerBackgroundStyle: AnyShapeStyle {
        if usesDarkShaderBackground {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.72),
                        Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(appPrimaryBackground)
    }

    var body: some View {
        ZStack {
            if chromeStyle == .fullscreen {
                if presentation == .overlay {
                    pageBackground
                        .ignoresSafeArea()
                        .onTapGesture { searchBarState.dismiss() }
                } else {
                    pageBackground
                        .ignoresSafeArea()
                }
            } else {
                Color.clear
            }

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(
                    OverlayDragGestureModifier(
                        enabled: presentation == .overlay,
                        gesture: dismissDragGesture,
                        includeSubviewsWhenAtTop: isScrollableContentAtTop
                    )
                )
                .overlay(alignment: .top) {
                    if showsPinnedHeader {
                        pinnedHeader
                    }
                }
            .offset(y: max(dragOffset, 0))
            .opacity(contentOpacity)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.12)) {
                contentOpacity = 1
            }
        }
    }

    /// Helper that conditionally attaches the dismiss drag gesture only when
    /// the view is presented as an overlay. In tab mode no dismiss gesture is
    /// attached at all.
    private struct OverlayDragGestureModifier<G: Gesture>: ViewModifier {
        let enabled: Bool
        let gesture: G
        let includeSubviewsWhenAtTop: Bool
        func body(content: Content) -> some View {
            if enabled {
                content.simultaneousGesture(
                    gesture,
                    including: includeSubviewsWhenAtTop ? .subviews : .none
                )
            } else {
                content
            }
        }
    }

    /// Same idea for the pinned header high-priority drag.
    private struct OverlayHeaderDragModifier<G: Gesture>: ViewModifier {
        let enabled: Bool
        let gesture: G
        func body(content: Content) -> some View {
            if enabled {
                content.highPriorityGesture(gesture)
            } else {
                content
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                // Snapshot once per gesture: the assistant may only be dismissed if
                // the drag either started inside the title/header area, or started
                // while the scroll content was already at the very top. Dragging
                // inside the content area while it is scrolled must never switch
                // into dismiss mode mid-gesture, even if the content later reaches
                // top via rubberband.
                if dragStartedAtTop == nil {
                    let startedInHeader = value.startLocation.y <= topPinnedInset
                    dragStartedAtTop = startedInHeader || isScrollableContentAtTop
                }
                guard value.translation.height > 0, dragStartedAtTop == true else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let canDismiss = dragStartedAtTop ?? isScrollableContentAtTop
                dragStartedAtTop = nil

                guard canDismiss else {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                    return
                }

                if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                    searchBarState.dismiss()
                } else {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button {
                    // Reset AI state BEFORE popping so the parent view re-renders
                    // with the idle "Assistente" title during the pop animation.
                    // Otherwise the user briefly sees a second "Modo IA" screen
                    // (the parent FullscreenAssistantView still in `.aiChat` mode).
                    pendingOpenChat = false
                    searchBarState.mode = .idle
                    searchBarState.aiChatPreset = .nutritionCoach
                    environmentDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Voltar")))
            }

            Text(searchBarState.mode == .aiChat ? String(localized: "Modo IA") : String(localized: "Assistente"))
                .font(assistantHeaderTitleFont)
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer()

            if searchBarState.mode == .aiChat {
                #if os(macOS)
                if usesDarkShaderBackground {
                    Menu {
                        Button {
                            searchBarState.requestAIHistory(source: "macOS dark header menu")
                        } label: {
                            Label("Histórico", systemImage: "clock.arrow.circlepath")
                        }

                        Button {
                            searchBarState.requestAINewConversation(source: "macOS dark header menu")
                        } label: {
                            Label("Nova conversa", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .menuOrder(.fixed)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        searchBarState.requestAINewConversation(source: "macOS header button")
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        searchBarState.requestAIHistory(source: "macOS header button")
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                #else
                Button {
                    searchBarState.requestAINewConversation(source: "iOS AI header")
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    searchBarState.requestAIHistory(source: "iOS AI header")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                    #endif
            }

            Button {
                searchBarState.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(presentation == .tab ? 0 : 1)
            .allowsHitTesting(presentation != .tab)
            .frame(width: presentation == .tab ? 0 : nil)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showResults = hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil

        if showResults {
            InlineSearchResultsView(
                searchBarState: searchBarState,
                searchService: searchService,
                onAction: onAction,
                topPinnedInset: topPinnedInset,
                isScrollAtTop: $isScrollableContentAtTop,
                pendingChatQuery: $pendingChatQuery,
                pendingOpenChat: $pendingOpenChat,
                pendingNewConversation: $pendingNewConversation,
                pendingShowHistory: $pendingShowHistory,
                disableEmptyTapDismiss: presentation == .tab
            )
        } else {
            idleActionButtons
        }
    }

    // MARK: - Idle Action Buttons (nothing typed)

    private var idleActionButtons: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ScrollOffsetReader(coordinateSpace: "AssistantIdleScroll")

                    Text("Adicione itens, crie receitas ou peça sugestões sem sair do Assistente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    LazyVGrid(columns: assistantActionColumns, alignment: .leading, spacing: 6) {
                        assistantActionButton(
                            title: String(localized: "Perguntar à IA"),
                            icon: "sparkles",
                            tint: assistantIAAccent,
                            imageName: "modo ia",
                            imageHeight: 82,
                            imageOffset: CGSize(width: 8, height: 12)
                        ) {
                            if let onRequestAIMode {
                                onRequestAIMode(.nutritionCoach, nil)
                            } else {
                                searchBarState.aiChatPreset = .nutritionCoach
                                searchBarState.mode = .aiChat
                                pendingChatQuery = nil
                                pendingOpenChat = true
                            }
                        }

                        assistantActionButton(
                            title: String(localized: "Ideias de receitas"),
                            icon: "fork.knife.circle.fill",
                            tint: assistantIAAccent,
                            imageName: "ideis",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            if let onRequestAIMode {
                                onRequestAIMode(.recipeIdeas, nil)
                            } else {
                                searchBarState.aiChatPreset = .recipeIdeas
                                searchBarState.mode = .aiChat
                                pendingChatQuery = nil
                                pendingOpenChat = true
                            }
                        }

                        assistantActionButton(
                            title: String(localized: "Adicionar à Despensa"),
                            icon: "shippingbox.fill",
                            tint: assistantListsAccent,
                            imageName: "despensa",
                            imageHeight: 72,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            triggerAction(.addPantryItem(prefill: ""))
                        }

                        assistantActionButton(
                            title: String(localized: "Adicionar ao Mercado"),
                            icon: "cart.badge.plus",
                            tint: assistantListsAccent,
                            imageName: "mercado",
                            imageHeight: 76,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            triggerAction(.addGroceryItem(prefill: ""))
                        }

                        if settings?.showUtensils == true {
                            assistantActionButton(
                                title: String(localized: "Adicionar Utensílio"),
                                icon: "fork.knife",
                                tint: assistantListsAccent,
                                imageName: "listas-utensilio",
                                imageHeight: 76,
                                imageOffset: CGSize(width: 6, height: 12)
                            ) {
                                triggerAction(.addUtensil(prefill: ""))
                            }
                        }

                        assistantActionButton(
                            title: String(localized: "Criar Receita"),
                            icon: "book.badge.plus",
                            tint: assistantRecipesAccent,
                            imageName: "receitas",
                            imageHeight: 70,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            triggerAction(.addRecipe(prefill: ""))
                        }

                        assistantActionButton(
                            title: String(localized: "Importar da Galeria"),
                            icon: "photo.on.rectangle.angled",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-importar",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            openRecipeImport(.gallery)
                        }

                        assistantActionButton(
                            title: String(localized: "Ler Receita"),
                            icon: "camera.viewfinder",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-ler",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            openRecipeImport(.camera)
                        }

                        #if os(macOS)
                        assistantActionButton(
                            title: String(localized: "Importar dos Arquivos"),
                            icon: "folder.fill",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-importar",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            openRecipeImport(.files)
                        }
                        #endif

                        assistantActionButton(
                            title: String(localized: "Registrar Alimento"),
                            icon: "fork.knife.circle.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            presentNutritionSheet(.captureText(prefillText: nil, autoAnalyze: false))
                        }

                        assistantActionButton(
                            title: String(localized: "Registrar com Áudio"),
                            icon: "mic.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-audio",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            presentNutritionSheet(.captureVoice)
                        }

                        assistantActionButton(
                            title: String(localized: "Registrar com Galeria"),
                            icon: "photo.on.rectangle.angled",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-galeria",
                            imageHeight: 68,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            presentFoodGalleryDirect()
                        }

                        assistantActionButton(
                            title: String(localized: "Registrar com Câmera"),
                            icon: "camera.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-camera",
                            imageHeight: 72,
                            imageOffset: CGSize(width: 6, height: 12)
                        ) {
                            presentFoodCameraDirect()
                        }

                        assistantActionButton(
                            title: String(localized: "Rastreio de Peso"),
                            icon: "scalemass.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "peso",
                            imageHeight: 82,
                            imageOffset: CGSize(width: 10, height: 12)
                        ) {
                            triggerAction(.openWeightTracker)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    aiModeSuggestionsSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, topPinnedInset)
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "AssistantIdleScroll")
            .onScrollOffsetChange { offset in
                isScrollableContentAtTop = offset >= idleScrollTopThreshold
            }
            .onAppear {
                isScrollableContentAtTop = true
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showImportRecipe, onDismiss: handleImportRecipeDismissed) {
            RecipeImportHostView(launchMode: recipeImportLaunchMode) { recipeID in
                pendingImportedRecipeID = recipeID
                showImportRecipe = false
            }
            .modelContainer(CloudSyncService.shared.container)
            .forceLightStatusBar()
        }
    }

    private func openRecipeImport(_ launchMode: RecipeImportLaunchMode) {
        recipeImportLaunchMode = launchMode
        showImportRecipe = true
    }

    private func presentNutritionSheet(_ sheet: NutritionEntrySheet) {
        searchBarState.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            searchBarState.pendingNutritionSheet = sheet
        }
    }

    private func presentFoodCameraDirect() {
        searchBarState.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenFoodCameraDirect()
        }
    }

    private func presentFoodGalleryDirect() {
        searchBarState.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onOpenFoodGalleryDirect()
        }
    }

    private func handleImportRecipeDismissed() {
        recipeImportLaunchMode = .picker

        guard let recipeID = pendingImportedRecipeID else { return }

        pendingImportedRecipeID = nil
        searchBarState.dismiss()
        openRecipeInRecipesTab(recipeID)
    }

    private func triggerAction(_ action: CommandBarAction) {
        onAction(action)
        searchBarState.selectResult()
    }

    // MARK: - Sugestões do Modo IA (espelhadas no Modo IA)

    @ViewBuilder
    private var aiModeSuggestionsSection: some View {
        let suggestions = AIModeSuggestions.nutritionCoachSuggestions(profile: nutritionProfiles.first)
        VStack(alignment: .leading, spacing: 10) {
            Text("Sugestões do Modo IA")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            AIModeSuggestionsList(suggestions: suggestions) { suggestion in
                openAIChat(with: suggestion.prompt)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    /// Opens the AI chat (overlay or pushed tab) and pre-fills it with the
    /// suggestion prompt so it is auto-sent.
    private func openAIChat(with prompt: String) {
        if let onRequestAIMode {
            // Tab presentation: push the AI page with prefill so it auto-sends.
            onRequestAIMode(.nutritionCoach, prompt)
        } else {
            searchBarState.aiChatPreset = .nutritionCoach
            searchBarState.mode = .aiChat
            pendingOpenChat = false
            pendingChatQuery = prompt
        }
    }

    private func assistantActionButton(
        title: String,
        icon: String,
        tint: Color,
        imageName: String? = nil,
        imageHeight: CGFloat = 78,
        imageOffset: CGSize = CGSize(width: 6, height: 0),
        trailingSystemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 52)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: assistantActionButtonBaseHeight, alignment: .center)
            .background(tint.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay(alignment: .trailing) {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: imageHeight)
                        .offset(imageOffset)
                        .allowsHitTesting(false)
                } else if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.28))
                        .symbolRenderingMode(.hierarchical)
                        .padding(.trailing, 14)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .modifier(
                    OverlayHeaderDragModifier(
                        enabled: presentation == .overlay,
                        gesture: dismissDragGesture
                    )
                )
                .background(headerBackgroundStyle, ignoresSafeAreaEdges: .top)

            Rectangle()
                .fill(.bar)
                .frame(height: 28)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(colorScheme == .dark ? 0.92 : 1), location: 0),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.65), location: 0.34),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var pageBackground: some View {
        if usesDarkShaderBackground {
            AssistantModeShaderBackground()
        } else {
            Rectangle()
                .fill(appPrimaryBackground)
        }
    }
}

private struct AssistantModeShaderBackground: View {
    @AppStorage(PerformancePreferences.backgroundShadersEnabledKey)
    private var backgroundShadersEnabled = true

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.065, blue: 0.075)

            if backgroundShadersEnabled {
                TexturedGradientSceneView(
                    color1: Color(red: 0.30, green: 0.31, blue: 0.34),
                    color2: Color(red: 0.18, green: 0.19, blue: 0.21),
                    color3: Color(red: 0.09, green: 0.10, blue: 0.12),
                    grainIntensity: 0.10,
                    shapeType: 5
                )
                .opacity(0.94)
            } else {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 0.25, green: 0.26, blue: 0.29),
                        Color(red: 0.19, green: 0.20, blue: 0.22),
                        Color(red: 0.15, green: 0.16, blue: 0.18),
                        Color(red: 0.14, green: 0.15, blue: 0.17),
                        Color(red: 0.10, green: 0.11, blue: 0.13),
                        Color(red: 0.08, green: 0.09, blue: 0.10),
                        Color(red: 0.07, green: 0.08, blue: 0.09),
                        Color(red: 0.05, green: 0.055, blue: 0.065),
                        Color.black
                    ]
                )
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#if os(macOS)
struct MacAssistantExpandedPage: View {
    enum Mode {
        case assistant
        case aiMode

        var title: String {
            switch self {
            case .assistant:
                return String(localized: "Assistente")
            case .aiMode:
                return String(localized: "Modo IA")
            }
        }
    }

    let mode: Mode
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService

    let onAction: (CommandBarAction) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void
    let onRequestAIMode: ((AIChatPreset, String?) -> Void)?

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .home,
            backgroundOverride: AnyView(AssistantModeShaderBackground()),
            header: { isInverted in
                PageHeader(title: mode.title, isInverted: isInverted) {
                    if mode == .aiMode {
                        GlassButtonGroup {
                            GlassGroupMenu(systemImage: "ellipsis.circle") {
                                Button {
                                    searchBarState.requestAIHistory(source: "macOS expanded AI menu")
                                } label: {
                                    Label("Histórico", systemImage: "clock.arrow.circlepath")
                                }

                                Button {
                                    searchBarState.requestAINewConversation(source: "macOS expanded AI menu")
                                } label: {
                                    Label("Nova conversa", systemImage: "square.and.pencil")
                                }
                            }
                        }
                    } else {
                        EmptyView()
                    }
                }
            },
            content: {
                FullscreenAssistantView(
                    searchBarState: searchBarState,
                    searchService: searchService,
                    onAction: onAction,
                    onOpenFoodCameraDirect: onOpenFoodCameraDirect,
                    onOpenFoodGalleryDirect: onOpenFoodGalleryDirect,
                    pendingChatQuery: $pendingChatQuery,
                    pendingOpenChat: $pendingOpenChat,
                    pendingNewConversation: $pendingNewConversation,
                    pendingShowHistory: $pendingShowHistory,
                    presentation: .tab,
                    chromeStyle: .embeddedPanel,
                    usesDarkShaderBackground: false,
                    onRequestAIMode: mode == .assistant ? onRequestAIMode : nil,
                    showsBackButton: false
                )
            },
            infoContent: {
                EmptyView()
            }
        )
        .tint(PageTheme.home.accentColor)
    }
}
#endif

/// Identifies the AI page pushed onto the search tab navigation stack.
struct AssistantTabAIDestination: Hashable {
    let preset: AIChatPreset
    var prefill: String? = nil
}

// MARK: - Search-Tab Hosting

/// Tab content used by the new "Buscar" (search) tab. Hosts the assistant in
/// `.tab` presentation mode (no close/dismiss affordances) and routes the
/// "Perguntar à IA" / "Ideias de receitas" actions through a NavigationStack
/// push so the AI mode lives as a separate page with a native back button.
struct AssistantSearchTabContent: View {
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService

    let onAction: (CommandBarAction) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    @Binding var path: [AssistantTabAIDestination]

    var usesDarkShaderBackground: Bool = false
    var aiPageShowsBackButton: Bool = true

    var body: some View {
        NavigationStack(path: $path) {
            FullscreenAssistantView(
                searchBarState: searchBarState,
                searchService: searchService,
                onAction: onAction,
                onOpenFoodCameraDirect: onOpenFoodCameraDirect,
                onOpenFoodGalleryDirect: onOpenFoodGalleryDirect,
                pendingChatQuery: $pendingChatQuery,
                pendingOpenChat: $pendingOpenChat,
                pendingNewConversation: $pendingNewConversation,
                pendingShowHistory: $pendingShowHistory,
                presentation: .tab,
                usesDarkShaderBackground: usesDarkShaderBackground,
                onRequestAIMode: { preset, prefill in
                    path.append(AssistantTabAIDestination(preset: preset, prefill: prefill))
                }
            )
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: AssistantTabAIDestination.self) { destination in
                AssistantSearchTabAIPage(
                    destination: destination,
                    searchBarState: searchBarState,
                    searchService: searchService,
                    onAction: onAction,
                    onOpenFoodCameraDirect: onOpenFoodCameraDirect,
                    onOpenFoodGalleryDirect: onOpenFoodGalleryDirect,
                    pendingChatQuery: $pendingChatQuery,
                    pendingOpenChat: $pendingOpenChat,
                    pendingNewConversation: $pendingNewConversation,
                    pendingShowHistory: $pendingShowHistory,
                    usesDarkShaderBackground: usesDarkShaderBackground,
                    showsBackButton: aiPageShowsBackButton
                )
            }
        }
    }
}

/// Pushed page that displays the assistant locked in AI chat mode. Uses the
/// system back button (NavigationStack) and exposes the same chat UI as the
/// overlay flow, but without any close affordances.
private struct AssistantSearchTabAIPage: View {
    let destination: AssistantTabAIDestination
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService

    let onAction: (CommandBarAction) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    var usesDarkShaderBackground: Bool = false
    var showsBackButton: Bool = true

    /// Tracks whether the initial AI-mode configuration has been applied.
    /// Without this, every tab switch re-fires `.onAppear` which would
    /// reset `pendingOpenChat = true`, clobbering the active conversation
    /// (the chat would be reloaded fresh and the messages would disappear).
    @State private var didConfigureOnce = false

    var body: some View {
        FullscreenAssistantView(
            searchBarState: searchBarState,
            searchService: searchService,
            onAction: onAction,
            onOpenFoodCameraDirect: onOpenFoodCameraDirect,
            onOpenFoodGalleryDirect: onOpenFoodGalleryDirect,
            pendingChatQuery: $pendingChatQuery,
            pendingOpenChat: $pendingOpenChat,
            pendingNewConversation: $pendingNewConversation,
            pendingShowHistory: $pendingShowHistory,
            presentation: .tab,
            usesDarkShaderBackground: usesDarkShaderBackground,
            onRequestAIMode: nil,
            showsBackButton: showsBackButton
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            // Always make sure the AI chat mode is active when this page is on
            // screen — but only configure prefill/openChat ONCE so subsequent
            // tab returns preserve the existing conversation.
            searchBarState.aiChatPreset = destination.preset
            searchBarState.mode = .aiChat

            guard !didConfigureOnce else { return }
            didConfigureOnce = true

            if let prefill = destination.prefill, !prefill.isEmpty {
                pendingOpenChat = false
                pendingChatQuery = prefill
            } else {
                pendingChatQuery = nil
                pendingOpenChat = true
            }
        }
        // Note: no `.onDisappear` reset. Tab switches must NOT clear chat
        // state — the user explicitly leaves the AI page only by tapping the
        // back button, which performs its own cleanup before popping.
    }
}


