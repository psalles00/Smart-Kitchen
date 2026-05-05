import SwiftUI

/// Phase 1 — Step 6. Mostra os 3 caminhos para registrar comida (foto, texto,
/// voz). Cada caminho é animado em sequência; ao final, os três aparecem
/// lado a lado para reforçar a flexibilidade.
struct MultimodalLoggingStepView: View {
    let onContinue: () -> Void

    enum Mode: Int, CaseIterable {
        case photo, text, voice
    }

    @State private var activeMode: Mode = .photo
    @State private var showAll: Bool = false
    @State private var typedText: String = ""
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var entranceTask: Task<Void, Never>? = nil
    @State private var loopTask: Task<Void, Never>? = nil

    private let textPrompt = String(localized: "2 fatias de pizza")

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            stage
                .padding(.horizontal, 18)
                .frame(height: 360)
                .opacity(showHero ? 1 : 0)
                .scaleEffect(showHero ? 1 : 0.94)
                .animation(.spring(response: 0.85, dampingFraction: 0.84), value: showHero)

            VStack(spacing: 0) {
            VStack(spacing: 12) {
                OnboardingFeatureChip(
                    icon: "square.and.pencil",
                    title: String(localized: "Registro de refeições"),
                    tint: Color(red: 0.42, green: 0.78, blue: 0.55)
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Registre do jeito mais fácil pra você"),
                    subtitle: String(localized: "Foto, voz, texto ou rótulo — a IA cuida do resto.")
                )
                .opacity(showHeader ? 1 : 0)
                .offset(y: showHeader ? 0 : 14)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)
            }

                Spacer(minLength: 14)

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
        .onAppear { beginEntrance() }
        .onDisappear {
            entranceTask?.cancel(); entranceTask = nil
            loopTask?.cancel(); loopTask = nil
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(neutralSurfaceColor)
                .shadow(color: .black.opacity(0.05), radius: 16, y: 8)

            if showAll {
                allModesGrid
                    .padding(18)
                    .transition(.opacity)
            } else {
                singleModeView
                    .padding(18)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var singleModeView: some View {
        switch activeMode {
        case .photo: photoMode
        case .text:  textMode
        case .voice: voiceMode
        }
    }

    private var allModesGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                miniCard(icon: "camera.fill", title: String(localized: "Foto"), tint: Color(red: 0.96, green: 0.55, blue: 0.40))
                miniCard(icon: "text.cursor", title: String(localized: "Texto"), tint: Color(red: 0.42, green: 0.78, blue: 0.55))
                miniCard(icon: "mic.fill", title: String(localized: "Voz"), tint: Color(red: 0.55, green: 0.50, blue: 0.96))
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text(String(localized: "A IA reconhece, calcula e organiza"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.50, blue: 0.96), Color(red: 0.86, green: 0.40, blue: 0.86)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                detectedRow(name: String(localized: "Pizza · 2 fatias"), kcal: 540)
                detectedRow(name: String(localized: "Salada verde"), kcal: 80)
                detectedRow(name: String(localized: "Suco natural"), kcal: 110)
            }
        }
    }

    private func miniCard(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 64)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detectedRow(name: String, kcal: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(kcal) kcal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Photo

    private var photoMode: some View {
        VStack(spacing: 12) {
            modeHeader(icon: "camera.fill", title: String(localized: "Foto"), tint: Color(red: 0.96, green: 0.55, blue: 0.40))

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.55, blue: 0.40), Color(red: 0.99, green: 0.75, blue: 0.50)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // mock plate
                Circle().fill(Color.white.opacity(0.95)).frame(width: 130, height: 130)
                Circle().fill(Color(red: 0.93, green: 0.55, blue: 0.30)).frame(width: 96, height: 96)
                Image(systemName: "fork.knife")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                // scan line
                ScanLine()
                    .frame(height: 180)
                    .padding(.horizontal, 12)

                // corner brackets
                cornerBrackets
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                Text(String(localized: "Reconhecido: prato com proteína e carboidrato"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private var cornerBrackets: some View {
        VStack {
            HStack {
                Bracket(corner: .topLeading)
                Spacer()
                Bracket(corner: .topTrailing)
            }
            Spacer()
            HStack {
                Bracket(corner: .bottomLeading)
                Spacer()
                Bracket(corner: .bottomTrailing)
            }
        }
        .padding(20)
    }

    // MARK: - Text

    private var textMode: some View {
        VStack(spacing: 12) {
            modeHeader(icon: "text.cursor", title: String(localized: "Texto"), tint: Color(red: 0.42, green: 0.78, blue: 0.55))

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "O que você comeu?"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text(typedText)
                        .font(.system(size: 18, weight: .bold))
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                        Rectangle()
                            .fill(Color.accentColor.opacity(on ? 0.85 : 0))
                            .frame(width: 2, height: 18)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05))
            )

            if typedText.count >= textPrompt.count {
                detectedRow(name: String(localized: "Pizza · 2 fatias"), kcal: 540)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Voice

    private var voiceMode: some View {
        VStack(spacing: 12) {
            modeHeader(icon: "mic.fill", title: String(localized: "Voz"), tint: Color(red: 0.55, green: 0.50, blue: 0.96))

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.55, green: 0.50, blue: 0.96), Color(red: 0.86, green: 0.40, blue: 0.86)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(red: 0.55, green: 0.50, blue: 0.96).opacity(0.4), radius: 14, y: 6)

                PulsingRings()

                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 130)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .symbolEffect(.variableColor)
                    Text(String(localized: "Transcrevendo…"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Text("\u{201C}" + String(localized: "Almoço: arroz, feijão, frango grelhado") + "\u{201D}")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05))
            )
        }
    }

    private func modeHeader(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Spacer()
            HStack(spacing: 4) {
                ForEach(Mode.allCases, id: \.rawValue) { mode in
                    Circle()
                        .fill(mode == activeMode && !showAll ? Color.primary : Color.primary.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false; showHeader = false; showButton = false
        showAll = false; activeMode = .photo; typedText = ""

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) { showHero = true }
            await wait(150)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { showHeader = true }
            await wait(150)
            withAnimation(.spring(response: 0.74, dampingFraction: 0.86)) { showButton = true }
            await wait(220)
            await runLoop()
        }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            // Photo
            withAnimation(.easeInOut(duration: 0.35)) {
                showAll = false
                activeMode = .photo
            }
            HapticManager.impact(style: .light)
            await wait(2200)

            // Text
            withAnimation(.easeInOut(duration: 0.35)) { activeMode = .text }
            HapticManager.impact(style: .light)
            typedText = ""
            await wait(420)
            for char in textPrompt {
                if Task.isCancelled { return }
                typedText.append(char)
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            await wait(900)

            // Voice
            withAnimation(.easeInOut(duration: 0.35)) { activeMode = .voice }
            HapticManager.impact(style: .medium)
            await wait(2200)

            // All together
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) {
                showAll = true
            }
            HapticManager.impact(style: .light)
            await wait(2400)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Helpers

private struct ScanLine: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.85), Color.white.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(height: 14)
                .offset(y: (proxy.size.height - 14) * (offset + 1) / 2)
                .blur(radius: 2)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        offset = 1
                    }
                }
        }
    }
}

private struct Bracket: View {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    let corner: Corner

    var body: some View {
        Path { path in
            let len: CGFloat = 16
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: 0, y: len))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: len, y: 0))
            case .topTrailing:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: len, y: 0))
                path.addLine(to: CGPoint(x: len, y: len))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: len))
                path.addLine(to: CGPoint(x: len, y: len))
            case .bottomTrailing:
                path.move(to: CGPoint(x: 0, y: len))
                path.addLine(to: CGPoint(x: len, y: len))
                path.addLine(to: CGPoint(x: len, y: 0))
            }
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 16, height: 16)
    }
}

private struct PulsingRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .scaleEffect(animate ? 1.6 + CGFloat(i) * 0.1 : 1.0)
                    .opacity(animate ? 0 : 0.6)
                    .frame(width: 100, height: 100)
                    .animation(
                        .easeOut(duration: 1.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.4),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
