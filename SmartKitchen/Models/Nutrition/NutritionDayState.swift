import Foundation

/// Estado visual / lógico de um dia na timeline de Nutrição.
///
/// O estado é derivado de três sinais:
/// 1) Posição relativa a hoje (futuro / hoje / passado).
/// 2) Existência de `NutritionDayLog` com `completedAt` ou `canceledAt`.
/// 3) Existência de pelo menos uma `FoodEntry` registrada naquele dia.
enum NutritionDayState: Equatable {
    /// Datas no futuro — não interagíveis.
    case future
    /// Hoje, sem nenhum registro ainda.
    case todayEmpty
    /// Hoje, com pelo menos um registro mas ainda não concluído.
    case todayInProgress
    /// Dia concluído pelo usuário (entra na média).
    case completed
    /// Dia passado, com registros mas não concluído (pendência).
    case pastInProgress
    /// Dia passado, sem nenhum registro e não cancelado (pendência vermelha).
    case pastEmpty
    /// Dia explicitamente marcado como vazio/cancelado pelo usuário.
    case canceled

    /// Indica se o dia conta como "pendência" para avisos na Home.
    var isPending: Bool {
        switch self {
        case .pastInProgress, .pastEmpty, .todayInProgress: return true
        case .future, .todayEmpty, .completed, .canceled:   return false
        }
    }

    /// Dias considerados "iniciados" (têm registros mas não foram concluídos).
    /// Hoje vazio NÃO conta como iniciado.
    var isStartedButNotFinished: Bool {
        switch self {
        case .todayInProgress, .pastInProgress: return true
        default: return false
        }
    }
}
