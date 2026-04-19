import SwiftUI
import SwiftData

/// Inline recipe card shown in the chat when the assistant references recipes.
/// Uses the same gradient-overlay aesthetic as the main Recipes tab, with pantry compatibility info.
struct RecipeCardMessage: View {
    let recipeIds: [UUID]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }) private var pantryItems: [UnifiedItem]

    private var pantryNames: [String] {
        pantryItems.map {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        }
    }

    private var matchedRecipes: [Recipe] {
        let recipesById = Dictionary(uniqueKeysWithValues: allRecipes.map { ($0.id, $0) })
        return recipeIds.compactMap { recipesById[$0] }
    }

    var body: some View {
        if !matchedRecipes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
        let compat = recipe.compatibility(against: pantryNames)

        return ZStack(alignment: .bottomLeading) {
            // Image / placeholder
            if let data = recipe.imageData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipped()
            } else {
                ZStack {
                    Color(.tertiarySystemBackground)
                    Image(systemName: "book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                }
                .frame(width: 160, height: 160)
            }

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Info overlay
            VStack(alignment: .leading, spacing: 3) {
                Spacer()

                Text(recipe.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if recipe.totalTime > 0 {
                        Label("\(recipe.totalTime) min", systemImage: "clock")
                    }
                    Label(recipe.difficulty.rawValue, systemImage: recipe.difficulty.icon)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))

                if let compat {
                    HStack(spacing: 4) {
                        if compat.ratio >= 1.0 {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "checklist")
                        }
                        Text(compat.longText)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(10)
        }
        .frame(width: 160, height: 160)
        .clipShape(.rect(cornerRadius: 14))
    }
}
