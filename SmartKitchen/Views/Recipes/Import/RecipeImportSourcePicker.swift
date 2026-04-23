import SwiftUI

/// Bottom sheet letting the user choose HOW they want to import a recipe.
/// Presents quick entry points for link, gallery, camera, text, and files on macOS.
struct RecipeImportSourcePicker: View {

    let onPickLink: () -> Void
    let onPickImage: () -> Void
    let onPickCamera: () -> Void
    let onPickFiles: (() -> Void)?
    let onPickVideo: () -> Void
    let onPickText: () -> Void
    let onCreateManual: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    VStack(spacing: 10) {
                        card(
                            icon: "link",
                            title: "Colar link",
                            subtitle: "De qualquer site, blog ou rede social",
                            accent: .blue
                        ) {
                            onPickLink()
                        }

                        card(
                            icon: "photo.on.rectangle.angled",
                            title: "Importar da galeria",
                            subtitle: "Foto ou screenshot da receita",
                            accent: .orange
                        ) {
                            onPickImage()
                        }

                        card(
                            icon: "camera.viewfinder",
                            title: "Ler com câmera",
                            subtitle: "Fotografe a receita impressa ou na tela",
                            accent: .green
                        ) {
                            onPickCamera()
                        }

                        #if os(macOS)
                        if let onPickFiles {
                            card(
                                icon: "folder.fill",
                                title: "Importar dos arquivos",
                                subtitle: "Abrir uma imagem salva no Mac",
                                accent: .indigo
                            ) {
                                onPickFiles()
                            }
                        }
                        #endif

                        card(
                            icon: "video.fill",
                            title: "Importar vídeo",
                            subtitle: "Reels, TikTok, YouTube — em breve",
                            accent: .pink,
                            disabled: true
                        ) {
                            onPickVideo()
                        }

                        card(
                            icon: "text.alignleft",
                            title: "Colar texto",
                            subtitle: "Texto bruto de uma receita",
                            accent: .purple
                        ) {
                            onPickText()
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    Button {
                        onCreateManual()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.pencil")
                            Text("Criar do zero")
                                .font(.body.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(PageTheme.recipes.accentColor)
                        .background(PageTheme.recipes.accentColor.opacity(0.08), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .modalNavigationTitle("Adicionar receita")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .tint(.secondary)
                }
                #else
                ToolbarItem {
                    Button("Fechar") {
                        dismiss()
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Como você quer importar?")
                .font(.headline.weight(.semibold))
            Text("Cole um link, envie uma foto, use a câmera ou texto — nós estruturamos em uma receita editável.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func card(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            guard !disabled else { return }
            action()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(disabled ? 0.08 : 0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent.opacity(disabled ? 0.5 : 1))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(disabled ? Color.secondary : .primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            .opacity(disabled ? 0.65 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
