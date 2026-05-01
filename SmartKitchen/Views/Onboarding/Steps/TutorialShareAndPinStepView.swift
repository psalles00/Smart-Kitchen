import SwiftUI

/// Phase 3 — Step 10. Two informational cards:
/// 1. Share recipes from social apps via the Share sheet → app icon.
/// 2. Suggest pinning the app to the home screen.
/// Both are illustrative — the continue button is always enabled.
struct TutorialShareAndPinStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                title: String(localized: "Receitas direto das redes."),
                subtitle: String(localized: "Compartilhe links do Instagram, TikTok e YouTube — a IA monta a receita pra você.")
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ShareIllustrationCard()
                    PinAppCard()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            OnboardingPrimaryButton(
                title: String(localized: "Continuar"),
                isEnabled: true,
                action: onContinue
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Share illustration

private struct ShareIllustrationCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "Toque em Compartilhar"), systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                socialMockup
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
                appIconMockup
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var socialMockup: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.95, green: 0.45, blue: 0.30),
                        Color(red: 0.78, green: 0.20, blue: 0.55),
                        Color(red: 0.45, green: 0.15, blue: 0.65),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 90, height: 110)

            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .scaleEffect(pulse ? 1.18 : 1.0)
        }
    }

    private var appIconMockup: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.18, green: 0.18, blue: 0.22),
                        Color(red: 0.06, green: 0.06, blue: 0.08),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image("AppLogoB")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }
            .frame(width: 72, height: 72)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            Text("Savoria")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Pin to home screen

private struct PinAppCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "Acesso rápido"), systemImage: "pin.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(String(localized: "Adicione o Savoria à sua tela inicial para acessar receitas, despensa e lista de compras com um toque."))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HomeScreenMockup()
                .frame(height: 130)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(neutralSurfaceColor)
        )
    }
}

private struct HomeScreenMockup: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [
                    Color(red: 0.30, green: 0.55, blue: 0.85),
                    Color(red: 0.15, green: 0.30, blue: 0.55),
                ], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 14) {
                ForEach(0..<4) { index in
                    if index == 1 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [
                                    Color(red: 0.18, green: 0.18, blue: 0.22),
                                    Color(red: 0.06, green: 0.06, blue: 0.08),
                                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image("AppLogoB")
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        }
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 2)
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 56, height: 56)
                    }
                }
            }
        }
    }
}
