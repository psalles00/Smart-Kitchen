import SwiftUI

/// Phase 4 — Step 17. Animated "preparing" screen. While the user watches,
/// `commitOnboardingChoices` writes everything to SwiftData. After the
/// rotation finishes, we show a brief "ready!" frame with confetti before
/// auto-advancing to the paywall.
struct PreparingStepView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onFinished: () -> Void

    @State private var progress: Double = 0
    @State private var phaseIndex: Int = 0
    @State private var hasFired = false
    @State private var showFinale = false
    @State private var fireConfetti = 0

    private let phases: [(String, String)] = [
        ("flame.fill",          String(localized: "Calculando suas calorias")),
        ("chart.pie.fill",      String(localized: "Ajustando macros")),
        ("cabinet.fill",        String(localized: "Preparando despensa")),
        ("book.closed.fill",    String(localized: "Salvando receitas")),
    ]
    private let totalDuration: Double = 3.6
    private let finaleDuration: Double = 1.6

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(white: 0.06), Color(white: 0.10)]
                    : [Color(white: 0.99), Color(white: 0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    if showFinale {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 160, height: 160)
                            Image(systemName: "checkmark")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.10), lineWidth: 8)
                                .frame(width: 160, height: 160)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 160, height: 160)
                                .animation(.linear(duration: 0.1), value: progress)
                            Image(systemName: phases[phaseIndex].0)
                                .font(.system(size: 48, weight: .bold))
                                .transition(.scale.combined(with: .opacity))
                                .id(phaseIndex)
                        }
                    }
                }

                VStack(spacing: 8) {
                    if showFinale {
                        Text(String(localized: "Tudo pronto!"))
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                        Text(String(localized: "Recebemos seus dados. Seu Savoria está pronto pra usar."))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    } else {
                        Text(phases[phaseIndex].1)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(phaseIndex)

                        Text(String(localized: "Personalizando sua experiência…"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }

            ConfettiView(trigger: fireConfetti)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { start() }
    }

    private func start() {
        guard !hasFired else { return }
        hasFired = true

        let stepInterval = totalDuration / Double(phases.count)
        for i in 1..<phases.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(i)) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    phaseIndex = i
                }
            }
        }

        let frameInterval = 1.0 / 60.0
        var elapsed = 0.0
        Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            elapsed += frameInterval
            progress = min(1.0, elapsed / totalDuration)
            if elapsed >= totalDuration {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                        showFinale = true
                    }
                    fireConfetti &+= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + finaleDuration) {
                        onFinished()
                    }
                }
            }
        }
    }
}

// MARK: - Confetti

/// Lightweight confetti rain using `TimelineView` + `Canvas`. Trigger an
/// `Int` to (re)spawn a fresh batch.
private struct ConfettiView: View {
    let trigger: Int

    private struct Piece: Identifiable {
        let id = UUID()
        let xRatio: Double
        let startDelay: Double
        let duration: Double
        let rotationSpeed: Double
        let drift: Double
        let size: CGSize
        let color: Color
    }

    @State private var pieces: [Piece] = []
    @State private var startTime: Date = .distantFuture

    private let palette: [Color] = [
        Color(red: 1.00, green: 0.72, blue: 0.30),
        Color(red: 1.00, green: 0.40, blue: 0.20),
        Color(red: 0.30, green: 0.78, blue: 0.55),
        Color(red: 0.30, green: 0.55, blue: 0.95),
        Color(red: 0.85, green: 0.30, blue: 0.65),
        Color(red: 0.95, green: 0.85, blue: 0.30),
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                Canvas { ctx, size in
                    let now = context.date.timeIntervalSince(startTime)
                    guard now >= 0 else { return }
                    for piece in pieces {
                        let local = now - piece.startDelay
                        guard local >= 0 else { continue }
                        let t = min(1.0, local / piece.duration)
                        let x = piece.xRatio * size.width + sin(local * 2.4) * piece.drift
                        let y = -20 + (size.height + 40) * t
                        let rot = local * piece.rotationSpeed * .pi * 2
                        var transform = CGAffineTransform.identity
                        transform = transform.translatedBy(x: x, y: y)
                        transform = transform.rotated(by: rot)
                        let rect = CGRect(
                            x: -piece.size.width / 2,
                            y: -piece.size.height / 2,
                            width: piece.size.width,
                            height: piece.size.height
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        ctx.drawLayer { layer in
                            layer.transform = transform
                            layer.opacity = Double(1.0 - max(0, t - 0.85) / 0.15)
                            layer.fill(path, with: .color(piece.color))
                        }
                    }
                }
            }
            .onChange(of: trigger) { _, _ in
                spawn(in: geo.size)
            }
        }
    }

    private func spawn(in size: CGSize) {
        var new: [Piece] = []
        for _ in 0..<140 {
            new.append(Piece(
                xRatio: Double.random(in: 0...1),
                startDelay: Double.random(in: 0...0.4),
                duration: Double.random(in: 1.4...2.4),
                rotationSpeed: Double.random(in: 0.6...1.6),
                drift: Double.random(in: -30...30),
                size: CGSize(
                    width: CGFloat.random(in: 5...10),
                    height: CGFloat.random(in: 9...16)
                ),
                color: palette.randomElement() ?? .orange
            ))
        }
        pieces = new
        startTime = Date()
    }
}
