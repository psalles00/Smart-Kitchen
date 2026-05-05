import SwiftUI

/// Phase 1 — Step 8 (final intro). Mostra um chat com o Nutrition Coach:
/// usuário escreve, IA responde com sugestões. Em seguida, chips de
/// exemplo se alternam para mostrar a variedade de uso.
struct NutritionCoachStepView: View {
    let onContinue: () -> Void

    @State private var messages: [ChatMessageMock] = []
    @State private var typingFromUser: Bool = false
    @State private var typedUserText: String = ""
    @State private var coachIsTyping: Bool = false
    @State private var revealedChips: Int = 0
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var entranceTask: Task<Void, Never>? = nil
    @State private var loopTask: Task<Void, Never>? = nil

    private let userPrompt = String(localized: "Tô comendo muito pão")

    private let chips: [String] = [
        String(localized: "Como bater minha meta de proteína?"),
        String(localized: "Substituições saudáveis para arroz branco"),
        String(localized: "Cardápio fit pra essa semana"),
        String(localized: "O que cozinhar com a despensa de hoje?"),
    ]

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
                    icon: "sparkles",
                    title: String(localized: "Coach de IA"),
                    tint: Color(red: 0.55, green: 0.50, blue: 0.96)
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Tenha sempre um Nutrition Coach com você"),
                    subtitle: String(localized: "IA que entende sua rotina e sugere ajustes inteligentes.")
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

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(neutralSurfaceColor)
                .shadow(color: .black.opacity(0.05), radius: 16, y: 8)

            VStack(spacing: 10) {
                coachHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }

                        if coachIsTyping {
                            HStack {
                                TypingBubble()
                                Spacer()
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                if typingFromUser || !typedUserText.isEmpty {
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            if typedUserText.isEmpty {
                                Text(String(localized: "Pergunte ao Coach…"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary.opacity(0.55))
                            }
                            Text(typedUserText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(typedUserText.isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.07))
                    )
                    .padding(.horizontal, 14)
                }

                chipRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    private var coachHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.55, green: 0.50, blue: 0.96), Color(red: 0.86, green: 0.40, blue: 0.86)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Nutrition Coach"))
                    .font(.system(size: 13, weight: .bold))
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(String(localized: "Online"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                    if index < revealedChips {
                        Text(chip)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
        }
        .frame(height: 32)
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false; showHeader = false; showButton = false
        messages = []
        typingFromUser = false
        typedUserText = ""
        coachIsTyping = false
        revealedChips = 0

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
            // Reset
            withAnimation(.easeOut(duration: 0.25)) {
                messages = []
                revealedChips = 0
            }
            typedUserText = ""
            typingFromUser = false
            coachIsTyping = false
            await wait(400)

            // User starts typing
            withAnimation(.easeOut(duration: 0.25)) { typingFromUser = true }
            HapticManager.impact(style: .light)
            for char in userPrompt {
                if Task.isCancelled { return }
                typedUserText.append(char)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            await wait(420)

            // User sends
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                messages.append(ChatMessageMock(id: UUID().uuidString, isUser: true, text: typedUserText))
                typedUserText = ""
                typingFromUser = false
            }

            await wait(500)

            // Coach typing
            withAnimation(.easeOut(duration: 0.25)) { coachIsTyping = true }
            await wait(900)

            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                coachIsTyping = false
                messages.append(ChatMessageMock(
                    id: UUID().uuidString,
                    isUser: false,
                    text: String(localized: "Que tal alternar com aveia ou tapioca no café? Mantém a saciedade e diversifica os carboidratos.")
                ))
            }

            // Reveal example chips
            await wait(550)
            for index in 0..<chips.count {
                if Task.isCancelled { return }
                if index % 2 == 0 { HapticManager.impact(style: .light) }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    revealedChips = index + 1
                }
                await wait(180)
            }

            await wait(2400)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Models & Subviews

private struct ChatMessageMock: Identifiable {
    let id: String
    let isUser: Bool
    let text: String
}

private struct ChatBubble: View {
    let message: ChatMessageMock

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 12, weight: message.isUser ? .semibold : .medium))
                .foregroundStyle(message.isUser ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    bubbleShape
                        .fill(
                            message.isUser
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(Color.primary.opacity(0.06))
                        )
                )
                .frame(maxWidth: 220, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 14,
                bottomLeading: message.isUser ? 14 : 4,
                bottomTrailing: message.isUser ? 4 : 14,
                topTrailing: 14
            ),
            style: .continuous
        )
    }
}

private struct TypingBubble: View {
    @State private var dot1 = false
    @State private var dot2 = false
    @State private var dot3 = false

    var body: some View {
        HStack(spacing: 4) {
            dot(active: dot1)
            dot(active: dot2)
            dot(active: dot3)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 14, bottomLeading: 4, bottomTrailing: 14, topTrailing: 14),
                style: .continuous
            ).fill(Color.primary.opacity(0.06))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { dot1.toggle() }
            withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(0.15)) { dot2.toggle() }
            withAnimation(.easeInOut(duration: 0.5).repeatForever().delay(0.3)) { dot3.toggle() }
        }
    }

    private func dot(active: Bool) -> some View {
        Circle()
            .fill(Color.primary.opacity(active ? 0.7 : 0.25))
            .frame(width: 5, height: 5)
    }
}
