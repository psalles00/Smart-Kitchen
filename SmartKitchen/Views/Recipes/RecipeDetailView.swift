import SwiftUI
import SwiftData
import AVKit
import AVFoundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct RecipeDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.grocerySortOrder) private var groceryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.pantrySortOrder) private var pantryListItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]
    @Query(filter: #Predicate<UnifiedItem> { $0.isUtensil }, sort: \UnifiedItem.name) private var utensilItems: [UnifiedItem]
    @Bindable var recipe: Recipe
    @State private var showCookingMode = false
    @State private var showEditRecipe = false
    @State private var previewSelection: PreparationMediaSelection?
    @State private var editingItem: UnifiedItemSelection?
    @State private var ingredientEditorSheet: IngredientEditorSheet?
    @State private var pendingIngredientReplacement: PendingIngredientReplacement?
    /// Porções exibidas no detail. Não persiste; só aplica multiplicador a quantities/nutrição.
    @State private var displayServings: Int = 1
    @State private var didInitDisplayServings = false
    @State private var cachedSortedIngredients: [RecipeIngredient]
    @State private var cachedSortedIngredientSections: [RecipeIngredientSection]
    @State private var cachedIngredientGroups: [IngredientDisplayGroup]
    @State private var cachedSortedSteps: [RecipeStep]
    @State private var cachedSortedPreparationMedia: [RecipePreparationMedia]
    @State private var displayCacheSignature: Int

    #if os(iOS)
    @State private var coverAccent: Color = PageTheme.recipes.accentColor
    @State private var coverPaletteRevision = 0
    #endif

    private let heroHeight: CGFloat = 580
    private let baseContentOverlap: CGFloat = 34
    private let floatingHeroActionSize: CGFloat = 62

    init(recipe: Recipe) {
        self.recipe = recipe
        let cache = Self.makeDisplayCache(for: recipe)
        _cachedSortedIngredients = State(initialValue: cache.ingredients)
        _cachedSortedIngredientSections = State(initialValue: cache.sections)
        _cachedIngredientGroups = State(initialValue: cache.ingredientGroups)
        _cachedSortedSteps = State(initialValue: cache.steps)
        _cachedSortedPreparationMedia = State(initialValue: cache.preparationMedia)
        _displayCacheSignature = State(initialValue: cache.signature)
    }

    private var sortedIngredients: [RecipeIngredient] {
        cachedSortedIngredients
    }

    private var sortedIngredientSections: [RecipeIngredientSection] {
        cachedSortedIngredientSections
    }

    /// Ordered groups for display: the first group (if any unsectioned
    /// ingredients exist) has no header; subsequent groups are each section
    /// followed by their ingredients.
    private var ingredientGroups: [IngredientDisplayGroup] {
        cachedIngredientGroups
    }

    private var sortedSteps: [RecipeStep] {
        cachedSortedSteps
    }

    private var sortedPreparationMedia: [RecipePreparationMedia] {
        cachedSortedPreparationMedia
    }

    private var hasPreparationMedia: Bool {
        !sortedPreparationMedia.isEmpty
    }

    private var containsVideoMedia: Bool {
        sortedPreparationMedia.contains { $0.mediaType == .video }
    }

    private var mediaHeroActionIcon: String {
        containsVideoMedia ? "video" : "photo.stack"
    }

    private var mediaHeroActionAccessibilityLabel: String {
        String(localized: "Mídias da Receita")
    }

    private var favoriteHeroActionAccessibilityLabel: String {
        recipe.isFavorite
            ? String(localized: "Desfavoritar receita")
            : String(localized: "Favoritar receita")
    }

    private var heroActionCount: Int {
        var count = 1
        if externalURL != nil { count += 1 }
        if hasPreparationMedia { count += 1 }
        return count
    }

    private var heroActionVerticalInset: CGFloat {
        heroActionCount >= 3 ? 8 : 0
    }

    private var contentOverlap: CGFloat {
        baseContentOverlap - (heroActionCount >= 3 ? 6 : 0)
    }

    private var preferredPreviewMedia: RecipePreparationMedia? {
        sortedPreparationMedia.first(where: { $0.mediaType == .video }) ?? sortedPreparationMedia.first
    }

    private var preparationMediaCountLabel: String {
        let count = sortedPreparationMedia.count
        return count == 1 ? "1 mídia" : "\(count) mídias"
    }

    private var settings: AppSettings? { settingsArray.first }

    private var mainAreaColor: Color {
        appPrimaryBackground
    }

    private var detailSurfaceColor: Color {
        neutralSurfaceColor
    }

    private var contentTopPadding: CGFloat { 34 + heroActionVerticalInset }
    private var contentBottomPadding: CGFloat { 132 }

    private var heroTitleFontSize: CGFloat {
        let characterCount = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).count

        switch characterCount {
        case 0...18:
            return 39
        case 19...28:
            return 36
        case 29...42:
            return 33
        case 43...56:
            return 30
        default:
            return 27
        }
    }

    private var heroMetadataItems: [HeroMetadataItem] {
        var items: [HeroMetadataItem] = []

        if recipe.totalTime > 0 {
            items.append(HeroMetadataItem(systemImage: "clock", text: "\(recipe.totalTime) min"))
        }

        items.append(HeroMetadataItem(systemImage: recipe.difficulty.icon, text: recipe.difficulty.displayName))

        if recipe.servings > 0 {
            items.append(HeroMetadataItem(systemImage: "person.2", text: "\(recipe.servings) porções"))
        }

        if let calories = recipe.calories {
            items.append(HeroMetadataItem(systemImage: "flame", text: "\(calories) kcal"))
        }

        let categories = recipe.categories.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !categories.isEmpty {
            items.append(HeroMetadataItem(systemImage: "tag", text: categories.joined(separator: ", ")))
        }

        return items
    }

    private var externalURL: URL? {
        let trimmed = recipe.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var pantryNames: [String] {
        pantryListItems.map {
            $0.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
        }
    }

    private var defaultListCategory: String {
        allCategories.first(where: { $0.type == .pantry })?.name ?? "Outros"
    }

    private var defaultUtensilCategory: String {
        allCategories.first(where: { $0.type == .utensil })?.name ?? "Outros"
    }

    private var hasMissingIngredientsInGrocery: Bool {
        sortedIngredients.contains { !ingredientIsInGrocery($0) }
    }

    private struct DisplayCache {
        let ingredients: [RecipeIngredient]
        let sections: [RecipeIngredientSection]
        let ingredientGroups: [IngredientDisplayGroup]
        let steps: [RecipeStep]
        let preparationMedia: [RecipePreparationMedia]
        let signature: Int
    }

    private static func makeDisplayCache(for recipe: Recipe) -> DisplayCache {
        let ingredients = (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let sections = (recipe.ingredientSections ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let steps = (recipe.steps ?? []).sorted { $0.order < $1.order }
        let preparationMedia = (recipe.preparationMedia ?? []).sorted { $0.sortOrder < $1.sortOrder }

        var groups: [IngredientDisplayGroup] = []
        let unsectioned = ingredients.filter { $0.sectionID == nil }
        if !unsectioned.isEmpty {
            groups.append(IngredientDisplayGroup(section: nil, ingredients: unsectioned))
        }
        for section in sections {
            let items = ingredients.filter { $0.sectionID == section.id }
            groups.append(IngredientDisplayGroup(section: section, ingredients: items))
        }

        var hasher = Hasher()
        hasher.combine(recipe.id)
        hasher.combine(recipe.updatedAt)
        hasher.combine(ingredients.count)
        for ingredient in ingredients {
            hasher.combine(ingredient.id)
            hasher.combine(ingredient.sortOrder)
            hasher.combine(ingredient.sectionID)
            hasher.combine(ingredient.name)
            hasher.combine(ingredient.quantity)
            hasher.combine(ingredient.unit)
            hasher.combine(ingredient.preparationState)
            hasher.combine(ingredient.iconName ?? "")
        }
        hasher.combine(sections.count)
        for section in sections {
            hasher.combine(section.id)
            hasher.combine(section.sortOrder)
            hasher.combine(section.title)
            hasher.combine(section.subtitle)
        }
        hasher.combine(steps.count)
        for step in steps {
            hasher.combine(step.id)
            hasher.combine(step.order)
            hasher.combine(step.instruction)
            hasher.combine(step.durationMinutes)
        }
        hasher.combine(preparationMedia.count)
        for media in preparationMedia {
            hasher.combine(media.id)
            hasher.combine(media.sortOrder)
            hasher.combine(media.mediaTypeRaw)
            hasher.combine(media.data.count)
            hasher.combine(media.fileExtension)
        }

        return DisplayCache(
            ingredients: ingredients,
            sections: sections,
            ingredientGroups: groups,
            steps: steps,
            preparationMedia: preparationMedia,
            signature: hasher.finalize()
        )
    }

    private func refreshDisplayCacheIfNeeded(reason: String) {
        let next = Self.makeDisplayCache(for: recipe)
        guard next.signature != displayCacheSignature else { return }

        cachedSortedIngredients = next.ingredients
        cachedSortedIngredientSections = next.sections
        cachedIngredientGroups = next.ingredientGroups
        cachedSortedSteps = next.steps
        cachedSortedPreparationMedia = next.preparationMedia
        displayCacheSignature = next.signature

        PerformanceLogger.event(
            .recipes,
            "RecipeDetailView.displayCache refreshed",
            metadata: "trace=recipe-detail-cache recipe=\(recipe.id) reason=\(reason) ingredients=\(next.ingredients.count) steps=\(next.steps.count) media=\(next.preparationMedia.count)"
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                heroImage
                content
                    .padding(.top, -contentOverlap)
                    .zIndex(1)
            }
            .background {
                ScrollViewInsetAdjustmentDisabler()
            }
        }
        .coordinateSpace(name: "recipe-detail-scroll")
        #if os(iOS)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollClipDisabled()
        #endif
        .onAppear {
            #if os(iOS)
            ActionTrace.shared.begin(page: "recipe_detail", phase: "loaded")
            #endif
            PerformanceLogger.event(
                .recipes,
                "RecipeDetailView.onAppear",
                metadata: "trace=recipe-detail recipe=\(recipe.id) ingredients=\(sortedIngredients.count) steps=\(sortedSteps.count) media=\(sortedPreparationMedia.count)"
            )
            if !didInitDisplayServings {
                displayServings = max(recipe.servings, 1)
                didInitDisplayServings = true
            }
        }
        #if os(iOS)
        .task(id: coverPaletteRevision) {
            guard let data = recipe.imageData,
                  let rgb = await SavoriaImagePalette.averageRGB(from: data),
                  !Task.isCancelled else {
                if !Task.isCancelled { coverAccent = PageTheme.recipes.accentColor }
                return
            }
            coverAccent = Color(red: rgb.x, green: rgb.y, blue: rgb.z)
        }
        .onChange(of: recipe.imageData) { _, _ in
            coverPaletteRevision &+= 1
        }
        #endif
        .onChange(of: recipe.updatedAt) { _, _ in
            refreshDisplayCacheIfNeeded(reason: "updatedAt")
        }
        #if os(macOS)
        .padding(.top, -10)
        #else
        .ignoresSafeArea(edges: .top)
        #endif
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .background(mainAreaColor.ignoresSafeArea())
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditRecipe = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Editar")
            }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe)
        }
        #else
        .sheet(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe)
                .presentationSizing(.page)
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.last {
                            window.toggleFullScreen(nil)
                        }
                    }
                }
        }
        #endif
        .sheet(isPresented: $showEditRecipe) {
            NavigationStack {
                EditRecipeContainerView(recipeID: recipe.id)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $editingItem, onDismiss: { editingItem = nil }) { selection in
            ItemDetailContainerView(itemID: selection.id)
                .forceLightStatusBar()
        }
        .sheet(item: $ingredientEditorSheet, onDismiss: applyPendingIngredientReplacementIfNeeded) { sheet in
            switch sheet {
            case .replace(let ingredientID):
                if let ingredient = ingredient(withID: ingredientID) {
                    IngredientReplacementSheet(
                        ingredientName: ingredient.name,
                        pantryItems: pantryListItems,
                        groceryItems: groceryItems,
                        onSelect: { candidate in
                            pendingIngredientReplacement = PendingIngredientReplacement(
                                ingredientID: ingredientID,
                                candidate: candidate
                            )
                        }
                    )
                    .forceLightStatusBar()
                }
            case .quantity(let ingredientID):
                if let ingredient = ingredient(withID: ingredientID) {
                    IngredientQuantitySheet(ingredient: ingredient) { newQuantity in
                        ingredient.quantity = newQuantity
                        try? modelContext.save()
                    }
                    .forceLightStatusBar()
                }
            case .state(let ingredientID):
                if let ingredient = ingredient(withID: ingredientID) {
                    IngredientStateSheet(ingredient: ingredient) { newState in
                        ingredient.preparationState = newState
                        try? modelContext.save()
                    }
                    .forceLightStatusBar()
                }
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $previewSelection) { selection in
            PreparationMediaPreviewView(
                mediaItems: sortedPreparationMedia,
                selectedMediaID: selection.id,
                onClose: { previewSelection = nil }
            )
            .forceLightStatusBar()
        }
        #else
        .sheet(item: $previewSelection) { selection in
            PreparationMediaPreviewView(
                mediaItems: sortedPreparationMedia,
                selectedMediaID: selection.id,
                onClose: { previewSelection = nil }
            )
            .forceLightStatusBar()
        }
        #endif
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, Self.deviceTopSafeAreaInset())

            ZStack(alignment: .bottomLeading) {
                heroBackgroundImage(
                    pageWidth: proxy.size.width,
                    topInset: topInset
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openPreferredPreparationMedia()
                    }
                    .overlay {
                        if recipe.imageData == nil {
                            Color.black.opacity(0.32)
                        }
                    }

                heroTextBackdrop(
                    pageWidth: proxy.size.width,
                    topInset: topInset
                )

                VStack(alignment: .leading, spacing: 14) {
                    heroSummaryContent

                    Button {
                        showCookingMode = true
                    } label: {
                        Label("Começar a cozinhar", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if #available(iOS 26, macOS 26, *) {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 72)
            }
            .frame(width: proxy.size.width, height: heroHeight, alignment: .bottomLeading)
        }
        .frame(height: heroHeight)
    }

    private var heroSummaryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(recipe.name)
                .font(.custom("Bricolage Grotesque", size: heroTitleFontSize, relativeTo: .largeTitle).bold())
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.76)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.9))
                .frame(width: 92, height: 3)

            if !recipe.descriptionText.isEmpty {
                Text(recipe.descriptionText)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(3)
            }

            if !heroMetadataItems.isEmpty {
                heroMetadataRow
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openPreferredPreparationMedia()
        }
    }

    private func heroTextBackdrop(
        pageWidth: CGFloat,
        topInset: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("recipe-detail-scroll")).minY
            let pullDown = max(minY, 0)
            let baseHeight = proxy.size.height + topInset
            let stretchedHeight = baseHeight + pullDown

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: pageWidth, height: stretchedHeight, alignment: .bottom)
            .offset(y: -(pullDown + topInset))
        }
        .frame(width: pageWidth, height: heroHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func heroBackgroundImage(
        pageWidth: CGFloat,
        topInset: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("recipe-detail-scroll")).minY
            let pullDown = max(minY, 0)
            let baseHeight = proxy.size.height + topInset
            let stretchedHeight = baseHeight + pullDown
            let placeholderSources = sortedIngredients
                .prefix(10)
                .map(RecipePlaceholderIconSource.init)

            Group {
                RecipeThumbnail(recipe: recipe, maxPixel: 1600) {
                    RecipeImagePlaceholderCompact(iconSources: placeholderSources)
                }
            }
            .frame(width: pageWidth, height: stretchedHeight, alignment: .bottom)
            .offset(y: -(pullDown + topInset))
        }
        .frame(width: pageWidth, height: heroHeight)
    }

    private static func deviceTopSafeAreaInset() -> CGFloat {
        #if os(iOS)
        let inset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
            .first?
            .safeAreaInsets.top
        return inset ?? 44
        #else
        return 0
        #endif
    }

    private func openPreparationMedia(_ media: RecipePreparationMedia) {
        previewSelection = PreparationMediaSelection(id: media.id)
    }

    private func openPreferredPreparationMedia() {
        guard let previewMedia = preferredPreviewMedia else { return }
        openPreparationMedia(previewMedia)
    }

    private func openExternalURL(_ url: URL) {
        openURL(url)
    }

    private var heroMetadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(heroMetadataItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.caption.weight(.semibold))
                        Text(item.text)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 36) {
            // Ingredients
            if !sortedIngredients.isEmpty {
                ingredientsSection
            }

            // Utensils
            if !(recipe.requiredUtensils ?? []).isEmpty, settings?.showUtensils == true {
                utensilsSection
            }

            // Steps
            if !sortedSteps.isEmpty {
                stepsSection
            }

            if hasPreparationMedia {
                preparationMediaSection
            }

            // Nutrição
            if hasNutritionInfo {
                nutritionSection
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, contentTopPadding)
        .padding(.bottom, contentBottomPadding)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 30, bottomLeading: 0, bottomTrailing: 0, topTrailing: 30),
                style: .continuous
            )
            .fill(mainAreaColor)
            .shadow(color: Color.black.opacity(0.12), radius: 26, x: 0, y: -8)
        }
        #if os(iOS)
        .overlay {
            SavoriaLuminousBorder(accent: coverAccent, cornerRadius: 30, topCornersOnly: true)
        }
        #endif
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if hasPreparationMedia, let previewMedia = preferredPreviewMedia {
                    Button {
                        openPreparationMedia(previewMedia)
                    } label: {
                        Image(systemName: mediaHeroActionIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: floatingHeroActionSize, height: floatingHeroActionSize)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if #available(iOS 26, macOS 26, *) {
                            Circle()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: Circle())
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .accessibilityLabel(mediaHeroActionAccessibilityLabel)
                }

                if let externalURL {
                    Button {
                        openExternalURL(externalURL)
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: floatingHeroActionSize, height: floatingHeroActionSize)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if #available(iOS 26, macOS 26, *) {
                            Circle()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: Circle())
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .accessibilityLabel(String(localized: "Abrir receita na web"))
                }

                Button {
                    recipe.isFavorite.toggle()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(recipe.isFavorite ? .red : .primary)
                        .frame(width: floatingHeroActionSize, height: floatingHeroActionSize)
                }
                .buttonStyle(.plain)
                .background {
                    if #available(iOS 26, macOS 26, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: Circle())
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .accessibilityLabel(favoriteHeroActionAccessibilityLabel)
            }
            .padding(.trailing, 18)
            .offset(y: -(floatingHeroActionSize / 2))
        }
    }

    // MARK: - Ingredients

    /// Multiplicador aplicado a quantidades/nutrição quando o usuário ajusta as porções.
    private var portionMultiplier: Double {
        let original = max(recipe.servings, 1)
        let target = max(displayServings, 1)
        return Double(target) / Double(original)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ingredientes")
                .font(.sectionTitle)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(ingredientGroups.enumerated()), id: \.offset) { groupIndex, group in
                    if let section = group.section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title.isEmpty ? "Seção" : section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if !section.subtitle.isEmpty {
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, groupIndex == 0 ? 10 : 12)
                        .padding(.bottom, group.ingredients.isEmpty ? 10 : 8)

                        if !group.ingredients.isEmpty {
                            ItemListDivider()
                                .padding(.horizontal, 14)
                        }
                    }

                    ForEach(Array(group.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        ingredientRowView(for: ingredient)

                        let hasNextIngredientInGroup = index < group.ingredients.count - 1
                        let hasLaterGroupIngredients = ingredientGroups.dropFirst(groupIndex + 1).contains { !$0.ingredients.isEmpty }
                        if hasNextIngredientInGroup || hasLaterGroupIngredients {
                            ItemListDivider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
            .background(detailSurfaceColor, in: .rect(cornerRadius: 18))

            HStack(alignment: .center, spacing: 12) {
                portionsStepper

                Button {
                    addAllIngredientsToGrocery()
                } label: {
                    Label(
                        hasMissingIngredientsInGrocery ? "Adicionar todos em Mercado" : "Todos já adicionados",
                        systemImage: hasMissingIngredientsInGrocery ? "cart.badge.plus" : "checkmark.circle"
                    )
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.medium))
                .foregroundStyle(hasMissingIngredientsInGrocery ? .secondary : .tertiary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(detailSurfaceColor, in: .capsule)
                .disabled(!hasMissingIngredientsInGrocery)
            }
        }
    }

    @ViewBuilder
    private func ingredientRowView(for ingredient: RecipeIngredient) -> some View {
        let isAvailable = ingredientIsAvailable(ingredient)
        let isInGrocery = ingredientIsInGrocery(ingredient)

        HStack(spacing: 12) {
            IconImage(
                name: ingredient.name,
                iconFileName: resolvedIngredientIconName(for: ingredient),
                fallbackSymbol: "leaf",
                showBalloon: true,
                balloonColor: colorScheme == .dark ? Color(red: 0x19 / 255.0, green: 0x19 / 255.0, blue: 0x1A / 255.0) : .white
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(ingredient.name).fontWeight(.semibold))\(ingredient.formattedState.isEmpty ? Text("") : Text(" \(ingredient.formattedState)"))")
                    .font(.subheadline)

                if isAvailable {
                    Text("Disponível na despensa")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if isInGrocery {
                    Text("Já adicionado ao mercado")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let scaledQty = scaledQuantityText(for: ingredient), !scaledQty.isEmpty {
                Text(scaledQty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 64, alignment: .trailing)
            }

            NeutralItemActionButton(systemImage: isInGrocery ? "checkmark" : "cart.badge.plus") {
                guard !isInGrocery else { return }
                addIngredientToGrocery(ingredient)
            }
            .opacity(isInGrocery ? 0.7 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            openIngredientItem(ingredient)
        }
        .contextMenu {
            Button(
                isInGrocery ? "Já adicionado ao Mercado" : "Adicionar ao Mercado",
                systemImage: isInGrocery ? "checkmark.circle" : "cart.badge.plus"
            ) {
                guard !isInGrocery else { return }
                addIngredientToGrocery(ingredient)
            }
            .disabled(isInGrocery)
            Button("Adicionar à Despensa", systemImage: "refrigerator") {
                addIngredientToPantry(ingredient)
            }
            Button("Trocar ingrediente", systemImage: "arrow.triangle.2.circlepath") {
                ingredientEditorSheet = .replace(ingredient.id)
            }
            Button("Alterar quantidade", systemImage: "sum") {
                ingredientEditorSheet = .quantity(ingredient.id)
            }
            Button("Alterar estado", systemImage: "slider.horizontal.3") {
                ingredientEditorSheet = .state(ingredient.id)
            }
            Button("Remover ingrediente", systemImage: "trash", role: .destructive) {
                removeIngredient(ingredient)
            }
            if ingredientIsAvailable(ingredient) {
                Button("Já está disponível", systemImage: "checkmark.circle") { }
            }
        }
    }

    /// Retorna a quantidade exibida aplicando o multiplicador de porção quando aplicável.
    private func scaledQuantityText(for ingredient: RecipeIngredient) -> String? {
        let m = portionMultiplier
        let unit = ingredient.unit.trimmingCharacters(in: .whitespaces)

        if let qty = ingredient.quantity, qty > 0 {
            let scaled = IngredientQuantityScaler.formatNumber(qty * m)
            if unit.isEmpty {
                return scaled
            }
            return "\(scaled) \(unit)"
        }

        // Sem quantidade numérica armazenada: mantém o `formattedQuantity` original
        // (não tenta escalar texto livre para evitar resultados confusos).
        let original = ingredient.formattedQuantity
        return original.isEmpty ? nil : original
    }

    // MARK: - Portions stepper

    private var portionsStepper: some View {
        HStack(spacing: 8) {
            Button {
                if displayServings > 1 {
                    displayServings -= 1
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(displayServings > 1 ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(displayServings <= 1)

            HStack(spacing: 4) {
                Text("\(displayServings)")
                    .font(.headline.monospacedDigit())
                Text(displayServings == 1 ? "porção" : "porções")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)

            Button {
                if displayServings < 64 {
                    displayServings += 1
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(displayServings < 64 ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(displayServings >= 64)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(detailSurfaceColor, in: .capsule)
    }

    // MARK: - Nutrition

    /// `true` quando há ao menos um valor nutricional para mostrar.
    private var hasNutritionInfo: Bool {
        recipe.calories != nil
            || recipe.proteinG != nil
            || recipe.carbsG != nil
            || recipe.fatG != nil
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nutrição")
                    .font(.sectionTitle)
                if recipe.nutritionEstimated == true {
                    Text("estimada")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill).opacity(0.7), in: .capsule)
                }
                Spacer()
                Text(displayServings == 1 ? "por porção" : "para \(displayServings) porções")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                if let kcal = recipe.calories {
                    nutritionTile(
                        title: "Calorias",
                        value: formatNutrition(Double(kcal), suffix: " kcal", isInt: true),
                        accent: .orange,
                        icon: "flame.fill"
                    )
                }
                if let p = recipe.proteinG {
                    nutritionTile(
                        title: "Proteínas",
                        value: formatNutrition(p, suffix: " g"),
                        accent: .red,
                        icon: "fish.fill"
                    )
                }
                if let c = recipe.carbsG {
                    nutritionTile(
                        title: "Carboidratos",
                        value: formatNutrition(c, suffix: " g"),
                        accent: .yellow,
                        icon: "leaf.fill"
                    )
                }
                if let f = recipe.fatG {
                    nutritionTile(
                        title: "Gorduras",
                        value: formatNutrition(f, suffix: " g"),
                        accent: .purple,
                        icon: "drop.fill"
                    )
                }
            }

            if recipe.fiberG != nil || recipe.sugarG != nil || recipe.sodiumMg != nil {
                HStack(spacing: 10) {
                    if let fiber = recipe.fiberG {
                        nutritionMicroChip(label: "Fibras", value: formatNutrition(fiber, suffix: " g"))
                    }
                    if let sugar = recipe.sugarG {
                        nutritionMicroChip(label: "Açúcares", value: formatNutrition(sugar, suffix: " g"))
                    }
                    if let sodium = recipe.sodiumMg {
                        nutritionMicroChip(label: "Sódio", value: formatNutrition(sodium, suffix: " mg", isInt: true))
                    }
                }
            }
        }
    }

    private func nutritionTile(title: String, value: String, accent: Color, icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(detailSurfaceColor, in: .rect(cornerRadius: 14))
    }

    private func nutritionMicroChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill).opacity(0.5), in: .capsule)
    }

    /// Formata um valor nutricional aplicando o multiplicador de porção.
    private func formatNutrition(_ value: Double, suffix: String, isInt: Bool = false) -> String {
        let scaled = value * portionMultiplier
        if isInt {
            return "\(Int(scaled.rounded()))\(suffix)"
        }
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.current().formattingLocale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        let str = formatter.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
        return "\(str)\(suffix)"
    }

    // MARK: - Utensils

    private var utensilsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Utensílios")
                .font(.sectionTitle)
                .padding(.top, 8)

            ForEach(recipe.requiredUtensils ?? [], id: \.self) { utensil in
                let isAvailable = utensilIsAvailable(utensil)
                let matchingUtensil = utensilItems.first(where: { sameName($0.name, utensil) })
                let iconName = matchingUtensil?.resolvedIconName()
                    ?? ItemDatabase.shared.exactMatch(for: utensil)?.nomeDoArquivo

                HStack(spacing: 12) {
                    IconImage(
                        name: utensil,
                        iconFileName: iconName,
                        fallbackSymbol: "fork.knife",
                        showBalloon: true,
                        balloonColor: .white
                    )

                    Text(utensil)
                        .font(.subheadline)

                    Spacer()

                    Button {
                        toggleUtensilAvailability(utensil)
                    } label: {
                        Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isAvailable ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    openUtensilItem(utensil)
                }
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Modo de Preparo")
                .font(.sectionTitle)
                .padding(.top, 8)

            ForEach(sortedSteps) { step in
                HStack(alignment: .top, spacing: 14) {
                    // Step number circle
                    Text("\(step.order)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(PageTheme.recipes.accentColor, in: .circle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.instruction)
                            .font(.subheadline)

                        if let duration = step.durationMinutes, duration > 0 {
                            Label("\(duration) min", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var preparationMediaSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text("Mídias da Receita")
                    .font(.sectionTitle)

                Text(preparationMediaCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: .capsule)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)

            if sortedPreparationMedia.count == 1, let media = sortedPreparationMedia.first {
                Button {
                    openPreparationMedia(media)
                } label: {
                    preparationMediaCard(for: media, width: nil, height: 188)
                }
                .buttonStyle(.plain)
            } else {
                PreparationMediaDeckView(
                    mediaItems: sortedPreparationMedia,
                    onSelect: { media in
                        openPreparationMedia(media)
                    }
                )
            }
        }
    }

    private func preparationMediaCard(for media: RecipePreparationMedia, width: CGFloat?, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            RecipeMediaCardArtworkView(media: media)

            if media.mediaType == .video {
                RecipeMediaPlayButton(size: 94)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Media Count Overlay
            Text(preparationMediaCountLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            LinearGradient(
                colors: [Color.black.opacity(0.48), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            HStack(spacing: 8) {
                Image(systemName: media.mediaType == .photo ? "photo" : "video.fill")
                    .font(.caption.weight(.bold))
                Text(media.mediaType == .photo ? "Foto" : "Vídeo")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.5), in: .capsule)
            .padding(16)
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func ingredientIsAvailable(_ ingredient: RecipeIngredient) -> Bool {
        let normalizedIngredient = ingredient.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return pantryNames.contains(where: { pantry in
            pantry == normalizedIngredient || pantry.contains(normalizedIngredient) || normalizedIngredient.contains(pantry)
        })
    }

    private func ingredientIsInGrocery(_ ingredient: RecipeIngredient) -> Bool {
        groceryItems.contains { sameName($0.name, ingredient.name) }
    }

    private func utensilIsAvailable(_ utensilName: String) -> Bool {
        utensilItems.contains { sameName($0.name, utensilName) }
    }

    private func addAllIngredientsToGrocery() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            for ingredient in sortedIngredients {
                if !ingredientIsInGrocery(ingredient) {
                    addIngredientToGrocery(ingredient)
                }
            }
        }
    }

    private func addIngredientToGrocery(_ ingredient: RecipeIngredient) {
        let category = resolvedListCategory(for: ingredient.name)
        if let existingItem = groceryItems.first(where: { sameName($0.name, ingredient.name) && $0.category == category }) {
            applyQuantity(from: ingredient, to: existingItem)
        } else {
            let item = UnifiedItem(
                name: ingredient.name,
                category: category,
                quantity: ingredient.quantity,
                unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                iconName: ItemDatabase.shared.preferredMatch(for: ingredient.name)?.nomeDoArquivo,
                isPantry: false,
                isGrocery: true,
                isUtensil: false,
                grocerySortOrder: (groceryItems.map(\.grocerySortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func toggleUtensilAvailability(_ utensilName: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            let existingItems = utensilItems.filter { sameName($0.name, utensilName) }

            if existingItems.isEmpty {
                let item = UnifiedItem(
                    name: utensilName,
                    category: resolvedUtensilCategory(for: utensilName),
                    iconName: ItemDatabase.shared.exactMatch(for: utensilName)?.nomeDoArquivo,
                    isPantry: false,
                    isGrocery: false,
                    isUtensil: true,
                    utensilSortOrder: (utensilItems.map(\.utensilSortOrder).max() ?? -1) + 1
                )
                modelContext.insert(item)
            } else {
                for existing in existingItems {
                    if existing.isPantry || existing.isGrocery || existing.isReserve {
                        existing.isUtensil = false
                    } else {
                        modelContext.delete(existing)
                    }
                }
            }
        }

        try? modelContext.save()
    }

    private func addIngredientToPantry(_ ingredient: RecipeIngredient) {
        let category = resolvedListCategory(for: ingredient.name)
        if let existingItem = pantryListItems.first(where: { sameName($0.name, ingredient.name) && $0.category == category }) {
            applyQuantity(from: ingredient, to: existingItem)
        } else {
            let item = UnifiedItem(
                name: ingredient.name,
                category: category,
                quantity: ingredient.quantity,
                unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                iconName: ItemDatabase.shared.preferredMatch(for: ingredient.name)?.nomeDoArquivo,
                isPantry: true,
                isGrocery: false,
                isUtensil: false,
                pantrySortOrder: (pantryListItems.map(\.pantrySortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func resolvedListCategory(for ingredientName: String) -> String {
        if let pantryMatch = pantryListItems.first(where: { sameName($0.name, ingredientName) }) {
            return pantryMatch.category
        }
        if let groceryMatch = groceryItems.first(where: { sameName($0.name, ingredientName) }) {
            return groceryMatch.category
        }
        if let databaseCategory = ItemDatabase.shared.preferredMatch(for: ingredientName)?.categoria,
           allCategories.contains(where: { $0.type == .pantry && sameName($0.name, databaseCategory) }) {
            return databaseCategory
        }
        return allCategories.contains(where: { $0.type == .pantry && sameName($0.name, recipe.category) })
            ? recipe.category
            : defaultListCategory
    }

    private func resolvedIngredientIconName(for ingredient: RecipeIngredient) -> String? {
        if let iconName = ingredient.iconName, !iconName.isEmpty {
            return iconName
        }

        let trimmedName = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return ItemDatabase.shared.preferredMatch(for: trimmedName)?.nomeDoArquivo
    }

    private func resolvedUtensilCategory(for utensilName: String) -> String {
        if let existingMatch = utensilItems.first(where: { sameName($0.name, utensilName) }) {
            return existingMatch.category
        }

        if let databaseCategory = ItemDatabase.shared.exactMatch(for: utensilName)?.categoria,
           allCategories.contains(where: { $0.type == .utensil && sameName($0.name, databaseCategory) }) {
            return databaseCategory
        }

        return defaultUtensilCategory
    }

    private func openIngredientItem(_ ingredient: RecipeIngredient) {
        if let pantryItem = pantryListItems.first(where: { sameName($0.name, ingredient.name) }) {
            editingItem = UnifiedItemSelection(id: pantryItem.id)
            return
        }

        if let groceryItem = groceryItems.first(where: { sameName($0.name, ingredient.name) }) {
            editingItem = UnifiedItemSelection(id: groceryItem.id)
        }
    }

    private func openUtensilItem(_ utensilName: String) {
        if let item = utensilItems.first(where: { sameName($0.name, utensilName) }) {
            editingItem = UnifiedItemSelection(id: item.id)
        }
    }

    private func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ==
        rhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func applyQuantity(from ingredient: RecipeIngredient, to item: UnifiedItem) {
        if let quantity = ingredient.quantity {
            item.quantity = (item.quantity ?? 0) + quantity
        } else if item.quantity == nil {
            item.quantity = 1
        }
        if !ingredient.unit.isEmpty {
            item.unit = ingredient.unit
        }
    }

    private func ingredient(withID id: UUID) -> RecipeIngredient? {
        sortedIngredients.first(where: { $0.id == id })
    }

    private func removeIngredient(_ ingredient: RecipeIngredient) {
        modelContext.delete(ingredient)

        for (index, remaining) in sortedIngredients.filter({ $0.id != ingredient.id }).enumerated() {
            remaining.sortOrder = index
        }

        try? modelContext.save()
    }

    private func applyPendingIngredientReplacementIfNeeded() {
        guard let pendingIngredientReplacement else { return }
        let pending = pendingIngredientReplacement
        self.pendingIngredientReplacement = nil

        guard let ingredient = ingredient(withID: pending.ingredientID) else {
            NSLog("Ingredient replacement skipped because ingredient %@ is no longer available.", pending.ingredientID.uuidString)
            return
        }

        do {
            try applyIngredientReplacement(pending.candidate, to: ingredient)
        } catch {
            NSLog(
                "Ingredient replacement failed for ingredient %@: %@",
                ingredient.id.uuidString,
                String(describing: error)
            )
        }
    }

    private func applyIngredientReplacement(_ candidate: IngredientReplacementCandidate, to ingredient: RecipeIngredient) throws {
        ingredient.name = candidate.name
        ingredient.iconName = candidate.iconName

        if ingredient.quantity == nil {
            ingredient.quantity = candidate.quantity
        }

        if ingredient.unit.isEmpty, let unit = candidate.unit, !unit.isEmpty {
            ingredient.unit = unit
        }

        try modelContext.save()
    }
}

private struct HeroMetadataItem: Identifiable {
    let id: String
    let systemImage: String
    let text: String

    init(systemImage: String, text: String) {
        self.id = "\(systemImage)-\(text)"
        self.systemImage = systemImage
        self.text = text
    }
}

private enum IngredientEditorSheet: Identifiable {
    case replace(UUID)
    case quantity(UUID)
    case state(UUID)

    var id: String {
        switch self {
        case .replace(let id):
            return "replace-\(id.uuidString)"
        case .quantity(let id):
            return "quantity-\(id.uuidString)"
        case .state(let id):
            return "state-\(id.uuidString)"
        }
    }
}

private struct IngredientReplacementCandidate: Identifiable {
    let id: String
    let name: String
    let category: String
    let iconName: String?
    let quantity: Double?
    let unit: String?
    let listTypes: [SearchResultType]
}

private struct PendingIngredientReplacement {
    let ingredientID: UUID
    let candidate: IngredientReplacementCandidate
}

/// One displayable group of ingredients in `RecipeDetailView`. A `nil` section
/// represents the implicit top (unsectioned) group.
private struct IngredientDisplayGroup {
    let section: RecipeIngredientSection?
    let ingredients: [RecipeIngredient]
}

private enum IngredientReplacementSourceFilter: String, CaseIterable, Identifiable {
    case all
    case grocery
    case pantry

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return String(localized: "Ambos")
        case .grocery:
            return String(localized: "Mercado")
        case .pantry:
            return String(localized: "Despensa")
        }
    }

    func matches(_ candidate: IngredientReplacementCandidate) -> Bool {
        switch self {
        case .all:
            return true
        case .grocery:
            return candidate.listTypes.contains(.groceryItem)
        case .pantry:
            return candidate.listTypes.contains(.pantryItem)
        }
    }
}

private struct IngredientReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let ingredientName: String
    let pantryItems: [UnifiedItem]
    let groceryItems: [UnifiedItem]
    let onSelect: (IngredientReplacementCandidate) -> Void

    @State private var query = ""
    @State private var sourceFilter: IngredientReplacementSourceFilter = .all

    private var candidates: [IngredientReplacementCandidate] {
        var grouped: [String: IngredientReplacementCandidate] = [:]

        for item in pantryItems {
            merge(item: item, as: .pantryItem, into: &grouped)
        }

        for item in groceryItems {
            merge(item: item, as: .groceryItem, into: &grouped)
        }

        let trimmed = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return grouped.values
            .filter { candidate in
                guard sourceFilter.matches(candidate) else { return false }
                guard !trimmed.isEmpty else { return true }
                let haystack = [candidate.name, candidate.category]
                    .joined(separator: " ")
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
                return haystack.contains(trimmed)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Substituir \(ingredientName) por um item já existente na sua Despensa ou Mercado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filtrar origem")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Filtrar origem", selection: $sourceFilter) {
                            ForEach(IngredientReplacementSourceFilter.allCases) { filter in
                                Text(filter.title)
                                    .tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(16)

                Divider()

                if candidates.isEmpty {
                    ContentUnavailableView(
                        "Nenhum ingrediente encontrado",
                        systemImage: "magnifyingglass",
                        description: Text("Tente outro termo de busca.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconImage(name: candidate.name, iconFileName: candidate.iconName, fallbackSymbol: "leaf", showBalloon: true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    if !candidate.category.isEmpty {
                                        Text(candidate.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    ForEach(candidate.listTypes, id: \.rawValue) { type in
                                        IngredientListTag(type: type)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .modalNavigationTitle(String(localized: "Trocar ingrediente"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar ingrediente da sua lista"
            )
            #else
            .searchable(text: $query, prompt: "Buscar ingrediente da sua lista")
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }

    private func merge(item: UnifiedItem, as type: SearchResultType, into grouped: inout [String: IngredientReplacementCandidate]) {
        let normalized = UnifiedItem.normalizedName(item.name)
        guard !normalized.isEmpty else { return }

        if var existing = grouped[normalized] {
            guard !existing.listTypes.contains(type) else { return }
            existing = IngredientReplacementCandidate(
                id: existing.id,
                name: existing.name,
                category: existing.category,
                iconName: existing.iconName,
                quantity: existing.quantity,
                unit: existing.unit,
                listTypes: existing.listTypes + [type]
            )
            grouped[normalized] = existing
            return
        }

        grouped[normalized] = IngredientReplacementCandidate(
            id: normalized,
            name: item.name,
            category: item.category,
            iconName: item.iconName,
            quantity: item.quantity,
            unit: item.unit,
            listTypes: [type]
        )
    }
}

private struct IngredientQuantitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let ingredient: RecipeIngredient
    let onSave: (Double?) -> Void

    @State private var quantityText: String

    init(ingredient: RecipeIngredient, onSave: @escaping (Double?) -> Void) {
        self.ingredient = ingredient
        self.onSave = onSave
        if let quantity = ingredient.quantity {
            let formatted = quantity.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", quantity)
                : String(quantity)
            _quantityText = State(initialValue: formatted)
        } else {
            _quantityText = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quantidade") {
                    TextField("Ex.: 2.5", text: $quantityText)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif

                    if !ingredient.unit.isEmpty {
                        Text("Unidade atual: \(ingredient.unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .modalNavigationTitle(String(localized: "Alterar quantidade"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvar") {
                        let normalized = quantityText
                            .replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let quantity = normalized.isEmpty ? nil : Double(normalized)
                        onSave(quantity)
                        dismiss()
                    }
                }
                #else
                ToolbarItem {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem {
                    Button("Salvar") {
                        let normalized = quantityText
                            .replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let quantity = normalized.isEmpty ? nil : Double(normalized)
                        onSave(quantity)
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

private struct IngredientStateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let ingredient: RecipeIngredient
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSave("")
                    dismiss()
                } label: {
                    HStack {
                        Text("Sem estado")
                        Spacer()
                        if ingredient.preparationState.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(PageTheme.recipes.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(RecipeOptionCatalog.stateOptions, id: \.fullName) { option in
                    Button {
                        onSave(option.fullName)
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.menuLabel)
                            Spacer()
                            if ingredient.preparationState == option.fullName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(PageTheme.recipes.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .modalNavigationTitle(String(localized: "Alterar estado"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

private struct IngredientListTag: View {
    let type: SearchResultType

    private var title: String {
        switch type {
        case .pantryItem:
            return String(localized: "Despensa")
        case .groceryItem:
            return String(localized: "Mercado")
        default:
            return String(localized: "Lista")
        }
    }

    private var icon: String {
        switch type {
        case .pantryItem:
            return "refrigerator"
        case .groceryItem:
            return "cart"
        default:
            return "circle"
        }
    }

    private var tint: Color {
        switch type {
        case .pantryItem:
            return Color(red: 160 / 255, green: 58 / 255, blue: 19 / 255)
        case .groceryItem:
            return Color(red: 37 / 255, green: 79 / 255, blue: 34 / 255)
        default:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct PreparationMediaDeckView: View {
    let mediaItems: [RecipePreparationMedia]
    let onSelect: (RecipePreparationMedia) -> Void

    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, media in
                Button {
                    onSelect(media)
                } label: {
                    ZStack {
                        ForEach(Array(deckTrailingMedia(for: index).enumerated()), id: \.element.id) { offset, stackedMedia in
                            RecipeMediaDeckCard(
                                media: stackedMedia,
                                depth: offset + 1
                            )
                        }

                        RecipeMediaDeckCard(
                            media: media,
                            depth: 0
                        )
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .frame(height: 214)
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        #endif
        .overlay(alignment: .bottom) {
            #if os(macOS)
            if mediaItems.count > 1 {
                HStack(spacing: 16) {
                    Button {
                        withAnimation { selectedIndex = max(0, selectedIndex - 1) }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIndex == 0)

                    Text("\(selectedIndex + 1)/\(mediaItems.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))

                    Button {
                        withAnimation { selectedIndex = min(mediaItems.count - 1, selectedIndex + 1) }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIndex >= mediaItems.count - 1)
                }
                .padding(.bottom, 4)
            }
            #endif
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: selectedIndex)
    }

    private func deckTrailingMedia(for index: Int) -> [RecipePreparationMedia] {
        guard mediaItems.count > 1 else { return [] }
        let nextIndices = (1...min(2, mediaItems.count - 1)).compactMap { offset -> Int? in
            let candidate = index + offset
            return candidate < mediaItems.count ? candidate : nil
        }
        return nextIndices.map { mediaItems[$0] }.reversed()
    }
}

private struct PreparationMediaSelection: Identifiable {
    let id: UUID
}

private struct RecipeMediaDeckCard: View {
    let media: RecipePreparationMedia
    let depth: Int

    private var mediaCountLabel: String {
        let count = (media.recipe?.preparationMedia ?? []).count
        return count == 1 ? "1 mídia" : "\(count) mídias"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            RecipeMediaCardArtworkView(media: media)

            if media.mediaType == .video {
                RecipeMediaPlayButton(size: 98)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Media Count Overlay
            Text(mediaCountLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            LinearGradient(
                colors: [Color.black.opacity(0.42), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            HStack(spacing: 8) {
                Image(systemName: media.mediaType == .photo ? "photo" : "video.fill")
                    .font(.caption.weight(.bold))
                Text(media.mediaType == .photo ? "Foto" : "Vídeo")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.45), in: .capsule)
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 184)
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .scaleEffect(depth == 0 ? 1 : 1 - (CGFloat(depth) * 0.04), anchor: .center)
        .offset(x: CGFloat(depth) * 14, y: CGFloat(depth) * 2)
        .opacity(depth == 0 ? 1 : max(0.35, 0.78 - (CGFloat(depth) * 0.18)))
        .allowsHitTesting(depth == 0)
    }
}

private struct PreparationMediaPreviewView: View {
    let mediaItems: [RecipePreparationMedia]
    let selectedMediaID: UUID
    let onClose: () -> Void

    @State private var selectedIndex = 0
    @State private var dragOffset: CGFloat = 0

    private var dismissProgress: CGFloat {
        min(max(dragOffset / 240, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(1 - Double(dismissProgress * 0.45))
                    .ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, media in
                        previewPage(for: media, isActive: selectedIndex == index)
                            .tag(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: max(dragOffset, 0))
                .scaleEffect(1 - (dismissProgress * 0.08))
                .simultaneousGesture(dismissDragGesture)

                if mediaItems.count > 1 {
                    VStack {
                        Spacer()

                        mediaDots
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18) + 8)
                    }
                }

                Button {
                    onClose()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.42))

                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.trailing, 16)
            }
            .onAppear {
                if let index = mediaItems.firstIndex(where: { $0.id == selectedMediaID }) {
                    selectedIndex = index
                }
            }
        }
    }

    @ViewBuilder
    private func previewPage(for media: RecipePreparationMedia, isActive: Bool) -> some View {
        switch media.mediaType {
        case .photo:
            if let image = PlatformImage(data: media.data) {
                ZoomablePhotoView(image: image)
                    .background(Color.black)
            } else {
                ContentUnavailableView("Foto indisponível", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        case .video:
            if let url = temporaryFileURL(for: media) {
                FullscreenRecipeVideoView(url: url, isActive: isActive)
            } else {
                ContentUnavailableView("Vídeo indisponível", systemImage: "play.slash")
                    .foregroundStyle(.white)
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let isVerticalDismiss = value.translation.height > 0
                    && abs(value.translation.height) > abs(value.translation.width)

                guard isVerticalDismiss else {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                    return
                }

                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    onClose()
                } else {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func temporaryFileURL(for media: RecipePreparationMedia) -> URL? {
        RecipeMediaLocalAssetStore.fileURL(for: media)
    }

    private var mediaDots: some View {
        HStack(spacing: 8) {
            ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.34))
                    .frame(width: index == selectedIndex ? 8 : 7, height: index == selectedIndex ? 8 : 7)
                    .scaleEffect(index == selectedIndex ? 1 : 0.92)
                    .animation(.smooth(duration: 0.18), value: selectedIndex)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.72), in: .capsule)
    }
}

private struct RecipeMediaCardArtworkView: View {
    let media: RecipePreparationMedia

    @State private var videoThumbnail: PlatformImage?

    private var assetSnapshot: RecipeMediaAssetSnapshot {
        RecipeMediaAssetSnapshot(
            id: media.id,
            data: media.data,
            fileExtension: media.fileExtension,
            isVideo: media.mediaType == .video
        )
    }

    var body: some View {
        ZStack {
            if media.mediaType == .photo, let image = PlatformImage(data: media.data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let videoThumbnail {
                Image(platformImage: videoThumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.88), Color.black.opacity(0.42)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
        }
        .clipped()
        .task(id: media.id) {
            guard assetSnapshot.isVideo else {
                videoThumbnail = nil
                return
            }

            if let thumbnailData = await RecipeMediaThumbnailStore.shared.thumbnailData(for: assetSnapshot),
               !Task.isCancelled,
               let thumbnail = PlatformImage(data: thumbnailData) {
                videoThumbnail = thumbnail
            }
        }
    }
}

private struct RecipeMediaPlayButton: View {
    let size: CGFloat

    var body: some View {
        RecipeMediaGlassCircle(size: size) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.035)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }
}

private struct RecipeMediaGlassCircle<Content: View>: View {
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if #available(iOS 26, macOS 26, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
            }

            content()
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
    }
}

import AVKit
import SwiftUI

// Use AVKit directly for fullscreen to get native controls and better UX
private struct FullscreenRecipeVideoView: View {
    let url: URL
    let isActive: Bool
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .onAppear {
                configurePlayerIfNeeded()
                updatePlaybackState()
            }
            .onChange(of: isActive) { _, _ in
                updatePlaybackState()
            }
            .onDisappear {
                player.pause()
                player.seek(to: .zero)
                player.replaceCurrentItem(with: nil)
                #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                #endif
            }
    }

    private func configurePlayerIfNeeded() {
        if (player.currentItem?.asset as? AVURLAsset)?.url != url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.actionAtItemEnd = .pause
        }

        player.isMuted = false
        player.volume = 1

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func updatePlaybackState() {
        guard player.currentItem != nil else { return }
        if isActive {
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }
}

private struct RecipeMediaAssetSnapshot: Sendable {
    let id: UUID
    let data: Data
    let fileExtension: String
    let isVideo: Bool
}

private actor RecipeMediaThumbnailStore {
    static let shared = RecipeMediaThumbnailStore()

    private var cachedThumbnailData: [UUID: Data] = [:]
    private var pendingTasks: [UUID: Task<Data?, Never>] = [:]

    func thumbnailData(for asset: RecipeMediaAssetSnapshot) async -> Data? {
        guard asset.isVideo else { return nil }

        if let cached = cachedThumbnailData[asset.id] {
            return cached
        }

        if let pending = pendingTasks[asset.id] {
            return await pending.value
        }

        let task = Task.detached(priority: .userInitiated) {
            RecipeMediaThumbnailStore.generateThumbnailData(for: asset)
        }
        pendingTasks[asset.id] = task

        let result = await task.value
        pendingTasks[asset.id] = nil

        if let result {
            cachedThumbnailData[asset.id] = result
        }

        return result
    }

    private static func generateThumbnailData(for asset: RecipeMediaAssetSnapshot) -> Data? {
        guard let url = RecipeMediaLocalAssetStore.fileURL(for: asset) else { return nil }

        let videoAsset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            #if os(iOS)
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
            #else
            let representation = NSBitmapImageRep(cgImage: cgImage)
            return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
            #endif
        } catch {
            return nil
        }
    }
}

private enum RecipeMediaLocalAssetStore {
    private static var cacheDirectory: URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeMediaCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func fileURL(for media: RecipePreparationMedia) -> URL? {
        fileURL(
            for: RecipeMediaAssetSnapshot(
                id: media.id,
                data: media.data,
                fileExtension: media.fileExtension,
                isVideo: media.mediaType == .video
            )
        )
    }

    static func fileURL(for asset: RecipeMediaAssetSnapshot) -> URL? {
        let ext = asset.fileExtension.isEmpty ? defaultExtension(for: asset) : asset.fileExtension
        let url = cacheDirectory
            .appendingPathComponent(asset.id.uuidString)
            .appendingPathExtension(ext)

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try asset.data.write(to: url, options: .atomic)
            } catch {
                return nil
            }
        }

        return url
    }

    private static func defaultExtension(for asset: RecipeMediaAssetSnapshot) -> String {
        asset.isVideo ? "mov" : "jpg"
    }
}

#if os(iOS)
private struct RecipeVideoPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        // `layerClass` guarantees the backing layer is an `AVPlayerLayer`,
        // so the cast is safe by construction. In the impossible event of a
        // mismatch we fall back to an empty layer instead of crashing.
        var playerLayer: AVPlayerLayer {
            if let layer = layer as? AVPlayerLayer {
                return layer
            }
            assertionFailure("Expected AVPlayerLayer backing layer")
            return AVPlayerLayer()
        }
    }
}
#elseif os(macOS)
private struct RecipeVideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.controlsStyle = .none
        nsView.videoGravity = .resizeAspectFill
    }
}
#endif

#if os(iOS)
private struct ScrollViewInsetAdjustmentDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> InsetDisablerView {
        InsetDisablerView(frame: .zero)
    }

    func updateUIView(_ view: InsetDisablerView, context: Context) {
        view.applyToEnclosingScrollView()
    }

    final class InsetDisablerView: UIView {
        private weak var targetScrollView: UIScrollView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyToEnclosingScrollView()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            applyToEnclosingScrollView()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyToEnclosingScrollView()
        }

        func applyToEnclosingScrollView() {
            if let targetScrollView,
               targetScrollView.window != nil,
               isManagedVerticalScrollView(targetScrollView) {
                applyAdjustment(to: targetScrollView)
                return
            }

            var candidate: UIView? = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView,
                   isManagedVerticalScrollView(scrollView) {
                    targetScrollView = scrollView
                    applyAdjustment(to: scrollView)
                    return
                }
                candidate = view.superview
            }
        }

        private func isManagedVerticalScrollView(_ scrollView: UIScrollView) -> Bool {
            let verticalOverflow = scrollView.contentSize.height - scrollView.bounds.height
            let horizontalOverflow = scrollView.contentSize.width - scrollView.bounds.width

            if scrollView.isPagingEnabled {
                return false
            }

            if horizontalOverflow > 6,
               horizontalOverflow > max(verticalOverflow, 0) * 1.2 {
                return false
            }

            if scrollView.alwaysBounceVertical {
                return true
            }

            if scrollView.showsVerticalScrollIndicator,
               !scrollView.showsHorizontalScrollIndicator {
                return true
            }

            return verticalOverflow > 6
        }

        private func applyAdjustment(to scrollView: UIScrollView) {
            if scrollView.contentInsetAdjustmentBehavior != .never {
                scrollView.contentInsetAdjustmentBehavior = .never
            }
            if scrollView.automaticallyAdjustsScrollIndicatorInsets {
                scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            }
            if scrollView.contentInset.top != 0 {
                scrollView.contentInset.top = 0
            }
            if scrollView.verticalScrollIndicatorInsets.top != 0 {
                scrollView.verticalScrollIndicatorInsets.top = 0
            }
        }
    }
}
#else
private struct ScrollViewInsetAdjustmentDisabler: View {
    var body: some View {
        Color.clear
    }
}
#endif

// MARK: - Defensive wrapper: resolve Recipe by UUID and auto-dismiss on delete

/// Container that resolves a `Recipe` by UUID through `@Query` and renders
/// `RecipeDetailView` only while the underlying record exists. When the
/// recipe gets deleted (via AI tool, bulk-delete, dedup, or CloudKit remote
/// change), this wrapper pops itself instead of leaving a view bound to a
/// tombstoned `PersistentModel` — which is what was making SwiftData's
/// autosave/observation timer trap with `brk #0x1` on the main thread.
struct RecipeDetailContainer: View {
    let recipeID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Recipe]
    /// Tracks whether we ever saw the recipe. Only pop after we've seen it,
    /// otherwise a freshly-imported recipe that hasn't propagated to `@Query`
    /// yet would flash-dismiss before the detail can render.
    @State private var didResolveOnce = false

    init(recipeID: UUID) {
        self.recipeID = recipeID
        _matches = Query(filter: #Predicate<Recipe> { $0.id == recipeID })
    }

    var body: some View {
        Group {
            if let recipe = matches.first {
                RecipeDetailView(recipe: recipe)
                    .onAppear { didResolveOnce = true }
            } else if didResolveOnce {
                // Recipe was deleted while we were on screen: pop cleanly.
                Color.clear
                    .onAppear {
                        Task { @MainActor in
                            dismiss()
                        }
                    }
            } else {
                // Not-yet-resolved (e.g. just inserted, @Query not refreshed).
                // Show a tiny placeholder; will re-render as `@Query` updates.
                Color.clear
            }
        }
    }
}
