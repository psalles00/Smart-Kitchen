import SwiftUI
import SwiftData
import AVKit

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \GroceryItem.sortOrder) private var groceryItems: [GroceryItem]
    @Query(sort: \PantryItem.sortOrder) private var pantryListItems: [PantryItem]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Bindable var recipe: Recipe
    @State private var showCookingMode = false
    @State private var showEditRecipe = false
    @State private var previewSelection: PreparationMediaSelection?

    private var sortedIngredients: [RecipeIngredient] {
        recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedSteps: [RecipeStep] {
        recipe.steps.sorted { $0.order < $1.order }
    }

    private var sortedPreparationMedia: [RecipePreparationMedia] {
        recipe.preparationMedia.sorted { $0.sortOrder < $1.sortOrder }
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

    private var hasMissingIngredientsInGrocery: Bool {
        sortedIngredients.contains { !ingredientIsInGrocery($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImage
                content
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Editar", systemImage: "pencil") {
                        showEditRecipe = true
                    }
                    Button(
                        recipe.isFavorite ? "Desfavoritar" : "Favoritar",
                        systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                    ) {
                        recipe.isFavorite.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe)
        }
        .sheet(isPresented: $showEditRecipe) {
            NavigationStack {
                EditRecipeView(recipe: recipe)
            }
        }
        .sheet(item: $previewSelection) { selection in
            PreparationMediaPreviewView(
                mediaItems: sortedPreparationMedia,
                selectedMediaID: selection.id
            )
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 280)
                .clipped()
        } else {
            ZStack {
                Color(.tertiarySystemBackground)
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
            }
            .frame(height: 200)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title + description
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.name)
                    .font(.pageTitle)

                if !recipe.descriptionText.isEmpty {
                    Text(recipe.descriptionText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Metadata chips
            metadataRow

            // Start cooking button
            Button {
                showCookingMode = true
            } label: {
                Label("Começar a Cozinhar", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            if !sortedPreparationMedia.isEmpty {
                preparationMediaSection
            }

            // Ingredients
            if !sortedIngredients.isEmpty {
                ingredientsSection
            }

            // Steps
            if !sortedSteps.isEmpty {
                stepsSection
            }

            if let externalURL {
                linkSection(url: externalURL)
            }
        }
        .padding(20)
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if recipe.totalTime > 0 {
                    metadataChip(icon: "clock", text: "\(recipe.totalTime) min")
                }
                metadataChip(icon: recipe.difficulty.icon, text: recipe.difficulty.rawValue)
                if recipe.servings > 0 {
                    metadataChip(icon: "person.2", text: "\(recipe.servings) porções")
                }
                if let cal = recipe.calories {
                    metadataChip(icon: "flame", text: "\(cal) kcal")
                }
                metadataChip(icon: "tag", text: recipe.category)
            }
        }
    }

    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredientes")
                    .font(.sectionTitle)

                Spacer()

                Button(hasMissingIngredientsInGrocery ? "Adicionar todos ao mercado" : "Todos já adicionados") {
                    addAllIngredientsToGrocery()
                }
                .font(.caption.weight(.semibold))
                .disabled(!hasMissingIngredientsInGrocery)
            }

            ForEach(sortedIngredients) { ingredient in
                let isAvailable = ingredientIsAvailable(ingredient)
                let isInGrocery = ingredientIsInGrocery(ingredient)

                HStack(spacing: 12) {
                    IconImage(name: ingredient.name, fallbackSymbol: "leaf")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ingredient.name)
                            .font(.body)

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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NeutralItemActionButton(systemImage: isInGrocery ? "checkmark" : "cart.badge.plus") {
                        guard !isInGrocery else { return }
                        addIngredientToGrocery(ingredient)
                    }
                    .opacity(isInGrocery ? 0.7 : 1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    isAvailable ? Color.green.opacity(0.08) : Color(.secondarySystemBackground),
                    in: .rect(cornerRadius: 16)
                )
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
                    if ingredientIsAvailable(ingredient) {
                        Button("Já está disponível", systemImage: "checkmark.circle") { }
                    }
                }

                if ingredient.id != sortedIngredients.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modo de Preparo")
                .font(.sectionTitle)

            ForEach(sortedSteps) { step in
                HStack(alignment: .top, spacing: 14) {
                    // Step number circle
                    Text("\(step.order)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor, in: .circle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.instruction)
                            .font(.body)

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Mídias da Receita")
                .font(.sectionTitle)

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

            if media.mediaType == .photo, let image = UIImage(data: media.data) {
                Image(uiImage: image)
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

    private func linkSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link da Receita")
                .font(.sectionTitle)

            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundStyle(Color.accentColor)
                    Text(url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            }
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
            let item = GroceryItem(
                name: ingredient.name,
                category: category,
                quantity: ingredient.quantity,
                unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                sortOrder: (groceryItems.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func addIngredientToPantry(_ ingredient: RecipeIngredient) {
        let category = resolvedListCategory(for: ingredient.name)
        if let existingItem = pantryListItems.first(where: { sameName($0.name, ingredient.name) && $0.category == category }) {
            applyQuantity(from: ingredient, to: existingItem)
        } else {
            let item = PantryItem(
                name: ingredient.name,
                category: category,
                quantity: ingredient.quantity,
                unit: ingredient.unit.isEmpty ? nil : ingredient.unit,
                sortOrder: (pantryListItems.map(\.sortOrder).max() ?? -1) + 1
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

    private func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ==
        rhs.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func applyQuantity(from ingredient: RecipeIngredient, to item: GroceryItem) {
        if let quantity = ingredient.quantity {
            item.quantity = (item.quantity ?? 0) + quantity
        } else if item.quantity == nil {
            item.quantity = 1
        }
        if !ingredient.unit.isEmpty {
            item.unit = ingredient.unit
        }
    }

    private func applyQuantity(from ingredient: RecipeIngredient, to item: PantryItem) {
        if let quantity = ingredient.quantity {
            item.quantity = (item.quantity ?? 0) + quantity
        } else if item.quantity == nil {
            item.quantity = 1
        }
        if !ingredient.unit.isEmpty {
            item.unit = ingredient.unit
        }
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
        .tabViewStyle(.page(indexDisplayMode: .automatic))
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

            if media.mediaType == .photo, let image = UIImage(data: media.data) {
                Image(uiImage: image)
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
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            if let image = UIImage(data: media.data) {
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

private struct ZoomablePhotoView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(lastScale * value, 4))
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
            }
            .contentMargins(.vertical, 32)
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
