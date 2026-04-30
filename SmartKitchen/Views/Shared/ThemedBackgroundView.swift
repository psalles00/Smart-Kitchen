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
        switch selection.type {
        case .texturedGradient:
            if let preset = selection.texturedPreset {
                StaticTexturedGradientBackground(preset: preset)
            } else {
                StaticNebulaBackground(theme: theme)
            }
        case .original:
            StaticNebulaBackground(theme: theme)
        case .waves:
            StaticWavesBackground()
        }
    }

    private var nebulaTheme: NebulaTheme {
        switch theme {
        case .home: .home
        case .lists: .lists
        case .recipes: .recipes
        case .nutrients: .nutrients
        }
    }
}

private struct StaticNebulaBackground: View {
    let theme: PageTheme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                glowTint.opacity(0.74),         primaryTint.opacity(0.62),      primaryTint.opacity(0.46),
                primaryTint.opacity(0.50),      primaryTint.opacity(0.30),      Color(red: 0.04, green: 0.02, blue: 0.03),
                Color(red: 0.03, green: 0.015, blue: 0.02), Color.black,       Color.black
            ]
        )
        .overlay {
            ZStack {
                Color.black.opacity(theme == .home ? 0.26 : 0.20)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.24),
                        Color.black.opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primaryTint: Color {
        switch theme {
        case .home:
            Color(red: 0.82, green: 0.10, blue: 0.18)
        case .lists:
            Color(red: 0.20, green: 0.50, blue: 1.0)
        case .recipes:
            Color(red: 0.90, green: 0.62, blue: 0.12)
        case .nutrients:
            Color(red: 0.10, green: 0.90, blue: 0.30)
        }
    }

    private var glowTint: Color {
        switch theme {
        case .home:
            Color(red: 0.98, green: 0.36, blue: 0.28)
        case .lists:
            Color(red: 0.52, green: 0.76, blue: 1.0)
        case .recipes:
            Color(red: 0.98, green: 0.76, blue: 0.26)
        case .nutrients:
            Color(red: 0.40, green: 0.96, blue: 0.58)
        }
    }
}

private struct StaticWavesBackground: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                Color(red: 0.18, green: 0.48, blue: 0.60),
                Color(red: 0.12, green: 0.38, blue: 0.56),
                Color(red: 0.07, green: 0.28, blue: 0.44),
                Color(red: 0.05, green: 0.22, blue: 0.38),
                Color(red: 0.03, green: 0.14, blue: 0.28),
                Color(red: 0.02, green: 0.07, blue: 0.16),
                Color(red: 0.015, green: 0.05, blue: 0.12),
                Color(red: 0.01, green: 0.03, blue: 0.08),
                Color.black
            ]
        )
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StaticTexturedGradientBackground: View {
    let preset: TexturedGradientPreset

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                preset.color1.opacity(0.72),    preset.color1.opacity(0.56),    preset.color2.opacity(0.66),
                preset.color2.opacity(0.52),    preset.color2.opacity(0.34),    preset.color3.opacity(0.68),
                preset.color3.opacity(0.50),    Color(red: 0.03, green: 0.025, blue: 0.04), Color.black
            ]
        )
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.26),
                    Color.black.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}