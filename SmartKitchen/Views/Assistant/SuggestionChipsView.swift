import SwiftUI
import SwiftData

/// Suggestion chips shown in the assistant empty states.
struct SuggestionChipsView: View {
    let onTap: (String) -> Void

    @Query private var nutritionProfiles: [NutritionProfile]

    private var baseSuggestions: [(label: String, prompt: String)] {
        [
            (String(localized: "🍳 O que posso cozinhar?"), String(localized: "Com base nos ingredientes da minha despensa, o que posso cozinhar?")),
            (String(localized: "➕ Criar receita"), String(localized: "Quero adicionar uma nova receita.")),
            (String(localized: "✏️ Editar receita"), String(localized: "Quero editar uma receita existente.")),
            (String(localized: "📚 Minhas receitas"), String(localized: "Mostre minhas receitas salvas.")),
            (String(localized: "🛒 Lista de mercado"), String(localized: "Mostre minha lista de mercado atual.")),
            (String(localized: "🧊 O que tem na despensa?"), String(localized: "O que eu tenho na despensa agora?")),
            (String(localized: "🏷️ Categorias"), String(localized: "Mostre e gerencie minhas categorias.")),
            (String(localized: "🥗 Receita saudável"), String(localized: "Sugira uma receita saudável e rápida.")),
        ]
    }

    private var nutritionSuggestions: [(label: String, prompt: String)] {
        [
            (String(localized: "🥗 O que comi hoje?"), String(localized: "Mostre meu consumo de hoje e como está em relação às metas.")),
            (String(localized: "📝 Registrar refeição"), String(localized: "Quero registrar uma refeição que acabei de comer.")),
            (String(localized: "🎯 Estou na meta?"), String(localized: "Estou dentro das minhas metas de calorias e macros hoje?")),
        ]
    }

    private var suggestions: [(label: String, prompt: String)] {
        let hasNutrition = nutritionProfiles.first?.hasCompletedOnboarding == true
        return hasNutrition ? (baseSuggestions + nutritionSuggestions) : baseSuggestions
    }

    var body: some View {
        ExpandingFlowLayout(spacing: 6) {
            ForEach(suggestions, id: \.label) { chip in
                Button {
                    onTap(chip.prompt)
                } label: {
                    Text(chip.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(neutralSurfaceColor, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}
