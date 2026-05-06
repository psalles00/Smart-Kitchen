import SwiftUI
import StoreKit

/// Phase 5 — Final paywall. Redesigned 2026-05 to follow a focused single-plan
/// layout (annual w/ trial) with an expandable "show more plans" toggle that
/// reveals the monthly option, a Free × Premium comparison table, and a
/// floating CTA with restore / legal links beneath.
///
/// The onboarding **conclui** ao chamar `onFinish(subscribed:)` — independente
/// de o usuário comprar ou pular. Os dados (NutritionProfile, pantry, grocery,
/// recipes) já foram gravados na tela `preparing`.
struct PaywallStepView: View {
    @Bindable var state: OnboardingState
    let onFinish: (_ subscribed: Bool) -> Void

    @State private var manager = SubscriptionManager()
    @State private var selectedID: String = SubscriptionManager.annualProductID
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showAllPlans = false



    private let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.73, green: 0.89, blue: 1.00),
            Color(red: 0.49, green: 0.70, blue: 1.00),
            Color(red: 0.38, green: 0.86, blue: 0.98)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundLayer.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroSection
                        .padding(.top, 2)
                    titleBlock
                    plansSection
                    benefitsTable
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 260)
            }

            // Discreet close button — top-left.
            closeButton
                .padding(.leading, 14)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseSection
        }
        .task {
            state.selectedPlanID = selectedID
            await manager.loadProducts()
        }
        .alert(String(localized: "Erro na compra"), isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
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

    // MARK: - Close

    private var closeButton: some View {
        Button(action: { onFinish(false) }) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Fechar"))
    }

    // MARK: - Hero

    private var heroSection: some View {
        Image("AppLogoB")
            .resizable()
            .scaledToFit()
            .frame(width: 118, height: 118)
            .shadow(color: Color.black.opacity(0.30), radius: 26, y: 10)
            .offset(y: -10)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Savoria")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("PREMIUM")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(primaryGradient)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .tracking(0.6)

            // "Achieve your goals 4.3x faster" — 4.3x with gradient.
            achieveHeadline
                .font(.custom("Bricolage Grotesque", size: 40, relativeTo: .largeTitle).weight(.heavy))
                .tracking(-0.5)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    private var achieveHeadline: Text {
        let prefix = String(localized: "Alcance seus objetivos ")
        let highlight = String(localized: "4.3x")
        let suffix = String(localized: " mais rápido")
        return Text(prefix).foregroundStyle(.white)
            + Text(highlight).foregroundStyle(primaryGradient)
            + Text(suffix).foregroundStyle(.white)
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 12) {
            // Annual plan — always visible, highlighted.
            planCard(
                product: manager.annualProduct,
                productID: SubscriptionManager.annualProductID,
                title: String(localized: "7 dias grátis"),
                badge: String(localized: "Mais popular"),
                fallbackPrice: "$3.34",
                period: String(localized: "por mês"),
                subtitle: annualSubtitle,
                isAnnual: true
            )

            if showAllPlans {
                planCard(
                    product: manager.monthlyProduct,
                    productID: SubscriptionManager.monthlyProductID,
                    title: String(localized: "Mensal"),
                    badge: nil,
                    fallbackPrice: "$6.99",
                    period: String(localized: "por mês"),
                    subtitle: nil,
                    isAnnual: false
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    showAllPlans.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(showAllPlans
                         ? String(localized: "Ocultar planos")
                         : String(localized: "Mostrar mais planos"))
                    Image(systemName: showAllPlans ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    /// "then $79.98 → $39.98/yr" subtitle for the annual card.
    private var annualSubtitle: AttributedString? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = manager.annualProduct?.priceFormatStyle.locale ?? Locale.current
        let annualPriceStr = manager.annualProduct?.displayPrice ?? "$39.98"
        let referenceStr: String = {
            guard let monthly = manager.monthlyProduct else { return nil }
            let reference = monthly.price * 12
            return formatter.string(from: reference as NSDecimalNumber)
        }() ?? "$79.98"

        // Compose: "then $79.98 → $39.98/yr"
        let prefix = String(localized: "depois ")
        let arrow = "  →  "
        let yrSuffix = String(localized: "/ano")

        var attr = AttributedString(prefix)
        attr.foregroundColor = PlatformColor.white.withAlphaComponent(0.55)
        var ref = AttributedString(referenceStr)
        ref.foregroundColor = PlatformColor.white.withAlphaComponent(0.55)
        ref.strikethroughStyle = NSUnderlineStyle.single
        attr.append(ref)
        var arrowAttr = AttributedString(arrow)
        arrowAttr.foregroundColor = PlatformColor.white.withAlphaComponent(0.55)
        attr.append(arrowAttr)
        var price = AttributedString(annualPriceStr + yrSuffix)
        price.foregroundColor = PlatformColor.white.withAlphaComponent(0.85)
        attr.append(price)
        return attr
    }

    @ViewBuilder
    private func planCard(
        product: Product?,
        productID: String,
        title: String,
        badge: String?,
        fallbackPrice: String,
        period: String,
        subtitle: AttributedString?,
        isAnnual: Bool
    ) -> some View {
        let isSelected = selectedID == productID
        let priceString: String = {
            if isAnnual, let p = product {
                let perMonth = p.price / Decimal(12)
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = p.priceFormatStyle.locale
                return formatter.string(from: perMonth as NSDecimalNumber) ?? fallbackPrice
            }
            return product?.displayPrice ?? fallbackPrice
        }()

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedID = productID
                state.selectedPlanID = productID
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(primaryGradient)
                        )
                        .foregroundStyle(.white)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.custom("Bricolage Grotesque", size: 22, relativeTo: .title2).weight(.bold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(priceString)
                            .font(.custom("Bricolage Grotesque", size: 24, relativeTo: .title2).weight(.bold))
                            .foregroundStyle(.white)
                        Text(period)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(primaryGradient)
                            : AnyShapeStyle(Color.white.opacity(0.12)),
                        lineWidth: isSelected ? 2.0 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Benefits comparison table

    private var benefitsTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "O que você ganha"))
                .font(.custom("Bricolage Grotesque", size: 20, relativeTo: .title3).weight(.bold))
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                tableHeader

                Divider().background(Color.white.opacity(0.18)).opacity(0.6)

                ForEach(comparisonRows.indices, id: \.self) { idx in
                    let row = comparisonRows[idx]
                    benefitRow(icon: row.icon, title: row.title, freeIncluded: row.free, premiumIncluded: row.premium)
                    if idx < comparisonRows.count - 1 {
                        Divider().background(Color.white.opacity(0.10))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Text(String(localized: "Grátis"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 60, alignment: .center)
            Text(String(localized: "Premium"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(primaryGradient)
                .frame(width: 60, alignment: .center)
        }
        .padding(.bottom, 8)
    }

    private struct ComparisonRow {
        let icon: String
        let title: String
        let free: Bool
        let premium: Bool
    }

    private var comparisonRows: [ComparisonRow] {
        [
            .init(icon: "wand.and.stars",
                  title: String(localized: "IA ilimitada"),
                  free: false, premium: true),
            .init(icon: "square.and.arrow.down",
                  title: String(localized: "Importação ilimitada de receitas"),
                  free: false, premium: true),
            .init(icon: "icloud.fill",
                  title: String(localized: "iCloud + backup"),
                free: false, premium: true),
            .init(icon: "person.2.fill",
                  title: String(localized: "Compartilhamento familiar"),
                  free: false, premium: true),
            .init(icon: "chart.pie.fill",
                  title: String(localized: "Nutrição IA sem limites"),
                  free: false, premium: true),
            .init(icon: "bolt.fill",
                  title: String(localized: "Recursos novos primeiro"),
                  free: false, premium: true)
        ]
    }

    private func benefitRow(icon: String, title: String, freeIncluded: Bool, premiumIncluded: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(primaryGradient)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
            includedMark(included: freeIncluded, premium: false)
                .frame(width: 60, alignment: .center)
            includedMark(included: premiumIncluded, premium: true)
                .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func includedMark(included: Bool, premium: Bool) -> some View {
        if included {
            if premium {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryGradient)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            Image(systemName: "minus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.30))
        }
    }

    // MARK: - Purchase section (floating bottom)

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Button(action: handleBuy) {
                HStack {
                    if case .purchasing = manager.purchaseState {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaLabel)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(primaryGradient)
                )
                .shadow(color: Color(red: 0.38, green: 0.86, blue: 0.98).opacity(0.30), radius: 22, y: 10)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(manager.products.isEmpty)
            .opacity(manager.products.isEmpty ? 0.6 : 1)
            .sensoryFeedback(.impact(weight: .medium), trigger: manager.purchaseState.isSuccess)

            HStack {
                Button(String(localized: "Restaurar compras"), action: handleRestore)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(footerDisclaimer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.trailing)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 22)
        .padding(.top, 72)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            // Dark gradient backdrop — transitions from transparent at the top
            // (so content above can blend) to fully opaque dark at the bottom
            // for crisp legibility behind the CTA.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.16),
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.92),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var footerDisclaimer: String {
        if selectedID == SubscriptionManager.monthlyProductID {
            return String(localized: "Cancele quando quiser.")
        }
        return String(localized: "Sem cobrança agora. Cancele quando quiser.")
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

    private func handleRestore() {
        Task {
            await manager.restore()
            if manager.isSubscribed { onFinish(true) }
        }
    }
}

private extension SubscriptionManager.PurchaseState {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
