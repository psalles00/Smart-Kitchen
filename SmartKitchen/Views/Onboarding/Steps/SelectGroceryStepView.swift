import SwiftUI

/// Phase 2 — Step 6. Grocery capture: pick at least 3 items to seed the
/// initial shopping list.
struct SelectGroceryStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            OnboardingHeader(
                title: String(localized: "O que precisa comprar?"),
                subtitle: String(localized: "Escolha pelo menos 3 itens. Arraste para descobrir mais.")
            )
            .padding(.top, 8)

            AsymmetricCircleCanvas(
                items: OnboardingCatalog.groceryItems,
                labelFor: { $0.displayName },
                iconFileFor: { $0.iconFileName },
                isSelected: { state.selectedGroceryItemIDs.contains($0.id) },
                toggle: { toggle($0.id) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                Text(counterLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state.canAdvanceGrocerySelection ? .secondary : Color.orange)
                    .animation(.easeOut(duration: 0.2), value: state.selectedGroceryItemIDs.count)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.canAdvanceGrocerySelection,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if state.selectedGroceryItemIDs.contains(id) {
                state.selectedGroceryItemIDs.remove(id)
            } else {
                state.selectedGroceryItemIDs.insert(id)
            }
        }
    }

    private var counterLabel: String {
        let count = state.selectedGroceryItemIDs.count
        return count >= 3
            ? String(localized: "\(count) selecionados")
            : String(localized: "Selecione mais \(3 - count) para continuar")
    }
}
