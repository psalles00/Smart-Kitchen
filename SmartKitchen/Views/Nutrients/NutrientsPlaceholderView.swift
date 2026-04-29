import SwiftUI

struct NutrientsPlaceholderView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @State private var sharedFoodCaptureInbox = SharedFoodCaptureInbox.shared
    @State private var contentResetToken: Int = 0

    var body: some View {
        ExpandedPageLayout(
            pageTheme: .nutrients,
            header: { isInverted in
                PageHeader(title: String(localized: "Nutrição"), isInverted: isInverted) {
                    SettingsButton()
                }
            },
            content: {
                ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)

                    if let capture = sharedFoodCaptureInbox.pendingCapture {
                        sharedCaptureCard(capture)
                            .padding(.horizontal, 24)
                    }

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
                        featureRow(icon: "flame", title: String(localized: "Calorias diárias"), description: String(localized: "Acompanhe sua ingestão calórica"))
                        featureRow(icon: "chart.pie", title: String(localized: "Macronutrientes"), description: String(localized: "Carboidratos, proteínas e gorduras"))
                        featureRow(icon: "bell.badge", title: String(localized: "Metas e alertas"), description: String(localized: "Defina metas nutricionais personalizadas"))
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .id(contentResetToken)
                }
            },
            infoContent: {
                EmptyView()
            }
        )
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .tint(PageTheme.nutrients.accentColor)
        .onChange(of: scrollToTopTrigger) { _, _ in
            contentResetToken += 1
        }
    }

    private func sharedCaptureCard(_ capture: SharedFoodCaptureItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imagem recebida para registro")
                .font(.headline.weight(.semibold))

            if let image = previewImage(from: capture.imageData) {
                Group {
                    #if os(iOS)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    #else
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                    #endif
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(.rect(cornerRadius: 16))
            }

            Text(capture.filename ?? "Use esta captura como referência quando o registro nutricional estiver disponível.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Limpar imagem") {
                sharedFoodCaptureInbox.clear()
            }
            .buttonStyle(.bordered)
            .tint(PageTheme.nutrients.accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
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

    private func previewImage(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }
}
