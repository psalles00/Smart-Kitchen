import SwiftUI

/// Display de calorias restantes do dia. Sem círculo: exibe apenas o número
/// grande na fonte de título (Bricolage Grotesque) e os subtítulos abaixo.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    var remaining: Int { max(goal - consumed, 0) }
    var rawRemaining: Int { goal - consumed }

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

    private var titleFont: Font {
        .custom("Bricolage Grotesque", size: 96, relativeTo: .largeTitle).weight(.bold)
    }

    var body: some View {
        VStack(spacing: -10) {
            Text("\(displayedRemaining)")
                .font(titleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .foregroundStyle(
                    RadialGradient(
                        colors: [
                            displayedRemaining < 0 
                                ? Color(red: 0.9, green: 0.3, blue: 0.3) 
                                : Color(red: 0.35, green: 0.85, blue: 0.45),
                            displayedRemaining < 0
                                ? Color(red: 0.15, green: 0.02, blue: 0.02)
                                : Color(red: 0.02, green: 0.12, blue: 0.06)
                        ],
                        center: UnitPoint(x: 0.5, y: -1.5),
                        startRadius: 0,
                        endRadius: 320
                    )
                )

            Text(displayedRemaining < 0 ? "kcal extras consumidas" : "de \(goal) kcal restantes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
}

#Preview {
    CalorieRingView(consumed: 814, goal: 2100)
        .padding()
}
