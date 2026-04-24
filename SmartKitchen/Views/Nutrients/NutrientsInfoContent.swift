import SwiftUI

struct NutrientsInfoContent: View {
    var profile: NutritionProfile? = nil
    var caloriesToday: Int = 0

    private var goal: Int { profile?.effectiveCalories ?? 0 }
    private var remaining: Int { max(goal - caloriesToday, 0) }
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(caloriesToday) / Double(goal), 1.0)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hoje")
                    .font(.headline)
                    .foregroundColor(.white)
                if profile?.hasCompletedOnboarding == true {
                    HStack(spacing: 8) {
                        Label("\(caloriesToday) kcal", systemImage: "flame.fill")
                        if goal > 0 {
                            Label("\(remaining) restam", systemImage: "target")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.88))
                } else {
                    Text("Configure seu perfil para ver suas metas.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            Spacer()

            if profile?.hasCompletedOnboarding == true, goal > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("da meta")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(.bottom, 12)
    }
}
