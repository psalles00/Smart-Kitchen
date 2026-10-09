import SwiftUI

struct ThemedBackgroundView: View {
    let theme: PageTheme
    var progress: CGFloat = 1.0
    var animates: Bool = true

    var body: some View {
        #if os(iOS)
        SavoriaShaderBackground(theme: theme, animates: animates)
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        StaticPageBackground(theme: theme)
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(iOS)
/// Keep the animation in a leaf so frames never invalidate the page's queries.
private struct SavoriaShaderBackground: View {
    let theme: PageTheme
    let animates: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var epoch = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20,
                                paused: !animates || reduceMotion || scenePhase != .active)) { timeline in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.savoriaNebula(
                        .float2(geometry.size),
                        .float(Float(reduceMotion || !animates ? 0 : timeline.date.timeIntervalSince(epoch))),
                        .color(theme.shaderTint),
                        .float(1)
                    ))
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.08), .black.opacity(contrast == .increased ? 0.68 : 0.48)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension PageTheme {
    /// Preserve each existing orbital background hue rather than tinting all pages blue.
    var shaderTint: Color {
        let hue: Double = switch self {
        case .home: 0.9841
        case .lists: 0.5982
        case .recipes: 0.1050
        case .nutrients: 0.3958
        case .settings: 0.6000
        case .assistant: 0.6667
        }
        return Color(hue: hue, saturation: 0.86, brightness: 0.82)
    }
}

/// Rotina's neutral column and two-layer edge, fitted to Savoria's existing geometry.
struct SavoriaColumnSurface: View {
    let theme: PageTheme
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
    }

    var body: some View {
        shape
            .fill(colorScheme == .dark ? Color(red: 14 / 255.0, green: 14 / 255.0, blue: 16 / 255.0) : .white)
            .overlay {
                LinearGradient(colors: [theme.accentColor.opacity(contrast == .increased ? 0 : (colorScheme == .dark ? 0.065 : 0.025)), .clear],
                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.5, y: 0.3))
                    .clipShape(shape)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SavoriaColumnBorder: View {
    let theme: PageTheme
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
    }

    var body: some View {
        ZStack {
            shape.strokeBorder(theme.secondaryAccentColor.opacity(colorScheme == .dark ? 0.32 : 0.16), lineWidth: 1.2)
                .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                             .init(color: .white.opacity(0.06), location: 0.08),
                                             .init(color: .white.opacity(0.28), location: 1)],
                                     startPoint: .top, endPoint: .bottom))

            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.88),
                                                       theme.secondaryAccentColor.opacity(0.40), .clear],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: contrast == .increased ? 1.5 : 1)
                .mask(alignment: .top) {
                    LinearGradient(colors: [.white, .white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 100)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

struct StaticPageBackground: View {
    let theme: PageTheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let orbSize = max(width, height) * 1.05

            ZStack {
                Color.black

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.88, green: 0.94, blue: 1.00).opacity(0.92),
                                orbAccentTint.opacity(0.58),
                                orbDarkTint.opacity(0.86),
                                Color.black.opacity(0.0)
                            ],
                            center: .topLeading,
                            startRadius: 40,
                            endRadius: orbSize * 0.62
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .blur(radius: 54)
                    .offset(x: -width * 0.34, y: -height * 0.28)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                orbAccentTint.opacity(0.28),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: width * 1.15, height: height * 0.42)
                    .blur(radius: 38)
                    .rotationEffect(.degrees(-16))
                    .offset(x: width * 0.18, y: height * 0.12)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear,
                        Color.black.opacity(0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.12)
                    .blendMode(.screen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orbAccentTint: Color {
        Color(
            hue: themeOrbHue,
            saturation: 0.98,
            brightness: 0.43
        )
    }

    private var orbDarkTint: Color {
        Color(
            hue: themeOrbHue,
            saturation: 0.96,
            brightness: 0.30
        )
    }

    private var themeOrbHue: Double {
        switch theme {
        case .home:
            0.9841
        case .lists:
            0.5982
        case .recipes:
            0.1050
        case .nutrients:
            0.3958
        case .settings:
            0.6000
        case .assistant:
            0.6667
        }
    }
}
