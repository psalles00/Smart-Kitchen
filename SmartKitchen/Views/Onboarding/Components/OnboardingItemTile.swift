import SwiftUI

/// A single picker tile used by the pantry/grocery selection screens.
/// Tap toggles selection with a spring + selection haptic.
struct OnboardingItemTile: View {
    let title: String
    let iconFileName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(neutralSurfaceColor)

                    if let img = IconResolver.image(forFilename: iconFileName) {
                        Image(platformImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(14)
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 2.5)

                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.primary))
                                    .padding(8)
                            }
                            Spacer()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

