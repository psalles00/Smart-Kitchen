import SwiftUI

/// Phase 4 — Step 16. Desired rate of weight change. Two input modes:
/// 1. Target weight in N months (default, more intuitive).
/// 2. kg per week (advanced, classic).
/// The internal source of truth is `state.nutritionWeeklyChangeKg`. When in
/// target-weight mode, we derive it from `(currentWeight - targetWeight) /
/// (months * 4.345)` (avg weeks per month).
struct RateStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    @State private var didInitTarget = false

    private var goal: WeightGoal {
        WeightGoal(rawValue: state.nutritionGoalRaw ?? "") ?? .maintain
    }

    private let weeklyRange: ClosedRange<Double> = 0.1...1.0
    private let monthsRange: ClosedRange<Double> = 1...12

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(title: title, subtitle: subtitle)

            if goal == .maintain {
                maintainCard
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        modeToggle
                        if state.nutritionRateMode == .targetWeight {
                            targetWeightCard
                        } else {
                            perWeekCard
                        }
                        warningIfNeeded
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }

            Spacer(minLength: 0)

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
        .onAppear { initializeTargetIfNeeded() }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        Picker("", selection: $state.nutritionRateMode) {
            Text(String(localized: "Por meta")).tag(RateInputMode.targetWeight)
            Text(String(localized: "Por semana")).tag(RateInputMode.perWeek)
        }
        .pickerStyle(.segmented)
        .onChange(of: state.nutritionRateMode) { _, newMode in
            if newMode == .perWeek {
                // Recompute weekly from current target/months pair so user
                // sees a coherent value when switching.
                syncWeeklyFromTarget()
            } else {
                // Recompute target weight from current weekly when switching
                // back, so the target slider reflects current intent.
                syncTargetFromWeekly()
            }
        }
    }

    // MARK: - Target weight card

    private var targetWeightCard: some View {
        VStack(spacing: 16) {
            // Target weight stepper row
            VStack(spacing: 8) {
                Text(String(localized: "Quero chegar a"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.0f", state.nutritionTargetWeightKg))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.25, dampingFraction: 0.85),
                                   value: state.nutritionTargetWeightKg)
                    Text("kg")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $state.nutritionTargetWeightKg,
                    in: targetWeightRange,
                    step: 1
                )
                .tint(.primary)
                .onChange(of: state.nutritionTargetWeightKg) { _, _ in
                    syncWeeklyFromTarget()
                }
            }

            Divider().opacity(0.3)

            // Months stepper row
            VStack(spacing: 8) {
                Text(String(localized: "Em quantos meses"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.nutritionTargetMonths)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.25, dampingFraction: 0.85),
                                   value: state.nutritionTargetMonths)
                    Text(state.nutritionTargetMonths == 1
                         ? String(localized: "mês")
                         : String(localized: "meses"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(state.nutritionTargetMonths) },
                        set: { state.nutritionTargetMonths = Int($0.rounded()) }
                    ),
                    in: monthsRange,
                    step: 1
                )
                .tint(.primary)
                .onChange(of: state.nutritionTargetMonths) { _, _ in
                    syncWeeklyFromTarget()
                }
            }

            // Derived rate summary
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                Text(String(format: String(localized: "Equivale a %.2f kg/semana"),
                            state.nutritionWeeklyChangeKg))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
    }

    // MARK: - Per-week card

    private var perWeekCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", state.nutritionWeeklyChangeKg))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.85),
                               value: state.nutritionWeeklyChangeKg)
                Text(String(localized: "kg/semana"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $state.nutritionWeeklyChangeKg, in: weeklyRange, step: 0.1)
                .tint(.primary)
                .padding(.horizontal, 8)
                .onChange(of: state.nutritionWeeklyChangeKg) { _, _ in
                    syncTargetFromWeekly()
                }

            HStack {
                Text(String(localized: "Devagar"))
                Spacer()
                Text(String(localized: "Agressivo"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
        .animation(.easeOut(duration: 0.2), value: state.nutritionWeeklyChangeKg)
    }

    // MARK: - Maintain card

    private var maintainCard: some View {
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
    }

    @ViewBuilder
    private var warningIfNeeded: some View {
        if state.nutritionWeeklyChangeKg > 0.75 {
            Label(String(localized: "Ritmos acima de 0,75 kg/semana podem ser difíceis de manter."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.orange)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale))
        }
    }

    // MARK: - Conversion helpers

    /// Recompute `nutritionWeeklyChangeKg` from target weight + months.
    private func syncWeeklyFromTarget() {
        let weeks = Double(state.nutritionTargetMonths) * 4.345
        guard weeks > 0 else { return }
        let totalDelta = abs(state.nutritionWeightKg - state.nutritionTargetWeightKg)
        let weekly = (totalDelta / weeks).clamped(to: weeklyRange)
        state.nutritionWeeklyChangeKg = weekly
    }

    /// Recompute target weight from weekly rate (assuming current
    /// `nutritionTargetMonths`). Keeps months stable; nudges target weight.
    private func syncTargetFromWeekly() {
        let weeks = Double(state.nutritionTargetMonths) * 4.345
        let delta = state.nutritionWeeklyChangeKg * weeks
        let signed = goal == .lose ? -delta : delta
        let candidate = state.nutritionWeightKg + signed
        state.nutritionTargetWeightKg = candidate.clamped(to: targetWeightRange)
    }

    private func initializeTargetIfNeeded() {
        guard !didInitTarget else { return }
        didInitTarget = true
        // Default target = current ± 5 kg, in the goal direction.
        let baseDelta: Double = 5
        let signed = goal == .lose ? -baseDelta : baseDelta
        state.nutritionTargetWeightKg = (state.nutritionWeightKg + signed)
            .clamped(to: targetWeightRange)
        // Ensure the weekly rate matches the default target.
        syncWeeklyFromTarget()
    }

    private var targetWeightRange: ClosedRange<Double> {
        switch goal {
        case .lose:
            // Allow at most 30 kg below current, but not below 35 kg total.
            let lower = max(35, state.nutritionWeightKg - 30)
            let upper = max(lower + 1, state.nutritionWeightKg - 1)
            return lower...upper
        case .gain:
            let lower = state.nutritionWeightKg + 1
            let upper = state.nutritionWeightKg + 30
            return lower...upper
        case .maintain:
            return state.nutritionWeightKg...state.nutritionWeightKg
        }
    }

    private var title: String {
        switch goal {
        case .lose:     return String(localized: "Qual seu plano de perda?")
        case .gain:     return String(localized: "Qual seu plano de ganho?")
        case .maintain: return String(localized: "Tudo certo!")
        }
    }

    private var subtitle: String {
        switch goal {
        case .lose, .gain:
            return String(localized: "Defina o peso-alvo e o prazo. Você pode ajustar pra kg/semana se preferir.")
        case .maintain:
            return String(localized: "Sem necessidade de definir um ritmo de mudança.")
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
