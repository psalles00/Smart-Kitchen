import SwiftUI

/// Phase 4 — Step 15. Activity level (TDEE multiplier).
struct ActivityStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Como é sua rotina?"),
                subtitle: String(localized: "Inclui exercício e movimentação do dia a dia.")
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(ActivityLevel.allCases) { level in
                        OnboardingChoiceCard(
                            title: levelTitle(level),
                            subtitle: levelSubtitle(level),
                            isSelected: state.nutritionActivityRaw == level.rawValue,
                            icon: {
                                Image(systemName: icon(for: level))
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.primary)
                            },
                            action: { state.nutritionActivityRaw = level.rawValue }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: state.nutritionActivityRaw != nil,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func levelTitle(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary:   return String(localized: "Sedentário")
        case .light:       return String(localized: "Leve")
        case .moderate:    return String(localized: "Moderado")
        case .active:      return String(localized: "Ativo")
        case .veryActive:  return String(localized: "Muito ativo")
        case .extraActive: return String(localized: "Extremamente ativo")
        }
    }

    private func levelSubtitle(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary:   return String(localized: "Pouco ou nenhum exercício")
        case .light:       return String(localized: "Exercício leve 1–3x por semana")
        case .moderate:    return String(localized: "Exercício moderado 3–5x por semana")
        case .active:      return String(localized: "Exercício intenso 6–7x por semana")
        case .veryActive:  return String(localized: "Exercício muito intenso diário")
        case .extraActive: return String(localized: "Treino físico pesado ou trabalho manual")
        }
    }

    private func icon(for level: ActivityLevel) -> String {
        switch level {
        case .sedentary:   "figure.seated.side"
        case .light:       "figure.walk"
        case .moderate:    "figure.run"
        case .active:      "figure.strengthtraining.traditional"
        case .veryActive:  "figure.highintensity.intervaltraining"
        case .extraActive: "flame.fill"
        }
    }
}
