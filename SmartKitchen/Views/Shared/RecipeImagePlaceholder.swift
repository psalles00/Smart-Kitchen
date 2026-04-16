import SwiftUI

/// A placeholder image for recipes without photos.
/// Displays a staggered grid of ingredient icons inside pastel-tinted rounded tiles.
/// Always uses a dark background regardless of the system color scheme.
struct RecipeImagePlaceholder: View {
    let ingredients: [RecipeIngredient]

    private static let columns = 6
    private static let rows = 4
    private static let totalSlots = columns * rows

    /// Resolved icons from ingredients (only those with a valid icon).
    private var resolvedIcons: [(image: PlatformImage, color: Color)] {
        var result: [(PlatformImage, Color)] = []
        for ingredient in ingredients {
            if let img = Self.resolveIcon(for: ingredient) {
                result.append((img, img.averageColor()))
            }
        }
        return result
    }

    /// Fills exactly `totalSlots` by cycling resolved icons.
    private var iconSlots: [(image: PlatformImage, color: Color)] {
        let icons = resolvedIcons
        guard !icons.isEmpty else { return [] }
        var slots: [(PlatformImage, Color)] = []
        while slots.count < Self.totalSlots {
            slots.append(contentsOf: icons)
        }
        return Array(slots.prefix(Self.totalSlots))
    }

    var body: some View {
        if iconSlots.isEmpty {
            fallbackPlaceholder
        } else {
            GeometryReader { geo in
                let spacing: CGFloat = 6
                let tileSize = (geo.size.width + spacing) / CGFloat(Self.columns - 1) - spacing
                let halfShift = (tileSize + spacing) * 0.5

                ZStack {
                    Color.black

                    VStack(spacing: spacing) {
                        ForEach(0..<Self.rows, id: \.self) { row in
                            let isOffsetRow = row == 1 || row == 3
                            let start = row * Self.columns
                            let rowSlots = Array(iconSlots[start..<start + Self.columns])

                            HStack(spacing: spacing) {
                                ForEach(0..<rowSlots.count, id: \.self) { i in
                                    IngredientTile(
                                        image: rowSlots[i].image,
                                        tileColor: rowSlots[i].color,
                                        size: tileSize
                                    )
                                }
                            }
                            .offset(x: isOffsetRow ? halfShift : 0)
                        }
                    }
                }
                .clipped()
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

    private static func resolveIcon(for ingredient: RecipeIngredient) -> PlatformImage? {
        if let name = ingredient.iconName, !name.isEmpty,
           let img = IconResolver.image(forFilename: name) {
            return img
        }
        if !ingredient.name.isEmpty {
            return IconResolver.image(for: ingredient.name)
        }
        return nil
    }
}

// MARK: - Individual Tile

private struct IngredientTile: View {
    let image: PlatformImage
    let tileColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(pastelColor)

            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }

    /// Pastel version: desaturate & lighten, then apply low opacity on dark bg.
    private var pastelColor: Color {
        tileColor.opacity(0.18)
    }
}
