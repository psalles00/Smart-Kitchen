import SwiftUI

/// Phase 1 — Step 2. Visual story for "Crie e importe receitas das suas
/// redes sociais". An Instagram/TikTok-style URL chip flies into a
/// stylised recipe card via `matchedGeometryEffect`, looping every few
/// seconds.
struct RecipesIntroStepView: View {
    let onContinue: () -> Void

    @Namespace private var ns
    @State private var phase: Int = 0 // 0: link state, 1: morphed card

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            stage
                .frame(height: 280)
                .padding(.horizontal, 24)

            OnboardingHeader(
                title: String(localized: "Receitas direto das redes."),
                subtitle: String(localized: "Compartilhe um link do TikTok ou Instagram e o Savoria estrutura tudo pra você — ingredientes, passos e mídias.")
            )

            Spacer()

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) {
                phase = 1
            }
            try? await Task.sleep(for: .milliseconds(2200))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                phase = 0
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            // soft tinted backdrop card
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(neutralSurfaceColor)
                .shadow(color: .black.opacity(0.06), radius: 18, y: 10)

            if phase == 0 {
                LinkChip(ns: ns)
                    .transition(.opacity)
            } else {
                RecipeCardPreview(ns: ns)
                    .transition(.opacity)
            }
        }
    }
}

private struct LinkChip: View {
    let ns: Namespace.ID

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "link")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(0.85)

            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.pink, Color.orange, Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18, height: 18)
                    .matchedGeometryEffect(id: "ico", in: ns)

                Text("instagram.com/p/recipe…")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .matchedGeometryEffect(id: "title", in: ns)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .matchedGeometryEffect(id: "shape", in: ns)
            )
        }
    }
}

private struct RecipeCardPreview: View {
    let ns: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.pink, Color.orange, Color.purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .matchedGeometryEffect(id: "ico", in: ns)
                Text(String(localized: "Pasta ao molho rosé"))
                    .font(.cardTitle)
                    .matchedGeometryEffect(id: "title", in: ns)
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach([
                    String(localized: "25 min"),
                    String(localized: "4 porções"),
                    String(localized: "Fácil")
                ], id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach([
                    String(localized: "300 g de penne"),
                    String(localized: "200 ml de creme de leite"),
                    String(localized: "1 lata de tomate pelado"),
                ], id: \.self) { line in
                    HStack(spacing: 10) {
                        Circle().fill(Color.primary.opacity(0.4)).frame(width: 5, height: 5)
                        Text(line)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .matchedGeometryEffect(id: "shape", in: ns)
        )
        .padding(.horizontal, 16)
    }
}
