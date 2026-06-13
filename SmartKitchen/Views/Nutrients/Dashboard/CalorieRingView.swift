import Foundation
import SwiftUI

/// Display de calorias restantes do dia.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    var remaining: Int { max(goal - consumed, 0) }
    var rawRemaining: Int { goal - consumed }

    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedRemaining = 0

    private var titleColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.92, alpha: 1)
                : UIColor(red: 39 / 255, green: 39 / 255, blue: 39 / 255, alpha: 1)
        })
        #else
        return Color(red: 39 / 255, green: 39 / 255, blue: 39 / 255)
        #endif
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(consumed) / Double(goal), 1)
    }

    private var accentColor: Color {
        Color(red: 0.31, green: 0.74, blue: 0.46)
    }

    private var titleFont: Font {
        .custom("Bricolage Grotesque", size: 96, relativeTo: .largeTitle).weight(.bold)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(neutralSurfaceColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)
                }

            HStack {
                Spacer()

                calorieTrackerIcon
                    .frame(width: 132, height: 132)
                    .opacity(colorScheme == .dark ? 0.30 : 0.22)
                    .offset(x: 22, y: -22)
            }
            .allowsHitTesting(false)

            VStack(spacing: -10) {
                Text("\(displayedRemaining)")
                    .font(titleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .foregroundStyle(titleColor)

                remainingCaption
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 184)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            displayedRemaining = 0

            DispatchQueue.main.async {
                withAnimation(.snappy(duration: 0.25)) {
                    displayedRemaining = rawRemaining
                }
            }
        }
        .onChange(of: rawRemaining) { _, newValue in
            withAnimation(.snappy(duration: 0.25)) {
                displayedRemaining = newValue
            }
        }
    }

    private var calorieTrackerIcon: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10))

            Circle()
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.20 : 0.16), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image("nutrientes")
                .resizable()
                .scaledToFit()
                .padding(18)
        }
    }

    @ViewBuilder
    private var remainingCaption: some View {
        if displayedRemaining < 0 {
            Text("kcal extras consumidas")
        } else {
            let format = String(localized: "de **%lld kcal** restantes")
            let localizedText = String.localizedStringWithFormat(format, goal)
            if let attributed = try? AttributedString(
                markdown: localizedText,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
            } else {
                Text(localizedText)
            }
        }
    }
}

#Preview {
    CalorieRingView(consumed: 814, goal: 2100)
        .padding()
}
