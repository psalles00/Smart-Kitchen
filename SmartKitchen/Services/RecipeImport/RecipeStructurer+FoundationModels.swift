import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - On-device structuring (Apple Foundation Models, iOS 26+)

#if canImport(FoundationModels)

@available(iOS 26.0, macOS 26.0, *)
extension RecipeStructurer {

    /// Attempts to structure the recipe using Apple's on-device Foundation Models.
    /// Returns `nil` when the model is unavailable so callers can fall back to OpenAI.
    func structureOnDeviceFoundationModels(text: String, hints: Hints) async throws -> RecipeDraft? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            RecipeImportLogger.debug("FoundationModels unavailable availability=\(String(describing: model.availability))")
            return nil
        }
        RecipeImportLogger.info("FoundationModels available, generating draft")

        let instructions = Self.systemPrompt
        let session = LanguageModelSession(instructions: instructions)
        let prompt = Self.userPrompt(text: text, hints: hints)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedRecipe.self
            )
            RecipeImportLogger.info("FoundationModels response received")
            return Self.draft(from: response.content, hints: hints)
        } catch {
            // On-device failure shouldn't abort the whole import. Fall back.
            RecipeImportLogger.error("FoundationModels failed error=\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Generable schema

    @Generable
    struct GeneratedRecipe {
        @Guide(description: "Nome da receita, em português brasileiro.")
        var name: String

        @Guide(description: "Descrição curta, opcional.")
        var description: String

        @Guide(description: "Categoria: Café da manhã, Almoço, Jantar, Lanche, Sobremesa, Bebida ou Outros.")
        var category: String

        @Guide(description: "Dificuldade: Fácil, Médio ou Difícil.")
        var difficulty: String

        @Guide(description: "Tempo de preparo em minutos. 0 se desconhecido.")
        var prepTimeMinutes: Int

        @Guide(description: "Tempo de cozimento em minutos. 0 se desconhecido.")
        var cookTimeMinutes: Int

        @Guide(description: "Número de porções. 1 se desconhecido.")
        var servings: Int

        @Guide(description: "Calorias por porção. 0 se desconhecido.")
        var calories: Int

        @Guide(description: "Lista de utensílios necessários.")
        var requiredUtensils: [String]

        @Guide(description: "Lista completa de ingredientes da receita.")
        var ingredients: [GeneratedIngredient]

        @Guide(description: "Passos do preparo em ordem numerada.")
        var steps: [GeneratedStep]
    }

    @Generable
    struct GeneratedIngredient {
        @Guide(description: "Nome do ingrediente sem quantidade.")
        var name: String

        @Guide(description: "Quantidade numérica. 0 quando indeterminada.")
        var quantity: Double

        @Guide(description: "Unidade canônica (g, mL, Xícara, Colher de sopa, etc.). Vazio se indefinido.")
        var unit: String

        @Guide(description: "Estado/preparo (Picado, Peneirado, etc.). Vazio se indefinido.")
        var state: String

        @Guide(description: "Confiança na extração: high, medium ou low.")
        var confidence: String
    }

    @Generable
    struct GeneratedStep {
        @Guide(description: "Número do passo, começando em 1.")
        var order: Int

        @Guide(description: "Instrução concisa no imperativo.")
        var instruction: String

        @Guide(description: "Duração do passo em minutos. 0 se não mencionado.")
        var durationMinutes: Int

        @Guide(description: "Confiança na extração: high, medium ou low.")
        var confidence: String
    }

    // MARK: - Mapping

    fileprivate static func draft(from generated: GeneratedRecipe, hints: Hints) -> RecipeDraft {
        var d = RecipeDraft()
        d.name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.name.isEmpty { d.nameConfidence = .high }

        d.descriptionText = generated.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.descriptionText.isEmpty { d.descriptionConfidence = .medium }

        let trimmedCategory = generated.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCategory.isEmpty {
            d.category = trimmedCategory
            d.categoryConfidence = .medium
        }

        if let matched = Difficulty.allCases.first(where: {
            $0.rawValue.compare(generated.difficulty, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            d.difficulty = matched
        }

        if generated.prepTimeMinutes > 0 {
            d.prepTime = generated.prepTimeMinutes
            d.prepTimeConfidence = .high
        }
        if generated.cookTimeMinutes > 0 {
            d.cookTime = generated.cookTimeMinutes
            d.cookTimeConfidence = .high
        }
        if generated.servings > 0 {
            d.servings = generated.servings
            d.servingsConfidence = .high
        }
        if generated.calories > 0 {
            d.calories = generated.calories
        }

        d.requiredUtensils = generated.requiredUtensils
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        d.ingredients = generated.ingredients.compactMap { ing -> IngredientDraft? in
            let name = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let qty: Double? = ing.quantity > 0 ? ing.quantity : nil
            let confidence = Self.mapConfidence(ing.confidence)
            return IngredientDraft(
                name: name,
                quantity: qty,
                unit: ing.unit.trimmingCharacters(in: .whitespaces),
                preparationState: ing.state.trimmingCharacters(in: .whitespaces),
                confidence: confidence
            )
        }

        d.steps = generated.steps.enumerated().compactMap { index, step -> StepDraft? in
            let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else { return nil }
            let order = step.order > 0 ? step.order : (index + 1)
            let duration: Int? = step.durationMinutes > 0 ? step.durationMinutes : nil
            return StepDraft(
                order: order,
                instruction: instruction,
                durationMinutes: duration,
                confidence: Self.mapConfidence(step.confidence)
            )
        }

        return d
    }

    fileprivate static func mapConfidence(_ raw: String) -> FieldConfidence {
        switch raw.lowercased() {
        case "high", "alta":    return .high
        case "low",  "baixa":   return .low
        default:                return .medium
        }
    }
}

#endif
