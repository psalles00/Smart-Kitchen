import SwiftUI
import SwiftData

/// Suggestion chips shown in the assistant empty states.
struct SuggestionChipsView: View {
    let onTap: (String) -> Void

    @Query private var nutritionProfiles: [NutritionProfile]

    private var baseSuggestions: [(label: String, prompt: String)] {
        [
            (String(localized: "🍳 O que posso cozinhar?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Com base nos ingredientes da minha despensa, o que posso cozinhar?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "➕ Criar receita", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Quero adicionar uma nova receita.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "✏️ Editar receita", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Quero editar uma receita existente.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "📚 Minhas receitas", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Mostre minhas receitas salvas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "🛒 Lista de mercado", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Mostre minha lista de mercado atual.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "🧊 O que tem na despensa?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "O que eu tenho na despensa agora?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "🏷️ Categorias", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Mostre e gerencie minhas categorias.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "🥗 Receita saudável", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Sugira uma receita saudável e rápida.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
        ]
    }

    private var nutritionSuggestions: [(label: String, prompt: String)] {
        [
            (String(localized: "🥗 O que comi hoje?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Mostre meu consumo de hoje e como está em relação às metas.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "📝 Registrar refeição", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Quero registrar uma refeição que acabei de comer.", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
            (String(localized: "🎯 Estou na meta?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale), String(localized: "Estou dentro das minhas metas de calorias e macros hoje?", bundle: AppLocalization.stringBundle, locale: AppLocalization.stringLocale)),
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
