import SwiftUI

/// Anel circular de progresso das calorias diárias (portado de Fud, reskinado com PageTheme.nutrients).
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    var remaining: Int { max(goal - consumed, 0) }
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1.0)
    }

    private var theme: PageTheme { .nutrients }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.accentColor.opacity(0.12), lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    theme.gradient,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: progress)

            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("kcal restantes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(consumed) / \(goal)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(width: 180, height: 180)
    }
}

#Preview {
    CalorieRingView(consumed: 1200, goal: 2100)
        .padding()
}
