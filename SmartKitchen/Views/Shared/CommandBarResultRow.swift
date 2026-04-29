import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A single row in the Command Bar results list.
struct CommandBarResultRow: View {
    let result: SearchResult
    let isPreSelected: Bool
    let action: () -> Void
    var onNavigate: (() -> Void)? = nil
    var onQuickAction: (() -> Void)? = nil

    private let checkboxSize: CGFloat = 30
    private let checkboxLineWidth: CGFloat = 3.5

    @State private var strokeProgress: CGFloat = 0
    @State private var fillOpacity: CGFloat = 0
    @State private var showDestIcon: Bool = false
    @State private var destIconScale: CGFloat = 0
    @State private var isAnimating = false
    @State private var animationSourceType: SearchResultType?

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
        switch result.type {
        case .pantryItem:
            return "cart.badge.plus"
        case .groceryItem:
            return "refrigerator"
        default:
            return "circle"
        }
    }

    /// The tint for the current target.
    private var currentTint: Color {
        switch result.type {
        case .pantryItem:
            return Color(red: 160/255, green: 58/255, blue: 19/255)
        case .groceryItem:
            return Color(red: 37/255, green: 79/255, blue: 34/255)
        default:
            return .secondary
        }
    }

    /// The destination icon shown during animation fill.
    private var destIcon: String {
        switch animationSourceType ?? result.type {
        case .pantryItem:
            return "refrigerator"
        case .groceryItem:
            return "cart.badge.plus"
        default:
            return "circle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                resultIcon
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !result.subtitle.isEmpty && result.type != .action {
                        Text(smartCategory)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Tags (stacked if multiple, inline if single)
                if !displayedListTypes.isEmpty {
                    listTagsView
                }

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
                            icon: "magnifyingglass",
                            tint: .secondary,
                            strokeProgress: navStrokeProgress,
                            fillOpacity: navFillOpacity,
                            iconScale: navIconScale
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isPreSelected ? Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255) : Color.clear,
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

    private var displayedListTypes: [SearchResultType] {
        if !result.listTypes.isEmpty {
            return result.listTypes
        }
        return result.type == .action ? [] : [result.type]
    }

    @ViewBuilder
    private var listTagsView: some View {
        if displayedListTypes.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(displayedListTypes, id: \.rawValue) { listType in
                    listTag(for: listType)
                }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(displayedListTypes, id: \.rawValue) { listType in
                    listTag(for: listType)
                }
            }
        }
    }

    @ViewBuilder
    private func listTag(for type: SearchResultType) -> some View {
        if type == .action {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: tagIcon(for: type))
                    .font(.system(size: 9, weight: .semibold))
                Text(tagLabel(for: type))
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(tagTint(for: type))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tagTint(for: type).opacity(0.12), in: .capsule)
        }
    }

    private func tagLabel(for type: SearchResultType) -> String {
        switch type {
        case .pantryItem:  return String(localized: "Despensa")
        case .groceryItem: return String(localized: "Mercado")
        case .recipe:      return String(localized: "Receita")
        case .utensil:     return String(localized: "Utensílio")
        case .suggestion:  return String(localized: "Sugestão")
        case .action:      return ""
        }
    }

    private func tagIcon(for type: SearchResultType) -> String {
        switch type {
        case .pantryItem:  return "refrigerator"
        case .groceryItem: return "cart"
        case .recipe:      return "book"
        case .utensil:     return "fork.knife"
        case .suggestion:  return "plus"
        case .action:      return "circle"
        }
    }

    private func tagTint(for type: SearchResultType) -> Color {
        switch type {
        case .pantryItem:  return Color(red: 37/255, green: 79/255, blue: 34/255)
        case .groceryItem: return Color(red: 160/255, green: 58/255, blue: 19/255)
        case .recipe:      return .red
        case .utensil:     return .purple
        case .suggestion:  return .blue
        case .action:      return .secondary
        }
    }

    @ViewBuilder
    private var resultIcon: some View {
        #if canImport(UIKit)
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
        #else
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
        #endif
    }

    // MARK: - Animation

    private func performToggleAnimation() {
        isAnimating = true
        animationSourceType = result.type
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
            onQuickAction?()

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

            animationSourceType = nil
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

    /// Shows only the category portion of the subtitle (without list info).
    private var smartCategory: String {
        result.subtitle
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
