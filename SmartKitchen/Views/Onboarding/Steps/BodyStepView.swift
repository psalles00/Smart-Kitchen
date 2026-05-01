import SwiftUI

/// Phase 4 — Step 14. Height + current weight via large inline pickers.
struct BodyStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Sua altura e peso"),
                subtitle: String(localized: "Não se preocupe — você pode atualizar quando quiser.")
            )

            VStack(spacing: 16) {
                metricCard(
                    title: String(localized: "Altura"),
                    icon: "ruler",
                    value: "\(Int(state.nutritionHeightCm))",
                    unit: "cm",
                    range: 120.0...220.0,
                    binding: $state.nutritionHeightCm,
                    step: 1
                )
                metricCard(
                    title: String(localized: "Peso atual"),
                    icon: "scalemass",
                    value: String(format: "%.1f", state.nutritionWeightKg),
                    unit: "kg",
                    range: 30.0...250.0,
                    binding: $state.nutritionWeightKg,
                    step: 0.5
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: true,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func metricCard(
        title: String,
        icon: String,
        value: String,
        unit: String,
        range: ClosedRange<Double>,
        binding: Binding<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: binding.wrappedValue)
                Text(unit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: binding, in: range, step: step)
                .tint(.primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
    }
}
