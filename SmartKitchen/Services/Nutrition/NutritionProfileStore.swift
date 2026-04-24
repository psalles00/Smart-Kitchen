import Foundation
import SwiftData

/// Gerencia o singleton `NutritionProfile` dentro do `ModelContext`.
/// Garante que sempre exista exatamente um registro; caso legado com múltiplas
/// cópias apareça (improvável, mas possível via sync), consolida no primeiro.
enum NutritionProfileStore {

    /// Busca o perfil singleton. Cria um novo (com valores padrão) se não existir.
    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> NutritionProfile {
        let descriptor = FetchDescriptor<NutritionProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let existing = (try? context.fetch(descriptor)) ?? []

        if let primary = existing.first {
            // Consolida duplicatas legadas — mantém o mais antigo.
            if existing.count > 1 {
                for duplicate in existing.dropFirst() {
                    context.delete(duplicate)
                }
                try? context.save()
            }
            return primary
        }

        let profile = NutritionProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Busca o perfil sem criar — útil em contextos onde criação é proibida.
    @MainActor
    static func fetch(in context: ModelContext) -> NutritionProfile? {
        let descriptor = FetchDescriptor<NutritionProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Marca o onboarding como concluído e persiste.
    @MainActor
    static func markOnboardingComplete(in context: ModelContext) {
        let profile = fetchOrCreate(in: context)
        profile.hasCompletedOnboarding = true
        profile.updatedAt = .now
        try? context.save()
    }
}
