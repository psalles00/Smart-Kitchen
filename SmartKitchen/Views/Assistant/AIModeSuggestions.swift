import SwiftUI
import SwiftData

// MARK: - SavorIA Suggestions

/// Single source of truth for the suggestion buttons displayed in **SavorIA**
/// and mirrored in the **Assistente** idle screen ("Sugestões do SavorIA").
///
/// Any change here automatically propagates to both surfaces.
struct AIModeSuggestion: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
    let prompt: String
}

enum AIModeSuggestions {
    private static func suggestion(
        id: String,
        emoji: String,
        label: String.LocalizationValue,
        prompt: String.LocalizationValue
    ) -> AIModeSuggestion {
        AIModeSuggestion(
            id: id,
            emoji: emoji,
            label: String(localized: label),
            prompt: String(localized: prompt)
        )
    }

    // MARK: Fixed AI-driven actions (sempre visíveis no SavorIA / Assistente)

    /// Estes três botões executam pedidos analíticos para a IA. Como a IA já
    /// recebe contexto completo (despensa, mercado, receitas, nutrição), os
    /// prompts apenas pedem a análise — sem precisar de ferramentas extras.
    static let fixedActions: [AIModeSuggestion] = [
        suggestion(
            id: "ai_analyze_diet",
            emoji: "🔍",
            label: "Analise minha alimentação",
            prompt: """
            Faça uma análise completa da minha alimentação considerando:
            1) os itens da minha despensa e da lista de mercado;
            2) minhas receitas salvas e padrões de consumo recentes;
            3) meu progresso em Nutrição (peso, calorias e macros) frente às minhas metas.

            Diga objetivamente o que está alinhado com meus objetivos e o que está atrapalhando, e finalize com 3 a 5 dicas práticas e personalizadas para melhorar.
            """
        ),
        suggestion(
            id: "ai_progress",
            emoji: "📊",
            label: "Como está meu progresso?",
            prompt: """
            Analise especificamente meu progresso em Nutrição: tendência de peso, consistência nos registros, calorias e macros recentes vs. minhas metas.

            Aponte pontos fortes, pontos de atenção e sugira 3 ajustes concretos para eu evoluir mais rápido com segurança.
            """
        ),
        suggestion(
            id: "ai_substitutes",
            emoji: "🔁",
            label: "Sugira o que substituir",
            prompt: """
            Considerando meu objetivo atual e o que está na minha despensa, na lista de mercado e nas minhas receitas, sugira substituições mais alinhadas com a meta (por exemplo, trocar um achocolatado calórico por uma versão de baixa caloria, ou um doce frequente por uma alternativa mais leve).

            Se identificar padrões repetitivos (mesmo doce ou snack calórico aparecendo várias vezes), proponha alternativas — e, quando fizer sentido, indique novas receitas saudáveis para substituir.
            """
        )
    ]

    // MARK: Coach starter prompts (dinâmicos baseados no objetivo)

    static func coachStarters(profile: NutritionProfile?) -> [AIModeSuggestion] {
        guard profile?.hasCompletedOnboarding == true,
              let goal = profile?.weightGoal else {
            return [
                suggestion(id: "coach_default_1", emoji: "📈", label: "Qual é meu peso esperado em 30 dias?", prompt: "Qual é meu peso esperado em 30 dias?"),
                suggestion(id: "coach_default_2", emoji: "🎯", label: "O que devo comer no jantar?", prompt: "O que devo comer no jantar?"),
                suggestion(id: "coach_default_3", emoji: "🍽️", label: "Como bato minha meta?", prompt: "Como bato minha meta?"),
                suggestion(id: "coach_default_4", emoji: "🥗", label: "Como está minha tendência?", prompt: "Como está minha tendência?")
            ]
        }

        switch goal {
        case .lose:
            return [
                suggestion(id: "coach_lose_1", emoji: "📈", label: "Qual é meu peso esperado em 30 dias?", prompt: "Qual é meu peso esperado em 30 dias?"),
                suggestion(id: "coach_lose_2", emoji: "🎯", label: "Como posso emagrecer mais rápido com segurança?", prompt: "Como posso emagrecer mais rápido com segurança?"),
                suggestion(id: "coach_lose_3", emoji: "🍽️", label: "Estou comendo demais?", prompt: "Estou comendo demais?"),
                suggestion(id: "coach_lose_4", emoji: "🥗", label: "O que devo comer no jantar?", prompt: "O que devo comer no jantar?")
            ]
        case .gain:
            return [
                suggestion(id: "coach_gain_1", emoji: "📈", label: "Qual é meu peso esperado em 30 dias?", prompt: "Qual é meu peso esperado em 30 dias?"),
                suggestion(id: "coach_gain_2", emoji: "🎯", label: "Como posso ganhar peso de forma saudável?", prompt: "Como posso ganhar peso de forma saudável?"),
                suggestion(id: "coach_gain_3", emoji: "🍽️", label: "Estou comendo o suficiente?", prompt: "Estou comendo o suficiente?"),
                suggestion(id: "coach_gain_4", emoji: "🥗", label: "Quais alimentos ricos em proteína posso adicionar?", prompt: "Quais alimentos ricos em proteína posso adicionar?")
            ]
        case .maintain:
            return [
                suggestion(id: "coach_maintain_1", emoji: "📈", label: "Estou mantendo meu peso?", prompt: "Estou mantendo meu peso?"),
                suggestion(id: "coach_maintain_2", emoji: "🎯", label: "Qual é meu consumo médio?", prompt: "Qual é meu consumo médio?"),
                suggestion(id: "coach_maintain_3", emoji: "🍽️", label: "Sugestões de macros?", prompt: "Sugestões de macros?"),
                suggestion(id: "coach_maintain_4", emoji: "🥗", label: "Como está minha tendência?", prompt: "Como está minha tendência?")
            ]
        }
    }

    /// Lista combinada usada pelo SavorIA (preset coach) e pela seção
    /// "Sugestões do SavorIA" no Assistente. Inclui sugestões dinâmicas
    /// + ações fixas de IA.
    static func nutritionCoachSuggestions(profile: NutritionProfile?) -> [AIModeSuggestion] {
        coachStarters(profile: profile) + fixedActions
    }

    // MARK: Recipe ideas starter prompts

    static let recipeIdeasStarters: [AIModeSuggestion] = [
        suggestion(id: "ideas_1", emoji: "⚡", label: "Sugira novas receitas de jantar rápido.", prompt: "Sugira novas receitas de jantar rápido."),
        suggestion(id: "ideas_2", emoji: "🍗", label: "Sugira novas receitas com frango e legumes.", prompt: "Sugira novas receitas com frango e legumes."),
        suggestion(id: "ideas_3", emoji: "🌿", label: "Sugira novas receitas vegetarianas simples.", prompt: "Sugira novas receitas vegetarianas simples."),
        suggestion(id: "ideas_4", emoji: "🍰", label: "Sugira novas receitas de sobremesa.", prompt: "Sugira novas receitas de sobremesa.")
    ]
}

// MARK: - Reusable list view

/// Lista vertical de sugestões em formato pílula com emoji + texto.
/// Usada no estado vazio do SavorIA.
struct AIModeSuggestionsList: View {
    let suggestions: [AIModeSuggestion]
    let onTap: (AIModeSuggestion) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let primary = suggestions.first {
                suggestionButton(primary, style: .primary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(suggestions.dropFirst()) { suggestion in
                    suggestionButton(suggestion, style: .compact)
                }
            }
        }
    }

    private func suggestionButton(_ suggestion: AIModeSuggestion, style: SuggestionButtonStyle) -> some View {
        Button {
            onTap(suggestion)
        } label: {
            switch style {
            case .primary:
                HStack(spacing: 12) {
                    emojiBadge(suggestion.emoji, size: 40, font: .title3)

                    Text(suggestion.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(primarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }

            case .compact:
                VStack(alignment: .leading, spacing: 10) {
                    emojiBadge(suggestion.emoji, size: 32, font: .body)

                    Text(suggestion.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
                .background(neutralSurfaceColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func emojiBadge(_ emoji: String, size: CGFloat, font: Font) -> some View {
        Text(emoji)
            .font(font)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var primarySurface: some ShapeStyle {
        LinearGradient(
            colors: [
                PageTheme.home.accentColor.opacity(0.16),
                neutralSurfaceColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private enum SuggestionButtonStyle {
        case primary
        case compact
    }
}
