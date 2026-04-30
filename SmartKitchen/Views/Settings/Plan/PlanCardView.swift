import SwiftUI

/// Placeholder do card de plano exibido no topo de Configurações.
///
/// Esta tela é puramente visual e não está conectada a nenhum sistema real
/// de assinatura/StoreKit. Quando o paywall existir, esta view passa a
/// consultar o estado real do plano e a abrir o paywall de verdade.
struct PlanCardView: View {
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.85), .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)

                    Image(systemName: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plano atual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Free")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Conhecer Pro")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.tint)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallPlaceholderSheet()
        }
    }
}
