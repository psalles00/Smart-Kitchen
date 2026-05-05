import SwiftUI

/// Organic, non-uniform bubble canvas with fixed-size circles. Positions are
/// generated on a stretched spiral with deterministic jitter and collision
/// checks so the layout feels scattered rather than gridded, while still
/// guaranteeing that circles never overlap.
struct AsymmetricCircleCanvas<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let labelFor: (Item) -> String
    let iconFileFor: (Item) -> String
    let isSelected: (Item) -> Bool
    let toggle: (Item) -> Void

    private let diameter: CGFloat = 116
    private let minimumGap: CGFloat = 0.75

    var body: some View {
        let positions = layoutPositions(count: items.count)
        let bounds = canvasBounds(for: positions)

        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: bounds.width, height: bounds.height)

                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    let pos = positions[idx]
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
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center)
    }

    private let gapPattern: [CGFloat] = [0, 0, 4, 2, 6, 0, 3, 0, 5]

    private func layoutPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }

        var positions: [CGPoint] = []
        let spiralStep = diameter * 0.54

        for index in 0..<count {
            let preferredGap = gapPattern[index % gapPattern.count]
            var radius = CGFloat(sqrt(Double(index) + 0.6)) * spiralStep + preferredGap
            var angle = CGFloat(index) * 2.23 + noise(index, salt: 1) * 0.9
            var candidate = CGPoint.zero
            var placed = false

            for attempt in 0..<120 {
                candidate = CGPoint(
                    x: cos(angle) * radius * 1.18 + noise(index + attempt, salt: 2) * 8,
                    y: sin(angle) * radius * 0.84 + noise(index + attempt, salt: 3) * 8
                )

                if positions.allSatisfy({ existing in
                    hypot(candidate.x - existing.x, candidate.y - existing.y) >= diameter + minimumGap
                }) {
                    placed = true
                    break
                }

                radius += 9 + CGFloat(attempt % 3) * 2
                angle += 0.42 + noise(index + attempt, salt: 4) * 0.18
            }

            if !placed {
                candidate = CGPoint(x: cos(angle) * radius * 1.20, y: sin(angle) * radius * 0.86)
            }

            positions.append(candidate)
        }

        return positions
    }

    private func canvasBounds(for positions: [CGPoint]) -> (width: CGFloat,
                                                             height: CGFloat,
                                                             minX: CGFloat,
                                                             minY: CGFloat) {
        guard !positions.isEmpty else { return (820, 520, -410, -260) }
        let pad = diameter / 2 + 10
        let minX = (positions.map(\.x).min() ?? 0) - pad
        let maxX = (positions.map(\.x).max() ?? 0) + pad
        let minY = (positions.map(\.y).min() ?? 0) - pad
        let maxY = (positions.map(\.y).max() ?? 0) + pad
        return (maxX - minX, maxY - minY, minX, minY)
    }

    private func noise(_ index: Int, salt: Int) -> CGFloat {
        let value = sin(Double(index * 73 + salt * 197)) * 43758.5453
        let fractional = value - floor(value)
        return CGFloat(fractional - 0.5)
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

                VStack(spacing: 6) {
                    if let img = IconResolver.image(forFilename: iconFileName) {
                        Image(platformImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 10)
                }
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var fillColor: Color {
        if isSelected {
            return colorScheme == .dark ? .white : .black
        }
        return colorScheme == .dark ? Color(white: 0.15) : .white
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        }
        return .primary
    }
}
