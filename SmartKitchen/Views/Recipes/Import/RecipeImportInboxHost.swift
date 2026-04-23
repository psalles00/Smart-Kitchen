import SwiftUI

/// View modifier that presents the Recipe Import flow automatically whenever
/// `RecipeImportInbox.shared.pendingSource` becomes non-nil. Attach once at the
/// scene root (applied in `SmartKitchenApp`).
struct RecipeImportInboxHost: ViewModifier {

    @State private var inbox = RecipeImportInbox.shared

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { inbox.pendingSource != nil },
                    set: { newValue in if !newValue { inbox.clear() } }
                )
            ) {
                if let source = inbox.pendingSource {
                    RecipeImportHostView(initialSource: source) { _ in
                        inbox.clear()
                    }
                    .modelContainer(CloudSyncService.shared.container)
                    #if os(iOS)
                    .forceLightStatusBar()
                    #endif
                }
            }
    }
}

extension View {
    /// Presents the Recipe Import host whenever a new source arrives via the
    /// `RecipeImportInbox` (URL schemes, share extension, deep links).
    func recipeImportInboxHost() -> some View {
        modifier(RecipeImportInboxHost())
    }
}

struct SharedImportActionView: View {
    let item: SharedImportItem
    let onReviewRecipe: () -> Void
    let onRegisterFood: (() -> Void)?
    let onAskAssistant: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    previewCard

                    VStack(spacing: 12) {
                        actionCard(
                            icon: recipeActionIcon,
                            title: recipeActionTitle,
                            subtitle: recipeActionSubtitle,
                            accent: PageTheme.recipes.accentColor,
                            action: onReviewRecipe
                        )

                        if let onRegisterFood {
                            actionCard(
                                icon: "fork.knife.circle.fill",
                                title: "Registrar alimento",
                                subtitle: "Guarde esta imagem como referência para o módulo de Nutrientes.",
                                accent: PageTheme.nutrients.accentColor,
                                action: onRegisterFood
                            )
                        }

                        if let onAskAssistant {
                            actionCard(
                                icon: "sparkles",
                                title: "Abrir no assistente",
                                subtitle: "Usar o conteúdo compartilhado como contexto na conversa com a IA.",
                                accent: PageTheme.home.accentColor,
                                action: onAskAssistant
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .modalNavigationTitle("O que você quer fazer?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .tint(.secondary)
                }
                #else
                ToolbarItem {
                    Button("Fechar") {
                        onDismiss()
                    }
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
                .font(.headline.weight(.semibold))
            Text(item.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var previewCard: some View {
        switch item.kind {
        case .image:
            if let imageData = item.imageData, let image = platformImage(from: imageData) {
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
                .frame(height: 220)
                .clipped()
                .clipShape(.rect(cornerRadius: 18))
            }

        case .video:
            infoCard(icon: "video.fill", title: "Vídeo recebido", subtitle: item.filename ?? item.mediaFileURL?.lastPathComponent ?? "Vídeo compartilhado")

        case .url:
            infoCard(icon: "link", title: "Link recebido", subtitle: item.url?.absoluteString ?? "")

        case .text:
            infoCard(icon: "text.alignleft", title: "Texto recebido", subtitle: item.text ?? "")
        }
    }

    private var recipeActionTitle: String {
        switch item.kind {
        case .image:
            return "Identificar receita"
        case .video:
            return "Revisar receita do vídeo"
        case .url, .text:
            return "Revisar como receita"
        }
    }

    private var recipeActionSubtitle: String {
        switch item.kind {
        case .image:
            return "Extrair ingredientes e etapas da imagem e abrir a revisão antes de salvar."
        case .video:
            return "Transcrever o vídeo, estruturar a receita e abrir a revisão antes de salvar."
        case .url:
            return "Importar o link compartilhado e abrir a revisão da receita."
        case .text:
            return "Organizar o texto compartilhado em ingredientes e modo de preparo."
        }
    }

    private var recipeActionIcon: String {
        switch item.kind {
        case .image:
            return "photo.badge.magnifyingglass"
        case .video:
            return "play.rectangle.fill"
        case .url:
            return "link.badge.plus"
        case .text:
            return "text.badge.plus"
        }
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 18))
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }
}
