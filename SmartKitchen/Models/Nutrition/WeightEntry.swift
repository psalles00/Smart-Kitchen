import Foundation
import SwiftData

/// Registro de peso corporal em uma data específica.
@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0

    init(date: Date = .now, weightKg: Double) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
    }
}
