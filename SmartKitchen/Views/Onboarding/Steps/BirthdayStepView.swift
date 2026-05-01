import SwiftUI

/// Phase 4 — Step 13. Birthday picker (wheel) for age-based BMR.
struct BirthdayStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    /// Default to ~30 years ago if not set.
    private var defaultDate: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    }

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Quando você nasceu?"),
                subtitle: String(localized: "Sua idade afeta a quantidade de calorias que seu corpo precisa.")
            )

            DatePicker(
                "",
                selection: Binding(
                    get: { state.nutritionBirthday ?? defaultDate },
                    set: { state.nutritionBirthday = $0 }
                ),
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: true,
                action: {
                    if state.nutritionBirthday == nil {
                        state.nutritionBirthday = defaultDate
                    }
                    onContinue()
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
