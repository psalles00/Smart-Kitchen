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

    private let theme = PageTheme.lists

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundLayer.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                        benefits
                        plans
                        legalLinks
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, max(24, proxy.safeAreaInsets.top + 36))
                    .padding(.bottom, 180)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                purchaseSection
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
            }
            .overlay(alignment: .topLeading) {
                Button {
                    onFinish(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(String(localized: "Fechar"))
                .padding(.top, proxy.safeAreaInsets.top + 8)
                .padding(.leading, 16)
                .zIndex(10)
            }
        }
        .task {
            await manager.loadProducts()
        }
        .alert("Erro na compra", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            NebulaShaderView(theme: .lists, progress: 1.0)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.24),
                    Color.black.opacity(0.60)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppLogoB")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.30), radius: 24, y: 10)

            Text(String(localized: "Desbloqueie tudo no Savoria"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text(String(localized: "Comece com 7 dias grátis no plano anual."))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
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
        .glassEffect(.regular.tint(darkGlassTint).interactive(), in: .rect(cornerRadius: 24))
        .overlay(surfaceBorder(cornerRadius: 24))
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
                            .background(Capsule().fill(theme.secondaryAccentColor))
                            .foregroundStyle(.white)
                    }
                }
                .foregroundStyle(.white)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(priceString)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(period)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                }
                if let pricePerMonth {
                    Text(pricePerMonth)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                isSelected
                    ? .regular.tint(selectedGlassTint).interactive()
                    : .regular.tint(darkCardTint).interactive(),
                in: .rect(cornerRadius: 22)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.16),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var purchaseSection: some View {
        VStack(spacing: 14) {
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
            .tint(theme.accentColor)
            .controlSize(.extraLarge)
            .disabled(manager.products.isEmpty)
            .opacity(manager.products.isEmpty ? 0.6 : 1)

            // Discreet text-only fallback. No background, no chrome.
            Button(action: { onFinish(false) }) {
                Text(String(localized: "Continuar com plano grátis"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
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
        .foregroundStyle(.white.opacity(0.72))
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .glassEffect(.regular.tint(darkGlassTint), in: .capsule)
        .overlay(surfaceBorder(cornerRadius: 999))
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

    private var darkGlassTint: Color {
        Color(red: 0.05, green: 0.09, blue: 0.16).opacity(0.78)
    }

    private var darkCardTint: Color {
        Color(red: 0.06, green: 0.10, blue: 0.18).opacity(0.72)
    }

    private var selectedGlassTint: Color {
        theme.accentColor.opacity(0.28)
    }

    @ViewBuilder
    private func surfaceBorder(cornerRadius: CGFloat, emphasis: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                Color.white.opacity(emphasis ? 0.22 : 0.14),
                lineWidth: emphasis ? 1.2 : 1
            )
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
                .foregroundStyle(PageTheme.lists.secondaryAccentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
    }
}
