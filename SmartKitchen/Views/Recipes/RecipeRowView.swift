import SwiftUI

/// Row view for recipe list mode.
struct RecipeRowView: View, Equatable {
    let recipe: Recipe
    var compatibility: RecipeCompatibility? = nil
    var placeholderIconSources: [RecipePlaceholderIconSource] = []

    private var hasStoredImageData: Bool {
        guard let imageData = recipe.imageData else { return false }
        return !imageData.isEmpty
    }

    // PERF: SwiftData @Model classes are reference types — they don't get
    // synthesized Equatable. We compare by the concrete fields actually
    // rendered in `body`, so SwiftUI can skip re-rendering rows that didn't
    // visibly change (used together with `.equatable()` in the parent).
    nonisolated static func == (lhs: RecipeRowView, rhs: RecipeRowView) -> Bool {
        lhs.recipe.id == rhs.recipe.id
            && lhs.recipe.name == rhs.recipe.name
            && lhs.recipe.totalTime == rhs.recipe.totalTime
            && lhs.recipe.difficulty == rhs.recipe.difficulty
            && lhs.recipe.servings == rhs.recipe.servings
            && lhs.recipe.isFavorite == rhs.recipe.isFavorite
            && lhs.recipe.updatedAt == rhs.recipe.updatedAt
            && lhs.compatibility == rhs.compatibility
            && lhs.placeholderIconSources == rhs.placeholderIconSources
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            recipeThumb
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if recipe.totalTime > 0 {
                        Label("\(recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(recipe.difficulty.displayName, systemImage: recipe.difficulty.icon)
                    if recipe.servings > 0 {
                        Label("\(recipe.servings)", systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let compatibility {
                    HStack(spacing: 4) {
                        if compatibility.ratio >= 1.0 {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        Text(compatibility.longText)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var recipeThumb: some View {
        // 60pt on @3x screens lands around 180px; 200px keeps it crisp
        // without over-decoding large originals while scrolling.
        RecipeThumbnail(recipe: recipe, maxPixel: 200) {
            if hasStoredImageData {
                RecipeImageLoadingPlaceholder(iconSize: 18)
            } else {
                RecipeImagePlaceholderCompact(iconSources: placeholderIconSources)
            }
        }
    }
}
