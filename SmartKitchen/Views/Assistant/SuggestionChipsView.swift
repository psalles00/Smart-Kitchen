import SwiftUI

/// Suggestion chips shown in the assistant empty states.
struct SuggestionChipsView: View {
    let onTap: (String) -> Void

    private let suggestions: [(label: String, prompt: String)] = [
        ("🍳 O que posso cozinhar?", "Com base nos ingredientes da minha despensa, o que posso cozinhar?"),
        ("➕ Criar receita", "Quero adicionar uma nova receita."),
        ("✏️ Editar receita", "Quero editar uma receita existente."),
        ("📚 Minhas receitas", "Mostre minhas receitas salvas."),
        ("🛒 Lista de mercado", "Mostre minha lista de mercado atual."),
        ("🧊 O que tem na despensa?", "O que eu tenho na despensa agora?"),
        ("🏷️ Categorias", "Mostre e gerencie minhas categorias."),
        ("🥗 Receita saudável", "Sugira uma receita saudável e rápida."),
    ]

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
