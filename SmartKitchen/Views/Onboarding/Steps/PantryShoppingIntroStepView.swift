import SwiftUI

/// Phase 1 — Step 3. Animation showing an item bouncing between a "Despensa"
/// card and a "Mercado" card to communicate the bidirectional flow that the
/// app's lists support.
struct PantryShoppingIntroStepView: View {
    let onContinue: () -> Void

    /// 0 = item lives on the Pantry side, 1 = item lives on the Grocery side.
    @State private var sideIsGrocery = false
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)

            stage
                .padding(.horizontal, 24)
                .frame(height: 240)

            OnboardingHeader(
                title: String(localized: "Despensa e mercado, conectados."),
                subtitle: String(localized: "Tirou da despensa? Vai pro mercado. Comprou? Volta pra despensa. Sem listas paralelas, sem trabalho dobrado.")
            )

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) {
                    sideIsGrocery.toggle()
                }
            }
        }
    }

    private var stage: some View {
        HStack(spacing: 14) {
            sideCard(
                title: String(localized: "Despensa"),
                iconSystemName: "cabinet",
                tint: Color.green,
                showsItem: !sideIsGrocery
            )
            sideCard(
                title: String(localized: "Mercado"),
                iconSystemName: "cart",
                tint: Color.orange,
                showsItem: sideIsGrocery
            )
        }
    }

    @ViewBuilder
    private func sideCard(title: String, iconSystemName: String, tint: Color, showsItem: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: iconSystemName)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if showsItem {
                    travelingItem(tint: tint)
                        .matchedGeometryEffect(id: "tomato", in: ns)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func travelingItem(tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.32, blue: 0.28),
                             Color(red: 0.78, green: 0.18, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(
                    Capsule()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: 4, height: 8)
                        .offset(x: 0, y: -16)
                )
            Text(String(localized: "Tomate"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
