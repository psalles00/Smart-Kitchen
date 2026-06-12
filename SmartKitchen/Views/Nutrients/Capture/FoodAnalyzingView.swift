import SwiftUI

/// Tela de loading enquanto a IA analisa texto, foto ou rótulo.
struct FoodAnalyzingView: View {
    var image: PlatformImage? = nil
    var message: String = String(localized: "Analisando sua refeição…")

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 22) {
                if let image {
                    ScanningImageView(image: image)
                        .frame(width: 270, height: 270)
                } else {
                    ZStack {
                        Circle()
                            .fill(PageTheme.nutrients.accentColor.opacity(0.10))
                            .frame(width: 118, height: 118)
                            .scaleEffect(pulse ? 1.06 : 0.94)

                        Circle()
                            .stroke(PageTheme.nutrients.accentColor.opacity(0.18), lineWidth: 1)
                            .frame(width: 92, height: 92)

                        Image(systemName: "sparkles")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(PageTheme.nutrients.gradient)
                            .scaleEffect(pulse ? 1.03 : 0.97)
                    }
                    .accessibilityHidden(true)
                }

                Text(message)
                    .font(.headline)
                    .foregroundStyle(PageTheme.nutrients.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(PageTheme.nutrients.accentColor.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: PageTheme.nutrients.accentColor.opacity(0.12), radius: 24, x: 0, y: 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Self.backgroundBase,
                    PageTheme.nutrients.accentColor.opacity(0.06),
                    Self.backgroundBase
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private static var backgroundBase: Color {
        #if os(iOS)
        Color(.systemBackground)
        #elseif os(macOS)
        Color(.windowBackgroundColor)
        #else
        Color(.clear)
        #endif
    }
}

// MARK: - Scanning effect

/// Mostra a imagem analisada com uma linha de "scanner" animada deslizando
/// verticalmente, similar a leitores de QR/Face ID. A imagem fica levemente
/// dessaturada fora da faixa de varredura para destacar o foco da IA.
private struct ScanningImageView: View {
    let image: PlatformImage

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerRadius: CGFloat = 20
    private let bandHeight: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let accent = PageTheme.nutrients.accentColor

            ZStack {
                // Base image
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                // Subtle dim overlay so the scanning band reads better
                Rectangle()
                    .fill(.black.opacity(0.18))

                // Scanning band — gradient that fades at the edges
                LinearGradient(
                    colors: [
                        accent.opacity(0),
                        accent.opacity(0.55),
                        Color.white.opacity(0.85),
                        accent.opacity(0.55),
                        accent.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bandHeight)
                .blur(radius: 6)
                .blendMode(.plusLighter)
                .offset(y: scanOffset(in: size))

                // Crisp scanning line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0),
                                accent,
                                Color.white,
                                accent,
                                accent.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .shadow(color: accent.opacity(0.8), radius: 4, y: 0)
                    .offset(y: scanOffset(in: size))

                // Corner brackets to evoke a scanner viewfinder
                ScannerCorners(color: accent.opacity(0.85))
                    .padding(10)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.25), radius: 12, y: 4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityLabel("Analisando imagem da refeição")
    }

    /// Maps `phase` (0…1) to a vertical offset that travels from the top to the
    /// bottom of the frame and back, recentred around the view's mid-Y so we can
    /// place the band/line via `.offset`.
    private func scanOffset(in size: CGSize) -> CGFloat {
        let travel = size.height - bandHeight / 2
        // phase 0 → -travel/2 (top), phase 1 → +travel/2 (bottom)
        return (phase - 0.5) * travel
    }
}

private struct ScannerCorners: View {
    var color: Color
    var length: CGFloat = 22
    var thickness: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Top-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: length))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: length, y: 0))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                // Top-right
                Path { p in
                    p.move(to: CGPoint(x: w - length, y: 0))
                    p.addLine(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: w, y: length))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                // Bottom-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - length))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: length, y: h))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                // Bottom-right
                Path { p in
                    p.move(to: CGPoint(x: w - length, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: w, y: h - length))
                }
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            }
        }
    }
}
