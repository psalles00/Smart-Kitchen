import SwiftUI

/// Display de calorias restantes do dia. Sem círculo: exibe apenas o número
/// grande na fonte de título (Bricolage Grotesque) e os subtítulos abaixo.
struct CalorieRingView: View {
    let consumed: Int
    let goal: Int

    var remaining: Int { max(goal - consumed, 0) }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(remaining)")
                .font(.custom("Bricolage Grotesque", size: 96, relativeTo: .largeTitle).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())

            Text("Kcal restantes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview {
    CalorieRingView(consumed: 814, goal: 2100)
        .padding()
}
