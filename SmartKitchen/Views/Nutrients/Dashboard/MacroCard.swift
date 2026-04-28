import SwiftUI

/// Cartão compacto de nutriente. Mostra o título (mesma fonte dos itens
/// "Mercado / Despensa / Receitas / Alimento" da Home) e o valor formatado
/// (geralmente uma porcentagem) em fonte maior porém com peso menor.
///
/// Background: superfície neutra (`neutralSurfaceColor`) — adapta ao modo
/// escuro automaticamente via `secondarySystemBackground` no fallback.
struct MacroCard: View {
    let label: String
    /// Texto principal já formatado (ex: "32%", "—").
    let valueText: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(valueText)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(MacroCard.cardBackground, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }

    /// Background adaptativo: claro = #F8F8FA; escuro = `secondarySystemBackground`.
    private static var cardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.secondarySystemBackground
                : UIColor(red: 248/255, green: 248/255, blue: 250/255, alpha: 1)
        })
        #else
        return neutralSurfaceColor
        #endif
    }
}

extension MacroCard {
    /// Conveniência: monta a partir de current/goal exibindo "X%" do progresso.
    init(label: String, current: Double, goal: Double) {
        self.label = label
        if goal > 0 {
            let pct = Int((min(current / goal, 1.0) * 100).rounded())
            self.valueText = "\(pct)%"
        } else {
            self.valueText = "—"
        }
    }

    init(label: String, current: Int, goal: Int) {
        self.init(label: label, current: Double(current), goal: Double(goal))
    }
}

#Preview {
    HStack {
        MacroCard(label: "Proteína", valueText: "32%")
        MacroCard(label: "Carbos", valueText: "44%")
        MacroCard(label: "Gordura", valueText: "28%")
    }
    .padding()
}
