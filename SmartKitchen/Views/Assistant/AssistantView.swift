import SwiftUI
import SwiftData

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]

    @StateObject private var aiService = AIService()
    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var pendingToolExecution: PendingToolExecution?
    @FocusState private var isInputFocused: Bool

    private var apiKey: String { APIConfig.openAIAPIKey }
    private let confirmPrompt = "__confirm_pending_ai_change__"
    private let cancelPrompt = "__cancel_pending_ai_change__"

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Suggestion chips at top when chat is empty
                        if messages.isEmpty {
                            emptyState
                        }

                        if !messages.isEmpty {
                            SuggestionChipsView { prompt in
                                sendMessage(prompt)
                            }
                            .padding(.top, 8)
                        }

                        ForEach(messages) { message in
                            VStack(spacing: 6) {
                                if message.role != .system {
                                    ChatBubbleView(message: message) { action in
                                        sendMessage(action.prompt)
                                    }
                                }

                                // Inline recipe cards
                                if !message.attachedRecipeIds.isEmpty {
                                    RecipeCardMessage(recipeIds: message.attachedRecipeIds)
                                }
                            }
                            .id(message.id)
                        }

                        // Typing indicator
                        if aiService.isLoading {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: aiService.isLoading) {
                    scrollToBottom(proxy: proxy)
                }
            }

            // Error banner
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .onTapGesture { self.errorMessage = nil }
            }

            // Input bar
            inputBar
        }
        .navigationTitle("Assistente")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !messages.isEmpty {
                        Button("Novo chat", systemImage: "square.and.pencil") {
                            clearChat()
                        }
                        .tint(.secondary)
                    }
                    SettingsButton()
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("Assistente de Cozinha")
                .font(.pageTitle)

            Text("Pergunte sobre receitas, verifique sua despensa ou peça sugestões de pratos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SuggestionChipsView { prompt in
                sendMessage(prompt)
            }
            .padding(.top, 8)

            Spacer().frame(height: 20)
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(0.6)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: aiService.isLoading
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 4)

                TextField("Mensagem...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { sendIfValid() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    }
            )

            Button {
                sendIfValid()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? Color.accentColor : Color(.systemGray4), in: .circle)
                    .shadow(color: canSend ? Color.accentColor.opacity(0.28) : .clear, radius: 10, y: 6)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isLoading
    }

    // MARK: - Actions

    private func sendIfValid() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !aiService.isLoading else { return }
        sendMessage(text)
    }

    private func sendMessage(_ text: String) {
        if text == confirmPrompt {
            Task { await confirmPendingToolExecution() }
            return
        }

        if text == cancelPrompt {
            cancelPendingToolExecution()
            return
        }

        if pendingToolExecution != nil {
            modelContext.insert(ChatMessage(
                role: .assistant,
                content: "Tenho uma alteração pendente. Confirme ou cancele antes de continuar.",
                quickActions: [
                    QuickAction(label: "Confirmar", prompt: confirmPrompt),
                    QuickAction(label: "Cancelar", prompt: cancelPrompt)
                ]
            ))
            return
        }

        let userMessage = ChatMessage(role: .user, content: text)
        modelContext.insert(userMessage)
        inputText = ""
        errorMessage = nil

        if let recipeDiscoveryResponse = makeRecipeDiscoveryResponse(for: text) {
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: recipeDiscoveryResponse.content,
                attachedRecipeIds: recipeDiscoveryResponse.recipeIds,
                quickActions: recipeDiscoveryResponse.quickActions
            )
            modelContext.insert(assistantMessage)
            return
        }

        Task {
            await performAIChat(latestUserMessageID: userMessage.id, latestUserText: text)
        }
    }

    private func performAIChat(latestUserMessageID: UUID, latestUserText: String) async {
        guard !apiKey.isEmpty else {
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "⚠️ Chave de API não configurada. Vá em Ajustes para adicionar sua chave OpenAI."
            )
            modelContext.insert(errorMsg)
            return
        }

        do {
            try await continueConversation(
                with: buildAPIMessages(
                    latestUserMessageID: latestUserMessageID,
                    latestUserText: latestUserText
                )
            )
        } catch {
            errorMessage = error.localizedDescription
            let errorMsg = ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro: \(error.localizedDescription)"
            )
            modelContext.insert(errorMsg)
        }
    }

    private func buildAPIMessages(latestUserMessageID: UUID, latestUserText: String) -> [[String: Any]] {
        var msgs = [[String: Any]]()
        let normalizedLatestUserPrompt = normalized(latestUserText)
        let isRecipeManagementRequest = isRecipeManagementPrompt(normalizedLatestUserPrompt)

        // System prompt
        let systemPrompt = buildSystemPrompt(includeInventoryContext: !isRecipeManagementRequest)
        msgs.append(["role": "system", "content": systemPrompt])

        // Chat history (last 20 messages to manage token usage)
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

    private func continueConversation(with messages: [[String: Any]]) async throws {
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
                modelContext.insert(ChatMessage(
                    role: .assistant,
                    content: confirmationMessage(for: response.toolCalls),
                    quickActions: [
                        QuickAction(label: "Confirmar", prompt: confirmPrompt),
                        QuickAction(label: "Cancelar", prompt: cancelPrompt)
                    ]
                ))
                return
            }

            for toolCall in response.toolCalls {
                let result = await AITools.execute(toolCall, context: modelContext)
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": result
                ])
            }

            try await continueConversation(with: apiMessages)
            return
        }

        let content = response.content ?? "Desculpe, não consegui gerar uma resposta."
        let recipeIds = extractRecipeIds(from: content)
        modelContext.insert(ChatMessage(
            role: .assistant,
            content: content,
            attachedRecipeIds: recipeIds
        ))
    }

    private func confirmPendingToolExecution() async {
        guard let pendingToolExecution else { return }

        var apiMessages = pendingToolExecution.messages
        self.pendingToolExecution = nil
        modelContext.insert(ChatMessage(role: .user, content: "Confirmar alteração"))

        do {
            for toolCall in pendingToolExecution.toolCalls {
                let result = await AITools.execute(toolCall, context: modelContext)
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": result
                ])
            }

            try await continueConversation(with: apiMessages)
        } catch {
            errorMessage = error.localizedDescription
            modelContext.insert(ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro ao aplicar a alteração: \(error.localizedDescription)"
            ))
        }
    }

    private func cancelPendingToolExecution() {
        pendingToolExecution = nil
        modelContext.insert(ChatMessage(role: .user, content: "Cancelar alteração"))
        modelContext.insert(ChatMessage(
            role: .assistant,
            content: "Alteração cancelada. Nenhuma informação foi modificada."
        ))
    }

    private func buildSystemPrompt(includeInventoryContext: Bool = true) -> String {
        var parts = [String]()

        // Core instructions
        parts.append("""
        Você é o "Smart Kitchen", um assistente de cozinha inteligente e pessoal. \
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

        // Full RAG context: Pantry
        let pantryDescriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.category)])
        if let pantryItems = try? modelContext.fetch(pantryDescriptor) {
            if pantryItems.isEmpty {
                parts.append("## Despensa atual\nA despensa está vazia.")
            } else {
                let itemDescriptions = pantryItems.map { $0.aiReadableDescription }
                parts.append("## Despensa atual (\(pantryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }
        }

        // Full RAG context: Grocery list
        let groceryDescriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.category)])
        if let groceryItems = try? modelContext.fetch(groceryDescriptor) {
            if groceryItems.isEmpty {
                parts.append("## Lista de compras\nA lista de compras está vazia.")
            } else {
                let itemDescriptions = groceryItems.map { $0.aiReadableDescription }
                parts.append("## Lista de compras (\(groceryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }
        }

        // Full RAG context: Recipes
        let recipeDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
        if let recipes = try? modelContext.fetch(recipeDescriptor) {
            if recipes.isEmpty {
                parts.append("## Receitas\nNão há receitas salvas.")
            } else {
                var recipeLines = [String]()
                for r in recipes {
                    var line = "- \(r.name) [\(r.category)] (\(r.difficulty.rawValue), \(r.totalTime) min, \(r.servings) porções)"
                    let ingredientNames = r.ingredients.map(\.name)
                    if !ingredientNames.isEmpty {
                        line += " — Ingredientes: \(ingredientNames.joined(separator: ", "))"
                    }
                    recipeLines.append(line)
                }
                parts.append("## Receitas salvas (\(recipes.count))\n\(recipeLines.joined(separator: "\n"))")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    /// Try to match recipe names mentioned in AI response to actual recipe UUIDs.
    private func extractRecipeIds(from content: String) -> [UUID] {
        let lowered = content.lowercased()
        return allRecipes
            .filter { lowered.contains($0.name.lowercased()) }
            .map(\.id)
    }

    private func clearChat() {
        pendingToolExecution = nil
        for message in messages {
            modelContext.delete(message)
        }
    }

    private func makeRecipeDiscoveryResponse(for text: String) -> RecipeDiscoveryResponse? {
        let normalizedPrompt = normalized(text)
        guard isRecipeSuggestionPrompt(normalizedPrompt) else { return nil }

        let pantryItems = (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? []
        let pantryNames = pantryItems.map { normalized($0.name) }
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
                let ingredientNames = recipe.ingredients.map { normalized($0.name) }
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
        if isRecipeManagementPrompt(text) {
            return false
        }

        let suggestionCues = [
            "o que posso",
            "posso fazer",
            "posso cozinhar",
            "me sugira",
            "sugira",
            "sugerir",
            "quais opcoes",
            "quais receitas",
            "opcoes disponiveis",
            "me mostre",
            "me mostra",
            "quero uma",
            "quero um"
        ]
        let recipeCues = [
            "receita",
            "receitas",
            "cozinhar",
            "fazer",
            "preparar",
            "sobremesa",
            "doce"
        ]

        return suggestionCues.contains(where: text.contains) && recipeCues.contains(where: text.contains)
    }

    private func isRecipeManagementPrompt(_ text: String) -> Bool {
        let managementCues = [
            "adicione",
            "adicionar",
            "crie",
            "criar",
            "cadastre",
            "cadastrar",
            "salve",
            "salvar",
            "edite",
            "editar",
            "atualize",
            "atualizar",
            "exclua",
            "excluir",
            "apague",
            "apagar",
            "remova",
            "remover"
        ]
        let recipeTargets = [
            "receita",
            "receitas",
            "como fazer",
            "modo de preparo"
        ]

        return managementCues.contains(where: text.contains) && recipeTargets.contains(where: text.contains)
    }

    private func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if aiService.isLoading {
            withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
        } else if let lastId = messages.last?.id {
            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
        }
    }

    private func requiresConfirmation(for toolCall: ToolCallRequest) -> Bool {
        Set([
            "create_recipe",
            "update_recipe",
            "delete_recipe",
            "add_pantry_item",
            "remove_pantry_item",
            "add_grocery_item",
            "create_category",
            "rename_category",
            "delete_category",
            "move_category"
        ]).contains(toolCall.name)
    }

    private func makeAssistantToolCallMessage(from response: ChatCompletionResponse) -> [String: Any] {
        var assistantMessage: [String: Any] = ["role": "assistant"]
        if let content = response.content {
            assistantMessage["content"] = content
        }
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
            case "create_recipe": "criar receita"
            case "update_recipe": "editar receita"
            case "delete_recipe": "excluir receita"
            case "add_pantry_item": "adicionar item na despensa"
            case "remove_pantry_item": "remover item da despensa"
            case "add_grocery_item": "adicionar item no mercado"
            case "create_category": "criar categoria"
            case "rename_category": "renomear categoria"
            case "delete_category": "excluir categoria"
            case "move_category": "reordenar categoria"
            default: "alterar informações"
            }
        }
        .joined(separator: ", ")

        return "Confirma esta alteração no app?\n\nAção pendente: \(summary)."
    }
}

private struct RecipeDiscoveryResponse {
    let content: String
    let recipeIds: [UUID]
    let quickActions: [QuickAction]
}

private struct PendingToolExecution {
    let messages: [[String: Any]]
    let toolCalls: [ToolCallRequest]
}
