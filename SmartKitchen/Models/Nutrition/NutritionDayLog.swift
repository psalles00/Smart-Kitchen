import Foundation
import SwiftData

/// Marca o estado de "dia de Nutrição" para um determinado dia (no fuso local).
///
/// - `dayStart`: chave do dia, sempre `Calendar.current.startOfDay(for:)`.
/// - `completedAt`: definido quando o usuário concluiu o registro daquele dia.
///   Dias concluídos entram na média e são considerados "verdes" na timeline.
/// - `canceledAt`: definido quando o usuário marca o dia como vazio/cancelado.
///   Dias cancelados saem das pendências e não entram na média.
///
/// Este modelo vive **apenas no schema "Private"** (`.private(cloudKitContainerID)`),
/// portanto sincroniza somente com a base privada do iCloud do próprio usuário e
/// **nunca** participa de Compartilhamento Familiar (CKShare/Shared store).
///
/// Todas as propriedades têm valor default — exigência do CloudKit/SwiftData
/// para mirroring automático sem migração destrutiva.
@Model
final class NutritionDayLog {
    var id: UUID = UUID()
    /// Início do dia (00:00 local). Usado como chave única lógica.
    var dayStart: Date = Date()
    var completedAt: Date? = nil
    var canceledAt: Date? = nil
    var createdAt: Date = Date()

    init(
        dayStart: Date,
        completedAt: Date? = nil,
        canceledAt: Date? = nil
    ) {
        self.id = UUID()
        self.dayStart = Calendar.current.startOfDay(for: dayStart)
        self.completedAt = completedAt
        self.canceledAt = canceledAt
        self.createdAt = Date()
    }

    var isCompleted: Bool { completedAt != nil && canceledAt == nil }
    var isCanceled: Bool { canceledAt != nil }
}

extension NutritionDayLog {
    /// Chave canônica para um dia (startOfDay no fuso local).
    static func key(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}
