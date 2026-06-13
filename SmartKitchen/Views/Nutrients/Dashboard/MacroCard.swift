import SwiftUI

/// Card compacto de nutriente no padrão dos cards visuais da Home:
/// superfície neutra, borda de progresso, ícone e texto abaixo.
struct MacroCard: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let iconFileName: String
    var fallbackSymbol: String = "leaf"
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
                isColored: true,
                progress: progress
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
            IconImage(
                name: label,
                iconFileName: iconFileName,
                fallbackSymbol: fallbackSymbol,
                size: 74,
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
    var progress: Double? = nil

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
            .nutrientGlassProgressBorder(
                cornerRadius: cornerRadius,
                accentColor: accentColor,
                isColored: isColored,
                progress: progress
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

private struct NutrientGlassProgressBorderModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accentColor: Color
    let isColored: Bool
    let progress: Double?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                if let progress {
                    TopCenterRoundedRectProgressShape(progress: progress, cornerRadius: cornerRadius)
                        .stroke(
                            progressColor.opacity(colorScheme == .dark ? 0.34 : 0.24),
                            style: StrokeStyle(
                                lineWidth: colorScheme == .dark ? 8.0 : 7.0,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .blur(radius: colorScheme == .dark ? 5.0 : 4.0)
                        .blendMode(colorScheme == .dark ? .screen : .plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: 1.35))
                        .padding(1.35)
                        .allowsHitTesting(false)

                    TopCenterRoundedRectProgressShape(progress: progress, cornerRadius: cornerRadius)
                        .stroke(
                            progressColor,
                            style: StrokeStyle(
                                lineWidth: colorScheme == .dark ? 2.4 : 2.2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .padding(1.35)
                        .shadow(color: progressColor.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 3, x: 0, y: 1)
                        .allowsHitTesting(false)
                }
            }
    }

    private var progressColor: Color {
        accentColor.opacity(isColored ? (colorScheme == .dark ? 0.72 : 0.50) : (colorScheme == .dark ? 0.76 : 0.62))
    }
}

private struct TopCenterRoundedRectProgressShape: Shape {
    var progress: Double
    let cornerRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > 0 else { return Path() }

        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let points = perimeterPoints(in: rect, radius: radius)
        guard points.count > 1 else { return Path() }

        let segmentLengths = zip(points, points.dropFirst()).map { distance(from: $0, to: $1) }
        let totalLength = segmentLengths.reduce(0, +)
        let targetLength = totalLength * clampedProgress

        var path = Path()
        path.move(to: points[0])

        var consumedLength: CGFloat = 0
        for index in segmentLengths.indices {
            let segmentLength = segmentLengths[index]
            let nextConsumedLength = consumedLength + segmentLength

            if nextConsumedLength <= targetLength {
                path.addLine(to: points[index + 1])
                consumedLength = nextConsumedLength
                continue
            }

            let remainingLength = max(targetLength - consumedLength, 0)
            if segmentLength > 0 {
                let t = remainingLength / segmentLength
                path.addLine(to: interpolate(from: points[index], to: points[index + 1], progress: t))
            }
            break
        }

        return path
    }

    private func perimeterPoints(in rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX
        let samplesPerCorner = 12

        var points: [CGPoint] = [CGPoint(x: midX, y: minY)]

        points.append(CGPoint(x: maxX - radius, y: minY))
        appendArcPoints(
            to: &points,
            center: CGPoint(x: maxX - radius, y: minY + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 0,
            samples: samplesPerCorner
        )
        points.append(CGPoint(x: maxX, y: maxY - radius))
        appendArcPoints(
            to: &points,
            center: CGPoint(x: maxX - radius, y: maxY - radius),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            samples: samplesPerCorner
        )
        points.append(CGPoint(x: minX + radius, y: maxY))
        appendArcPoints(
            to: &points,
            center: CGPoint(x: minX + radius, y: maxY - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            samples: samplesPerCorner
        )
        points.append(CGPoint(x: minX, y: minY + radius))
        appendArcPoints(
            to: &points,
            center: CGPoint(x: minX + radius, y: minY + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: .pi * 1.5,
            samples: samplesPerCorner
        )
        points.append(CGPoint(x: midX, y: minY))

        return points
    }

    private func appendArcPoints(
        to points: inout [CGPoint],
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        samples: Int
    ) {
        guard samples > 0 else { return }

        for step in 1...samples {
            let t = CGFloat(step) / CGFloat(samples)
            let angle = startAngle + ((endAngle - startAngle) * t)
            points.append(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress)
        )
    }
}

private extension View {
    func nutrientGlassReflectionBorder(cornerRadius: CGFloat, accentColor: Color, isColored: Bool) -> some View {
        modifier(NutrientGlassReflectionBorderModifier(cornerRadius: cornerRadius, accentColor: accentColor, isColored: isColored))
    }

    func nutrientGlassProgressBorder(cornerRadius: CGFloat, accentColor: Color, isColored: Bool, progress: Double?) -> some View {
        modifier(NutrientGlassProgressBorderModifier(cornerRadius: cornerRadius, accentColor: accentColor, isColored: isColored, progress: progress))
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
