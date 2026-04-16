import SwiftUI

// MARK: - Shared helpers

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

/// Builds an array of resolved icon images from ingredients, cycling to fill `count`.
/// Keeps original list order. Skips ingredients without icons.
private func buildIconSlots(from ingredients: [RecipeIngredient], count: Int) -> [PlatformImage] {
    let images = ingredients.compactMap { resolveIcon(for: $0) }
    guard !images.isEmpty else { return [] }
    var slots: [PlatformImage] = []
    while slots.count < count {
        slots.append(contentsOf: images)
    }
    return Array(slots.prefix(count))
}

/// Shared gradient background for recipe placeholders.
private let recipePlaceholderGradient = LinearGradient(
    colors: [
        Color(red: 0.12, green: 0.04, blue: 0.02),
        Color(red: 0.20, green: 0.06, blue: 0.03),
        Color(red: 0.14, green: 0.03, blue: 0.01),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// Uniform tile background color for all tiles.
private let tileBackgroundColor = Color.white.opacity(0.08)

// MARK: - Full placeholder (recipe detail page)

/// Full-size placeholder with 4 rows of ingredient icons.
/// Rows 1 & 3: 6 cols. Rows 2 & 4: 7 cols (offset right).
/// First/last tiles in each row are cropped at the edges for continuity.
/// Rows 2 & 3 start at a different horizontal offset from rows 1 & 4.
struct RecipeImagePlaceholder: View {
    let ingredients: [RecipeIngredient]
    var darkenOverlay: Bool = false

    private static let normalCols = 6
    private static let offsetCols = 7
    private static let rows = 4
    private static let totalSlots = normalCols * 2 + offsetCols * 2 // 26

    var body: some View {
        let slots = buildIconSlots(from: ingredients, count: Self.totalSlots)
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
                            let isOffset = row == 1 || row == 3
                            let cols = isOffset ? Self.offsetCols : Self.normalCols
                            let start = Self.startIndex(forRow: row)
                            let rowSlots = Array(slots[start..<start + cols])
                            // Rows 2 & 4 (index 1, 3) get the same extra shift.
                            // Rows 1 & 3 (index 0, 2) share the base start position.
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

    private static func startIndex(forRow row: Int) -> Int {
        (0..<row).reduce(0) { sum, r in
            sum + ((r % 2 == 0) ? normalCols : offsetCols)
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
    let ingredients: [RecipeIngredient]
    var darkenOverlay: Bool = false

    private static let baseCols = 5
    private static let expandedCols = 6
    private static let rows = 3
    private static let totalSlots = 16

    var body: some View {
        let slots = buildIconSlots(from: ingredients, count: Self.totalSlots)
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

                    if darkenOverlay {
                        Color.black.opacity(0.36)
                    }
                }
                .clipped()
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
