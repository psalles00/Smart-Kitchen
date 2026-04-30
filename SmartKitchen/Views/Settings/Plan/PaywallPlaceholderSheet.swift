import SwiftUI

/// Placeholder do paywall. Substituir por StoreKit + planos reais no futuro.
struct PaywallPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct PlanRow: Identifiable {
        let id = UUID()
        let name: LocalizedStringKey
        let price: LocalizedStringKey
        let features: [LocalizedStringKey]
        let recommended: Bool
    }

    private let plans: [PlanRow] = [
        PlanRow(
            name: "Free",
            price: "Grátis",
            features: [
                "Receitas, despensa e mercado ilimitados",
                "Sincronização iCloud",
                "Backup local diário"
            ],
            recommended: false
        ),
        PlanRow(
            name: "Pro",
            price: "Em breve",
            features: [
                "IA avançada (planejamento semanal)",
                "Importação ilimitada de receitas externas",
                "Backup automático em iCloud Drive",
                "Compartilhamento familiar premium"
            ],
            recommended: true
        ),
        PlanRow(
            name: "Premium",
            price: "Em breve",
            features: [
                "Tudo de Pro",
                "Cache de nutrição com prioridade",
                "Suporte prioritário",
                "Recursos exclusivos antecipados"
            ],
            recommended: false
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 14) {
                        ForEach(plans) { plan in
                            planCard(plan)
                        }
                    }
                    .padding(.horizontal)

                    Text("O Smart Kitchen Pro chega em breve. Você poderá assinar diretamente daqui assim que a App Store liberar a função.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        dismiss()
                    } label: {
                        Text("Continuar no plano Free")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            .modalNavigationTitle(String(localized: "Smart Kitchen Pro"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.85), .blue.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text("Smart Kitchen Pro")
                .font(.title2.weight(.bold))
            Text("Recursos avançados para tirar o máximo da sua cozinha conectada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func planCard(_ plan: PlanRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            planHeaderRow(plan)
            Text(plan.price)
                .font(.title3.weight(.bold))
                .foregroundStyle(plan.recommended ? .primary : .secondary)
            planFeaturesList(plan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(plan.recommended ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func planHeaderRow(_ plan: PlanRow) -> some View {
        HStack {
            Text(plan.name)
                .font(.headline)
            Spacer()
            if plan.recommended {
                Text("Recomendado")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func planFeaturesList(_ plan: PlanRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(plan.features.enumerated()), id: \.offset) { _, feature in
                Label {
                    Text(feature)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(plan.recommended ? Color.accentColor : .secondary)
                }
            }
        }
        .padding(.top, 4)
    }
}
