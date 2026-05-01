import SwiftUI
import StoreKit

/// Phase 5 — Step 18. Final paywall. Two product cards (Anual com trial /
/// Mensal), CTA grande, links Termos/Privacidade/Restaurar e botão "Continuar
/// gratuitamente" abaixo (sem trial-paywall hostil).
///
/// O onboarding **conclui** ao chamar `onFinish(subscribed:)` — independente
/// de o usuário comprar ou pular. Os dados (NutritionProfile, pantry, grocery,
/// recipes) já foram gravados na tela `preparing`.
struct PaywallStepView: View {
    @Bindable var state: OnboardingState
    let onFinish: (_ subscribed: Bool) -> Void

    @State private var manager = SubscriptionManager()
    @State private var selectedID: String = SubscriptionManager.annualProductID
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            backgroundLayer.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    benefits
                    plans
                    purchaseSection
                    legalLinks
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            await manager.loadProducts()
        }
        .alert("Erro na compra", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .preferredColorScheme(nil)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.92, blue: 0.78),
                Color(red: 0.95, green: 0.78, blue: 0.62),
                Color(red: 0.92, green: 0.65, blue: 0.50),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppLogoB")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            Text(String(localized: "Desbloqueie tudo no Savoria"))
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text(String(localized: "Comece com 7 dias grátis no plano anual."))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(icon: "wand.and.stars", title: String(localized: "IA ilimitada"), subtitle: String(localized: "Sugestões, importações e nutrição sem limites."))
            BenefitRow(icon: "icloud.fill", title: String(localized: "iCloud + backup"), subtitle: String(localized: "Sincronização entre dispositivos com restauração."))
            BenefitRow(icon: "person.2.fill", title: String(localized: "Compartilhamento familiar"), subtitle: String(localized: "Despensa e listas em tempo real com a família."))
            BenefitRow(icon: "bolt.fill", title: String(localized: "Recursos novos primeiro"), subtitle: String(localized: "Acesso antecipado a tudo que lançamos."))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Plans

    private var plans: some View {
        VStack(spacing: 12) {
            planCard(
                product: manager.annualProduct,
                productID: SubscriptionManager.annualProductID,
                title: String(localized: "Anual"),
                badge: String(localized: "7 dias grátis"),
                fallbackPrice: "$39.99",
                period: String(localized: "/ano"),
                pricePerMonth: pricePerMonthLabel(for: manager.annualProduct, dividedBy: 12),
                isBestValue: true
            )
            planCard(
                product: manager.monthlyProduct,
                productID: SubscriptionManager.monthlyProductID,
                title: String(localized: "Mensal"),
                badge: nil,
                fallbackPrice: "$6.99",
                period: String(localized: "/mês"),
                pricePerMonth: nil,
                isBestValue: false
            )
        }
    }

    @ViewBuilder
    private func planCard(
        product: Product?,
        productID: String,
        title: String,
        badge: String?,
        fallbackPrice: String,
        period: String,
        pricePerMonth: String?,
        isBestValue: Bool
    ) -> some View {
        let isSelected = selectedID == productID
        let priceString = product?.displayPrice ?? fallbackPrice

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedID = productID
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(red: 1.0, green: 0.55, blue: 0.20)))
                            .foregroundStyle(.white)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(priceString)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(period)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let pricePerMonth {
                    Text(pricePerMonth)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                isSelected
                    ? .regular.tint(Color.white.opacity(0.45)).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: 22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : Color.black.opacity(0.10), lineWidth: isSelected ? 2.5 : 1)
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            Button(action: handleBuy) {
                HStack {
                    if case .purchasing = manager.purchaseState {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaLabel)
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(red: 0.96, green: 0.40, blue: 0.18))
            .controlSize(.extraLarge)
            .disabled(manager.products.isEmpty)
            .opacity(manager.products.isEmpty ? 0.6 : 1)

            Button(action: { onFinish(false) }) {
                Text(String(localized: "Continuar com plano grátis"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
    }

    private var ctaLabel: String {
        if selectedID == SubscriptionManager.annualProductID {
            return String(localized: "Iniciar 7 dias grátis")
        }
        return String(localized: "Assinar agora")
    }

    private func handleBuy() {
        guard let product = manager.products[selectedID] else { return }
        Task {
            let success = await manager.purchase(product)
            if success {
                onFinish(true)
            } else if case .failed(let msg) = manager.purchaseState {
                errorMessage = msg
                showingErrorAlert = true
            }
        }
    }

    // MARK: - Legal

    private var legalLinks: some View {
        HStack(spacing: 18) {
            Button(String(localized: "Restaurar")) {
                Task {
                    await manager.restore()
                    if manager.isSubscribed { onFinish(true) }
                }
            }
            Button(String(localized: "Termos")) {
                if let url = URL(string: "https://savoria.app/terms") { openURL(url) }
            }
            Button(String(localized: "Privacidade")) {
                if let url = URL(string: "https://savoria.app/privacy") { openURL(url) }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    @Environment(\.openURL) private var openURL

    // MARK: - Helpers

    private func pricePerMonthLabel(for product: Product?, dividedBy months: Int) -> String? {
        guard let product else { return nil }
        let perMonth = product.price / Decimal(months)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        if let str = formatter.string(from: perMonth as NSDecimalNumber) {
            return String(format: String(localized: "Equivale a %@/mês"), str)
        }
        return nil
    }
}

// MARK: - Benefit row

private struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.15))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(subtitle).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
