import SwiftUI

/// Phase 1 — Step 1. Hero welcome screen with the Nebula shader as backdrop
/// and an orbital search motif rendered around the new Liquid Glass center.
struct WelcomeStepView: View {
    let onContinue: () -> Void

    @State private var showHeroScene = false
    @State private var showHeroGlow = false
    @State private var showOrbitRings = false
    @State private var showCore = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false
    @State private var animateOrbits = false
    @State private var revealedPlanetIDs: Set<String> = []
    @State private var entranceTask: Task<Void, Never>? = nil

    private let planetRevealOrder = [
        "sushi",
        "cheese",
        "mango",
        "banana",
        "pasta",
        "orange",
        "hot-pot",
        "broccoli",
        "strawberry"
    ]

    var body: some View {
        ZStack {
            NebulaShaderView(theme: .home, progress: 1.0)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.05), Color.black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                Spacer(minLength: 6)

                OrbitalSearchHero(
                    animateOrbits: animateOrbits,
                    showGlow: showHeroGlow,
                    showRings: showOrbitRings,
                    showCore: showCore,
                    revealedPlanetIDs: revealedPlanetIDs
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 388)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                    .scaleEffect(showHeroScene ? 1 : 0.92)
                    .opacity(showHeroScene ? 1 : 0)
                    .offset(y: showHeroScene ? -54 : -18)
                    .animation(.spring(response: 0.95, dampingFraction: 0.8), value: showHeroScene)

                VStack(spacing: 12) {
                    localizedTitle
                        .textRenderer(WelcomeTitleUnderlineRenderer(gradientColors: titleGradientColors))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 18)
                        .animation(.spring(response: 0.8, dampingFraction: 0.84), value: showTitle)

                    localizedSubtitle
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 12)
                        .animation(.easeOut(duration: 0.45), value: showSubtitle)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .offset(y: showTitle ? -8 : 10)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showTitle)

                WelcomeLiquidGlassButton(
                    title: String(localized: "Começar"),
                    action: onContinue
                )
                .padding(.top, 10)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 24)
                .animation(.spring(response: 0.74, dampingFraction: 0.86), value: showButton)
            }
        }
        .onAppear {
            beginEntranceSequence()
        }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
        .preferredColorScheme(.dark)
    }

    private var titleFont: Font {
        .custom("Bricolage Grotesque", size: 34, relativeTo: .largeTitle).weight(.bold)
    }

    private var titleGradientColors: [Color] {
        [
            Color(red: 0.98, green: 0.83, blue: 0.43),
            Color(red: 1.00, green: 0.53, blue: 0.62),
            Color(red: 0.82, green: 0.60, blue: 1.00)
        ]
    }

    private var localizedTitle: Text {
        let localized = String(localized: "Organizar sua cozinha e comer bem não precisa ser difícil")

        let segments = markdownTitleSegments(from: localized)
        if segments.isEmpty {
            return Text(localized)
                .font(titleFont)
                .foregroundColor(.white)
        }

        return segments.reduce(Text("")) { partial, segment in
            let baseText = Text(segment.content).font(titleFont)

            let styledText: Text
            if segment.isEmphasized {
                styledText = baseText
                    .italic()
                    .foregroundColor(.white)
                    .customAttribute(WelcomeTitleUnderlineAttribute())
            } else {
                styledText = baseText.foregroundColor(.white)
            }

            return partial + styledText
        }
    }

    private func markdownTitleSegments(from localized: String) -> [TitleSegment] {
        var segments: [TitleSegment] = []
        var buffer = ""
        var isEmphasized = false
        var index = localized.startIndex

        while index < localized.endIndex {
            if localized[index] == "*" {
                if !buffer.isEmpty {
                    segments.append(TitleSegment(content: buffer, isEmphasized: isEmphasized))
                    buffer = ""
                }

                while index < localized.endIndex, localized[index] == "*" {
                    index = localized.index(after: index)
                }
                isEmphasized.toggle()
                continue
            }

            buffer.append(localized[index])
            index = localized.index(after: index)
        }

        if !buffer.isEmpty {
            segments.append(TitleSegment(content: buffer, isEmphasized: isEmphasized))
        }

        return segments
    }

    private var localizedSubtitle: Text {
        let full = String(localized: "Boas-vindas ao Savoria")
        let accent = LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.83, blue: 0.43),
                Color(red: 1.00, green: 0.53, blue: 0.62),
                Color(red: 0.82, green: 0.60, blue: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        guard let range = full.range(of: "Savoria") else {
            return Text(full).foregroundStyle(.white.opacity(0.78))
        }

        let prefix = String(full[..<range.lowerBound])
        let suffix = String(full[range.upperBound...])

        return Text(prefix).foregroundStyle(.white.opacity(0.78))
            + Text("Savoria").foregroundStyle(accent)
            + Text(suffix).foregroundStyle(.white.opacity(0.78))
    }

    private func beginEntranceSequence() {
        entranceTask?.cancel()
        showHeroScene = false
        showHeroGlow = false
        showOrbitRings = false
        showCore = false
        showTitle = false
        showSubtitle = false
        showButton = false
        animateOrbits = false
        revealedPlanetIDs = []

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) {
                showHeroScene = true
            }

            await wait(milliseconds: 180)
            HapticManager.impact(style: .light)
            withAnimation(.easeOut(duration: 0.55)) {
                showHeroGlow = true
            }

            await wait(milliseconds: 180)
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 1.0, dampingFraction: 0.84)) {
                showOrbitRings = true
            }
            animateOrbits = true

            await wait(milliseconds: 260)
            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.92, dampingFraction: 0.8)) {
                showCore = true
            }

            await wait(milliseconds: 180)
            for (index, planetID) in planetRevealOrder.enumerated() {
                if Task.isCancelled { return }
                if index == 0 || index == 3 || index == 6 {
                    HapticManager.impact(style: .light)
                }
                withAnimation(.spring(response: 0.78, dampingFraction: 0.72)) {
                    revealedPlanetIDs.insert(planetID)
                }
                await wait(milliseconds: 120)
            }

            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.84)) {
                showTitle = true
            }

            await wait(milliseconds: 180)
            withAnimation(.easeOut(duration: 0.45)) {
                showSubtitle = true
            }

            await wait(milliseconds: 260)
            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.76, dampingFraction: 0.86)) {
                showButton = true
            }
        }
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

private struct WelcomeTitleUnderlineAttribute: TextAttribute {}

private struct TitleSegment {
    let content: String
    let isEmphasized: Bool
}

private struct WelcomeTitleUnderlineRenderer: TextRenderer {
    let gradientColors: [Color]

    private let lineWidth: CGFloat = 1.4
    private let amplitude: CGFloat = 1.6
    private let wavelength: CGFloat = 14
    private let step: CGFloat = 1.5
    private let baselineOffset: CGFloat = 4.5

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)

                if run[WelcomeTitleUnderlineAttribute.self] != nil {
                    drawUnderline(for: run, in: &context)
                }
            }
        }
    }

    private func drawUnderline(for run: Text.Layout.Run, in context: inout GraphicsContext) {
        let rect = run.typographicBounds.rect
        guard rect.width > 2 else { return }

        let startX = rect.minX + 0.5
        let endX = rect.maxX - 0.5
        let baseY = rect.maxY + baselineOffset

        var path = Path()
        path.move(to: CGPoint(x: startX, y: baseY))

        var x = startX
        while x <= endX {
            let phase = ((x - startX) / wavelength) * 2 * .pi
            let y = baseY + sin(phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        if x - step < endX {
            path.addLine(to: CGPoint(x: endX, y: baseY))
        }

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: gradientColors),
                startPoint: CGPoint(x: startX, y: baseY),
                endPoint: CGPoint(x: endX, y: baseY)
            ),
            lineWidth: lineWidth
        )
    }
}

private struct OrbitalSearchHero: View {
    let animateOrbits: Bool
    let showGlow: Bool
    let showRings: Bool
    let showCore: Bool
    let revealedPlanetIDs: Set<String>

    private let orbitLayers: [OrbitLayer] = [
        OrbitLayer(
            id: "middle",
            diameterMultiplier: 0.68,
            lineWidth: 1.15,
            lineOpacity: 0.34,
            rotationDegrees: 360,
            duration: 26,
            planets: [
                OrbitPlanet(id: "sushi", iconFileName: "sushi.png", angle: -90, size: 60),
                OrbitPlanet(id: "cheese", iconFileName: "cheese.png", angle: 0, size: 58),
                OrbitPlanet(id: "strawberry", iconFileName: "strawberry.png", angle: 96, size: 62),
                OrbitPlanet(id: "mango", iconFileName: "mango.png", angle: 182, size: 62)
            ]
        ),
        OrbitLayer(
            id: "outer",
            diameterMultiplier: 1.10,
            lineWidth: 1,
            lineOpacity: 0.23,
            rotationDegrees: -360,
            duration: 40,
            planets: [
                OrbitPlanet(id: "banana", iconFileName: "banana.png", angle: -132, size: 68),
                OrbitPlanet(id: "pasta", iconFileName: "pasta.png", angle: -56, size: 66),
                OrbitPlanet(id: "orange", iconFileName: "orange.png", angle: 18, size: 64),
                OrbitPlanet(id: "hot-pot", iconFileName: "hot-pot.png", angle: 104, size: 76),
                OrbitPlanet(id: "broccoli", iconFileName: "broccoli.png", angle: 176, size: 70)
            ]
        ),
        OrbitLayer(
            id: "farOuter",
            diameterMultiplier: 1.72,
            lineWidth: 0.9,
            lineOpacity: 0.16,
            rotationDegrees: 360,
            duration: 58,
            planets: []
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let heroSize = min(proxy.size.width, proxy.size.height) * 0.96
            let centerSize = heroSize * 0.42
            let orbitCanvasSize = heroSize * 1.72
            let orbitCenterX = proxy.size.width / 2
            let orbitCenterY = (proxy.size.height / 2) - 8

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.025), Color.white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: heroSize * 0.32
                        )
                    )
                    .frame(width: heroSize * 0.48, height: heroSize * 0.48)
                    .blur(radius: 16)
                    .opacity(showGlow ? 1 : 0)
                    .scaleEffect(showGlow ? 1 : 0.72)
                    .animation(.easeOut(duration: 0.65), value: showGlow)

                ForEach(orbitLayers) { layer in
                    OrbitRing(
                        layer: layer,
                        diameter: heroSize * layer.diameterMultiplier,
                        animateOrbits: animateOrbits,
                        isVisible: showRings,
                        revealedPlanetIDs: revealedPlanetIDs
                    )
                }

                SearchUniverseCore(size: centerSize, isVisible: showCore)
            }
            .frame(width: orbitCanvasSize, height: orbitCanvasSize)
            .position(x: orbitCenterX, y: orbitCenterY)
        }
        .accessibilityHidden(true)
    }
}

private struct OrbitRing: View {
    let layer: OrbitLayer
    let diameter: CGFloat
    let animateOrbits: Bool
    let isVisible: Bool
    let revealedPlanetIDs: Set<String>

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(layer.lineOpacity), lineWidth: layer.lineWidth)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.84)
                .animation(.spring(response: 1.0, dampingFraction: 0.86), value: isVisible)

            ZStack {
                ForEach(layer.planets) { planet in
                    WelcomeOrbitPlanet(
                        planet: planet,
                        isVisible: revealedPlanetIDs.contains(planet.id)
                    )
                        .rotationEffect(.degrees(animateOrbits ? -layer.rotationDegrees : 0))
                        .offset(offset(for: planet.angle, radius: diameter / 2))
                }
            }
            .rotationEffect(.degrees(animateOrbits ? layer.rotationDegrees : 0))
            .animation(
                .linear(duration: layer.duration).repeatForever(autoreverses: false),
                value: animateOrbits
            )
        }
        .frame(width: diameter, height: diameter)
    }

    private func offset(for angleDegrees: Double, radius: CGFloat) -> CGSize {
        let angle = Angle.degrees(angleDegrees)
        return CGSize(
            width: CGFloat(cos(angle.radians)) * radius,
            height: CGFloat(sin(angle.radians)) * radius
        )
    }
}

private struct SearchUniverseCore: View {
    let size: CGFloat
    let isVisible: Bool

    var body: some View {
        ZStack {
            if let image = IconResolver.image(forFilename: "egg-icon.png") {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size * 1.20, height: size * 1.20)
                    .offset(x: (size * 0.11) - 4, y: (size * 0.17) - 15)
            } else {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .scaleEffect(isVisible ? 1 : 0.3)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 10)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.48), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
        .animation(.spring(response: 0.9, dampingFraction: 0.8), value: isVisible)
    }
}

private struct WelcomeOrbitPlanet: View {
    let planet: OrbitPlanet
    let isVisible: Bool

    var body: some View {
        IconImage(
            name: "",
            iconFileName: planet.iconFileName,
            fallbackSymbol: "leaf.fill",
            size: planet.size
        )
        .frame(width: planet.size, height: planet.size)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
        .scaleEffect(isVisible ? 1 : 0.28)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 8)
        .animation(.spring(response: 0.76, dampingFraction: 0.72), value: isVisible)
    }
}

private struct WelcomeLiquidGlassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Color(red: 0.16, green: 0.16, blue: 0.19))
        .foregroundStyle(.white)
        .background {
            if #available(iOS 26, macOS 26, *) {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.28)).interactive(), in: Capsule())
            }
        }
    }
}

private struct OrbitLayer: Identifiable {
    let id: String
    let diameterMultiplier: CGFloat
    let lineWidth: CGFloat
    let lineOpacity: Double
    let rotationDegrees: Double
    let duration: Double
    let planets: [OrbitPlanet]
}

private struct OrbitPlanet: Identifiable {
    let id: String
    let iconFileName: String
    let angle: Double
    let size: CGFloat
}
