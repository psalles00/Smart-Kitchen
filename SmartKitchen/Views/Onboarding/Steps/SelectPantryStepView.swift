import SwiftUI

/// Phase 2 — Step 5. Pantry capture: pick at least 3 staples to seed the
/// app's pantry with. Selections are stored in `OnboardingState` and only
/// inserted into SwiftData when the flow commits at the very end.
struct SelectPantryStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            OnboardingHeader(
                title: String(localized: "O que tem na sua despensa?"),
                subtitle: String(localized: "Escolha pelo menos 3 itens. Arraste para descobrir mais.")
            )
            .padding(.top, 8)

            AsymmetricCircleCanvas(
                items: OnboardingCatalog.pantryItems,
                labelFor: { $0.displayName },
                iconFileFor: { $0.iconFileName },
                isSelected: { state.selectedPantryItemIDs.contains($0.id) },
                toggle: { toggle($0.id) },
                layoutSeed: 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                Text(counterLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state.canAdvancePantrySelection ? .secondary : Color.orange)
                    .animation(.easeOut(duration: 0.2), value: state.selectedPantryItemIDs.count)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.canAdvancePantrySelection,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if state.selectedPantryItemIDs.contains(id) {
                state.selectedPantryItemIDs.remove(id)
            } else {
                state.selectedPantryItemIDs.insert(id)
            }
        }
    }

    private var counterLabel: String {
        let count = state.selectedPantryItemIDs.count
        return count >= 3
            ? String(
                format: String(localized: "%lld selecionados"),
                locale: Locale.current,
                count
            )
            : String(
                format: String(localized: "Selecione mais %lld para continuar"),
                locale: Locale.current,
                3 - count
            )
    }
}
