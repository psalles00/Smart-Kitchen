import SwiftUI

/// A single row in the Command Bar results list.
struct CommandBarResultRow: View {
    let result: SearchResult
    let isPreSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                resultIcon
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text(result.typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(typeTintColor.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeTintColor.opacity(0.12), in: .capsule)

                if isPreSelected {
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isPreSelected ? Color(.tertiarySystemFill) : Color.clear,
                in: .rect(cornerRadius: 12)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch result.type {
        case .pantryItem, .groceryItem, .utensil, .recipe, .suggestion:
            IconImage(
                name: result.title,
                iconFileName: result.iconFilename,
                fallbackSymbol: result.icon,
                size: 36
            )
        case .action:
            Image(systemName: result.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(typeTintColor)
                .frame(width: 36, height: 36)
                .background(typeTintColor.opacity(0.12), in: .rect(cornerRadius: 10))
        }
    }

    private var typeTintColor: Color {
        switch result.typeTint {
        case "orange": .orange
        case "green":  .green
        case "red":    .red
        case "purple": .purple
        case "blue":   .blue
        default:       .secondary
        }
    }
}
