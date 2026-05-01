import SwiftUI

/// Pannable canvas that lays out items as overlapping asymmetric circles
/// (Vogel sunflower distribution + varying diameters). The user can drag
/// the canvas in any direction to discover more items.
///
/// The label sits centered inside each circle; the icon sits above it.
/// Selected items invert (dark fill + white text) and slightly scale up.
struct AsymmetricCircleCanvas<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let labelFor: (Item) -> String
    let iconFileFor: (Item) -> String
    let isSelected: (Item) -> Bool
    let toggle: (Item) -> Void

    var body: some View {
        let positions = layoutPositions(count: items.count)
        let bounds = canvasBounds(for: positions)

        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: bounds.width, height: bounds.height)

                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    let pos = positions[idx]
                    let diameter = diameterFor(index: idx)
                    CircleNode(
                        title: labelFor(item),
                        iconFileName: iconFileFor(item),
                        diameter: diameter,
                        isSelected: isSelected(item),
                        action: { toggle(item) }
                    )
                    .position(x: pos.x - bounds.minX, y: pos.y - bounds.minY)
                }
            }
            .padding(40)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center)
    }

    // MARK: - Layout

    private let goldenAngle: Double = 137.508 * .pi / 180
    private let baseRadius: CGFloat = 56
    private let sizeCycle: [CGFloat] = [104, 78, 92, 118, 86, 100, 72, 110, 90]

    private func diameterFor(index: Int) -> CGFloat {
        sizeCycle[index % sizeCycle.count]
    }

    private func layoutPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let r = baseRadius * sqrt(Double(i + 1))
            let a = Double(i) * goldenAngle
            return CGPoint(x: r * cos(a), y: r * sin(a))
        }
    }

    private func canvasBounds(for positions: [CGPoint]) -> (width: CGFloat,
                                                             height: CGFloat,
                                                             minX: CGFloat,
                                                             minY: CGFloat) {
        guard !positions.isEmpty else { return (600, 600, -300, -300) }
        let maxDiameter = sizeCycle.max() ?? 120
        let pad = maxDiameter / 2 + 12
        let minX = (positions.map(\.x).min() ?? 0) - pad
        let maxX = (positions.map(\.x).max() ?? 0) + pad
        let minY = (positions.map(\.y).min() ?? 0) - pad
        let maxY = (positions.map(\.y).max() ?? 0) + pad
        return (maxX - minX, maxY - minY, minX, minY)
    }
}

// MARK: - CircleNode

private struct CircleNode: View {
    let title: String
    let iconFileName: String
    let diameter: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .shadow(
                        color: Color.black.opacity(isSelected ? 0.18 : 0.08),
                        radius: isSelected ? 14 : 8,
                        y: isSelected ? 6 : 3
                    )

                VStack(spacing: 4) {
                    if let img = IconResolver.image(forFilename: iconFileName) {
                        Image(platformImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                    }

                    Text(title)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isSelected ? 1.06 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var fillColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.black
        }
        return colorScheme == .dark
            ? Color(white: 0.18)
            : Color.white
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.black : Color.white
        }
        return Color.primary
    }

    private var iconSize: CGFloat { max(28, diameter * 0.42) }
    private var labelFontSize: CGFloat {
        // Smaller circles get smaller labels; clamp 10–14pt.
        max(10, min(14, diameter * 0.13))
    }
}
