import SwiftUI

// MARK: - Assistant Trigger Bar

/// Compact pill button displayed above the tab bar on iOS.
/// Uses matchedGeometryEffect to morph into the full-width search bar
/// when the fullscreen assistant opens.
struct AssistantTriggerBar: View {
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))

                Text("Assistente")
                    .font(.subheadline.weight(.medium))

                #if os(iOS)
                actionIcon("mic.fill")
                #endif
                actionIcon("photo.on.rectangle")
                actionIcon("camera")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
            .background(background)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: "assistantBar", in: namespace)
        .accessibilityLabel("Assistente")
    }

    private func actionIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.65))
    }

    @ViewBuilder
    private var background: some View {
        if #available(iOS 26, macOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(Color(.tertiarySystemFill))
        }
    }
}
