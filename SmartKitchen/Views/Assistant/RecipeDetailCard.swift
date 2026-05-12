import SwiftUI

/// Compact inline recipe card displayed in the chat.
/// Shows title, subtitle, ingredients, steps, and the button that creates the recipe in the app.
struct RecipeDetailCard: View {
    let recipe: RecipeCardData
    let onAddToRecipes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero (opcional) — usa heroImageURL quando disponível, senão tenta
            // resolver um ícone do banco a partir do ingrediente principal.
            heroSection

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                if let subtitle = recipe.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if let category = recipe.category, !category.isEmpty {
                    Label(CategoryMutationService.localizedDisplayName(for: category, type: .recipe), systemImage: "books.vertical")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Ingredients
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "Ingredientes"), systemImage: "basket")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            if !ingredient.detail.isEmpty {
                                Text(ingredient.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }

                            Text(ingredient.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "Modo de Preparo"), systemImage: "list.number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.accentColor.opacity(0.7), in: .circle)

                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Create button
            Divider()
                .padding(.horizontal, 16)

            Button {
                onAddToRecipes()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.caption.weight(.medium))
                    Text(String(localized: "Criar receita no app"))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if let urlString = recipe.heroImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    heroFallback
                case .empty:
                    Color(.tertiarySystemBackground)
                @unknown default:
                    heroFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipped()
            .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        } else if let main = recipe.mainIngredient,
                  !main.isEmpty,
                  let icon = IconResolver.image(for: main) {
            ZStack {
                LinearGradient(
                    colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(platformImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipShape(.rect(topLeadingRadius: 16, topTrailingRadius: 16))
        }
    }

    private var heroFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }
}
