import SwiftUI

/// Phase 4 — Step 17. Animated "preparing" screen. While the user watches,
/// `commitOnboardingChoices` writes everything to SwiftData. Auto-advances
/// to the paywall when the rotation finishes.
struct PreparingStepView: View {
    let onFinished: () -> Void

    @State private var progress: Double = 0
    @State private var phaseIndex: Int = 0
    @State private var hasFired = false

    private let phases: [(String, String)] = [
        ("flame.fill",          String(localized: "Calculando suas calorias")),
        ("chart.pie.fill",      String(localized: "Ajustando macros")),
        ("cabinet.fill",        String(localized: "Preparando despensa")),
        ("book.closed.fill",    String(localized: "Salvando receitas")),
    ]
    private let totalDuration: Double = 3.6

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.18, green: 0.10, blue: 0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

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

                VStack(spacing: 8) {
                    Text(phases[phaseIndex].1)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(phaseIndex)

                    Text(String(localized: "Personalizando sua experiência…"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { start() }
    }

    private func start() {
        guard !hasFired else { return }
        hasFired = true

        // Step the phase label every (totalDuration / phases.count) seconds.
        let stepInterval = totalDuration / Double(phases.count)
        for i in 1..<phases.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(i)) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    phaseIndex = i
                }
            }
        }

        // Smooth progress sweep using a Timer.
        let frameInterval = 1.0 / 60.0
        var elapsed = 0.0
        Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            elapsed += frameInterval
            progress = min(1.0, elapsed / totalDuration)
            if elapsed >= totalDuration {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onFinished()
                }
            }
        }
    }
}
