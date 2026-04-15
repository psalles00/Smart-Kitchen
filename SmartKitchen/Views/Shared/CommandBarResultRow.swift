import SwiftUI

/// A single row in the Command Bar results list.
struct CommandBarResultRow: View {
    let result: SearchResult
    let isPreSelected: Bool
    let action: () -> Void
    var onNavigate: (() -> Void)? = nil
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

    // Navigate button animation state
    @State private var navStrokeProgress: CGFloat = 0
    @State private var navFillOpacity: CGFloat = 0
    @State private var navIconScale: CGFloat = 0
    @State private var navIsAnimating = false

    // Enter button animation state
    @State private var enterStrokeProgress: CGFloat = 0
    @State private var enterFillOpacity: CGFloat = 0
    @State private var enterIconScale: CGFloat = 0
    @State private var enterIsAnimating = false

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

                    if !result.subtitle.isEmpty || result.type != .action {
                        Text(smartSubtitle)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Quick action checkbox: only for single-list items
                if let _ = onQuickAction, !result.isAlsoInOtherList,
                   (result.type == .pantryItem || result.type == .groceryItem) {
                    Button {
                        guard !isAnimating else { return }
                        performToggleAnimation()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(lineWidth: checkboxLineWidth)
                                .foregroundStyle(Color(.tertiarySystemFill))
                                .frame(width: checkboxSize, height: checkboxSize)

                            Circle()
                                .trim(from: 0, to: strokeProgress)
                                .stroke(
                                    currentTint,
                                    style: StrokeStyle(lineWidth: checkboxLineWidth, lineCap: .round)
                                )
                                .frame(width: checkboxSize, height: checkboxSize)
                                .rotationEffect(.degrees(-90))

                            Circle()
                                .fill(currentTint)
                                .frame(width: checkboxSize, height: checkboxSize)
                                .opacity(fillOpacity)

                            Image(systemName: currentIcon)
                                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .opacity(showDestIcon ? 0 : 1)

                            Image(systemName: destIcon)
                                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(showDestIcon ? 1 : 0)
                                .scaleEffect(destIconScale)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Navigate to item in its list
                if let onNavigate {
                    Button {
                        guard !navIsAnimating else { return }
                        performButtonAnimation(
                            strokeProgress: $navStrokeProgress,
                            fillOpacity: $navFillOpacity,
                            iconScale: $navIconScale,
                            isAnimating: $navIsAnimating,
                            tint: .secondary,
                            action: onNavigate
                        )
                    } label: {
                        animatedCircleIndicator(
                            icon: "arrow.right",
                            tint: .secondary,
                            strokeProgress: navStrokeProgress,
                            fillOpacity: navFillOpacity,
                            iconScale: navIconScale
                        )
                    }
                    .buttonStyle(.plain)
                }

                if isPreSelected {
                    Button {
                        guard !enterIsAnimating else { return }
                        performButtonAnimation(
                            strokeProgress: $enterStrokeProgress,
                            fillOpacity: $enterFillOpacity,
                            iconScale: $enterIconScale,
                            isAnimating: $enterIsAnimating,
                            tint: .secondary,
                            action: action
                        )
                    } label: {
                        animatedCircleIndicator(
                            icon: "return",
                            tint: .secondary,
                            strokeProgress: enterStrokeProgress,
                            fillOpacity: enterFillOpacity,
                            iconScale: enterIconScale
                        )
                    }
                    .buttonStyle(.plain)
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
    private func circleIndicator(icon: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: checkboxLineWidth)
                .foregroundStyle(Color(.tertiarySystemFill))
                .frame(width: checkboxSize, height: checkboxSize)

            Image(systemName: icon)
                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                .foregroundStyle(tint.opacity(0.6))
        }
    }

    @ViewBuilder
    private func animatedCircleIndicator(icon: String, tint: Color, strokeProgress: CGFloat, fillOpacity: CGFloat, iconScale: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: checkboxLineWidth)
                .foregroundStyle(Color(.tertiarySystemFill))
                .frame(width: checkboxSize, height: checkboxSize)

            Circle()
                .trim(from: 0, to: strokeProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: checkboxLineWidth, lineCap: .round)
                )
                .frame(width: checkboxSize, height: checkboxSize)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(tint)
                .frame(width: checkboxSize, height: checkboxSize)
                .opacity(fillOpacity)

            Image(systemName: icon)
                .font(.system(size: checkboxSize * 0.38, weight: .bold))
                .foregroundStyle(fillOpacity > 0 ? .white : tint.opacity(0.6))
                .scaleEffect(iconScale > 0 ? iconScale : 1)
        }
    }

    @ViewBuilder
    private var typeIndicators: some View {
        let primary = isToggled ? (altTypeIcon, altTypeTint) : (typeIcon(for: result.type), typeTintColor)
        circleIndicator(icon: primary.0, tint: primary.1)

        if result.isAlsoInOtherList || isToggled {
            let secondary = isToggled
                ? (typeIcon(for: result.type), typeTintColor)
                : (typeIcon(forTint: result.secondaryTypeTint), tintColor(for: result.secondaryTypeTint ?? ""))
            circleIndicator(icon: secondary.0, tint: secondary.1)
        } else if let secondaryTint = result.secondaryTypeTint {
            circleIndicator(icon: typeIcon(forTint: secondaryTint), tint: tintColor(for: secondaryTint))
        }
    }

    private func typeIcon(for type: SearchResultType) -> String {
        switch type {
        case .pantryItem: return "refrigerator"
        case .groceryItem: return "cart"
        case .recipe: return "book"
        case .utensil: return "fork.knife"
        case .suggestion: return "plus"
        case .action: return "sparkles"
        }
    }

    private func typeIcon(forTint key: String?) -> String {
        switch key {
        case "orange": return "orange"  // pantry
        case "green": return "cart"     // grocery
        case "purple": return "fork.knife"
        case "red": return "book"
        default: return "circle"
        }
    }

    private var altTypeIcon: String {
        result.type == .pantryItem ? "cart" : "refrigerator"
    }

    @ViewBuilder
    private var resultIcon: some View {
        if result.type == .recipe, let data = result.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
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

    /// Generic button animation (navigate, enter, etc.) that mirrors the checkbox animation.
    private func performButtonAnimation(
        strokeProgress: Binding<CGFloat>,
        fillOpacity: Binding<CGFloat>,
        iconScale: Binding<CGFloat>,
        isAnimating: Binding<Bool>,
        tint: Color,
        action: @escaping () -> Void
    ) {
        isAnimating.wrappedValue = true
        HapticManager.impact(style: .medium)

        // Phase 1: stroke fill
        withAnimation(.easeInOut(duration: 0.25)) {
            strokeProgress.wrappedValue = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            // Phase 2: circle fill
            withAnimation(.easeIn(duration: 0.1)) {
                fillOpacity.wrappedValue = 1
            }
            try? await Task.sleep(for: .milliseconds(50))
            // Phase 3: icon pop
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                iconScale.wrappedValue = 1.15
            }
            HapticManager.impact(style: .light)

            // Fire the action
            action()

            // Phase 4: reverse
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.18)) {
                iconScale.wrappedValue = 0
                fillOpacity.wrappedValue = 0
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.18)) {
                strokeProgress.wrappedValue = 0
            }
            try? await Task.sleep(for: .milliseconds(200))
            iconScale.wrappedValue = 0
            isAnimating.wrappedValue = false
        }
    }

    // MARK: - Helpers

    /// Shows "Category, em Lista" combining the existing subtitle with the type label.
    private var smartSubtitle: String {
        let category = result.subtitle
        let list = result.typeLabel
        if category.isEmpty && list.isEmpty { return "" }
        if list.isEmpty { return category }
        if category.isEmpty { return "em \(list)" }
        return "\(category), em \(list)"
    }

    private var typeTintColor: Color {
        tintColor(for: result.typeTint)
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
