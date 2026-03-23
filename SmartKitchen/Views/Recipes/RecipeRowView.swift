import SwiftUI

/// Row view for recipe list mode.
struct RecipeRowView: View {
    let recipe: Recipe
    var compatibility: RecipeCompatibility? = nil

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
                    Label(recipe.difficulty.rawValue, systemImage: recipe.difficulty.icon)
                    if recipe.servings > 0 {
                        Label("\(recipe.servings)", systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let compatibility {
                    Text(compatibility.longText)
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
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.tertiarySystemBackground)
                Image(systemName: "book.closed")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
