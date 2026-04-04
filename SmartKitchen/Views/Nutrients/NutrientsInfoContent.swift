import SwiftUI

struct NutrientsInfoContent: View {
    let activeGoals: Int = 4
    let completedGoals: Int = 2
    let overallProgress: Double = 0.65
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suas Metas")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Label("\(activeGoals) ativas", systemImage: "target")
                    if completedGoals > 0 {
                        Label("\(completedGoals) concluídas", systemImage: "checkmark.seal.fill")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(overallProgress * 100))%")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("progresso geral")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.bottom, 12)
    }
}
