import Foundation
import SwiftUI
import SwiftData

enum AssistantRecipeCardTextSanitizer {
    private static let optionPattern = #"^\s*(?:[-*•]\s*)?\*\*(.+?)\*\*\s*[—–\-]\s*(.+)$"#

    static func companionText(for content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: optionPattern) else {
            return trimmed
        }

        let filteredLines = trimmed
            .components(separatedBy: .newlines)
            .filter { line in
                let range = NSRange(location: 0, length: (line as NSString).length)
                return regex.firstMatch(in: line, range: range) == nil
            }

        let sanitized = collapseBlankLines(in: filteredLines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? nil : sanitized
    }

    private static func collapseBlankLines(in text: String) -> String {
        var collapsed = text
        while collapsed.contains("\n\n\n") {
            collapsed = collapsed.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return collapsed
    }
}

/// Inline recipe card shown in the chat when the assistant references recipes.
/// Uses the same gradient-overlay aesthetic as the main Recipes tab, with pantry compatibility info.
struct RecipeCardMessage: View {
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    let recipeIds: [UUID]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }) private var pantryItems: [UnifiedItem]

    private let cardSize: CGFloat = 160

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
                        Button {
                            openRecipeInRecipesTab(recipe.id)
                        } label: {
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
        let hasStoredImageData = (recipe.imageData?.isEmpty == false)

        return ZStack(alignment: .bottomLeading) {
            // Image / placeholder
            RecipeThumbnail(recipe: recipe, maxPixel: 420) {
                if hasStoredImageData {
                    RecipeImageLoadingPlaceholder(darkenOverlay: true, iconSize: 24)
                } else {
                    RecipeImagePlaceholderCompact(
                        ingredients: (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder },
                        darkenOverlay: true
                    )
                }
            }
            .frame(width: cardSize, height: cardSize)
            .clipped()

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
                    Label(recipe.difficulty.displayName, systemImage: recipe.difficulty.icon)
                    if let kcal = recipe.calories {
                        Label("\(kcal) kcal", systemImage: "flame")
                    }
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
        .frame(width: cardSize, height: cardSize)
        .clipShape(.rect(cornerRadius: 14))
    }
}
