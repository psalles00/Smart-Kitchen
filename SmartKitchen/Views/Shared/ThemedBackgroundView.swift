import SwiftUI

struct ThemedBackgroundView: View {
    let theme: PageTheme
    var progress: CGFloat = 1.0

    var body: some View {
        StaticPageBackground(theme: theme)
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
