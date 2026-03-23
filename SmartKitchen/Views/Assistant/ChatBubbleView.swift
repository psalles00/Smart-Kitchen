import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let onQuickAction: (QuickAction) -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)), in: bubbleShape)
                    .foregroundStyle(isUser ? .white : .primary)

                // Quick actions
                if !message.quickActions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(message.quickActions) { action in
                            Button {
                                onQuickAction(action)
                            } label: {
                                Text(action.label)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if isUser {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: 4, topTrailingRadius: 18
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 4,
                bottomTrailingRadius: 18, topTrailingRadius: 18
            )
        }
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += maxH + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let maxH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += maxH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows = [[LayoutSubviews.Element]]()
        var currentRow = [LayoutSubviews.Element]()
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !currentRow.isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append(currentRow)
                currentRow = [subview]
                currentWidth = size.width
            } else {
                currentRow.append(subview)
                currentWidth += (currentRow.count > 1 ? spacing : 0) + size.width
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }
}
