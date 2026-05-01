import SwiftUI

/// Phase 2 — Step 5. Pantry capture: pick at least 3 staples to seed the
/// app's pantry with. Selections are stored in `OnboardingState` and only
/// inserted into SwiftData when the flow commits at the very end.
struct SelectPantryStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 14)]

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "O que tem na sua despensa?"),
                subtitle: String(localized: "Escolha pelo menos 3 itens. Você pode editar tudo depois.")
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(OnboardingCatalog.pantryItems) { item in
                        OnboardingItemTile(
                            title: item.displayName,
                            iconFileName: item.iconFileName,
                            isSelected: state.selectedPantryItemIDs.contains(item.id),
                            action: { toggle(item.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

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
            ? String(localized: "\(count) selecionados")
            : String(localized: "Selecione mais \(3 - count) para continuar")
    }
}
