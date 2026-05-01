import SwiftUI

/// Phase 1 — Step 1. Hero welcome screen with the Nebula shader as backdrop
/// and a custom animated brand mark drawn with `Canvas` (no SF Symbol).
struct WelcomeStepView: View {
    let onContinue: () -> Void

    @State private var didAppear = false
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            NebulaShaderView(theme: .home, progress: 1.0)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 28) {
                Spacer()

                BrandMark()
                    .frame(width: 132, height: 132)
                    .scaleEffect(didAppear ? 1 : 0.65)
                    .opacity(didAppear ? 1 : 0)
                    .animation(.spring(response: 0.85, dampingFraction: 0.62).delay(0.05), value: didAppear)

                VStack(spacing: 10) {
                    Text("Smart Kitchen")
                        .font(.custom("Bricolage Grotesque", size: 42, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(.white)
                        .opacity(didAppear ? 1 : 0)
                        .offset(y: didAppear ? 0 : 14)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.18), value: didAppear)

                    Text(String(localized: "Sua cozinha mais inteligente."))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .opacity(didAppear ? 1 : 0)
                        .offset(y: didAppear ? 0 : 14)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.28), value: didAppear)
                }

                Spacer()

                OnboardingPrimaryButton(
                    title: String(localized: "Começar"),
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 24)
                .animation(.spring(response: 0.65, dampingFraction: 0.85).delay(0.42), value: didAppear)
            }
        }
        .onAppear { didAppear = true }
        .preferredColorScheme(.dark)
    }
}

/// Custom brand mark: two interlocking arcs (knife + pan) drawn via `Canvas`.
/// No SF Symbol, no PNG — purely vector and animatable.
private struct BrandMark: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let breathing = CGFloat(sin(t * 1.4) * 0.5 + 0.5)
                let radius = min(size.width, size.height) * 0.42
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                // Outer halo
                let halo = Path(ellipseIn: CGRect(
                    x: center.x - radius * 1.18,
                    y: center.y - radius * 1.18,
                    width: radius * 2.36,
                    height: radius * 2.36
                ))
                ctx.fill(halo, with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.18 + breathing * 0.10),
                        Color.white.opacity(0.0)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius * 1.2
                ))

                // Pan arc (lower bowl)
                var pan = Path()
                pan.addArc(center: center,
                           radius: radius,
                           startAngle: .degrees(20),
                           endAngle: .degrees(160),
                           clockwise: true)
                ctx.stroke(pan,
                           with: .linearGradient(
                            Gradient(colors: [Color.white, Color.white.opacity(0.65)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: size.height)),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))

                // Pan handle
                var handle = Path()
                handle.move(to: CGPoint(x: center.x + radius * 0.94, y: center.y + radius * 0.34))
                handle.addLine(to: CGPoint(x: center.x + radius * 1.55, y: center.y + radius * 0.62))
                ctx.stroke(handle,
                           with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round))

                // Steam dots — subtle vertical drift
                for i in 0..<3 {
                    let phaseOffset = Double(i) * 0.7
                    let y = sin(t * 1.6 + phaseOffset) * 6
                    let alpha = 0.35 + 0.4 * (sin(t * 2 + phaseOffset) * 0.5 + 0.5)
                    let p = CGPoint(
                        x: center.x + CGFloat(i - 1) * radius * 0.32,
                        y: center.y - radius * 0.85 + CGFloat(y)
                    )
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    ctx.fill(dot, with: .color(.white.opacity(alpha)))
                }
            }
        }
    }
}
