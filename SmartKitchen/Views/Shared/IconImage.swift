import SwiftUI

extension View {
    /// The soft reflection uses the icon's own pixels, silhouette and colors.
    /// Apply to the icon only, before any enclosing button surface.
    @ViewBuilder
    func savoriaIconDepth(size: CGFloat) -> some View {
        #if os(iOS)
        modifier(SavoriaIconDepthModifier(size: size))
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct SavoriaIconDepthModifier: ViewModifier {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let radius = min(10, max(2, size * 0.09))
        content
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12),
                    radius: radius * 0.45, y: max(1, radius * 0.35))
            .background {
                if contrast != .increased {
                    content
                        .blur(radius: radius)
                        .opacity(colorScheme == .dark ? 0.36 : 0.14)
                        .offset(y: radius * 0.65)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
#endif

/// Displays an icon from the bundled icon library, falling back to an SF Symbol.
/// When `showBalloon` is true, wraps the icon in a circular background.
struct IconImage: View {
    @Environment(\.colorScheme) private var colorScheme

    let name: String
    var iconFileName: String? = nil
    var fallbackSymbol: String = "leaf"
    var size: CGFloat = 28
    var showBalloon: Bool = false
    var balloonColor: Color? = nil

    var body: some View {
        let balloonSize = size + size * 0.35
        Group {
            if showBalloon {
                iconContent
                    .frame(width: size, height: size)
                    .savoriaIconDepth(size: size)
                    .padding(size * 0.175)
                    .background(resolvedBalloonBackgroundColor, in: Circle())
                    .frame(width: balloonSize, height: balloonSize)
            } else {
                iconContent
                    .frame(width: size, height: size)
                    .savoriaIconDepth(size: size)
            }
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        if let resolved = resolvedImage {
            Image(platformImage: resolved)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.55))
                .foregroundStyle(.secondary)
        }
    }

    private var resolvedImage: PlatformImage? {
        // 1. Try explicit filename first
        if let fileName = iconFileName, !fileName.isEmpty,
           let img = IconResolver.image(forFilename: fileName) {
            return img
        }
        // 2. Fall back to name-based resolution
        if !name.isEmpty {
            return IconResolver.image(for: name)
        }
        return nil
    }

    private var resolvedBalloonBackgroundColor: Color {
        if let balloonColor {
            return balloonColor
        }

        return colorScheme == .dark
            ? Color(red: 0x54 / 255.0, green: 0x54 / 255.0, blue: 0x58 / 255.0)
            : neutralSurfaceColor
    }
}
