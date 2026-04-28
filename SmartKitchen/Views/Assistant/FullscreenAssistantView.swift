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
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @Environment(\.colorScheme) private var colorScheme
    @Query private var settingsArray: [AppSettings]

    let onAction: (CommandBarAction) -> Void
    let onOpenFoodCameraDirect: () -> Void
    let onOpenFoodGalleryDirect: () -> Void

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

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
    private let topPinnedInset: CGFloat = 72

    private var settings: AppSettings? { settingsArray.first }
    private var idleScrollTopThreshold: CGFloat {
        AssistantScrollMetrics.topThreshold(forTopPadding: topPinnedInset)
    }
    private var assistantIAAccent: Color { PageTheme.home.accentColor }
    private var assistantListsAccent: Color { PageTheme.lists.accentColor }
    private var assistantRecipesAccent: Color { PageTheme.recipes.accentColor }
    private var assistantNutrientsAccent: Color { PageTheme.nutrients.accentColor }
    private var assistantActionButtonBaseHeight: CGFloat { 62 }
    private var assistantActionColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }

    var body: some View {
        ZStack {
            // Tappable background — dismiss on tap
            pageBackground
                .ignoresSafeArea()
                .onTapGesture { searchBarState.dismiss() }

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    dismissDragGesture,
                    including: isScrollableContentAtTop ? .subviews : .none
                )
                .overlay(alignment: .top) {
                    pinnedHeader
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
        HStack(alignment: .top) {
            Text(searchBarState.mode == .aiChat ? "Modo IA" : "Assistente")
                .font(.pageTitle)
                .foregroundStyle(Color.primary)

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
                searchBarState.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
                pendingShowHistory: $pendingShowHistory
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
                            title: "Perguntar à IA",
                            icon: "sparkles",
                            tint: assistantIAAccent,
                            imageName: "modo ia",
                            imageHeight: 82,
                            imageOffset: CGSize(width: 8, height: 0)
                        ) {
                            searchBarState.aiChatPreset = .nutritionCoach
                            searchBarState.mode = .aiChat
                            pendingChatQuery = nil
                            pendingOpenChat = true
                        }

                        assistantActionButton(
                            title: "Ideias de receitas",
                            icon: "fork.knife.circle.fill",
                            tint: assistantIAAccent,
                            imageName: "ideis",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            searchBarState.aiChatPreset = .recipeIdeas
                            searchBarState.mode = .aiChat
                            pendingChatQuery = nil
                            pendingOpenChat = true
                        }

                        assistantActionButton(
                            title: "Adicionar à Despensa",
                            icon: "shippingbox.fill",
                            tint: assistantListsAccent,
                            imageName: "despensa",
                            imageHeight: 72,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            triggerAction(.addPantryItem(prefill: ""))
                        }

                        assistantActionButton(
                            title: "Adicionar ao Mercado",
                            icon: "cart.badge.plus",
                            tint: assistantListsAccent,
                            imageName: "mercado",
                            imageHeight: 76,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            triggerAction(.addGroceryItem(prefill: ""))
                        }

                        if settings?.showUtensils == true {
                            assistantActionButton(
                                title: "Adicionar Utensílio",
                                icon: "fork.knife",
                                tint: assistantListsAccent,
                                imageName: "listas-utensilio",
                                imageHeight: 76,
                                imageOffset: CGSize(width: 6, height: 0)
                            ) {
                                triggerAction(.addUtensil(prefill: ""))
                            }
                        }

                        assistantActionButton(
                            title: "Criar Receita",
                            icon: "book.badge.plus",
                            tint: assistantRecipesAccent,
                            imageName: "receitas",
                            imageHeight: 70,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            triggerAction(.addRecipe(prefill: ""))
                        }

                        assistantActionButton(
                            title: "Importar da Galeria",
                            icon: "photo.on.rectangle.angled",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-importar",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            openRecipeImport(.gallery)
                        }

                        assistantActionButton(
                            title: "Ler Receita",
                            icon: "camera.viewfinder",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-ler",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            openRecipeImport(.camera)
                        }

                        #if os(macOS)
                        assistantActionButton(
                            title: "Importar dos Arquivos",
                            icon: "folder.fill",
                            tint: assistantRecipesAccent,
                            imageName: "receitas-importar",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            openRecipeImport(.files)
                        }
                        #endif

                        assistantActionButton(
                            title: "Registrar Alimento",
                            icon: "fork.knife.circle.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            presentNutritionSheet(.captureText(prefillText: nil, autoAnalyze: false))
                        }

                        assistantActionButton(
                            title: "Registrar com Áudio",
                            icon: "mic.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-audio",
                            imageHeight: 74,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            presentNutritionSheet(.captureVoice)
                        }

                        assistantActionButton(
                            title: "Registrar com Galeria",
                            icon: "photo.on.rectangle.angled",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-galeria",
                            imageHeight: 68,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            presentFoodGalleryDirect()
                        }

                        assistantActionButton(
                            title: "Registrar com Câmera",
                            icon: "camera.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "nutrientes-camera",
                            imageHeight: 72,
                            imageOffset: CGSize(width: 6, height: 0)
                        ) {
                            presentFoodCameraDirect()
                        }

                        assistantActionButton(
                            title: "Rastreio de Peso",
                            icon: "scalemass.fill",
                            tint: assistantNutrientsAccent,
                            imageName: "peso",
                            imageHeight: 82,
                            imageOffset: CGSize(width: 10, height: 0)
                        ) {
                            triggerAction(.openWeightTracker)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
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
                .highPriorityGesture(dismissDragGesture)
                .background(Color.white, ignoresSafeAreaEdges: .top)

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
        Rectangle()
            .fill(Color.white)
    }
}
