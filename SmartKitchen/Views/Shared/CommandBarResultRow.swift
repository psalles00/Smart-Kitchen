import SwiftUI

/// A single row in the Command Bar results list.
struct CommandBarResultRow: View {
    let result: SearchResult
    let isPreSelected: Bool
    let action: () -> Void
    var onQuickAction: (() -> Void)? = nil
    var onReverseAction: (() -> Void)? = nil

    private let checkboxSize: CGFloat = 30
    private let checkboxLineWidth: CGFloat = 3.5

    /// Tracks whether the item has been moved to the other list.
    @State private var isToggled = false
    @State private var strokeProgress: CGFloat = 0
    @State private var fillOpacity: CGFloat = 0
    @State private var showDestIcon: Bool = false
    @State private var destIconScale: CGFloat = 0
    @State private var isAnimating = false

    /// The icon for the current target list.
    private var currentIcon: String {
        if result.type == .pantryItem {
            return isToggled ? "refrigerator" : "cart.badge.plus"
        } else {
            return isToggled ? "cart.badge.plus" : "refrigerator"
        }
    }

    /// The tint for the current target.
    private var currentTint: Color {
        if result.type == .pantryItem {
            return isToggled ? .orange : .green
        } else {
            return isToggled ? .green : .orange
        }
    }

    /// The destination icon shown during animation fill.
    private var destIcon: String {
        if result.type == .pantryItem {
            return isToggled ? "cart.badge.plus" : "refrigerator"
        } else {
            return isToggled ? "refrigerator" : "cart.badge.plus"
        }
    }

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

                // Quick action checkbox: only for single-list items
                if let onQuickAction, !result.isAlsoInOtherList,
                   (result.type == .pantryItem || result.type == .groceryItem) {
                    Button {
                        guard !isAnimating else { return }
                        performToggleAnimation()
                    } label: {
                        ZStack {
                            // Unchecked circle
                            Circle()
                                .stroke(lineWidth: checkboxLineWidth)
                                .foregroundStyle(Color(.tertiarySystemFill))
                                .frame(width: checkboxSize, height: checkboxSize)

                            // Animated stroke
                            Circle()
                                .trim(from: 0, to: strokeProgress)
                                .stroke(
                                    currentTint,
                                    style: StrokeStyle(lineWidth: checkboxLineWidth, lineCap: .round)
                                )
                                .frame(width: checkboxSize, height: checkboxSize)
                                .rotationEffect(.degrees(-90))

                            // Fill
                            Circle()
                                .fill(currentTint)
                                .frame(width: checkboxSize, height: checkboxSize)
                                .opacity(fillOpacity)

                            // Resting icon (current target)
                            Image(systemName: currentIcon)
                                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                                .foregroundStyle(Color(.tertiarySystemFill))
                                .opacity(showDestIcon ? 0 : 1)

                            // Animated destination icon
                            Image(systemName: destIcon)
                                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(showDestIcon ? 1 : 0)
                                .scaleEffect(destIconScale)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Type tags
                HStack(spacing: 4) {
                    typeBadge(
                        label: isToggled ? altTypeLabel : result.typeLabel,
                        tint: isToggled ? altTypeTint : typeTintColor
                    )

                    if result.isAlsoInOtherList || isToggled {
                        typeBadge(
                            label: isToggled ? result.typeLabel : (result.secondaryTypeLabel ?? ""),
                            tint: isToggled ? typeTintColor : tintColor(for: result.secondaryTypeTint ?? "")
                        )
                    } else if let secondaryLabel = result.secondaryTypeLabel,
                              let secondaryTint = result.secondaryTypeTint {
                        typeBadge(label: secondaryLabel, tint: tintColor(for: secondaryTint))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isToggled)

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

    // MARK: - Subviews

    @ViewBuilder
    private func typeBadge(label: String, tint: Color) -> some View {
        if !label.isEmpty {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: .capsule)
        }
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

    // MARK: - Animation

    private func performToggleAnimation() {
        isAnimating = true
        HapticManager.impact(style: .medium)

        // Phase 1: stroke fill
        withAnimation(.easeInOut(duration: 0.25)) {
            strokeProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            // Phase 2: circle fill
            withAnimation(.easeIn(duration: 0.1)) {
                fillOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(50))
            // Phase 3: show destination icon
            showDestIcon = true
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                destIconScale = 1
            }
            HapticManager.impact(style: .light)

            // Fire the action
            if isToggled {
                onReverseAction?()
            } else {
                onQuickAction?()
            }

            // Phase 4: reverse animation after a pause
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.18)) {
                destIconScale = 0
                fillOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(120))
            showDestIcon = false
            withAnimation(.easeOut(duration: 0.18)) {
                strokeProgress = 0
            }
            try? await Task.sleep(for: .milliseconds(200))

            // Toggle state
            isToggled.toggle()
            isAnimating = false
        }
    }

    // MARK: - Helpers

    private var typeTintColor: Color {
        tintColor(for: result.typeTint)
    }

    private var altTypeLabel: String {
        result.type == .pantryItem ? "Mercado" : "Despensa"
    }

    private var altTypeTint: Color {
        result.type == .pantryItem ? .green : .orange
    }

    private func tintColor(for key: String) -> Color {
        switch key {
        case "orange": .orange
        case "green":  .green
        case "red":    .red
        case "purple": .purple
        case "blue":   .blue
        default:       .secondary
        }
    }
}
