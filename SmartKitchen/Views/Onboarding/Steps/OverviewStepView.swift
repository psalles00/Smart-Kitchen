import SwiftUI

/// Phase 1 — Step 2 (overview). Apresenta os pilares do app em formato
/// orbital animado: cada planeta representa uma área (Receitas, Despensa,
/// Mercado, Nutrição, IA, Utensílios) e linhas finas conectam tudo ao
/// núcleo central, comunicando "tudo em um só lugar e sincronizado".
struct OverviewStepView: View {
    let onContinue: () -> Void

    @State private var showHero = false
    @State private var showCore = false
    @State private var showRing = false
    @State private var revealedPlanetIDs: Set<String> = []
    @State private var connectionsActive: Bool = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var animateOrbits = false
    @State private var entranceTask: Task<Void, Never>? = nil

    private let planets: [OverviewPlanet] = [
        OverviewPlanet(id: "recipes",   icon: "book.closed.fill",       label: String(localized: "Receitas"),   color: Color(red: 0.96, green: 0.55, blue: 0.40), angle: -90),
        OverviewPlanet(id: "pantry",    icon: "cabinet.fill",           label: String(localized: "Despensa"),   color: Color(red: 0.42, green: 0.78, blue: 0.55), angle: -28),
        OverviewPlanet(id: "grocery",   icon: "cart.fill",              label: String(localized: "Mercado"),    color: Color(red: 0.98, green: 0.72, blue: 0.34), angle: 36),
        OverviewPlanet(id: "nutrition", icon: "chart.bar.doc.horizontal.fill", label: String(localized: "Nutrição"), color: Color(red: 0.55, green: 0.50, blue: 0.96), angle: 100),
        OverviewPlanet(id: "ai",        icon: "sparkles",               label: String(localized: "IA"),         color: Color(red: 0.86, green: 0.40, blue: 0.86), angle: 164),
        OverviewPlanet(id: "utensils",  icon: "fork.knife",             label: String(localized: "Utensílios"), color: Color(red: 0.44, green: 0.70, blue: 0.92), angle: 228),
    ]

    private var revealOrder: [String] { planets.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            heroStage
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .opacity(showHero ? 1 : 0)
                .scaleEffect(showHero ? 1 : 0.92)
                .animation(.spring(response: 0.85, dampingFraction: 0.82), value: showHero)

            VStack(spacing: 0) {
            VStack(spacing: 12) {
                OnboardingFeatureChip(
                    icon: "square.grid.2x2.fill",
                    title: String(localized: "Visão geral"),
                    tint: .accentColor
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Toda a sua cozinha em um só lugar"),
                    subtitle: String(localized: "Receitas, despensa, mercado e nutrição que conversam entre si.")
                )
                .opacity(showHeader ? 1 : 0)
                .offset(y: showHeader ? 0 : 14)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)
            }

                Spacer(minLength: 16)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 18)
                .animation(.spring(response: 0.74, dampingFraction: 0.86), value: showButton)
            }
        }
        .onAppear { beginEntranceSequence() }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
    }

    // MARK: - Hero stage

    private var heroStage: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.96
            let radius = size * 0.36
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height / 2

            ZStack {
                // Soft glow behind the core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius * 0.9
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)
                    .blur(radius: 18)
                    .scaleEffect(showCore ? 1 : 0.6)
                    .opacity(showCore ? 1 : 0)

                // Connection lines from center to each revealed planet
                ForEach(planets) { planet in
                    if revealedPlanetIDs.contains(planet.id) {
                        ConnectionLine(
                            angle: planet.angle,
                            radius: radius,
                            tint: planet.color,
                            isActive: connectionsActive
                        )
                    }
                }

                // Orbit ring
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .opacity(showRing ? 1 : 0)
                    .scaleEffect(showRing ? 1 : 0.84)

                // Planets
                ForEach(planets) { planet in
                    OverviewPlanetView(
                        planet: planet,
                        isVisible: revealedPlanetIDs.contains(planet.id)
                    )
                    .offset(offset(for: planet.angle, radius: radius, animate: animateOrbits))
                }

                // Central core
                OverviewCore(isVisible: showCore)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .position(x: centerX, y: centerY)
        }
        .accessibilityHidden(true)
    }

    private func offset(for angleDegrees: Double, radius: CGFloat, animate: Bool) -> CGSize {
        let angle = Angle.degrees(angleDegrees)
        return CGSize(
            width: CGFloat(cos(angle.radians)) * radius,
            height: CGFloat(sin(angle.radians)) * radius
        )
    }

    // MARK: - Entrance sequence

    private func beginEntranceSequence() {
        entranceTask?.cancel()
        showHero = false
        showCore = false
        showRing = false
        revealedPlanetIDs = []
        connectionsActive = false
        showHeader = false
        showButton = false
        animateOrbits = false

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) {
                showHero = true
            }

            await wait(milliseconds: 160)
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.92, dampingFraction: 0.8)) {
                showCore = true
            }

            await wait(milliseconds: 220)
            withAnimation(.spring(response: 1.0, dampingFraction: 0.86)) {
                showRing = true
            }

            await wait(milliseconds: 200)
            for (index, planetID) in revealOrder.enumerated() {
                if Task.isCancelled { return }
                if index % 2 == 0 {
                    HapticManager.impact(style: .light)
                }
                withAnimation(.spring(response: 0.78, dampingFraction: 0.74)) {
                    revealedPlanetIDs.insert(planetID)
                }
                await wait(milliseconds: 130)
            }

            // Activate connections after planets land
            HapticManager.impact(style: .medium)
            withAnimation(.easeInOut(duration: 0.55)) {
                connectionsActive = true
            }
            animateOrbits = true

            await wait(milliseconds: 220)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.84)) {
                showHeader = true
            }

            await wait(milliseconds: 220)
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.76, dampingFraction: 0.86)) {
                showButton = true
            }
        }
    }

    private func wait(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

// MARK: - Subviews

private struct OverviewPlanet: Identifiable {
    let id: String
    let icon: String
    let label: String
    let color: Color
    let angle: Double
}

private struct OverviewPlanetView: View {
    let planet: OverviewPlanet
    let isVisible: Bool

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(planet.color.opacity(0.18))
                    .frame(width: 56, height: 56)
                    .blur(radius: 6)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [planet.color.opacity(0.95), planet.color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: planet.color.opacity(0.45), radius: 10, y: 4)

                Image(systemName: planet.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(planet.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.78))
        }
        .scaleEffect(isVisible ? 1 : 0.3)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct OverviewCore: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.85, blue: 0.46),
                            Color(red: 1.00, green: 0.55, blue: 0.65),
                            Color(red: 0.78, green: 0.55, blue: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .scaleEffect(isVisible ? 1 : 0.4)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 10)
    }
}

private struct ConnectionLine: View {
    let angle: Double
    let radius: CGFloat
    let tint: Color
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 1.4) * 0.5 + 0.5) * 0.6 + 0.25

            Path { path in
                let radians = Angle.degrees(angle).radians
                let endX = cos(radians) * radius
                let endY = sin(radians) * radius
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(
                tint.opacity(isActive ? pulse : 0),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 4])
            )
        }
        .allowsHitTesting(false)
    }
}
