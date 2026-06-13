import SwiftUI

/// Card compacto de nutriente no padrão dos cards visuais da Home:
/// superfície neutra, ícone em círculo com progresso e texto abaixo.
struct MacroCard: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let systemImage: String
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(current / goal, 0), 1)
    }

    private var valueText: String {
        "\(Self.formattedAmount(current))/\(Self.formattedAmount(goal))\(unit)"
    }

    var body: some View {
        VStack(spacing: 6) {
            progressIcon

            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(valueText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .padding(.horizontal, 7)
        .background(cardSurface)
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(valueText)")
    }

    private var progressIcon: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))

            Circle()
                .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 46, height: 46)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(neutralSurfaceColor)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.0 : 0.025), radius: 4, x: 0, y: 3)
    }

    private static func formattedAmount(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    HStack(spacing: 10) {
        MacroCard(
            label: "Proteína",
            current: 75,
            goal: 150,
            unit: "g",
            systemImage: "bolt.fill",
            tint: Color(red: 0.91, green: 0.37, blue: 0.31)
        )
        MacroCard(
            label: "Carbos",
            current: 120,
            goal: 220,
            unit: "g",
            systemImage: "leaf.fill",
            tint: Color(red: 0.34, green: 0.68, blue: 0.36)
        )
        MacroCard(
            label: "Gordura",
            current: 38,
            goal: 70,
            unit: "g",
            systemImage: "drop.fill",
            tint: Color(red: 0.95, green: 0.63, blue: 0.22)
        )
    }
    .padding()
}
