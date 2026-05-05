import SwiftUI

/// Phase 1 — Step 3. Mostra a busca inteligente: usuário digita um pedido
/// rápido (ex.: "Lanche fit, sem glúten") e o app responde com sugestões
/// compatíveis. Em seguida, abre uma das opções com ingredientes/passos.
struct RecipeIdeasStepView: View {
    let onContinue: () -> Void

    @State private var typedQuery: String = ""
    @State private var revealedSuggestions: Int = 0
    @State private var openedRecipe: Bool = false
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var loopTask: Task<Void, Never>? = nil
    @State private var entranceTask: Task<Void, Never>? = nil

    private let queryText = String(localized: "Lanche fit, sem glúten")

    private let suggestions: [RecipeSuggestionMock] = [
        .init(id: "wrap",      title: String(localized: "Wrap de frango com homus"),       minutes: 15, badge: String(localized: "Compatível com sua despensa"), badgeIsMatch: true,  iconColor: Color(red: 0.96, green: 0.55, blue: 0.40)),
        .init(id: "smoothie",  title: String(localized: "Smoothie de morango e aveia"),    minutes: 5,  badge: String(localized: "Sem glúten"), badgeIsMatch: false, iconColor: Color(red: 0.86, green: 0.40, blue: 0.86)),
        .init(id: "tuna-bowl", title: String(localized: "Bowl de atum com quinoa"),        minutes: 12, badge: String(localized: "Alta proteína"), badgeIsMatch: false, iconColor: Color(red: 0.55, green: 0.50, blue: 0.96)),
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
                    icon: "sparkle.magnifyingglass",
                    title: String(localized: "Ideias de receitas"),
                    tint: Color(red: 0.96, green: 0.55, blue: 0.40)
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Chega de travar na hora de cozinhar"),
                    subtitle: String(localized: "Receba ideias compatíveis com o que tem na despensa.")
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
        .onAppear {
            beginEntrance()
        }
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

            VStack(spacing: 14) {
                searchBar
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                if openedRecipe {
                    RecipeDetailMock(suggestion: suggestions[0])
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    suggestionsList
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                if typedQuery.isEmpty {
                    Text(String(localized: "Descreva o que está com vontade…"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                Text(typedQuery)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Spacer()
            // blinking cursor
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                Rectangle()
                    .fill(Color.accentColor.opacity(on ? 0.8 : 0.0))
                    .frame(width: 2, height: 14)
            }
            .opacity(openedRecipe ? 0 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous).fill(Color.primary.opacity(0.06))
        )
    }

    private var suggestionsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index < revealedSuggestions {
                    SuggestionRow(suggestion: suggestion, isHighlighted: index == 0 && revealedSuggestions >= suggestions.count)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false
        showHeader = false
        showButton = false
        typedQuery = ""
        revealedSuggestions = 0
        openedRecipe = false

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) { showHero = true }
            await wait(150)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { showHeader = true }
            await wait(150)
            withAnimation(.spring(response: 0.74, dampingFraction: 0.86)) { showButton = true }
            await wait(200)
            await runLoop()
        }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            // Reset
            typedQuery = ""
            withAnimation(.easeOut(duration: 0.25)) {
                revealedSuggestions = 0
                openedRecipe = false
            }
            await wait(400)

            // Type the query
            HapticManager.impact(style: .light)
            for char in queryText {
                if Task.isCancelled { return }
                typedQuery.append(char)
                try? await Task.sleep(nanoseconds: 38_000_000)
            }

            await wait(360)

            // Reveal suggestions
            for index in 0..<suggestions.count {
                if Task.isCancelled { return }
                HapticManager.impact(style: .light)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    revealedSuggestions = index + 1
                }
                await wait(220)
            }

            await wait(750)

            // Open the first one
            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) {
                openedRecipe = true
            }

            await wait(2400)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Models

private struct RecipeSuggestionMock: Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let badge: String
    let badgeIsMatch: Bool
    let iconColor: Color
}

// MARK: - Subviews

private struct SuggestionRow: View {
    let suggestion: RecipeSuggestionMock
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: [suggestion.iconColor.opacity(0.95), suggestion.iconColor.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(suggestion.minutes) min")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)

                    Text("•").foregroundStyle(.secondary).font(.system(size: 11))

                    Text(suggestion.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                suggestion.badgeIsMatch
                                    ? Color.green.opacity(0.18)
                                    : Color.primary.opacity(0.07)
                            )
                        )
                        .foregroundStyle(
                            suggestion.badgeIsMatch ? Color.green : Color.secondary
                        )
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHighlighted ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.green.opacity(0.55) : Color.clear,
                    lineWidth: 1.2
                )
        )
    }
}

private struct RecipeDetailMock: View {
    let suggestion: RecipeSuggestionMock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [suggestion.iconColor.opacity(0.95), suggestion.iconColor.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 40, height: 40)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 14, weight: .bold))
                    Text("\(suggestion.minutes) min · " + String(localized: "2 porções"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Ingredientes"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach([
                    String(localized: "1 wrap sem glúten"),
                    String(localized: "120 g de frango grelhado"),
                    String(localized: "2 colheres de homus")
                ], id: \.self) { line in
                    HStack(spacing: 8) {
                        Circle().fill(Color.primary.opacity(0.4)).frame(width: 4, height: 4)
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Passos"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach(Array([
                    String(localized: "Aqueça o wrap rapidamente."),
                    String(localized: "Espalhe o homus e monte com o frango."),
                ].enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.primary.opacity(0.85)))
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 14)
    }
}
