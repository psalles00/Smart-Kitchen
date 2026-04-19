import SwiftUI

/// Gallery card for a recipe — shows image with title overlay.
struct RecipeCardView: View {
    let recipe: Recipe
    var compatibility: RecipeCompatibility? = nil
    var columns: Int = 2
    var cornerRadii: RectangleCornerRadii = .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16)

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
                            Label(recipe.difficulty.rawValue, systemImage: recipe.difficulty.icon)
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
        if let data = recipe.imageData, let image = PlatformImage(data: data) {
            GeometryReader { geo in
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            RecipeImagePlaceholderCompact(
                ingredients: (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder },
                darkenOverlay: true
            )
        }
    }

    private func availableIngredientsText(for compatibility: RecipeCompatibility) -> String {
        "\(compatibility.matchedIngredients) de \(compatibility.totalIngredients)"
    }
}
