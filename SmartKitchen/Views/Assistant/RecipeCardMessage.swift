import SwiftUI
import SwiftData

/// Inline recipe card shown in the chat when the assistant references recipes.
struct RecipeCardMessage: View {
    let recipeIds: [UUID]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]

    private var matchedRecipes: [Recipe] {
        let recipesById = Dictionary(uniqueKeysWithValues: allRecipes.map { ($0.id, $0) })
        return recipeIds.compactMap { recipesById[$0] }
    }

    var body: some View {
        if !matchedRecipes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(matchedRecipes) { recipe in
                        NavigationLink(value: recipe.id) {
                            recipeCard(recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.tertiarySystemFill)
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .frame(width: 232, height: 132)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if recipe.totalTime > 0 {
                        Label("\(recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(recipe.difficulty.rawValue, systemImage: recipe.difficulty.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 232, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }
}
