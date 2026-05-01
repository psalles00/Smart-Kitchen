import SwiftUI

/// Top-of-screen progress bar that maps to the current `OnboardingSection`.
/// Mirrors the reference: a back chevron on the left and a slim animated bar
/// fading out toward the right edge.
struct OnboardingProgressBar: View {
    let progress: Double // 0...1
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.55)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 6)

                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(Color.primary)
                        .frame(width: max(8, proxy.size.width * progress), height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: progress)
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
