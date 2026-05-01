import SwiftUI

/// Standard onboarding screen header — large bricolage title + soft subtitle.
struct OnboardingHeader: View {
    let title: String
    var subtitle: String? = nil
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(title)
                .font(.custom("Bricolage Grotesque", size: 32, relativeTo: .largeTitle).weight(.bold))
                .multilineTextAlignment(textAlignment)
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .padding(.horizontal, 24)
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}
