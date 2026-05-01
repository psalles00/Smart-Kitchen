import SwiftUI

/// Phase 2 — Step 7. Recipe interests: each card has a custom gradient
/// cover (no asset weight) plus name + meta. Pick ≥3 to seed the recipe
/// library with full templates (ingredients + steps).
struct SelectRecipesStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "O que você gosta de cozinhar?"),
                subtitle: String(localized: "Escolha pelo menos 3 receitas para começar sua coleção.")
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(OnboardingCatalog.recipeTemplates) { template in
                        RecipeTemplateCard(
                            template: template,
                            isSelected: state.selectedRecipeTemplateIDs.contains(template.id),
                            action: { toggle(template.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            VStack(spacing: 8) {
                Text(counterLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state.canAdvanceRecipeSelection ? .secondary : Color.orange)
                    .animation(.easeOut(duration: 0.2), value: state.selectedRecipeTemplateIDs.count)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.canAdvanceRecipeSelection,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if state.selectedRecipeTemplateIDs.contains(id) {
                state.selectedRecipeTemplateIDs.remove(id)
            } else {
                state.selectedRecipeTemplateIDs.insert(id)
            }
        }
    }

    private var counterLabel: String {
        let count = state.selectedRecipeTemplateIDs.count
        return count >= 3
            ? String(localized: "\(count) selecionadas")
            : String(localized: "Selecione mais \(3 - count) para continuar")
    }
}

private struct RecipeTemplateCard: View {
    let template: OnboardingCatalog.RecipeTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                gradientCover
                    .aspectRatio(16.0/11.0, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("\(template.prepMinutes + template.cookMinutes) min · \(template.calories) kcal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(neutralSurfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var gradientCover: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: template.gradientColors.map { Color(hex: $0) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle radial highlight to add depth
            RadialGradient(
                colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 140
            )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary))
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    ForEach(template.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.32)))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
