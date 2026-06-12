import SwiftUI

/// Full-width primary CTA used throughout the onboarding flow. Mirrors the
/// pill-shaped button used in the system reference screenshots.
struct OnboardingPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(backgroundColor)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
        .sensoryFeedback(.impact(weight: .medium), trigger: isEnabled)
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.secondary.opacity(0.35)
        }

        return colorScheme == .dark ? Color.white : Color.primary
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return colorScheme == .dark
                ? Color.white.opacity(0.45)
                : Color.white.opacity(0.7)
        }

        return colorScheme == .dark ? Color.black : Color.white
    }
}

/// Subtle text-only secondary action (e.g. "Skip", "Continue with free plan").
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
