import SwiftUI
import StoreKit

/// Card de plano exibido no topo de Configurações.
///
/// Lê estado real da assinatura via `SubscriptionManager` (StoreKit 2) e
/// abre o paywall quando o usuário toca. Para usuários premium, mostra a
/// data de renovação/expiração e abre o sheet nativo de gerenciamento.
struct PlanCardView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false
    @State private var showManage = false

    private var isPremium: Bool { subscriptionManager.isSubscribed }

    private var planLabel: String {
        #if DEBUG && os(iOS)
        if subscriptionManager.debugMode != .appStore {
            return subscriptionManager.debugMode.title
        }
        #endif
        guard let id = subscriptionManager.activeProductID else {
            return String(localized: "Free")
        }
        if id == SubscriptionManager.annualProductID {
            return String(localized: "Premium Anual")
        }
        if id == SubscriptionManager.monthlyProductID {
            return String(localized: "Premium Mensal")
        }
        return String(localized: "Premium")
    }

    private var subtitle: String? {
        #if DEBUG && os(iOS)
        if subscriptionManager.debugMode != .appStore { return String(localized: "Plano simulado") }
        #endif
        guard isPremium, let date = subscriptionManager.expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(format: String(localized: "Renova em %@"), formatter.string(from: date))
    }

    var body: some View {
        Button {
            #if DEBUG && os(iOS)
            if subscriptionManager.debugMode != .appStore {
                showPaywall = true
                return
            }
            #endif
            if isPremium {
                showManage = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isPremium
                                    ? [Color(red: 0.98, green: 0.83, blue: 0.43),
                                       Color(red: 0.82, green: 0.60, blue: 1.00)]
                                    : [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: isPremium ? "crown.fill" : "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plano atual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(planLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isPremium {
                    Text("Gerenciar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("Conhecer Premium")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(reason: .manual)
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $showManage)
        #endif
    }
}
