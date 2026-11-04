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
                title: String(localized: "Quando você nasceu?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
                subtitle: String(localized: "Sua idade afeta a quantidade de calorias que seu corpo precisa.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)
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
#if os(iOS)
            .datePickerStyle(.wheel)
#else
            .datePickerStyle(.graphical)
#endif
            .labelsHidden()
            .padding(.horizontal, 20)

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale),
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

