import SwiftUI

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
                    .padding(size * 0.175)
                    .background(resolvedBalloonBackgroundColor, in: Circle())
                    .frame(width: balloonSize, height: balloonSize)
            } else {
                iconContent
                    .frame(width: size, height: size)
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
            ? Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255)
            : neutralSurfaceColor
    }
}
