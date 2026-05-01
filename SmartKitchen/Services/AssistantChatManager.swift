import SwiftUI
import SwiftData

/// Manages conversational AI chat state. Shared between the inline Home chat
/// and any other surface that needs AI assistant functionality.
@MainActor
final class AssistantChatManager: ObservableObject {
    @Published var errorMessage: String?
    @Published var pendingToolExecution: PendingToolExecution?

    let aiService = AIService()

    // Cached RAG context to avoid rebuilding on every message
    private var cachedInventoryContext: String?
    private var cachedInventoryDate: Date?
    private let contextCacheTTL: TimeInterval = 10

    private let confirmPrompt = "__confirm_pending_ai_change__"
    private let cancelPrompt = "__cancel_pending_ai_change__"

    var isConfirmPrompt: Bool { false }

    // MARK: - Public API

    /// Send a user message. Returns without doing anything if the message is
    /// a confirm/cancel prompt (those are handled internally).
    func sendMessage(
        _ text: String,
        context: ModelContext,
        allRecipes: [Recipe]
    ) {
        if text == confirmPrompt {
            Task { await confirmPendingToolExecution(context: context) }
            return
        }

        if text == cancelPrompt {
            cancelPendingToolExecution(context: context)
            return
        }

        if pendingToolExecution != nil {
            context.insert(ChatMessage(
                role: .assistant,
                content: String(localized: "Tenho uma alteração pendente. Confirme ou cancele antes de continuar."),
                quickActions: [
                    QuickAction(label: String(localized: "Confirmar"), prompt: confirmPrompt),
                    QuickAction(label: String(localized: "Cancelar"), prompt: cancelPrompt)
                ]
            ))
            return
        }

        let userMessage = ChatMessage(role: .user, content: text)
        context.insert(userMessage)
        errorMessage = nil

        if let recipeDiscoveryResponse = makeRecipeDiscoveryResponse(for: text, context: context, allRecipes: allRecipes) {
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: recipeDiscoveryResponse.content,
                attachedRecipeIds: recipeDiscoveryResponse.recipeIds,
                quickActions: recipeDiscoveryResponse.quickActions
            )
            context.insert(assistantMessage)
            return
        }

        Task {
            await performAIChat(
                latestUserMessageID: userMessage.id,
                latestUserText: text,
                context: context,
                allRecipes: allRecipes
            )
        }
    }

    func clearChat(context: ModelContext) {
        pendingToolExecution = nil
        let descriptor = FetchDescriptor<ChatMessage>()
        let messages = (try? context.fetch(descriptor)) ?? []
        for message in messages {
            context.delete(message)
        }
    }

    // MARK: - AI Chat

    private func performAIChat(
        latestUserMessageID: UUID,
        latestUserText: String,
        context: ModelContext,
        allRecipes: [Recipe]
    ) async {
        let apiKey = APIConfig.openAIAPIKey
        // OK if OpenAI key is empty, as long as we have an OpenRouter fallback.
        if apiKey.isEmpty && APIConfig.openRouterAPIKey.isEmpty {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ Nenhuma chave de IA configurada. Configure OpenAI ou OpenRouter em Config/Secrets.xcconfig."
            )
            context.insert(errorMsg)
            return
        }

        do {
            let messages = fetchMessages(context: context)
            try await continueConversation(
                with: buildAPIMessages(
                    latestUserMessageID: latestUserMessageID,
                    latestUserText: latestUserText,
                    messages: messages,
                    context: context
                ),
                context: context,
                allRecipes: allRecipes,
                apiKey: apiKey
            )
        } catch {
            errorMessage = error.localizedDescription
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro: \(error.localizedDescription)"
            )
            context.insert(errorMsg)
        }
    }

    private func fetchMessages(context: ModelContext) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.timestamp)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func buildAPIMessages(
        latestUserMessageID: UUID,
        latestUserText: String,
        messages: [ChatMessage],
        context: ModelContext
    ) -> [[String: Any]] {
        var msgs = [[String: Any]]()
        let normalizedLatestUserPrompt = normalized(latestUserText)
        let isRecipeManagementRequest = isRecipeManagementPrompt(normalizedLatestUserPrompt)

        let systemPrompt = buildSystemPrompt(includeInventoryContext: !isRecipeManagementRequest, context: context)
        msgs.append(["role": "system", "content": systemPrompt])

        let history = Array(messages.suffix(20))
        for msg in history {
            msgs.append(["role": msg.role.rawValue, "content": msg.content])
        }

        if !history.contains(where: { $0.id == latestUserMessageID }) {
            msgs.append(["role": MessageRole.user.rawValue, "content": latestUserText])
        }

        if isRecipeManagementRequest {
            msgs.append([
                "role": "system",
                "content": """
                O pedido mais recente do usuário é um fluxo de criação/edição/exclusão de receita.
                Priorize as ferramentas de receita.
                NÃO mencione despensa, mercado, compatibilidade de ingredientes ou receitas existentes, a menos que o usuário tenha pedido isso explicitamente.
                Se o usuário pedir algo como "adicione uma receita de como fazer arroz", interprete isso como criação de uma nova receita no app para esse prato.
                Se faltarem detalhes para salvar, faça uma pergunta objetiva ou proponha uma receita-base razoável para confirmação.
                """
            ])
        }

        return msgs
    }

    private func continueConversation(
        with messages: [[String: Any]],
        context: ModelContext,
        allRecipes: [Recipe],
        apiKey: String
    ) async throws {
        var apiMessages = messages
        let response = try await aiService.sendChat(
            messages: apiMessages,
            tools: AITools.definitions,
            apiKey: apiKey
        )

        if !response.toolCalls.isEmpty {
            let assistantMessage = makeAssistantToolCallMessage(from: response)
            apiMessages.append(assistantMessage)

            if response.toolCalls.contains(where: requiresConfirmation(for:)) {
                pendingToolExecution = PendingToolExecution(messages: apiMessages, toolCalls: response.toolCalls)
                context.insert(ChatMessage(
                    role: .assistant,
                    content: confirmationMessage(for: response.toolCalls),
                    quickActions: [
                        QuickAction(label: String(localized: "Confirmar"), prompt: confirmPrompt),
                        QuickAction(label: String(localized: "Cancelar"), prompt: cancelPrompt)
                    ]
                ))
                return
            }

            for toolCall in response.toolCalls {
                let result = await AITools.execute(toolCall, context: context)
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": result
                ])
            }

            cachedInventoryContext = nil
            cachedInventoryDate = nil

            try await continueConversation(with: apiMessages, context: context, allRecipes: allRecipes, apiKey: apiKey)
            return
        }

        let content = response.content ?? String(localized: "Desculpe, não consegui gerar uma resposta.")
        let recipeIds = extractRecipeIds(from: content, allRecipes: allRecipes)
        context.insert(ChatMessage(
            role: .assistant,
            content: content,
            attachedRecipeIds: recipeIds
        ))
    }

    private func confirmPendingToolExecution(context: ModelContext) async {
        guard let pending = pendingToolExecution else { return }

        var apiMessages = pending.messages
        self.pendingToolExecution = nil
        context.insert(ChatMessage(role: .user, content: String(localized: "Confirmar alteração")))

        do {
            for toolCall in pending.toolCalls {
                let result = await AITools.execute(toolCall, context: context)
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": result
                ])
            }

            cachedInventoryContext = nil
            cachedInventoryDate = nil

            let allRecipes = (try? context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)]))) ?? []
            try await continueConversation(with: apiMessages, context: context, allRecipes: allRecipes, apiKey: APIConfig.openAIAPIKey)
        } catch {
            errorMessage = error.localizedDescription
            context.insert(ChatMessage(
                role: .assistant,
                content: String(localized: "Desculpe, ocorreu um erro ao aplicar a alteração: \(error.localizedDescription)")
            ))
        }
    }

    private func cancelPendingToolExecution(context: ModelContext) {
        pendingToolExecution = nil
        context.insert(ChatMessage(role: .user, content: String(localized: "Cancelar alteração")))
        context.insert(ChatMessage(
            role: .assistant,
            content: String(localized: "Alteração cancelada. Nenhuma informação foi modificada.")
        ))
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(includeInventoryContext: Bool = true, context: ModelContext) -> String {
        var parts = [String]()

        parts.append("""
        Você é o "Savoria", um assistente de cozinha inteligente e pessoal. \
        Responda SEMPRE em português brasileiro, de forma amigável, concisa e útil.

        ## Suas capacidades
        Você gerencia a despensa, lista de compras e receitas do usuário. \
        Você pode consultar, adicionar, remover e modificar dados usando as ferramentas disponíveis.

        ## Regras obrigatórias
        1. Quando o usuário perguntar sobre a despensa, lista de compras ou receitas, \
        SEMPRE use as ferramentas (get_all_pantry, get_all_grocery, search_recipes, etc.) \
        para buscar os dados atualizados ANTES de responder. NUNCA invente dados.
        2. Ao sugerir receitas, chame get_all_pantry primeiro para saber o que o usuário tem, \
        depois use search_recipes ou suggest_recipe.
        3. Quando o usuário pedir sugestões como "o que posso cozinhar?", "o que posso fazer de sobremesa?" \
        ou qualquer variação de sugestão de receitas, NÃO liste os itens da despensa na resposta. \
        Responda com uma introdução curta dizendo que as opções abaixo foram encontradas com base na despensa \
        e nas receitas salvas, e feche perguntando se o usuário quer outras sugestões.
        4. Ao criar uma receita, use create_recipe com ingredientes detalhados (quantidade + unidade) \
        e passos claros e numerados.
        5. Você pode criar, editar, excluir, buscar e detalhar receitas usando as ferramentas de receita.
        6. Antes de modificar qualquer informação do app, peça confirmação clara do usuário. \
        Só prossiga com alterações depois que o usuário confirmar explicitamente.
        7. Você também pode ler e editar categorias de despensa, mercado e receitas usando as ferramentas de categoria.
        8. Sempre formate listas de forma organizada. Use emojis quando apropriado.
        9. Se o usuário pedir para adicionar, criar, editar, atualizar, excluir, remover, apagar, cadastrar ou salvar algo, \
        trate isso como um fluxo de alteração, não como sugestão de receitas.
        10. Quando o usuário pedir para adicionar uma receita nova, NÃO baseie a resposta automaticamente na despensa. \
        Esse fluxo pode ser totalmente independente dos itens atuais do app.
        11. Se não souber algo, diga que não sabe. Nunca invente informações.
        """)

        guard includeInventoryContext else {
            return parts.joined(separator: "\n\n")
        }

        if let cached = cachedInventoryContext,
           let cacheDate = cachedInventoryDate,
           Date().timeIntervalSince(cacheDate) < contextCacheTTL {
            parts.append(cached)
            return parts.joined(separator: "\n\n")
        }

        var inventoryParts = [String]()

        let pantryDescriptor = FetchDescriptor<UnifiedItem>(sortBy: [SortDescriptor(\.category)])
        if let allItems = try? context.fetch(pantryDescriptor) {
            let pantryItems = allItems.filter { $0.isPantry }
            if pantryItems.isEmpty {
                inventoryParts.append("## Despensa atual\nA despensa está vazia.")
            } else {
                let itemDescriptions = pantryItems.map { $0.aiReadableDescription }
                inventoryParts.append("## Despensa atual (\(pantryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }

            let groceryItems = allItems.filter { $0.isGrocery }
            if groceryItems.isEmpty {
                inventoryParts.append("## Lista de compras\nA lista de compras está vazia.")
            } else {
                let itemDescriptions = groceryItems.map { $0.aiReadableDescription }
                inventoryParts.append("## Lista de compras (\(groceryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }
        }

        let recipeDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
        if let recipes = try? context.fetch(recipeDescriptor) {
            if recipes.isEmpty {
                inventoryParts.append("## Receitas\nNão há receitas salvas.")
            } else {
                var recipeLines = [String]()
                for r in recipes {
                    var line = "- \(r.name) [\(r.category)] (\(r.difficulty.rawValue), \(r.totalTime) min, \(r.servings) porções)"
                    let ingredientNames = (r.ingredients ?? []).map(\.name)
                    if !ingredientNames.isEmpty {
                        line += " — Ingredientes: \(ingredientNames.joined(separator: ", "))"
                    }
                    recipeLines.append(line)
                }
                inventoryParts.append("## Receitas salvas (\(recipes.count))\n\(recipeLines.joined(separator: "\n"))")
            }
        }

        inventoryParts.append(CategoryMutationService.recipeCategoryPromptSection(context: context))
        inventoryParts.append(Self.nutritionPromptSection(context: context))

        let inventoryContext = inventoryParts.joined(separator: "\n\n")
        cachedInventoryContext = inventoryContext
        cachedInventoryDate = Date()

        parts.append(inventoryContext)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private func extractRecipeIds(from content: String, allRecipes: [Recipe]) -> [UUID] {
        let lowered = content.lowercased()
        return allRecipes
            .filter { lowered.contains($0.name.lowercased()) }
            .map(\.id)
    }

    private func makeRecipeDiscoveryResponse(for text: String, context: ModelContext, allRecipes: [Recipe]) -> RecipeDiscoveryResponse? {
        let normalizedPrompt = normalized(text)
        guard isRecipeSuggestionPrompt(normalizedPrompt) else { return nil }

        let pantryItems = (try? context.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        let pantryNames = pantryItems.filter { $0.isPantry }.map { normalized($0.name) }
        let wantsDessert = normalizedPrompt.contains("sobremesa") || normalizedPrompt.contains("doce")

        let rankedRecipes = allRecipes
            .filter { recipe in
                guard wantsDessert else { return true }
                let category = normalized(recipe.category)
                let tags = recipe.tags.map(normalized)
                return category.contains("sobremesa") ||
                    category.contains("doce") ||
                    tags.contains(where: { $0.contains("sobremesa") || $0.contains("doce") })
            }
            .compactMap { recipe -> (Recipe, Int)? in
                let ingredientNames = (recipe.ingredients ?? []).map { normalized($0.name) }
                guard !ingredientNames.isEmpty else { return nil }

                let score = ingredientNames.reduce(into: 0) { partialResult, ingredient in
                    if pantryNames.contains(where: { pantry in
                        pantry == ingredient || pantry.contains(ingredient) || ingredient.contains(pantry)
                    }) {
                        partialResult += 1
                    }
                }
                guard score > 0 else { return nil }
                return (recipe, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.isFavorite != $1.0.isFavorite { return $0.0.isFavorite && !$1.0.isFavorite }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }

        if rankedRecipes.isEmpty {
            return RecipeDiscoveryResponse(
                content: wantsDessert
                    ? "Não encontrei uma sobremesa compatível com o que você tem salvo na despensa e nas suas receitas. Se quiser, posso sugerir outras receitas baseadas no que você tem agora."
                    : "Não encontrei receitas compatíveis com o que você tem salvo na despensa e nas suas receitas. Se quiser, posso sugerir outras opções baseadas no que você tem agora.",
                recipeIds: [],
                quickActions: [
                    QuickAction(
                        label: wantsDessert ? "Sugerir outras sobremesas" : "Sugerir outras receitas",
                        prompt: wantsDessert
                            ? "Sugira outras sobremesas com base na minha despensa."
                            : "Sugira outras receitas com base na minha despensa."
                    )
                ]
            )
        }

        let recipes = rankedRecipes.prefix(6).map(\.0)
        let intro = wantsDessert
            ? "A partir dos itens da sua despensa e da sua lista de receitas, essas são as opções de sobremesa disponíveis:"
            : "A partir dos itens da sua despensa e da sua lista de receitas, essas são as opções disponíveis:"

        return RecipeDiscoveryResponse(
            content: "\(intro)\n\nSe quiser, posso sugerir outras receitas com base na sua despensa.",
            recipeIds: recipes.map(\.id),
            quickActions: [
                QuickAction(
                    label: wantsDessert ? "Sugerir outras sobremesas" : "Sugerir outras receitas",
                    prompt: wantsDessert
                        ? "Sugira outras sobremesas com base na minha despensa."
                        : "Sugira outras receitas com base na minha despensa."
                )
            ]
        )
    }

    private func isRecipeSuggestionPrompt(_ text: String) -> Bool {
        if isRecipeManagementPrompt(text) { return false }

        let suggestionCues = [
            "o que posso", "posso fazer", "posso cozinhar", "me sugira", "sugira", "sugerir",
            "quais opcoes", "quais receitas", "opcoes disponiveis", "me mostre", "me mostra",
            "quero uma", "quero um",
            // ES
            "que puedo", "puedo hacer", "puedo cocinar", "sugiereme", "sugiere", "sugerir",
            "que opciones", "que recetas", "opciones disponibles", "muestrame", "quiero una", "quiero un",
            // FR
            "que puis-je", "puis-je faire", "puis-je cuisiner", "suggere", "suggerer", "suggere-moi",
            "quelles options", "quelles recettes", "options disponibles", "montre-moi", "je veux une", "je veux un",
            // DE
            "was kann", "kann ich kochen", "kann ich machen", "schlage vor", "schlag vor",
            "zeig mir", "ich mochte", "welche optionen", "welche rezepte",
            // IT
            "cosa posso", "posso fare", "posso cucinare", "suggerisci", "suggeriscimi",
            "mostrami", "voglio una", "voglio un", "quali opzioni", "quali ricette", "opzioni disponibili",
            // JA
            "何を作", "何が作", "何が料理", "提案", "おすすめ", "見せて", "欲しい", "どんなレシピ", "どんなオプション",
            // EN
            "what can", "can i make", "can i cook", "suggest", "show me", "i want"
        ]
        let recipeCues = [
            "receita", "receitas", "cozinhar", "fazer", "preparar", "sobremesa", "doce",
            // ES
            "receta", "recetas", "cocinar", "preparar", "postre", "dulce",
            // FR
            "recette", "recettes", "cuisiner", "faire", "preparer", "dessert", "sucre",
            // DE
            "rezept", "rezepte", "kochen", "machen", "zubereiten", "nachtisch", "dessert", "suss", "vorratskammer",
            // IT
            "ricetta", "ricette", "cucinare", "fare", "preparare", "dessert", "dolce", "dispensa",
            // JA
            "レシピ", "料理", "作る", "準備", "デザート", "甘い", "パントリー",
            // EN
            "recipe", "recipes", "cook", "make", "dessert", "sweet"
        ]

        return suggestionCues.contains(where: text.contains) && recipeCues.contains(where: text.contains)
    }

    private func isRecipeManagementPrompt(_ text: String) -> Bool {
        let managementCues = [
            "adicione", "adicionar", "crie", "criar", "cadastre", "cadastrar",
            "salve", "salvar", "edite", "editar", "atualize", "atualizar",
            "exclua", "excluir", "apague", "apagar", "remova", "remover",
            // ES
            "añade", "añadir", "agrega", "agregar", "crea", "crear", "registra", "registrar",
            "guarda", "guardar", "edita", "editar", "actualiza", "actualizar",
            "elimina", "eliminar", "borra", "borrar", "quita", "quitar",
            // FR
            "ajoute", "ajouter", "cree", "creer", "enregistre", "enregistrer",
            "modifie", "modifier", "mets a jour", "mettre a jour",
            "supprime", "supprimer", "efface", "effacer", "retire", "retirer",
            // DE
            "hinzufugen", "fuge hinzu", "erstelle", "erstellen",
            "speichern", "speichere", "bearbeiten", "bearbeite",
            "aktualisieren", "aktualisiere", "loschen", "losche", "entfernen", "entferne",
            // IT
            "aggiungi", "aggiungere", "crea", "creare", "salva", "salvare",
            "modifica", "modificare", "aggiorna", "aggiornare",
            "elimina", "eliminare", "rimuovi", "rimuovere", "cancella", "cancellare",
            // JA
            "追加", "作成", "保存", "編集", "更新", "削除", "消去",
            // EN
            "add", "create", "save", "edit", "update", "delete", "remove"
        ]
        let recipeTargets = [
            "receita", "receitas", "como fazer", "modo de preparo",
            "receta", "recetas", "como hacer", "modo de preparación",
            "recette", "recettes", "comment faire", "preparation",
            "rezept", "rezepte", "wie macht man", "zubereitung",
            "ricetta", "ricette", "come fare", "preparazione", "modo di preparazione",
            "レシピ", "作り方", "調理法",
            "recipe", "recipes", "how to make", "instructions"
        ]
        return managementCues.contains(where: text.contains) && recipeTargets.contains(where: text.contains)
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private func requiresConfirmation(for toolCall: ToolCallRequest) -> Bool {
        Set([
            "create_recipe", "update_recipe", "delete_recipe",
            "add_pantry_item", "remove_pantry_item", "add_grocery_item",
            "create_category", "rename_category", "delete_category", "move_category",
            "log_food_manual", "delete_food_entry"
        ]).contains(toolCall.name)
    }

    private func makeAssistantToolCallMessage(from response: ChatCompletionResponse) -> [String: Any] {
        var assistantMessage: [String: Any] = ["role": "assistant"]
        if let content = response.content { assistantMessage["content"] = content }
        assistantMessage["tool_calls"] = response.toolCalls.map { toolCall in
            [
                "id": toolCall.id,
                "type": "function",
                "function": [
                    "name": toolCall.name,
                    "arguments": toolCall.argumentsJSON
                ]
            ]
        }
        return assistantMessage
    }

    private func confirmationMessage(for toolCalls: [ToolCallRequest]) -> String {
        let summary = toolCalls.map { toolCall in
            switch toolCall.name {
            case "create_recipe": String(localized: "criar receita")
            case "update_recipe": String(localized: "editar receita")
            case "delete_recipe": String(localized: "excluir receita")
            case "add_pantry_item": String(localized: "adicionar item na despensa")
            case "remove_pantry_item": String(localized: "remover item da despensa")
            case "add_grocery_item": String(localized: "adicionar item no mercado")
            case "create_category": String(localized: "criar categoria")
            case "rename_category": String(localized: "renomear categoria")
            case "delete_category": String(localized: "excluir categoria")
            case "move_category": String(localized: "reordenar categoria")
            case "log_food_manual": String(localized: "registrar refeição")
            case "delete_food_entry": String(localized: "remover refeição registrada")
            default: String(localized: "alterar informações")
            }
        }
        .joined(separator: ", ")

        return String(localized: "Confirma esta alteração no app?\n\nAção pendente: \(summary).")
    }

    // MARK: - Nutrition prompt section

    static func nutritionPromptSection(context: ModelContext) -> String {
        guard let profile = NutritionProfileStore.fetch(in: context),
              profile.hasCompletedOnboarding else {
            return "## Nutrição\nO usuário ainda não concluiu o onboarding de nutrição."
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let totalCal = entries.reduce(0) { $0 + $1.calories }
        let totalP = entries.reduce(0.0) { $0 + $1.proteinG }
        let totalC = entries.reduce(0.0) { $0 + $1.carbsG }
        let totalF = entries.reduce(0.0) { $0 + $1.fatG }

        var lines = ["## Nutrição (hoje)"]
        lines.append("- Metas diárias: \(profile.effectiveCalories) kcal · P \(profile.effectiveProteinG)g · C \(profile.effectiveCarbsG)g · G \(profile.effectiveFatG)g")
        if entries.isEmpty {
            lines.append("- Consumo de hoje: nenhum registro ainda.")
        } else {
            lines.append("- Consumo de hoje (\(entries.count) registros): \(totalCal) kcal · P \(Int(totalP.rounded()))g · C \(Int(totalC.rounded()))g · G \(Int(totalF.rounded()))g")
        }
        lines.append("- Para registrar refeições, use a ferramenta `log_food_manual` estimando calorias/macros a partir da descrição do usuário.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Supporting Types (shared)

struct RecipeDiscoveryResponse {
    let content: String
    let recipeIds: [UUID]
    let quickActions: [QuickAction]
}

struct PendingToolExecution {
    let messages: [[String: Any]]
    let toolCalls: [ToolCallRequest]
}
