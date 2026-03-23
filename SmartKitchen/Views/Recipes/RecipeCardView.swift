import SwiftUI

/// Gallery card for a recipe — shows image with title overlay.
struct RecipeCardView: View {
    let recipe: Recipe
    var compatibility: RecipeCompatibility? = nil

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
                    .font(.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if recipe.totalTime > 0 {
                        Label("\(recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(recipe.difficulty.rawValue, systemImage: recipe.difficulty.icon)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))

                if let compatibility {
                    Text(compatibility.longText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(12)
        }
        .frame(height: 190)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
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
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            // Placeholder with recipe icon
            ZStack {
                Color(.tertiarySystemBackground)
                Image(systemName: "book.closed")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
