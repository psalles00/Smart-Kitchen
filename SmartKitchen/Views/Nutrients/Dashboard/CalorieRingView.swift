import Foundation
import SwiftUI

/// Display de calorias restantes do dia.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedCalorieGoal = 0

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

    private var calorieProgressRingColor: Color {
        Color.secondary
    }

    private var titleFont: Font {
        .custom("Bricolage Grotesque", size: 82, relativeTo: .largeTitle).weight(.bold)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NutrientGlassCardSurface(
                cornerRadius: 26,
                accentColor: Color.primary.opacity(colorScheme == .dark ? 0.58 : 0.40),
                isColored: false
            )
            .padding(.top, 34)

            VStack(spacing: -8) {
                Spacer(minLength: 74)

                Text("\(displayedCalorieGoal)")
                    .font(titleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .foregroundStyle(titleColor)

                remainingCaption
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 28)
            }
            .padding(.horizontal, 18)

            calorieTrackerIcon
                .frame(width: 58, height: 58)
                .offset(y: 10)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 206)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear {
            displayedCalorieGoal = 0

            DispatchQueue.main.async {
                withAnimation(.snappy(duration: 0.25)) {
                    displayedCalorieGoal = goal
                }
            }
        }
        .onChange(of: goal) { _, newValue in
            withAnimation(.snappy(duration: 0.25)) {
                displayedCalorieGoal = newValue
            }
        }
    }

    private var calorieTrackerIcon: some View {
        ZStack {
            NutrientIconProgressRing(
                progress: progress,
                tint: calorieProgressRingColor,
                lineWidth: 3.6
            )
            .frame(width: 79, height: 79)

            Image("nutrientes")
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
        }
        .frame(width: 58, height: 58)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 6, x: 0, y: 5)
    }

    @ViewBuilder
    private var remainingCaption: some View {
        let format = String(localized: "de **%lld kcal** restantes")
        let localizedText = String.localizedStringWithFormat(format, displayedCalorieGoal)
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

#Preview {
    CalorieRingView(consumed: 814, goal: 2100)
        .padding()
}
