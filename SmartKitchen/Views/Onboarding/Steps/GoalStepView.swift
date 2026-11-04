import SwiftUI

/// Phase 4 — Step 11. Choose primary weight goal.
struct GoalStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Qual é o seu objetivo?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                subtitle: String(localized: "Vamos ajustar suas metas de calorias e macros pra você.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
            )

            VStack(spacing: 12) {
                ForEach(WeightGoal.allCases) { goal in
                    OnboardingChoiceCard(
                        title: goalTitle(goal),
                        subtitle: goalSubtitle(goal),
                        isSelected: state.nutritionGoalRaw == goal.rawValue,
                        icon: {
                            Image(systemName: goal.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                        },
                        action: { state.nutritionGoalRaw = goal.rawValue }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                isEnabled: state.nutritionGoalRaw != nil,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func goalTitle(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose:     return String(localized: "Perder peso", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .maintain: return String(localized: "Manter peso", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .gain:     return String(localized: "Ganhar peso", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        }
    }

    private func goalSubtitle(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose:     return String(localized: "Reduzir calorias com déficit saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .maintain: return String(localized: "Equilibrar consumo e gasto energético", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        case .gain:     return String(localized: "Ganhar massa com superávit calórico", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
        }
    }
}
