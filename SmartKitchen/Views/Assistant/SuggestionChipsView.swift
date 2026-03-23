import SwiftUI

/// Horizontal scrolling suggestion chips shown at the top of the chat.
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.label) { chip in
                    Button {
                        onTap(chip.prompt)
                    } label: {
                        Text(chip.label)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
