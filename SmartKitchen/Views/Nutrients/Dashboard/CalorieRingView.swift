import SwiftUI

/// Display de calorias restantes do dia. Sem círculo: exibe apenas o número
/// grande na fonte de título (Bricolage Grotesque) e os subtítulos abaixo.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    var remaining: Int { max(goal - consumed, 0) }

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
                .foregroundStyle(titleColor)

            Text("de \(goal) kcal restantes")
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
                    displayedRemaining = remaining
                }
            }
        }
        .onChange(of: remaining) { _, newValue in
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
