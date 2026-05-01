import SwiftUI

/// Phase 3 — Step 9. Reverse demo: tap the checkbox on a grocery item to
/// "buy" it; the item then jumps into the pantry. The user MUST perform the
/// gesture themselves.
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
                    panel(
                        title: String(localized: "Mercado"),
                        accent: Color.orange,
                        icon: "cart.fill",
                        items: groceryItems,
                        showCheckbox: true,
                        emptyMessage: String(localized: "Lista concluída!"),
                        onCheck: buy(_:)
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(localized: "Vai para a despensa"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)

                    panel(
                        title: String(localized: "Despensa"),
                        accent: Color.green,
                        icon: "cabinet",
                        items: pantryItems,
                        showCheckbox: false,
                        emptyMessage: String(localized: "Marque um item acima"),
                        onCheck: { _ in }
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
    private func panel(
        title: String,
        accent: Color,
        icon: String,
        items: [DemoItem],
        showCheckbox: Bool,
        emptyMessage: String,
        onCheck: @escaping (DemoItem) -> Void
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
                        HStack(spacing: 12) {
                            if showCheckbox {
                                Button(action: { onCheck(item) }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(accent, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                        if checkedID == item.id {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(accent)
                                                .frame(width: 24, height: 24)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .sensoryFeedback(.success, trigger: checkedID == item.id)
                            }

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
                            .matchedGeometryEffect(id: item.id, in: ns)

                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))

                            Spacer()
                        }
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
