import SwiftUI

// MARK: - Shared helpers

struct RecipePlaceholderIconSource: Hashable {
    let name: String
    let iconFileName: String?

    init(name: String, iconFileName: String? = nil) {
        self.name = name
        self.iconFileName = iconFileName
    }

    init(ingredient: RecipeIngredient) {
        self.name = ingredient.name
        self.iconFileName = ingredient.iconName
    }
}

private final class RecipePlaceholderIconSlotCache: @unchecked Sendable {
    static let shared = RecipePlaceholderIconSlotCache()

    private final class Entry {
        let images: [PlatformImage]
        init(_ images: [PlatformImage]) { self.images = images }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 600
        return cache
    }()

    func slots(from sources: [RecipePlaceholderIconSource], count: Int) -> [PlatformImage] {
        guard !sources.isEmpty, count > 0 else { return [] }

        let key = cacheKey(for: sources, count: count)
        if let cached = cache.object(forKey: key as NSString) {
            return cached.images
        }

        let images = sources.compactMap { resolveIcon(for: $0) }
        guard !images.isEmpty else {
            cache.setObject(Entry([]), forKey: key as NSString)
            return []
        }

        var slots: [PlatformImage] = []
        slots.reserveCapacity(count)
        while slots.count < count {
            slots.append(contentsOf: images)
        }

        let result = Array(slots.prefix(count))
        cache.setObject(Entry(result), forKey: key as NSString)
        return result
    }

    private func cacheKey(for sources: [RecipePlaceholderIconSource], count: Int) -> String {
        var hasher = Hasher()
        hasher.combine(count)
        for source in sources {
            hasher.combine(source.name)
            hasher.combine(source.iconFileName ?? "")
        }
        return String(hasher.finalize())
    }
}

/// Resolves a recipe ingredient to its icon image, if available.
private func resolveIcon(for ingredient: RecipeIngredient) -> PlatformImage? {
    if let name = ingredient.iconName, !name.isEmpty,
       let img = IconResolver.image(forFilename: name) {
        return img
    }
    if !ingredient.name.isEmpty {
        return IconResolver.image(for: ingredient.name)
    }
    return nil
}

private func resolveIcon(for source: RecipePlaceholderIconSource) -> PlatformImage? {
    if let name = source.iconFileName, !name.isEmpty,
       let img = IconResolver.image(forFilename: name) {
        return img
    }
    if !source.name.isEmpty {
        return IconResolver.image(for: source.name)
    }
    return nil
}

/// Builds an array of resolved icon images from ingredients, cycling to fill `count`.
/// Keeps original list order. Skips ingredients without icons.
private func buildIconSlots(from ingredients: [RecipeIngredient], count: Int) -> [PlatformImage] {
    buildIconSlots(from: ingredients.map(RecipePlaceholderIconSource.init), count: count)
}

private func buildIconSlots(from sources: [RecipePlaceholderIconSource], count: Int) -> [PlatformImage] {
    RecipePlaceholderIconSlotCache.shared.slots(from: sources, count: count)
}

/// Shared gradient background for recipe placeholders.
private var recipePlaceholderGradient: some View {
    LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.12, blue: 0.06),
            Color(red: 0.42, green: 0.15, blue: 0.08),
            Color(red: 0.32, green: 0.10, blue: 0.04),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Uniform tile background color for all tiles.
private let tileBackgroundColor = Color.white.opacity(0.08)

// MARK: - Full placeholder (recipe detail page)

/// Full-size placeholder with 5 rows of ingredient icons (5 cols each).
/// Rows 1, 3, 5 (indices 0, 2, 4): slightly cropped on the left edge.
/// Rows 2, 4 (indices 1, 3): shifted to a different horizontal offset.
/// This creates a staggered, dynamic look across the grid.
struct RecipeImagePlaceholder: View {
    let ingredients: [RecipeIngredient]
    var darkenOverlay: Bool = false

    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    private static let cols = 6
    private static let rows = 5
    private static let totalSlots = cols * rows // 30

    var body: some View {
        let slots = buildIconSlots(from: ingredients, count: Self.totalSlots)
        if !recipeIllustratedPlaceholdersEnabled {
            fallbackPlaceholder
        } else {
            if slots.isEmpty {
                fallbackPlaceholder
            } else {
                GeometryReader { geo in
                    let spacing: CGFloat = 6
                    let tileSize = (geo.size.height - spacing * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
                    let halfShift = (tileSize + spacing) * 0.5
                    // Start before left edge so first tile is cropped
                    let baseOffset = -(tileSize * 0.45)

                    ZStack {
                        recipePlaceholderGradient

                        VStack(spacing: spacing) {
                            ForEach(0..<Self.rows, id: \.self) { row in
                                let start = row * Self.cols
                                let rowSlots = Array(slots[start..<start + Self.cols])
                                // Rows 2 & 4 (indices 1, 3) get different horizontal shift.
                                // Rows 1, 3, 5 (indices 0, 2, 4) share the base cropped start.
                                let rowShift: CGFloat = (row == 1 || row == 3) ? halfShift : 0

                                HStack(spacing: spacing) {
                                    ForEach(0..<rowSlots.count, id: \.self) { i in
                                        IngredientTile(image: rowSlots[i], size: tileSize)
                                }
                                }
                                .offset(x: baseOffset + rowShift)
                            }
                        }

                        if darkenOverlay {
                            Color.black.opacity(0.36)
                        }
                    }
                    .clipped()
                }
            }
        }
    }

    @ViewBuilder
    private var fallbackPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Compact placeholder (cards, grid, home)

/// Compact placeholder with 3 rows and intentional overflow:
/// row 1 adds one icon on the right, row 2 adds one on the left, row 3 adds one on the right.
/// Existing visible icon positions are preserved.
struct RecipeImagePlaceholderCompact: View {
    let iconSources: [RecipePlaceholderIconSource]
    var darkenOverlay: Bool = false

    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    private static let baseCols = 5
    private static let expandedCols = 6
    private static let rows = 3
    private static let totalSlots = 16

    init(ingredients: [RecipeIngredient], darkenOverlay: Bool = false) {
        self.iconSources = ingredients.map(RecipePlaceholderIconSource.init)
        self.darkenOverlay = darkenOverlay
    }

    init(iconSources: [RecipePlaceholderIconSource], darkenOverlay: Bool = false) {
        self.iconSources = iconSources
        self.darkenOverlay = darkenOverlay
    }

    var body: some View {
        let slots = buildIconSlots(from: iconSources, count: Self.totalSlots)
        if !recipeIllustratedPlaceholdersEnabled {
            fallbackPlaceholder
        } else {
            if slots.isEmpty {
                fallbackPlaceholder
            } else {
                GeometryReader { geo in
                    let spacing: CGFloat = 4
                    let tileSize = (geo.size.height - spacing * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
                    let halfShift = (tileSize + spacing) * 0.5
                    let baseOffset = -(tileSize * 0.45)

                    ZStack {
                        recipePlaceholderGradient

                        VStack(spacing: spacing) {
                            ForEach(0..<Self.rows, id: \.self) { row in
                                let cols = Self.expandedCols
                                let start = Self.startIndex(forRow: row)
                                let rowSlots = Array(slots[start..<start + cols])
                                let step = tileSize + spacing
                                // Row 2 gains one icon on the left while keeping existing icons fixed.
                                let rowShift: CGFloat = (row == 1) ? (halfShift - step) : 0

                                HStack(spacing: spacing) {
                                    ForEach(0..<rowSlots.count, id: \.self) { i in
                                        IngredientTile(image: rowSlots[i], size: tileSize)
                                }
                                }
                                .offset(x: baseOffset + rowShift)
                            }
                        }
                        .scaleEffect(1.25)

                        if darkenOverlay {
                            Color.black.opacity(0.36)
                        }
                    }
                    .clipped()
                }
            }
        }
    }

    private static func startIndex(forRow row: Int) -> Int {
        switch row {
        case 0: return 0
        case 1: return 4
        default: return 10
        }
    }

    @ViewBuilder
    private var fallbackPlaceholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: "book.closed")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
        }
    }
}

struct RecipeImageLoadingPlaceholder: View {
    var darkenOverlay = false
    var iconSize: CGFloat = 26

    var body: some View {
        ZStack {
            recipePlaceholderGradient

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "book.closed")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.24))

            if darkenOverlay {
                Color.black.opacity(0.28)
            }
        }
    }
}

// MARK: - Individual Tile

private struct IngredientTile: View {
    let image: PlatformImage
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(tileBackgroundColor)

            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews

#if DEBUG

struct RecipeImagePlaceholder_Previews: PreviewProvider {
    static var sampleIngredients: [RecipeIngredient] {
        [
            RecipeIngredient(name: "Tomate", iconName: "tomato.png"),
            RecipeIngredient(name: "Cenoura", iconName: "carrot.png"),
            RecipeIngredient(name: "Cebola", iconName: "onion.png"),
            RecipeIngredient(name: "Alho", iconName: "garlic.png"),
            RecipeIngredient(name: "Batata", iconName: "potato.png"),
            RecipeIngredient(name: "Maçã", iconName: "apple.png"),
            RecipeIngredient(name: "Pão", iconName: "bread-white.png"),
            RecipeIngredient(name: "Queijo", iconName: "cheese.png"),
            RecipeIngredient(name: "Leite", iconName: "milk.png"),
            RecipeIngredient(name: "Ovo", iconName: "egg.png"),
        ]
    }

    static var previews: some View {
        Group {
            // Full — Detail hero (420h)
            RecipeImagePlaceholder(ingredients: sampleIngredients)
                .frame(height: 420)
                .preferredColorScheme(.dark)
                .previewDisplayName("Full — Detail Hero (420h)")

            // Compact — Gallery card (square)
            RecipeImagePlaceholderCompact(ingredients: sampleIngredients)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 180)
                .clipShape(.rect(cornerRadius: 16))
                .preferredColorScheme(.dark)
                .previewDisplayName("Compact — Gallery Card")
                .previewLayout(.sizeThatFits)

            // Compact — Home card
            RecipeImagePlaceholderCompact(ingredients: sampleIngredients)
                .frame(width: 210, height: 118)
                .clipShape(.rect(cornerRadius: 16))
                .preferredColorScheme(.dark)
                .previewDisplayName("Compact — Home Card (210×118)")
                .previewLayout(.sizeThatFits)

            // Compact — Row thumbnail
            RecipeImagePlaceholderCompact(ingredients: sampleIngredients)
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 10))
                .preferredColorScheme(.dark)
                .previewDisplayName("Compact — Row Thumb (60×60)")
                .previewLayout(.sizeThatFits)
        }
    }
}
#endif
