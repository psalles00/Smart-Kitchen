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
/// Every page samples the same clock, viewport and palette transition.
struct SavoriaBackdropPalette {
    var target: PageTheme = .home
    private var source: SIMD3<Double> = PageTheme.home.shaderRGB
    private var startedAt: TimeInterval = 0

    func rgb(at time: TimeInterval) -> SIMD3<Double> {
        let fraction = min(1, max(0, (time - startedAt) / 0.55))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return source + (target.shaderRGB - source) * eased
    }

    mutating func transition(to theme: PageTheme) {
        let now = ProcessInfo.processInfo.systemUptime
        source = rgb(at: now)
        startedAt = now
        target = theme
    }
}

private struct SavoriaBackdropPaletteKey: EnvironmentKey {
    static let defaultValue: SavoriaBackdropPalette? = nil
}
private struct SavoriaBackdropViewportKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}
extension EnvironmentValues {
    var savoriaBackdropPalette: SavoriaBackdropPalette? {
        get { self[SavoriaBackdropPaletteKey.self] }
        set { self[SavoriaBackdropPaletteKey.self] = newValue }
    }
    var savoriaBackdropViewport: CGSize {
        get { self[SavoriaBackdropViewportKey.self] }
        set { self[SavoriaBackdropViewportKey.self] = newValue }
    }
}

private enum SavoriaShaderClock {
    static let epoch = ProcessInfo.processInfo.systemUptime
}

private struct SavoriaShaderBackground: View {
    let theme: PageTheme
    let animates: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.savoriaBackdropPalette) private var palette
    @Environment(\.savoriaBackdropViewport) private var viewport

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 20,
                                    paused: !animates || reduceMotion || scenePhase != .active)) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                let tint = palette?.target == theme ? palette!.rgb(at: now) : theme.shaderRGB
                Rectangle()
                    .fill(.white)
                    .modifier(SavoriaAnimatedShaderTint(
                        tint: tint,
                        size: viewport.width > 0 ? viewport : geometry.size,
                        time: reduceMotion ? 0 : now - SavoriaShaderClock.epoch))
                    .overlay {
                        LinearGradient(colors: [.black.opacity(contrast == .increased ? 0.60 : 0.42), .black.opacity(contrast == .increased ? 0.85 : 0.72)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Only RGB interpolates. SwiftUI must never tween the clock or viewport uniforms.
private struct SavoriaAnimatedShaderTint: AnimatableModifier {
    nonisolated var tint: SIMD3<Double>
    let size: CGSize
    let time: TimeInterval

    nonisolated var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(tint.x, AnimatablePair(tint.y, tint.z)) }
        set { tint = SIMD3(newValue.first, newValue.second.first, newValue.second.second) }
    }

    func body(content: Content) -> some View {
        content.colorEffect(ShaderLibrary.savoriaNebula(
            .float2(size), .float(time),
            .color(Color(red: tint.x, green: tint.y, blue: tint.z)), .float(1)))
            .transaction { $0.animation = nil }
    }
}

private extension PageTheme {
    var shaderRGB: SIMD3<Double> {
        let hue: Double = switch self {
        case .home: 0.9841
        case .lists: 0.5982
        case .recipes: 0.1050
        case .nutrients: 0.3958
        case .settings: 0.6000
        case .assistant: 0.6667
        }
        let chroma = 0.82 * 0.86
        let sector = hue * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: SIMD3<Double> = switch Int(sector) {
        case 0: SIMD3(chroma, x, 0)
        case 1: SIMD3(x, chroma, 0)
        case 2: SIMD3(0, chroma, x)
        case 3: SIMD3(0, x, chroma)
        case 4: SIMD3(x, 0, chroma)
        default: SIMD3(chroma, 0, x)
        }
        return rgb + SIMD3(repeating: 0.82 - chroma)
    }

    var shaderTint: Color {
        let rgb = shaderRGB
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    var shaderHighlight: Color {
        let rgb = shaderRGB + (SIMD3<Double>(repeating: 1) - shaderRGB) * 0.6
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
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
                LinearGradient(colors: [theme.shaderTint.opacity(contrast == .increased ? 0 : (colorScheme == .dark ? 0.04 : 0.015)), .clear],
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
        shape.strokeBorder(
            LinearGradient(stops: [
                .init(color: theme.shaderHighlight.opacity(colorScheme == .dark ? 0.58 : 0.45), location: 0),
                .init(color: theme.shaderTint.opacity(0.18), location: 0.025),
                .init(color: theme.shaderTint.opacity(0.025), location: 0.12),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom),
            lineWidth: contrast == .increased ? 1.25 : 0.75)
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
