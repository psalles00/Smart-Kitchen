import SwiftUI

// MARK: - Occasion

/// Ocasiões oferecidas no wizard de Ideias de receitas.
enum RecipeIdeaOccasion: String, CaseIterable, Identifiable {
    case cafeDaManha
    case almoco
    case jantar
    case lancheRapido
    case drinks
    case bebidas
    case sobremesa
    case outro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cafeDaManha: return String(localized: "Café da manhã")
        case .almoco: return String(localized: "Almoço")
        case .jantar: return String(localized: "Jantar")
        case .lancheRapido: return String(localized: "Lanche rápido")
        case .drinks: return String(localized: "Drinks")
        case .bebidas: return String(localized: "Bebidas")
        case .sobremesa: return String(localized: "Sobremesa")
        case .outro: return String(localized: "Outro")
        }
    }

    var emoji: String {
        switch self {
        case .cafeDaManha: return "🥐"
        case .almoco: return "🍽️"
        case .jantar: return "🍝"
        case .lancheRapido: return "🥪"
        case .drinks: return "🍹"
        case .bebidas: return "🥤"
        case .sobremesa: return "🍰"
        case .outro: return "✏️"
        }
    }

    /// Ordena as 8 ocasiões dependendo da hora do dia (5–10 manhã, 11–14 meio-dia,
    /// 15–17 tarde, 18–22 noite, 23–4 madrugada).
    static func orderedForHour(_ hour: Int) -> [RecipeIdeaOccasion] {
        switch hour {
        case 5...10:
            return [.cafeDaManha, .lancheRapido, .bebidas, .sobremesa, .almoco, .jantar, .drinks, .outro]
        case 11...14:
            return [.almoco, .lancheRapido, .bebidas, .sobremesa, .jantar, .cafeDaManha, .drinks, .outro]
        case 15...17:
            return [.lancheRapido, .bebidas, .sobremesa, .almoco, .jantar, .cafeDaManha, .drinks, .outro]
        case 18...22:
            return [.jantar, .lancheRapido, .drinks, .sobremesa, .bebidas, .almoco, .cafeDaManha, .outro]
        default: // 23, 0, 1, 2, 3, 4
            return [.lancheRapido, .drinks, .bebidas, .sobremesa, .jantar, .almoco, .cafeDaManha, .outro]
        }
    }

    /// Texto da pergunta de refinamento.
    var refinementQuestion: String {
        switch self {
        case .cafeDaManha: return String(localized: "Como você quer seu café da manhã?")
        case .almoco: return String(localized: "Que tipo de almoço você quer?")
        case .jantar: return String(localized: "Como deve ser seu jantar?")
        case .lancheRapido: return String(localized: "Que lanche combina agora?")
        case .drinks: return String(localized: "Qual vibe do drink?")
        case .bebidas: return String(localized: "Que bebida você quer?")
        case .sobremesa: return String(localized: "Como você quer a sobremesa?")
        case .outro: return ""
        }
    }

    /// Refinamentos disponíveis (último é sempre "Outro" → texto livre).
    var refinements: [String] {
        switch self {
        case .cafeDaManha: return [String(localized: "Rápido"), String(localized: "Saudável"), String(localized: "Doce"), String(localized: "Proteico"), String(localized: "Outro")]
        case .almoco: return [String(localized: "Rápido"), String(localized: "Saudável"), String(localized: "Refeição completa"), String(localized: "Econômico"), String(localized: "Outro")]
        case .jantar: return [String(localized: "Leve"), String(localized: "Rápido"), String(localized: "Saudável"), String(localized: "Caprichado"), String(localized: "Outro")]
        case .lancheRapido: return [String(localized: "Salgado"), String(localized: "Doce"), String(localized: "Fit"), String(localized: "Muito rápido"), String(localized: "Com poucos ingredientes"), String(localized: "Outro")]
        case .drinks: return [String(localized: "Refrescante"), String(localized: "Forte"), String(localized: "Doce"), String(localized: "Sem álcool"), String(localized: "Outro")]
        case .bebidas: return [String(localized: "Gelada"), String(localized: "Quente"), String(localized: "Energizante"), String(localized: "Saudável"), String(localized: "Cremosa"), String(localized: "Outro")]
        case .sobremesa: return [String(localized: "Rápida"), String(localized: "Gelada"), String(localized: "Chocolate"), String(localized: "Frutas"), String(localized: "Poucos ingredientes"), String(localized: "Outro")]
        case .outro: return []
        }
    }
}

// MARK: - Wizard Sentinels

/// Marcadores embutidos em `QuickAction.prompt` da primeira quickAction de uma
/// `ChatMessage` para sinalizar que ela faz parte do fluxo de Ideias de receitas.
/// Mantemos sentinelas como strings para evitar mudanças de schema no SwiftData.
enum RecipeIdeasSentinel {
    static let occasionPrefix = "__wizard_occasion__"
    static let refinementPrefix = "__wizard_refinement__"
    static let resultsPrefix = "__wizard_results__"
    static let pantryBannerPrefix = "__wizard_pantry_banner__"

    /// Constrói prompt da quickAction para a etapa de refinamento de uma ocasião.
    static func refinementPrompt(for occasion: RecipeIdeaOccasion) -> String {
        "\(refinementPrefix):\(occasion.rawValue)"
    }

    /// Extrai a ocasião embutida em uma sentinela de refinamento, se houver.
    static func refinementOccasion(from prompt: String) -> RecipeIdeaOccasion? {
        let prefix = "\(refinementPrefix):"
        guard prompt.hasPrefix(prefix) else { return nil }
        let raw = String(prompt.dropFirst(prefix.count))
        return RecipeIdeaOccasion(rawValue: raw)
    }
}

// MARK: - Chips Row

/// Layout em wrap: todos os chips ficam visíveis em múltiplas linhas, sem rolagem horizontal.
private struct ChipsWrapLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, in: maxWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : arrangement.maxX, height: arrangement.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, in: bounds.width)
        for placement in arrangement.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.size.width, height: placement.size.height)
            )
        }
    }

    private struct Placement {
        let subview: LayoutSubview
        let x: CGFloat
        let y: CGFloat
        let size: CGSize
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> (placements: [Placement], totalHeight: CGFloat, maxX: CGFloat) {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            placements.append(Placement(subview: sub, x: x, y: y, size: size))
            x += size.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, size.height)
        }
        return (placements, y + rowHeight, maxX)
    }
}

/// Linha de chips em wrap, mostrando todas as opções na tela sem scroll horizontal.
struct RecipeIdeasChipsRow: View {
    let chips: [Chip]
    let onTap: (Chip) -> Void

    struct Chip: Identifiable, Equatable {
        let id: String
        let label: String
        let emoji: String?

        init(id: String, label: String, emoji: String? = nil) {
            self.id = id
            self.label = label
            self.emoji = emoji
        }
    }

    var body: some View {
        ChipsWrapLayout(spacing: 8, rowSpacing: 8) {
            ForEach(chips) { chip in
                Button {
                    onTap(chip)
                } label: {
                    HStack(spacing: 6) {
                        if let emoji = chip.emoji {
                            Text(emoji)
                                .font(.subheadline)
                        }
                        Text(chip.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.label)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Recipe Idea Suggestion Card

/// Cartão exibido para uma "Nova ideia" de receita gerada pela EXA.
struct RecipeIdeaSuggestionCard: View {
    let title: String
    let summary: String?
    let sourceHost: String?
    /// URL da imagem hero retornada pela EXA (quando disponível).
    let heroImageURL: String?
    /// Nome do principal ingrediente, usado como fallback de imagem.
    let mainIngredient: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                heroImage
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let sourceHost, !sourceHost.isEmpty {
                        Text(sourceHost)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = heroImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackImage
                case .empty:
                    placeholderImage
                @unknown default:
                    fallbackImage
                }
            }
        } else {
            fallbackImage
        }
    }

    @ViewBuilder
    private var fallbackImage: some View {
        if let mainIngredient,
           !mainIngredient.isEmpty,
           let platformImage = IconResolver.image(for: mainIngredient) {
            #if canImport(UIKit)
            Image(uiImage: platformImage)
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
            #else
            Image(nsImage: platformImage)
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
            #endif
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }
}
