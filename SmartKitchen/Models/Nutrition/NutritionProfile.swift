import Foundation
import SwiftData

/// Singleton por usuário com metas e dados corporais usados para cálculo de BMR/TDEE/macros.
/// Valores de override têm precedência sobre o cálculo automático.
@Model
final class NutritionProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Flag que indica se o onboarding de nutrição já foi concluído.
    var hasCompletedOnboarding: Bool = false

    // MARK: Corpo

    var sexRaw: String = NutritionSex.other.rawValue
    var birthday: Date? = nil
    var heightCm: Double = 170
    var weightKg: Double = 70
    var bodyFatPercent: Double? = nil

    // MARK: Atividade / Meta

    var activityLevelRaw: String = ActivityLevel.moderate.rawValue
    var weightGoalRaw: String = WeightGoal.maintain.rawValue
    var targetWeightKg: Double? = nil
    /// Velocidade semanal de mudança de peso em kg (positivo = ganho, negativo = perda).
    var weeklyChangeKg: Double = 0

    // MARK: Overrides (kcal/macros)

    var overrideCalories: Int? = nil
    var overrideProteinG: Int? = nil
    var overrideCarbsG: Int? = nil
    var overrideFatG: Int? = nil

    // MARK: Preferências

    var useMetric: Bool = true
    var weekStartsOnMonday: Bool = true

    init(
        sex: NutritionSex = .other,
        birthday: Date? = nil,
        heightCm: Double = 170,
        weightKg: Double = 70,
        activityLevel: ActivityLevel = .moderate,
        weightGoal: WeightGoal = .maintain
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.sexRaw = sex.rawValue
        self.birthday = birthday
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevelRaw = activityLevel.rawValue
        self.weightGoalRaw = weightGoal.rawValue
    }

    // MARK: - Enum accessors

    var sex: NutritionSex {
        get { NutritionSex(rawValue: sexRaw) ?? .other }
        set { sexRaw = newValue.rawValue; updatedAt = .now }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate }
        set { activityLevelRaw = newValue.rawValue; updatedAt = .now }
    }

    var weightGoal: WeightGoal {
        get { WeightGoal(rawValue: weightGoalRaw) ?? .maintain }
        set { weightGoalRaw = newValue.rawValue; updatedAt = .now }
    }

    /// Idade em anos completos a partir de `birthday`. Retorna 30 como fallback seguro se não definido.
    var ageYears: Int {
        guard let birthday else { return 30 }
        let comps = Calendar.current.dateComponents([.year], from: birthday, to: .now)
        return max(comps.year ?? 30, 0)
    }
}
