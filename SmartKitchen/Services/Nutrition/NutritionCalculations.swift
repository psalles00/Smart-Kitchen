import Foundation

/// Cálculos nutricionais puros (sem dependência de SwiftUI/SwiftData).
enum NutritionCalculations {

    // MARK: - BMR

    /// Mifflin-St Jeor — padrão quando não há % de gordura corporal.
    /// Fórmula: `10*kg + 6.25*cm - 5*idade + (5 se homem, -161 se mulher, -78 se outro como média)`.
    static func mifflinStJeor(weightKg: Double, heightCm: Double, ageYears: Int, sex: NutritionSex) -> Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(ageYears)
        switch sex {
        case .male:   return base + 5
        case .female: return base - 161
        case .other:  return base - 78 // média aproximada
        }
    }

    /// Katch-McArdle — usado quando % gordura corporal é conhecida (mais preciso).
    /// `370 + 21.6 * massa magra (kg)`.
    static func katchMcArdle(weightKg: Double, bodyFatPercent: Double) -> Double {
        let fatMass = weightKg * (bodyFatPercent / 100.0)
        let leanMass = max(weightKg - fatMass, 1)
        return 370 + 21.6 * leanMass
    }

    /// BMR efetivo: prioriza Katch-McArdle se bodyFat > 0, cai para Mifflin caso contrário.
    static func basalMetabolicRate(profile: NutritionProfile) -> Double {
        if let bf = profile.bodyFatPercent, bf > 0 {
            return katchMcArdle(weightKg: profile.weightKg, bodyFatPercent: bf)
        }
        return mifflinStJeor(
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            ageYears: profile.ageYears,
            sex: profile.sex
        )
    }

    // MARK: - TDEE & meta

    /// Total Daily Energy Expenditure = BMR * multiplicador de atividade.
    static func tdee(profile: NutritionProfile) -> Double {
        basalMetabolicRate(profile: profile) * profile.activityLevel.multiplier
    }

    /// Déficit/superávit diário em kcal a partir de `weeklyChangeKg`.
    /// Aproximação: 7700 kcal ≈ 1 kg de gordura corporal.
    static func dailyCalorieAdjustment(weeklyChangeKg: Double) -> Double {
        (weeklyChangeKg * 7700.0) / 7.0
    }

    /// Meta diária de calorias considerando TDEE + ajuste conforme `weightGoal`/`weeklyChangeKg`.
    static func targetCalories(profile: NutritionProfile) -> Int {
        let base = tdee(profile: profile)
        var adjustment: Double = 0
        switch profile.weightGoal {
        case .lose:     adjustment = -abs(dailyCalorieAdjustment(weeklyChangeKg: profile.weeklyChangeKg))
        case .gain:     adjustment =  abs(dailyCalorieAdjustment(weeklyChangeKg: profile.weeklyChangeKg))
        case .maintain: adjustment = 0
        }
        let total = max(base + adjustment, 1200) // piso de segurança
        return Int(total.rounded())
    }

    // MARK: - Macros

    /// Proteína em gramas: 1.8 g/kg de peso corporal por padrão.
    static func targetProteinG(profile: NutritionProfile) -> Int {
        Int((profile.weightKg * 1.8).rounded())
    }

    /// Gordura em gramas: 25% das calorias (9 kcal/g).
    static func targetFatG(profile: NutritionProfile, calories: Int) -> Int {
        let fatKcal = Double(calories) * 0.25
        return Int((fatKcal / 9.0).rounded())
    }

    /// Carboidratos em gramas: restante das calorias após proteína e gordura (4 kcal/g).
    static func targetCarbsG(profile: NutritionProfile, calories: Int, proteinG: Int, fatG: Int) -> Int {
        let proteinKcal = Double(proteinG) * 4.0
        let fatKcal = Double(fatG) * 9.0
        let remaining = max(Double(calories) - proteinKcal - fatKcal, 0)
        return Int((remaining / 4.0).rounded())
    }
}

// MARK: - Profile convenience (valores efetivos = override ?? calculado)

extension NutritionProfile {
    /// Meta efetiva de calorias (usa override se definido).
    var effectiveCalories: Int {
        overrideCalories ?? NutritionCalculations.targetCalories(profile: self)
    }

    var effectiveProteinG: Int {
        overrideProteinG ?? NutritionCalculations.targetProteinG(profile: self)
    }

    var effectiveFatG: Int {
        overrideFatG ?? NutritionCalculations.targetFatG(profile: self, calories: effectiveCalories)
    }

    var effectiveCarbsG: Int {
        overrideCarbsG ?? NutritionCalculations.targetCarbsG(
            profile: self,
            calories: effectiveCalories,
            proteinG: effectiveProteinG,
            fatG: effectiveFatG
        )
    }
}
