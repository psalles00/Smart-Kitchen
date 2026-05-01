import SwiftUI

/// Phase 4 — Step 12. Biological sex (used for BMR formula).
struct SexStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Qual é o seu sexo biológico?"),
                subtitle: String(localized: "Usamos isso pra calcular sua taxa metabólica basal com precisão.")
            )

            VStack(spacing: 12) {
                ForEach(NutritionSex.allCases) { sex in
                    OnboardingChoiceCard(
                        title: sexTitle(sex),
                        subtitle: nil,
                        isSelected: state.nutritionSexRaw == sex.rawValue,
                        icon: {
                            Image(systemName: sex.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                        },
                        action: { state.nutritionSexRaw = sex.rawValue }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: state.nutritionSexRaw != nil,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func sexTitle(_ sex: NutritionSex) -> String {
        switch sex {
        case .male:   return String(localized: "Masculino")
        case .female: return String(localized: "Feminino")
        case .other:  return String(localized: "Outro")
        }
    }
}
