import SwiftUI

/// Compact recipe option buttons shown in a wrapping flow layout.
/// Each option shows a small icon, name, and short description.
struct RecipeOptionButtonsView: View {
    let options: [RecipeOption]
    let onSelect: (RecipeOption) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    optionChip(option)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func optionChip(_ option: RecipeOption) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let filename = option.iconFilename,
                   let image = IconResolver.image(forFilename: filename) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }

                Text(option.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(String(option.description.prefix(50)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }
}
