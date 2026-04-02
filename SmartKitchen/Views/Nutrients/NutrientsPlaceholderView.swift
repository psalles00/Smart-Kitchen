import SwiftUI

struct NutrientsPlaceholderView: View {
    var body: some View {
        ExpandedPageLayout(
            pageTheme: .nutrients,
            startsWithInfoCollapsed: true,
            header: { isInverted in
                PageHeader(title: "Nutrientes", isInverted: isInverted) {
                    SettingsButton()
                }
            },
            content: {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)

                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 64))
                        .foregroundStyle(.tertiary)

                    Text("Rastreador de calorias e macronutrientes")
                        .font(.serifBody)
                        .foregroundStyle(.secondary)

                    Text("Em breve")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.tint, in: .capsule)

                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(icon: "flame", title: "Calorias diárias", description: "Acompanhe sua ingestão calórica")
                        featureRow(icon: "chart.pie", title: "Macronutrientes", description: "Carboidratos, proteínas e gorduras")
                        featureRow(icon: "bell.badge", title: "Metas e alertas", description: "Defina metas nutricionais personalizadas")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            },
            infoContent: {
                NutrientsInfoContent()
            },
            onRefresh: nil
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
