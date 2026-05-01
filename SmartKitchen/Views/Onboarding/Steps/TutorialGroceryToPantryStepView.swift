import SwiftUI

/// Phase 3 — Step 9. Reverse demo: tap the checkbox on a grocery item to
/// "buy" it; the item then jumps into the pantry. Visually mirrors
/// `GroceryListRow` (divider, balloon icon, native checkbox).
struct TutorialGroceryToPantryStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    @State private var groceryItems: [DemoItem] = [
        DemoItem(id: "apple",   name: String(localized: "Maçã"),    iconFileName: "apple.png"),
        DemoItem(id: "yogurt",  name: String(localized: "Iogurte"), iconFileName: "yogurt.png"),
        DemoItem(id: "rice",    name: String(localized: "Arroz"),   iconFileName: "rice.png"),
    ]
    @State private var pantryItems: [DemoItem] = []
    @State private var checkedID: String? = nil
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Comprou? Marca como feito."),
                subtitle: String(localized: "O item é enviado direto para sua despensa. Toque na caixinha de um item.")
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    listPanel(
                        title: String(localized: "Mercado"),
                        accent: Color.orange,
                        icon: "cart.fill",
                        items: groceryItems,
                        emptyMessage: String(localized: "Lista concluída!"),
                        rowButton: { item in
                            .checkbox(isChecked: checkedID == item.id,
                                      action: { buy(item) })
                        }
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(localized: "Vai para a despensa"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)

                    listPanel(
                        title: String(localized: "Despensa"),
                        accent: Color.green,
                        icon: "cabinet",
                        items: pantryItems,
                        emptyMessage: String(localized: "Marque um item acima"),
                        rowButton: { _ in .none }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                if !state.didCompleteGroceryToPantryTutorial {
                    Label(String(localized: "Toque na caixinha de um item"), systemImage: "hand.tap.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.didCompleteGroceryToPantryTutorial,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func buy(_ item: DemoItem) {
        withAnimation(.easeInOut(duration: 0.18)) {
            checkedID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                groceryItems.removeAll { $0.id == item.id }
                pantryItems.append(item)
                state.didCompleteGroceryToPantryTutorial = true
                checkedID = nil
            }
        }
    }

    @ViewBuilder
    private func listPanel(
        title: String,
        accent: Color,
        icon: String,
        items: [DemoItem],
        emptyMessage: String,
        rowButton: @escaping (DemoItem) -> TutorialItemRow.TrailingButton
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TutorialItemRow(
                            item: item,
                            namespace: ns,
                            showsDivider: index > 0,
                            trailingButton: rowButton(item)
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(neutralSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }
}
