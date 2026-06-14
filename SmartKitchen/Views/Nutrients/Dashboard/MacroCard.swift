import SwiftUI

/// Card compacto de nutriente no padrão dos cards visuais da Home:
/// superfície neutra, anel de progresso atrás do ícone e texto abaixo.
struct MacroCard: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let iconFileName: String
    var fallbackSymbol: String = "leaf"
    var iconSize: CGFloat = 74
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
        ZStack(alignment: .top) {
            NutrientGlassCardSurface(
                cornerRadius: 16,
                accentColor: tint,
                isColored: true
            )
            .padding(.top, 20)

            VStack(spacing: 5) {
                Spacer(minLength: 68)

                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(valueText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 7)

            progressIcon
                .offset(y: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(valueText)")
    }

    private var progressIcon: some View {
        ZStack {
            NutrientIconProgressRing(
                progress: progress,
                tint: tint,
                lineWidth: 3.2
            )
            .frame(width: 63, height: 63)

            IconImage(
                name: label,
                iconFileName: iconFileName,
                fallbackSymbol: fallbackSymbol,
                size: iconSize,
                showBalloon: false
            )
        }
        .frame(width: 58, height: 58)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.10), radius: 6, x: 0, y: 5)
    }

    private static func formattedAmount(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }
}

struct NutrientGlassCardSurface: View {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isColored: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surfaceColor)
            .overlay {
                surfaceGradient
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .nutrientGlassReflectionBorder(
                cornerRadius: cornerRadius,
                accentColor: accentColor,
                isColored: isColored
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.0 : 0.03), radius: 4, x: 0, y: 4)
    }

    private var surfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2E / 255.0)
            : neutralSurfaceColor
    }

    private var surfaceGradient: LinearGradient {
        if isColored {
            return LinearGradient(
                stops: [
                    .init(color: accentColor.opacity(colorScheme == .dark ? 0.30 : 0.17), location: 0.00),
                    .init(color: accentColor.opacity(colorScheme == .dark ? 0.15 : 0.09), location: 0.34),
                    .init(color: accentColor.opacity(colorScheme == .dark ? 0.06 : 0.035), location: 0.66),
                    .init(color: accentColor.opacity(0.00), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            stops: [
                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.055), location: 0.00),
                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.028), location: 0.48),
                .init(color: Color.primary.opacity(0.00), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct NutrientIconProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 3

    @Environment(\.colorScheme) private var colorScheme

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(colorScheme == .dark ? 0.18 : 0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    tint.opacity(colorScheme == .dark ? 0.78 : 0.62),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NutrientGlassReflectionBorderModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isColored: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(continuousEdgeReflection, lineWidth: colorScheme == .dark ? 1.25 : 1.15)
                        .mask(continuousEdgeOpacityMask)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(topReflection, lineWidth: colorScheme == .dark ? 0.95 : 1.05)
                        .mask(topReflectionMask)
                        .blendMode(colorScheme == .dark ? .screen : .normal)
                }
                .allowsHitTesting(false)
            }
    }

    private var continuousEdgeOpacityMask: some View {
        GeometryReader { geometry in
            let midCornerLocation = min(max((cornerRadius / 2) / max(geometry.size.height, 1), 0), 1)

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.05), location: midCornerLocation),
                    .init(color: .white.opacity(0.35), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var topReflectionMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white, location: 0.18),
                    .init(color: .white.opacity(0.56), location: 0.54),
                    .init(color: .white.opacity(0.18), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cornerRadius + 8)

            Rectangle()
                .fill(.white.opacity(0.18))
        }
    }

    private var topReflection: some ShapeStyle {
        AngularGradient(
            stops: [
                .init(color: accentColor.opacity(0.00), location: 0.00),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.18 : 0.12) : 0.06), location: 0.08),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.36 : 0.24) : 0.10), location: 0.18),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.58 : 0.38) : 0.14), location: 0.25),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.36 : 0.24) : 0.10), location: 0.32),
                .init(color: accentColor.opacity(isColored ? (colorScheme == .dark ? 0.18 : 0.12) : 0.06), location: 0.42),
                .init(color: accentColor.opacity(0.00), location: 0.50),
                .init(color: accentColor.opacity(0.00), location: 1.00)
            ],
            center: .center,
            startAngle: .degrees(-180),
            endAngle: .degrees(180)
        )
    }

    private var continuousEdgeReflection: some ShapeStyle {
        accentColor.opacity(isColored ? (colorScheme == .dark ? 0.28 : 0.18) : (colorScheme == .dark ? 0.16 : 0.10))
    }
}

private extension View {
    func nutrientGlassReflectionBorder(cornerRadius: CGFloat, accentColor: Color, isColored: Bool) -> some View {
        modifier(NutrientGlassReflectionBorderModifier(cornerRadius: cornerRadius, accentColor: accentColor, isColored: isColored))
    }
}

#Preview {
    HStack(spacing: 10) {
        MacroCard(
            label: "Proteína",
            current: 75,
            goal: 150,
            unit: "g",
            iconFileName: "protein-powder.png",
            fallbackSymbol: "bolt.fill",
            tint: Color(red: 0.91, green: 0.37, blue: 0.31)
        )
        MacroCard(
            label: "Carbos",
            current: 120,
            goal: 220,
            unit: "g",
            iconFileName: "bread-white.png",
            fallbackSymbol: "leaf.fill",
            tint: Color(red: 0.34, green: 0.68, blue: 0.36)
        )
        MacroCard(
            label: "Gordura",
            current: 38,
            goal: 70,
            unit: "g",
            iconFileName: "olive-oil.png",
            fallbackSymbol: "drop.fill",
            tint: Color(red: 0.95, green: 0.63, blue: 0.22)
        )
    }
    .padding()
}
