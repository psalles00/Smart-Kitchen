import SwiftUI
import SwiftData
import AVKit
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct RecipeDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.grocerySortOrder) private var groceryItems: [UnifiedItem]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.pantrySortOrder) private var pantryListItems: [UnifiedItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Query private var settingsArray: [AppSettings]
    @Query(filter: #Predicate<UnifiedItem> { $0.isUtensil }, sort: \UnifiedItem.name) private var utensilItems: [UnifiedItem]
    @Bindable var recipe: Recipe
    @State private var showCookingMode = false
    @State private var showEditRecipe = false
    @State private var previewSelection: PreparationMediaSelection?
    @State private var editingItem: UnifiedItem?
    @State private var ingredientEditorSheet: IngredientEditorSheet?
    @State private var pendingIngredientReplacement: PendingIngredientReplacement?
    @State private var showMoreActions = false

    private let heroHeight: CGFloat = 580
    private let contentOverlap: CGFloat = 34
    private let floatingHeroActionSize: CGFloat = 62

    private var sortedIngredients: [RecipeIngredient] {
        (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedIngredientSections: [RecipeIngredientSection] {
        (recipe.ingredientSections ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Ordered groups for display: the first group (if any unsectioned
    /// ingredients exist) has no header; subsequent groups are each section
    /// followed by their ingredients.
    private var ingredientGroups: [IngredientDisplayGroup] {
        let sections = sortedIngredientSections
        let all = sortedIngredients
        var groups: [IngredientDisplayGroup] = []

        let unsectioned = all.filter { $0.sectionID == nil }
        if !unsectioned.isEmpty {
            groups.append(IngredientDisplayGroup(section: nil, ingredients: unsectioned))
        }
        for section in sections {
            let items = all.filter { $0.sectionID == section.id }
            // Always show the section header, even when empty, so the user
            // can see the grouping they defined.
            groups.append(IngredientDisplayGroup(section: section, ingredients: items))
        }
        return groups
    }

    private var sortedSteps: [RecipeStep] {
        (recipe.steps ?? []).sorted { $0.order < $1.order }
    }

    private var sortedPreparationMedia: [RecipePreparationMedia] {
        (recipe.preparationMedia ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var settings: AppSettings? { settingsArray.first }

    private var mainAreaColor: Color {
        colorScheme == .dark
            ? Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)
            : Color.white
    }

    private var detailSurfaceColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)
    }

    private var contentTopPadding: CGFloat { 34 }
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

        items.append(HeroMetadataItem(systemImage: recipe.difficulty.icon, text: recipe.difficulty.rawValue))

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
        pantryItems.map {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImage
                content
                    .padding(.top, -contentOverlap)
                    .zIndex(1)
            }
        }
        .coordinateSpace(name: "recipe-detail-scroll")
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
                    showMoreActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mais opções")
                .popover(
                    isPresented: $showMoreActions,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    moreActionsPopover
                        .presentationCompactAdaptation(.popover)
                        .presentationBackground(.clear)
                }
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
                EditRecipeView(recipe: recipe)
            }
            .forceLightStatusBar()
        }
        .sheet(item: $editingItem) { item in
            ItemDetailView(mode: .edit(item))
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
        .sheet(item: $previewSelection) { selection in
            PreparationMediaPreviewView(
                mediaItems: sortedPreparationMedia,
                selectedMediaID: selection.id
            )
            .forceLightStatusBar()
        }
    }

    #if os(iOS)
    private var moreActionsPopover: some View {
        VStack(spacing: 10) {
            moreActionsPopoverButton(title: "Editar", systemImage: "pencil") {
                showEditRecipe = true
            }

            moreActionsPopoverButton(
                title: recipe.isFavorite ? "Desfavoritar" : "Favoritar",
                systemImage: recipe.isFavorite ? "heart.slash" : "heart"
            ) {
                recipe.isFavorite.toggle()
            }

            if let externalURL {
                moreActionsPopoverButton(title: "Abrir no navegador", systemImage: "globe") {
                    openExternalURL(externalURL)
                }
            }
        }
        .padding(12)
        .frame(width: 248)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.55), lineWidth: 1)
                }
        }
    }

    private func moreActionsPopoverButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showMoreActions = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(colorScheme == .dark ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            }
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("recipe-detail-scroll")).minY
            let stretch = max(minY, 0)

            ZStack(alignment: .bottomLeading) {
                heroBackgroundImage(in: proxy, minY: minY)
                    .overlay {
                        if recipe.imageData == nil {
                            Color.black.opacity(0.32)
                        }
                    }

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
                .padding(.bottom, 92)
            }
            .frame(width: proxy.size.width, height: heroHeight + stretch)
            .offset(y: stretch > 0 ? -stretch : 0)
            .clipped()
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private func heroBackgroundImage(in proxy: GeometryProxy, minY: CGFloat) -> some View {
        let stretch = max(minY, 0)
        let upwardScroll = max(-minY, 0)
        let parallaxOffset = minY > 0 ? 0 : upwardScroll * 0.18
        let parallaxHeight = heroHeight + stretch + (upwardScroll * 0.22)

        Group {
            if let data = recipe.imageData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RecipeImagePlaceholder(ingredients: sortedIngredients)
            }
        }
        .frame(width: proxy.size.width, height: parallaxHeight)
        .offset(y: parallaxOffset)
        .clipped()
    }

    private func openExternalURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
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
        VStack(alignment: .leading, spacing: 36) {
            if !sortedPreparationMedia.isEmpty {
                preparationMediaSection
            }

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
        .overlay(alignment: .topTrailing) {
            if let externalURL {
                Button {
                    openExternalURL(externalURL)
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black.opacity(0.7))
                        .frame(width: floatingHeroActionSize, height: floatingHeroActionSize)
                }
                .buttonStyle(.plain)
                .background {
                    if #available(iOS 26, macOS 26, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .background {
                                Circle()
                                    .fill(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.18))
                            }
                    } else {
                        Circle()
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28))
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 56)
                .offset(y: -(floatingHeroActionSize / 2))
                .accessibilityLabel("Abrir receita na web")
            }
        }
    }

    // MARK: - Ingredients

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

            HStack {
                Spacer()

                Button {
                    addAllIngredientsToGrocery()
                } label: {
                    Label(
                        hasMissingIngredientsInGrocery ? "Adicionar todos em Mercado" : "Todos já adicionados",
                        systemImage: hasMissingIngredientsInGrocery ? "cart.badge.plus" : "checkmark.circle"
                    )
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(hasMissingIngredientsInGrocery ? .secondary : .tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill).opacity(hasMissingIngredientsInGrocery ? 0.85 : 0.55), in: .capsule)
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
                iconFileName: ingredient.iconName,
                fallbackSymbol: "leaf",
                showBalloon: true,
                balloonColor: .white
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

            if !ingredient.formattedQuantity.isEmpty {
                Text(ingredient.formattedQuantity)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
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

    // MARK: - Utensils

    private var utensilsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Utensílios")
                .font(.sectionTitle)
                .padding(.top, 8)

            ForEach(recipe.requiredUtensils ?? [], id: \.self) { utensil in
                let isAvailable = utensilIsAvailable(utensil)
                let iconName = utensilItems.first(where: { sameName($0.name, utensil) })?.iconName
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
            Text("Mídias da Receita")
                .font(.sectionTitle)
                .padding(.top, 8)

            if sortedPreparationMedia.count == 1, let media = sortedPreparationMedia.first {
                Button {
                    previewSelection = PreparationMediaSelection(id: media.id)
                } label: {
                    preparationMediaCard(for: media, width: nil, height: 220)
                }
                .buttonStyle(.plain)
            } else {
                PreparationMediaDeckView(
                    mediaItems: sortedPreparationMedia,
                    onSelect: { media in
                        previewSelection = PreparationMediaSelection(id: media.id)
                    }
                )
            }
        }
    }

    private func preparationMediaCard(for media: RecipePreparationMedia, width: CGFloat?, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if media.mediaType == .photo, let image = PlatformImage(data: media.data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.86), Color.black.opacity(0.35)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
            }

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
                iconName: ItemDatabase.shared.exactMatch(for: ingredient.name)?.nomeDoArquivo,
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
                    if existing.isPantry || existing.isGrocery {
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
                iconName: ItemDatabase.shared.exactMatch(for: ingredient.name)?.nomeDoArquivo,
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
        return allCategories.contains(where: { $0.type == .pantry && sameName($0.name, recipe.category) })
            ? recipe.category
            : defaultListCategory
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
            editingItem = pantryItem
            return
        }

        if let groceryItem = groceryItems.first(where: { sameName($0.name, ingredient.name) }) {
            editingItem = groceryItem
        }
    }

    private func openUtensilItem(_ utensilName: String) {
        editingItem = utensilItems.first(where: { sameName($0.name, utensilName) })
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
            return "Ambos"
        case .grocery:
            return "Mercado"
        case .pantry:
            return "Despensa"
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
            .modalNavigationTitle("Trocar ingrediente")
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
            .modalNavigationTitle("Alterar quantidade")
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
            .modalNavigationTitle("Alterar estado")
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
            return "Despensa"
        case .groceryItem:
            return "Mercado"
        default:
            return "Lista"
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
        .frame(height: 250)
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if media.mediaType == .photo, let image = PlatformImage(data: media.data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.88), Color.black.opacity(0.42)],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(.white)
            }

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
        .frame(height: 220)
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
    @Environment(\.dismiss) private var dismiss
    let mediaItems: [RecipePreparationMedia]
    let selectedMediaID: UUID

    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, media in
                        previewPage(for: media)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .adaptiveLeading) {
                    Button("Fechar") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("\(selectedIndex + 1) de \(mediaItems.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .onAppear {
                if let index = mediaItems.firstIndex(where: { $0.id == selectedMediaID }) {
                    selectedIndex = index
                }
            }
        }
    }

    @ViewBuilder
    private func previewPage(for media: RecipePreparationMedia) -> some View {
        switch media.mediaType {
        case .photo:
            if let image = PlatformImage(data: media.data) {
                ZoomablePhotoView(image: image)
            } else {
                ContentUnavailableView("Foto indisponível", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        case .video:
            if let url = temporaryFileURL(for: media) {
                AutoPlayMutedVideoView(url: url)
            } else {
                ContentUnavailableView("Vídeo indisponível", systemImage: "play.slash")
                    .foregroundStyle(.white)
            }
        }
    }

    private func temporaryFileURL(for media: RecipePreparationMedia) -> URL? {
        let ext = media.fileExtension.isEmpty ? "mov" : media.fileExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(media.id.uuidString)
            .appendingPathExtension(ext)

        do {
            try media.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct AutoPlayMutedVideoView: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.isMuted = true
                player.play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
    }
}
