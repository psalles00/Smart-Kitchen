import SwiftUI

/// Phase 1 — Step 4. Mostra um iPhone mock com Instagram → Share Sheet →
/// Savoria, depois uma esteira de processamento "Analisando · Extraindo ·
/// Organizando · Pronto" e finaliza com a receita estruturada.
struct SaveRecipesStepView: View {
    let onContinue: () -> Void
    private let phoneShellCornerRadius: CGFloat = 32
    private let phoneScreenCornerRadius: CGFloat = 27
    private let phoneScreenInset: CGFloat = 4

    enum Stage: Int, CaseIterable {
        case feed
        case shareSheet
        case processing
        case done
    }

    @State private var stage: Stage = .feed
    @State private var processingStepIndex: Int = 0
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var entranceTask: Task<Void, Never>? = nil
    @State private var loopTask: Task<Void, Never>? = nil

    private let processingSteps: [String] = [
        String(localized: "Analisando"),
        String(localized: "Extraindo ingredientes"),
        String(localized: "Organizando passos"),
        String(localized: "Pronto"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            phoneStage
                .frame(height: 360)
                .opacity(showHero ? 1 : 0)
                .scaleEffect(showHero ? 1 : 0.94)
                .animation(.spring(response: 0.85, dampingFraction: 0.84), value: showHero)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    OnboardingFeatureChip(
                        icon: "square.and.arrow.down.fill",
                        title: String(localized: "Importar receitas"),
                        tint: Color(red: 0.86, green: 0.40, blue: 0.86)
                    )
                    .opacity(showHeader ? 1 : 0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                    OnboardingHeader(
                        title: String(localized: "Salve qualquer receita em segundos"),
                        subtitle: String(localized: "Compartilhe um link de Instagram, TikTok ou site — pronto.")
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

    private var phoneStage: some View {
        ZStack {
            phoneFrame
                .frame(width: 200, height: 340)

            VStack {
                Spacer()
                if stage == .shareSheet {
                    shareSheetView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .frame(width: 200, height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: phoneShellCornerRadius, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

            RoundedRectangle(cornerRadius: phoneScreenCornerRadius, style: .continuous)
                .fill(Color.white)
                .padding(phoneScreenInset)

            screenContent
                .mask(
                    RoundedRectangle(cornerRadius: phoneScreenCornerRadius, style: .continuous)
                        .padding(phoneScreenInset)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: phoneShellCornerRadius, style: .continuous))
        .aspectRatio(9.0/19.5, contentMode: .fit)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch stage {
        case .feed, .shareSheet:
            reelsPost
        case .processing:
            processingView
        case .done:
            recipeDoneView
        }
    }

    /// Vertical short-video (Reels/TikTok) mock that fills the entire phone
    /// screen — no header bar, overlay UI is anchored to the bottom-left and
    /// right edges like a real short.
    private var reelsPost: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.10, blue: 0.22),
                        Color(red: 0.55, green: 0.20, blue: 0.45),
                        Color(red: 0.96, green: 0.55, blue: 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                CookingShortVideoPreview()
                    .frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.46)
                    .offset(y: -proxy.size.height * 0.04)

                VStack(spacing: 14) {
                    Spacer()
                    reelsAction(icon: "heart.fill", label: "12k", highlighted: false)
                    reelsAction(icon: "bubble.right.fill", label: "284", highlighted: false)
                    ZStack {
                        reelsAction(icon: "arrowshape.turn.up.right.fill", label: String(localized: "Compartilhar"), highlighted: stage == .shareSheet)
                        if stage == .shareSheet {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .frame(width: 38, height: 38)
                                .offset(y: -8)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: stage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 10)
                .padding(.bottom, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(LinearGradient(
                            colors: [.pink, .orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing
                        )).frame(width: 22, height: 22)
                        Text("chef.savoria")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    Text("\u{1F525} " + String(localized: "Massa cremosa em 15 minutos…"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 8, weight: .bold))
                        Text(String(localized: "Som original · chef.savoria"))
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 10)
                .padding(.bottom, 16)
                .padding(.trailing, 72)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reelsAction(icon: String, label: String, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .scaleEffect(highlighted ? 1.2 : 1.0)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
    }

    private struct CookingShortVideoPreview: View {
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let simmer = CGFloat((sin(time * 0.80) + 1) / 2)
                let toss = CGFloat((sin(time * 0.62 + 1.4) + 1) / 2)

                ZStack {
                    skilletShadow
                    steamLayer(time: time)
                    fallingIngredients(toss: toss)
                    skillet(simmer: simmer)
                    panHandle
                }
            }
        }

        private var skilletShadow: some View {
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 120, height: 20)
                .offset(y: 62)
        }

        @ViewBuilder
        private func steamLayer(time: TimeInterval) -> some View {
            ForEach(0..<3, id: \.self) { index in
                steamPlume(index: index, time: time)
            }
        }

        private func steamPlume(index: Int, time: TimeInterval) -> some View {
            let delayed = CGFloat((sin(time * 0.72 - Double(index) * 0.58) + 1) / 2)
            return Capsule()
                .fill(.white.opacity(0.32 - Double(index) * 0.05))
                .frame(width: 6, height: 28)
                .scaleEffect(x: 1 - delayed * 0.35, y: 1)
                .offset(
                    x: CGFloat(index - 1) * 16 + delayed * 6 - 3,
                    y: -18 - delayed * 38
                )
                .opacity(1 - delayed)
                .blur(radius: 0.5)
        }

        @ViewBuilder
        private func fallingIngredients(toss: CGFloat) -> some View {
            Circle()
                .fill(Color(red: 1.00, green: 0.47, blue: 0.33))
                .frame(width: 10, height: 10)
                .offset(x: -26 + toss * 40, y: -34 + toss * 24)

            Ellipse()
                .fill(Color(red: 0.48, green: 0.79, blue: 0.44))
                .frame(width: 15, height: 8)
                .rotationEffect(.degrees(Double(-24 + toss * 82)))
                .offset(x: 18 - toss * 10, y: -38 + toss * 24)
        }

        private func skillet(simmer: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.18),
                            Color(red: 0.28, green: 0.28, blue: 0.34)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 116, height: 46)
                .overlay {
                    skilletContents(simmer: simmer)
                        .padding(.horizontal, 12)
                }
        }

        private func skilletContents(simmer: CGFloat) -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.76, blue: 0.29))
                    .frame(width: 82, height: 18)
                    .rotationEffect(.degrees(Double(-7 + simmer * 14)))
                    .offset(x: -4, y: -1)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.99, green: 0.84, blue: 0.44))
                    .frame(width: 78, height: 14)
                    .rotationEffect(.degrees(Double(11 - simmer * 16)))
                    .offset(x: 5, y: 4)

                Circle()
                    .fill(.white.opacity(0.26))
                    .frame(width: 14, height: 14)
                    .offset(x: 24, y: -6 + simmer * 5)
            }
        }

        private var panHandle: some View {
            Capsule()
                .fill(Color.white.opacity(0.78))
                .frame(width: 40, height: 10)
                .rotationEffect(.degrees(18))
                .offset(x: 56, y: 14)
        }
    }

    private var shareSheetView: some View {
        VStack(spacing: 8) {
            Capsule().fill(Color.gray.opacity(0.4)).frame(width: 32, height: 4).padding(.top, 6)
            Text(String(localized: "Compartilhar"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                shareIcon(label: "Mensagens", system: "message.fill", color: .green, highlighted: false)
                shareIcon(label: "Mail", system: "envelope.fill", color: .blue, highlighted: false)
                savoriaShareIcon
                shareIcon(label: "Notas", system: "note.text", color: .yellow, highlighted: false)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 14, bottomLeading: 0, bottomTrailing: 0, topTrailing: 14), style: .continuous)
                .fill(Color(.systemBackground))
        )
        .padding(.horizontal, 6)
    }

    private func shareIcon(label: String, system: String, color: Color, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.85))
                Image(systemName: system)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var savoriaShareIcon: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.99, green: 0.55, blue: 0.65), Color(red: 0.78, green: 0.55, blue: 1.00)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image("AppLogoB")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
            .frame(width: 32, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            )
            .scaleEffect(1.1)
            .shadow(color: Color.accentColor.opacity(0.5), radius: 6)
            Text("Savoria")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private var processingView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 4)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: CGFloat(processingStepIndex + 1) / CGFloat(processingSteps.count))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: processingStepIndex)
                Image("AppLogoB")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(processingSteps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 6) {
                        Group {
                            if index < processingStepIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if index == processingStepIndex {
                                Image(systemName: "circle.dotted")
                                    .foregroundStyle(Color.accentColor)
                                    .symbolEffect(.pulse)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary.opacity(0.4))
                            }
                        }
                        .font(.system(size: 11))
                        Text(step)
                            .font(.system(size: 10, weight: index == processingStepIndex ? .semibold : .medium))
                            .foregroundStyle(index <= processingStepIndex ? .primary : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        }
        .padding(.top, 24)
    }

    private var recipeDoneView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.55, blue: 0.40), Color(red: 0.86, green: 0.40, blue: 0.86)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(localized: "Salva"))
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                        .padding(6)
                    }
                    Spacer()
                }
            }
            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(String(localized: "Massa cremosa em 15 min"))
                .font(.system(size: 11, weight: .bold))

            HStack(spacing: 4) {
                miniTag(icon: "clock", text: "15 min")
                miniTag(icon: "person.2", text: String(localized: "2 porções"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Ingredientes"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach(["• " + String(localized: "200 g de massa"),
                         "• " + String(localized: "1 col. creme"),
                         "• " + String(localized: "Parmesão a gosto")], id: \.self) { line in
                    Text(line)
                        .font(.system(size: 9))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
    }

    private func miniTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            Text(text).font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false; showHeader = false; showButton = false
        stage = .feed; processingStepIndex = 0

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
            withAnimation(.easeOut(duration: 0.3)) { stage = .feed }
            await wait(1300)

            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { stage = .shareSheet }
            await wait(1450)

            HapticManager.impact(style: .medium)
            withAnimation(.easeInOut(duration: 0.45)) {
                stage = .processing
                processingStepIndex = 0
            }
            await wait(520)

            for index in 0..<processingSteps.count {
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    processingStepIndex = index
                }
                if index < processingSteps.count - 1 {
                    HapticManager.impact(style: .light)
                }
                await wait(680)
            }

            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.65, dampingFraction: 0.84)) { stage = .done }
            await wait(2100)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
