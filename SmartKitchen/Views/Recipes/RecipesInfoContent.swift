import SwiftUI

struct RecipesInfoContent: View {
    let totalHabits: Int = 8
    let completedToday: Int = 5
    
    private var completionPercentage: Double {
        guard totalHabits > 0 else { return 0 }
        return Double(completedToday) / Double(totalHabits)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hábitos de Hoje")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(completedToday) de \(totalHabits) concluídos")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 6)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: completionPercentage)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(completionPercentage * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.bottom, 12)
    }
}
