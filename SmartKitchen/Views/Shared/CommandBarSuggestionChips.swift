import SwiftUI

/// Horizontal flow of suggestion chips from the item database.
struct CommandBarSuggestionChips: View {
    let suggestions: [ItemEntry]
    let onSelect: (ItemEntry) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sugestões")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                WrappingHStack(items: suggestions) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(spacing: 5) {
                            IconImage(name: entry.preferredTitle(), fallbackSymbol: "leaf", size: 18)

                            Text(entry.preferredTitle())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Wrapping Horizontal Layout

/// A simple wrapping horizontal stack for laying out chips with multiple per row.
private struct WrappingHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// Make ItemEntry conform to Identifiable for ForEach
extension ItemEntry: Identifiable {
    public var id: String { nomeDoArquivo }
}
