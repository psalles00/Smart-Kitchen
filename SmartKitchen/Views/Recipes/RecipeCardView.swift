import SwiftUI

/// Gallery card for a recipe — shows image with title overlay.
struct RecipeCardView: View, Equatable {
    let recipe: Recipe
    var compatibility: RecipeCompatibility? = nil
    var columns: Int = 2
    var cornerRadii: RectangleCornerRadii = .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16)

    // PERF: Skip re-rendering visible cards that didn't visibly change.
    // The Recipe model is a SwiftData reference type, so we compare by
    // the fields that actually drive `body`.
    nonisolated static func == (lhs: RecipeCardView, rhs: RecipeCardView) -> Bool {
        lhs.recipe.id == rhs.recipe.id
            && lhs.recipe.name == rhs.recipe.name
            && lhs.recipe.totalTime == rhs.recipe.totalTime
            && lhs.recipe.difficulty == rhs.recipe.difficulty
            && lhs.recipe.isFavorite == rhs.recipe.isFavorite
            && (lhs.recipe.imageData?.count ?? 0) == (rhs.recipe.imageData?.count ?? 0)
            && lhs.compatibility == rhs.compatibility
            && lhs.columns == rhs.columns
            && cornerRadiiEqual(lhs.cornerRadii, rhs.cornerRadii)
    }

    nonisolated private static func cornerRadiiEqual(_ a: RectangleCornerRadii, _ b: RectangleCornerRadii) -> Bool {
        a.topLeading == b.topLeading
            && a.topTrailing == b.topTrailing
            && a.bottomLeading == b.bottomLeading
            && a.bottomTrailing == b.bottomTrailing
    }

    private var shouldDarkenRealImageForThreeColumnGrid: Bool {
        columns == 3
    }

    private var hasStoredImageData: Bool {
        guard let imageData = recipe.imageData else { return false }
        return !imageData.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image / placeholder
            recipeImage

            // Gradient overlay + title
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                Text(recipe.name)
                    .font(columns >= 3 ? .caption.weight(.semibold) : .cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(columns == 4 ? 3 : 2)

                if columns <= 3 {
                    HStack(spacing: 6) {
                        if columns == 3, let compatibility = compatibility {
                            if compatibility.ratio >= 1.0 {
                                Label(availableIngredientsText(for: compatibility), systemImage: "checkmark.seal.fill")
                            } else {
                                Label(availableIngredientsText(for: compatibility), systemImage: "basket")
                            }
                        } else if recipe.totalTime > 0 {
                            Label("\(recipe.totalTime)\(columns == 3 ? "m" : " min")", systemImage: "clock")
                        }
                        if columns == 2 {
                            Label(recipe.difficulty.displayName, systemImage: recipe.difficulty.icon)
                        }
                    }
                    .font(columns == 3 ? .caption2 : .caption)
                    .foregroundStyle(.white.opacity(0.85))
                }

                if columns == 2, let compatibility = compatibility {
                    HStack(spacing: 4) {
                        if compatibility.ratio >= 1.0 {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        Text(compatibility.longText)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(columns >= 3 ? 8 : 12)
        }
        #if os(macOS)
        .frame(width: 150, height: 150)
        #else
        .aspectRatio(1, contentMode: .fit)
        #endif
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadii: cornerRadii))
        .overlay {
            // Favorite badge
            if recipe.isFavorite {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.red, in: .circle)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var recipeImage: some View {
        // Size thumbnails close to the real rendered size to cut decode cost
        // and peak memory in gallery mode, especially on first paint.
        let maxPixel: CGFloat = {
            switch columns {
            case 1: return 960
            case 2: return 700
            case 3: return 420
            default: return 320
            }
        }()

        Color.clear
            .overlay {
                RecipeThumbnail(recipe: recipe, maxPixel: maxPixel) {
                    if hasStoredImageData {
                        RecipeImageLoadingPlaceholder(
                            darkenOverlay: true,
                            iconSize: columns >= 3 ? 22 : 28
                        )
                    } else {
                        RecipeImagePlaceholderCompact(
                            ingredients: (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder },
                            darkenOverlay: true
                        )
                    }
                }
                .clipped()
            }
            .overlay {
                if shouldDarkenRealImageForThreeColumnGrid, hasStoredImageData {
                    Color.black.opacity(0.2)
                }
            }
    }

    private func availableIngredientsText(for compatibility: RecipeCompatibility) -> String {
        "\(compatibility.matchedIngredients) de \(compatibility.totalIngredients)"
    }
}
