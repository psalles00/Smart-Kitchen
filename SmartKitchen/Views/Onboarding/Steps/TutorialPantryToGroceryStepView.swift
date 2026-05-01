import SwiftUI

/// Phase 3 — Step 8. Interactive demo: tap the "+" / market icon on a pantry
/// item to send it to the grocery list. The user MUST perform the gesture
/// themselves (no auto-animation) — the continue button only enables once
/// `state.didCompletePantryToGroceryTutorial` flips true.
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
                    panel(
                        title: String(localized: "Despensa"),
                        accent: Color.green,
                        icon: "cabinet",
                        items: pantryItems,
                        actionIcon: "cart.fill.badge.plus",
                        emptyMessage: String(localized: "Tudo enviado!"),
                        onTap: send(_:)
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(localized: "Vai para o mercado"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)

                    panel(
                        title: String(localized: "Mercado"),
                        accent: Color.orange,
                        icon: "cart.fill",
                        items: groceryItems,
                        actionIcon: nil,
                        emptyMessage: String(localized: "Toque em um item acima"),
                        onTap: { _ in }
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
    private func panel(
        title: String,
        accent: Color,
        icon: String,
        items: [DemoItem],
        actionIcon: String?,
        emptyMessage: String,
        onTap: @escaping (DemoItem) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        DemoItemRow(
                            item: item,
                            namespace: ns,
                            actionIcon: actionIcon,
                            actionTint: accent
                        ) { onTap(item) }
                    }
                }
            }
        }
        .padding(14)
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

// MARK: - Shared building blocks

struct DemoItem: Identifiable, Hashable {
    let id: String
    let name: String
    let iconFileName: String
}

struct DemoItemRow: View {
    let item: DemoItem
    let namespace: Namespace.ID
    let actionIcon: String?
    let actionTint: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let img = IconResolver.image(forFilename: item.iconFileName) {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                }
            }
            .frame(width: 44, height: 44)
            .matchedGeometryEffect(id: item.id, in: namespace)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if let actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(actionTint))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: false)
            }
        }
    }
}
