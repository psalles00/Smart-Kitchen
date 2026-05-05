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

// MARK: - Feature chip

/// Pequeno chip exibido acima do título nas páginas de apresentação para
/// dar contexto sobre qual área do app está sendo apresentada (ex.: "Diário
/// de calorias", "Receitas", "Despensa & Mercado"). Mantém o usuário
/// orientado quando as páginas mudam de função.
struct OnboardingFeatureChip: View {
    let icon: String
    let title: String
    let tint: Color

    init(icon: String, title: String, tint: Color = .accentColor) {
        self.icon = icon
        self.title = title
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        )
    }
}
