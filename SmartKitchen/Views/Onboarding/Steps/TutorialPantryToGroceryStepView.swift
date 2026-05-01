import SwiftUI

// MARK: - Demo model used by both pantry/grocery tutorials.

struct DemoItem: Identifiable, Hashable {
    let id: String
    let name: String
    let iconFileName: String
}

// MARK: - Demo row that visually mirrors PantryItemRow / GroceryListRow.

struct TutorialItemRow: View {
    let item: DemoItem
    let namespace: Namespace.ID
    let showsDivider: Bool
    let trailingButton: TrailingButton

    enum TrailingButton {
        /// Pantry → Grocery. Shows a circular "+ cart" button (lists accent).
        case sendToGrocery(action: () -> Void)
        /// Grocery → Pantry. Shows a checkbox that ticks before sending.
        case checkbox(isChecked: Bool, action: () -> Void)
        /// No action (passive row, e.g. items already moved).
        case none
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                ItemListDivider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            HStack(alignment: .center, spacing: 12) {
                IconImage(
                    name: item.name,
                    iconFileName: item.iconFileName,
                    fallbackSymbol: "leaf",
                    size: 24,
                    showBalloon: true
                )
                .matchedGeometryEffect(id: item.id, in: namespace)

                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer()

                trailingControl
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch trailingButton {
        case .sendToGrocery(let action):
            Button(action: action) {
                Image(systemName: "cart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(PageTheme.lists.accentColor))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: false)

        case .checkbox(let isChecked, let action):
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PageTheme.lists.accentColor, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isChecked {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PageTheme.lists.accentColor)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: isChecked)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Tutorial: Pantry → Grocery

/// Phase 3 — Step 8. Interactive demo: tap the cart on a pantry item to
/// send it to the grocery list. The continue button only enables once the
/// user performs the gesture themselves.
struct TutorialPantryToGroceryStepView: View {
    @Bindable var state: OnboardingState
    let onContinue: () -> Void

    @State private var pantryItems: [DemoItem] = [
        DemoItem(id: "tomato",  name: String(localized: "Tomate"),  iconFileName: "tomato.png"),
        DemoItem(id: "milk",    name: String(localized: "Leite"),   iconFileName: "milk.png"),
        DemoItem(id: "bread",   name: String(localized: "Pão"),     iconFileName: "bread-white.png"),
    ]
    @State private var groceryItems: [DemoItem] = []
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Acabou na despensa? Mande pro mercado."),
                subtitle: String(localized: "Toque no carrinho de um item para movê-lo para sua lista de compras.")
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    listPanel(
                        title: String(localized: "Despensa"),
                        accent: Color.green,
                        icon: "cabinet",
                        items: pantryItems,
                        emptyMessage: String(localized: "Tudo enviado!"),
                        rowButton: { item in .sendToGrocery(action: { send(item) }) }
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(localized: "Vai para o mercado"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)

                    listPanel(
                        title: String(localized: "Mercado"),
                        accent: Color.orange,
                        icon: "cart.fill",
                        items: groceryItems,
                        emptyMessage: String(localized: "Toque em um item acima"),
                        rowButton: { _ in .none }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                if !state.didCompletePantryToGroceryTutorial {
                    Label(String(localized: "Toque no ícone de carrinho de um item"), systemImage: "hand.tap.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    isEnabled: state.didCompletePantryToGroceryTutorial,
                    action: onContinue
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func send(_ item: DemoItem) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            pantryItems.removeAll { $0.id == item.id }
            groceryItems.append(item)
            state.didCompletePantryToGroceryTutorial = true
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
