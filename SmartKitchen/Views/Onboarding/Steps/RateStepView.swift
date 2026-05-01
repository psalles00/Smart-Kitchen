import SwiftUI

/// Phase 4 — Step 16. Desired weekly weight change rate. Skipped visually
/// when goal is `.maintain` (rate forced to 0 and view shows summary card).
struct RateStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    private var goal: WeightGoal {
        WeightGoal(rawValue: state.nutritionGoalRaw ?? "") ?? .maintain
    }

    /// Range depends on goal direction: 0.1–1.0 kg/week.
    private var range: ClosedRange<Double> { 0.1...1.0 }

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: title,
                subtitle: subtitle
            )

            if goal == .maintain {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Vamos manter seu peso atual com calorias equilibradas."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(neutralSurfaceColor)
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", state.nutritionWeeklyChangeKg))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.nutritionWeeklyChangeKg)
                        Text(String(localized: "kg/semana"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $state.nutritionWeeklyChangeKg, in: range, step: 0.1)
                        .tint(.primary)
                        .padding(.horizontal, 8)

                    HStack {
                        Text(String(localized: "Devagar"))
                        Spacer()
                        Text(String(localized: "Agressivo"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)

                    if state.nutritionWeeklyChangeKg > 0.75 {
                        Label(String(localized: "Ritmos acima de 0,75 kg/semana podem ser difíceis de manter."), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(neutralSurfaceColor)
                )
                .padding(.horizontal, 20)
                .animation(.easeOut(duration: 0.2), value: state.nutritionWeeklyChangeKg)
            }

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: true,
                action: {
                    if goal == .maintain { state.nutritionWeeklyChangeKg = 0 }
                    onContinue()
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var title: String {
        switch goal {
        case .lose:     return String(localized: "Quanto quer perder por semana?")
        case .gain:     return String(localized: "Quanto quer ganhar por semana?")
        case .maintain: return String(localized: "Tudo certo!")
        }
    }

    private var subtitle: String {
        switch goal {
        case .lose, .gain:
            return String(localized: "Recomendamos entre 0,3 e 0,75 kg/semana para resultados sustentáveis.")
        case .maintain:
            return String(localized: "Sem necessidade de definir um ritmo de mudança.")
        }
    }
}
