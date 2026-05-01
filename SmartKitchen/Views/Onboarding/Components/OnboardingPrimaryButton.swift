import SwiftUI

/// Full-width primary CTA used throughout the onboarding flow. Mirrors the
/// pill-shaped button used in the system reference screenshots.
struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
        .sensoryFeedback(.impact(weight: .medium), trigger: isEnabled)
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
