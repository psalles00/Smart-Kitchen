import SwiftUI

/// Cartão de macro (Proteína / Carbos / Gordura) com barra de progresso.
struct MacroCard: View {
    let label: String
    let current: Int
    let goal: Int
    let tint: Color

    private var progress: Double {
        goal > 0 ? min(Double(current) / Double(goal), 1.0) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(current)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                Text("/\(goal)g")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, geo.size.width * progress))
                        .animation(.spring(response: 0.8, dampingFraction: 0.75), value: current)
                }
            }
            .frame(height: 6)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(goal > current ? "\(goal - current)g restam" : "Meta atingida")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }
}

#Preview {
    HStack {
        MacroCard(label: "Proteína", current: 60, goal: 120, tint: .blue)
        MacroCard(label: "Carbos", current: 180, goal: 250, tint: .orange)
        MacroCard(label: "Gordura", current: 40, goal: 70, tint: .yellow)
    }
    .padding()
}
