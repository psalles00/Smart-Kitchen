import SwiftUI

struct ThemedBackgroundView: View {
    let theme: PageTheme
    let selection: BackgroundSelection
    var progress: CGFloat = 1.0
    var animated = true

    @AppStorage(PerformancePreferences.backgroundShadersEnabledKey)
    private var backgroundShadersEnabled = true

    private var shouldAnimateBackground: Bool {
        animated && backgroundShadersEnabled
    }

    var body: some View {
        Group {
            if shouldAnimateBackground {
                animatedBackground
            } else {
                staticBackground
                    .opacity(progress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var animatedBackground: some View {
        switch selection.type {
        case .texturedGradient:
            if let preset = selection.texturedPreset {
                TexturedGradientView(preset: preset, progress: progress)
            } else {
                NebulaShaderView(theme: nebulaTheme, progress: progress)
            }
        case .original:
            NebulaShaderView(theme: nebulaTheme, progress: progress)
        case .waves:
            WavesShaderView(progress: progress)
        }
    }

    @ViewBuilder
    private var staticBackground: some View {
        StaticAppleOrbBackground(theme: theme)
    }

    private var nebulaTheme: NebulaTheme {
        switch theme {
        case .home: .home
        case .lists: .lists
        case .recipes: .recipes
        case .nutrients: .nutrients
        case .settings: .settings
        case .assistant: .assistant
        }
    }
}

private struct StaticAppleOrbBackground: View {
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
                                Color(red: 0.80, green: 0.86, blue: 0.90).opacity(0.88),
                                orbAccentTint.opacity(0.44),
                                orbDarkTint.opacity(0.90),
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
                                Color.white.opacity(0.11),
                                orbAccentTint.opacity(0.18),
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
            saturation: 0.82,
            brightness: 0.3255
        )
    }

    private var orbDarkTint: Color {
        Color(
            hue: themeOrbHue,
            saturation: 0.82,
            brightness: 0.2300
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
