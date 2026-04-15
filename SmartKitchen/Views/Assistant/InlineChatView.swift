import SwiftUI
import SwiftData

/// Chat view embedded inline in the Assistente search tab.
/// Manages a single conversation with the AI, including tool execution, recipe discovery, and confirmation flows.
struct InlineChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]
    @Query(sort: \Recipe.name) private var allRecipes: [Recipe]

    @StateObject private var aiService = AIService()
    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var pendingToolExecution: PendingToolExecution?
    @FocusState private var isInputFocused: Bool

    // Cached RAG context
    @State private var cachedInventoryContext: String?
    @State private var cachedInventoryDate: Date?
    private let contextCacheTTL: TimeInterval = 10

    private var apiKey: String { APIConfig.openAIAPIKey }
    private let confirmPrompt = "__confirm_pending_ai_change__"
    private let cancelPrompt = "__cancel_pending_ai_change__"

    /// Optional initial query to auto-send on appear.
    let initialQuery: String?
    /// Called when the user taps back to return to search mode.
    let onDismiss: () -> Void
    /// Called when viewing conversation history.
    let onShowHistory: () -> Void
    /// Shared search bar state — when provided, the unified search bar acts as input.
    var searchBarState: SearchBarState? = nil
    /// External message to send (received from the unified search bar).
    @Binding var pendingExternalMessage: String?

    /// Current conversation ID. Nil means a new conversation will be created on first message.
    @State private var conversationId: UUID?
    /// If set, we're viewing an existing conversation (can still continue it).
    let existingConversationId: UUID?

    @State private var messages: [ChatMessage] = []
    @State private var hasSentInitialQuery = false

    init(
        initialQuery: String? = nil,
        existingConversationId: UUID? = nil,
        onDismiss: @escaping () -> Void,
        onShowHistory: @escaping () -> Void,
        searchBarState: SearchBarState? = nil,
        pendingExternalMessage: Binding<String?> = .constant(nil)
    ) {
        self.initialQuery = initialQuery
        self.existingConversationId = existingConversationId
        self.onDismiss = onDismiss
        self.onShowHistory = onShowHistory
        self.searchBarState = searchBarState
        self._pendingExternalMessage = pendingExternalMessage
    }

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        VStack(spacing: 0) {
            // Hide own header when the parent panel provides one
            if searchBarState == nil {
                chatHeader
            }

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if messages.isEmpty && !aiService.isLoading {
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
                                if message.role == .system {
                                    // Skip system messages
                                } else if parseRecipeDetailCard(from: message) != nil {
                                    // Recipe detail: show only the card, no text bubble
                                    if let card = parseRecipeDetailCard(from: message) {
                                        RecipeDetailCard(recipe: card) {
                                            addRecipeFromCard(card)
                                        }
                                    }
                                } else if !message.attachedRecipeIds.isEmpty {
                                    // Recipe discovery: text → cards → prominent button
                                    ChatBubbleView(
                                        message: messageWithoutQuickActions(message),
                                        onQuickAction: { _ in }
                                    )
                                    RecipeCardMessage(recipeIds: message.attachedRecipeIds)
                                    ForEach(message.quickActions) { action in
                                        createNewRecipesButton(action: action)
                                    }
                                } else if let split = splitMessageAroundOptions(message) {
                                    // AI recipe options: intro → buttons → trailing
                                    if !split.before.isEmpty {
                                        assistantTextBubble(split.before)
                                    }
                                    RecipeOptionButtonsView(options: split.options) { selectedOption in
                                        requestRecipeDetail(for: selectedOption)
                                    }
                                    if !split.after.isEmpty {
                                        assistantTextBubble(split.after)
                                    }
                                } else {
                                    // Regular message
                                    ChatBubbleView(
                                        message: message,
                                        onQuickAction: { action in
                                            sendMessage(action.prompt)
                                        }
                                    )
                                }
                            }
                            .id(message.id)
                        }

                        if aiService.isLoading {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, searchBarState != nil ? 60 : 0)
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

            // Hide own input bar when unified search bar is used as input
            if searchBarState == nil {
                inputBar
            }
        }
        .onChange(of: pendingExternalMessage) { _, newValue in
            if let message = newValue {
                pendingExternalMessage = nil
                sendMessage(message)
            }
        }
        .onAppear {
            if let existingConversationId {
                conversationId = existingConversationId
            }
            reloadMessages()

            // Auto-send initial query
            if let initialQuery, !initialQuery.isEmpty, !hasSentInitialQuery {
                hasSentInitialQuery = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    sendMessage(initialQuery)
                }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let recipe = allRecipes.first(where: { $0.id == id }) {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - Chat Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text("IA")
                .font(.headline)

            Spacer()

            Button {
                onShowHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Empty State (Skills)

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 30)

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("IA de Cozinha")
                .font(.pageTitle)

            Text("O que posso fazer por você?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                skillCard(
                    icon: "frying.pan",
                    title: "Cozinhar com Despensa",
                    description: "Descubra receitas com o que você já tem",
                    prompt: "Com base nos ingredientes da minha despensa, o que posso cozinhar?"
                )
                skillCard(
                    icon: "book",
                    title: "Minhas Receitas",
                    description: "Crie, edite e gerencie suas receitas",
                    prompt: "Quero gerenciar minhas receitas. O que posso fazer?"
                )
                skillCard(
                    icon: "list.clipboard",
                    title: "Minhas Listas",
                    description: "Gerencie despensa, mercado e categorias",
                    prompt: "Quero gerenciar minhas listas. O que posso fazer?"
                )
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 10)
        }
    }

    private func skillCard(icon: String, title: String, description: String, prompt: String) -> some View {
        Button {
            sendMessage(prompt)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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

    // MARK: - Conversation Management

    private func ensureConversation() -> UUID {
        if let conversationId { return conversationId }
        let conversation = ChatConversation()
        modelContext.insert(conversation)
        conversationId = conversation.id
        return conversation.id
    }

    private func startNewConversation() {
        conversationId = nil
        messages = []
        pendingToolExecution = nil
        errorMessage = nil
        cachedInventoryContext = nil
        cachedInventoryDate = nil
    }

    private func reloadMessages() {
        guard let conversationId else {
            messages = []
            return
        }
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 200
        messages = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func insertMessage(_ message: ChatMessage) {
        modelContext.insert(message)
        messages.append(message)

        // Update conversation timestamp
        if let conversationId,
           let descriptor = Optional(FetchDescriptor<ChatConversation>(
               predicate: #Predicate<ChatConversation> { $0.id == conversationId }
           )),
           let conversation = try? modelContext.fetch(descriptor).first {
            conversation.updatedAt = .now

            // Auto-title from first user message
            if conversation.title == nil && message.role == .user {
                conversation.generateTitle(from: message.content)
            }
        }
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
            let convId = ensureConversation()
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Tenho uma alteração pendente. Confirme ou cancele antes de continuar.",
                quickActions: [
                    QuickAction(label: "Confirmar", prompt: confirmPrompt),
                    QuickAction(label: "Cancelar", prompt: cancelPrompt)
                ],
                conversationId: convId
            ))
            return
        }

        let convId = ensureConversation()
        let userMessage = ChatMessage(role: .user, content: text, conversationId: convId)
        insertMessage(userMessage)
        inputText = ""
        errorMessage = nil

        if let recipeDiscoveryResponse = makeRecipeDiscoveryResponse(for: text) {
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: recipeDiscoveryResponse.content,
                attachedRecipeIds: recipeDiscoveryResponse.recipeIds,
                quickActions: recipeDiscoveryResponse.quickActions,
                conversationId: convId
            )
            insertMessage(assistantMessage)
            return
        }

        Task {
            await performAIChat(latestUserMessageID: userMessage.id, latestUserText: text)
        }
    }

    /// Called when user taps a recipe option button. Sends an internal instruction to the AI
    /// without displaying a user message bubble. Skips tools so the AI returns formatted text only.
    private func requestRecipeDetail(for option: RecipeOption) {
        let convId = ensureConversation()
        errorMessage = nil

        let internalInstruction = """
        O usu\u{e1}rio escolheu a receita "\(option.name)". \
        Forne\u{e7}a a receita completa usando EXATAMENTE este formato (sem texto antes ou depois):

        **\(option.name)**
        _Descri\u{e7}\u{e3}o curta da receita_

        **Ingredientes**
        - 200g de Ingrediente
        - 2 un de Outro Ingrediente

        **Modo de Preparo**
        1. Primeiro passo da receita.
        2. Segundo passo da receita.

        Regras:
        - Nomes dos ingredientes SEMPRE come\u{e7}am com letra mai\u{fa}scula.
        - Inclua quantidade e unidade para cada ingrediente.
        - Passos numerados, claros e objetivos.
        - N\u{e3}o adicione texto antes ou depois do formato acima.
        - N\u{e3}o chame nenhuma ferramenta. Apenas retorne o texto formatado.
        """

        Task {
            await performInternalAIChat(instruction: internalInstruction, conversationId: convId, skipTools: true)
        }
    }

    /// Sends an AI request without creating a visible user message.
    private func performInternalAIChat(instruction: String, conversationId: UUID, skipTools: Bool = false) async {
        guard !apiKey.isEmpty else { return }

        var msgs = [[String: Any]]()
        let systemPrompt = buildSystemPrompt(includeInventoryContext: true)
        msgs.append(["role": "system", "content": systemPrompt])

        let history = Array(messages.suffix(20))
        for msg in history {
            msgs.append(["role": msg.role.rawValue, "content": msg.content])
        }

        msgs.append(["role": "user", "content": instruction])

        do {
            try await continueConversation(with: msgs, skipTools: skipTools)
        } catch {
            errorMessage = error.localizedDescription
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro: \(error.localizedDescription)",
                conversationId: conversationId
            ))
        }
    }

    private func performAIChat(latestUserMessageID: UUID, latestUserText: String) async {
        guard !apiKey.isEmpty else {
            let convId = ensureConversation()
            insertMessage(ChatMessage(
                role: .assistant,
                content: "⚠️ Chave de API não configurada. Vá em Ajustes para adicionar sua chave OpenAI.",
                conversationId: convId
            ))
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
            let convId = ensureConversation()
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro: \(error.localizedDescription)",
                conversationId: convId
            ))
        }
    }

    private func buildAPIMessages(latestUserMessageID: UUID, latestUserText: String) -> [[String: Any]] {
        var msgs = [[String: Any]]()
        let normalizedLatestUserPrompt = normalized(latestUserText)
        let isRecipeManagementRequest = isRecipeManagementPrompt(normalizedLatestUserPrompt)

        let systemPrompt = buildSystemPrompt(includeInventoryContext: !isRecipeManagementRequest)
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

    private func continueConversation(with messages: [[String: Any]], skipTools: Bool = false) async throws {
        var apiMessages = messages
        let response = try await aiService.sendChat(
            messages: apiMessages,
            tools: skipTools ? nil : AITools.definitions,
            apiKey: apiKey
        )

        if !response.toolCalls.isEmpty {
            let assistantMessage = makeAssistantToolCallMessage(from: response)
            apiMessages.append(assistantMessage)

            if response.toolCalls.contains(where: requiresConfirmation(for:)) {
                pendingToolExecution = PendingToolExecution(messages: apiMessages, toolCalls: response.toolCalls)
                let convId = ensureConversation()
                insertMessage(ChatMessage(
                    role: .assistant,
                    content: confirmationMessage(for: response.toolCalls),
                    quickActions: [
                        QuickAction(label: "Confirmar", prompt: confirmPrompt),
                        QuickAction(label: "Cancelar", prompt: cancelPrompt)
                    ],
                    conversationId: convId
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

            cachedInventoryContext = nil
            cachedInventoryDate = nil

            try await continueConversation(with: apiMessages)
            return
        }

        let content = response.content ?? "Desculpe, não consegui gerar uma resposta."
        let recipeIds = extractRecipeIds(from: content)
        let convId = ensureConversation()
        insertMessage(ChatMessage(
            role: .assistant,
            content: content,
            attachedRecipeIds: recipeIds,
            conversationId: convId
        ))
    }

    private func confirmPendingToolExecution() async {
        guard let pending = pendingToolExecution else { return }

        var apiMessages = pending.messages
        self.pendingToolExecution = nil
        let convId = ensureConversation()
        insertMessage(ChatMessage(role: .user, content: "Confirmar alteração", conversationId: convId))

        do {
            for toolCall in pending.toolCalls {
                let result = await AITools.execute(toolCall, context: modelContext)
                apiMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": result
                ])
            }

            cachedInventoryContext = nil
            cachedInventoryDate = nil

            try await continueConversation(with: apiMessages)
        } catch {
            errorMessage = error.localizedDescription
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Desculpe, ocorreu um erro ao aplicar a alteração: \(error.localizedDescription)",
                conversationId: convId
            ))
        }
    }

    private func cancelPendingToolExecution() {
        pendingToolExecution = nil
        let convId = ensureConversation()
        insertMessage(ChatMessage(role: .user, content: "Cancelar alteração", conversationId: convId))
        insertMessage(ChatMessage(
            role: .assistant,
            content: "Alteração cancelada. Nenhuma informação foi modificada.",
            conversationId: convId
        ))
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(includeInventoryContext: Bool = true) -> String {
        var parts = [String]()

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

        ## Sugestão de receitas novas
        Quando o usuário pedir para criar opções de receitas ou sugerir novas receitas que ele não tem salvas:
        - Use seu conhecimento interno para sugerir 4-6 opções de receitas.
        - Responda APENAS com uma frase introdutória curta (ex: "Aqui estão algumas opções:").
        - Em seguida, liste cada opção em uma linha separada com o formato: "**Nome da Receita** — Descrição breve"
        - A descrição de cada opção deve ter NO MÁXIMO 50 caracteres.
        - NÃO repita as opções como texto corrido. As opções devem estar APENAS no formato acima.
        - NÃO adicione texto depois da lista de opções.
        - Se o usuário pedir receitas novas sem especificar "a partir da despensa" ou "do zero", e a despensa tiver 3+ itens, assuma que quer receitas com base na despensa e mencione isso na introdução.
        - Se a despensa tiver menos de 3 itens, pergunte: "Quer receitas com base na sua despensa ou partindo do zero?"
        - REGRA OBRIGATÓRIA: Quando for com base na despensa, TODOS os ingredientes de cada receita sugerida DEVEM estar presentes na despensa do usuário. NÃO sugira receitas que necessitem de ingredientes que o usuário NÃO possui na despensa.
        - Se o usuário pedir receitas que incluam ingredientes que ele NÃO tem na despensa, envie uma mensagem de confirmação ANTES de listar: "Essas receitas podem incluir ingredientes que você não tem na despensa. Deseja continuar?"
        - Apenas prossiga com receitas com ingredientes fora da despensa se o usuário confirmar explicitamente.

        ## Receita completa
        Quando for apresentar uma receita completa (após o usuário escolher uma opção):
        - NÃO chame a ferramenta create_recipe. Apenas retorne o texto formatado abaixo.
        - O usuário decidirá se quer salvar a receita através de um botão na interface.
        - Use EXATAMENTE este formato:

        **Nome da Receita**
        _Descrição curta_

        **Ingredientes**
        - 200g de Ingrediente
        - 2 un de Outro Ingrediente

        **Modo de Preparo**
        1. Primeiro passo.
        2. Segundo passo.

        - Nomes dos ingredientes SEMPRE começam com letra maiúscula.
        - Inclua quantidade e unidade para cada ingrediente.
        - Passos numerados, claros e objetivos.
        - NÃO adicione texto antes ou depois deste formato.
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

        let pantryDescriptor = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.category)])
        if let pantryItems = try? modelContext.fetch(pantryDescriptor) {
            if pantryItems.isEmpty {
                inventoryParts.append("## Despensa atual\nA despensa está vazia.")
            } else {
                let itemDescriptions = pantryItems.map { $0.aiReadableDescription }
                inventoryParts.append("## Despensa atual (\(pantryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }
        }

        let groceryDescriptor = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.category)])
        if let groceryItems = try? modelContext.fetch(groceryDescriptor) {
            if groceryItems.isEmpty {
                inventoryParts.append("## Lista de compras\nA lista de compras está vazia.")
            } else {
                let itemDescriptions = groceryItems.map { $0.aiReadableDescription }
                inventoryParts.append("## Lista de compras (\(groceryItems.count) itens)\n\(itemDescriptions.joined(separator: "\n"))")
            }
        }

        let recipeDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
        if let recipes = try? modelContext.fetch(recipeDescriptor) {
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

        let inventoryContext = inventoryParts.joined(separator: "\n\n")
        cachedInventoryContext = inventoryContext
        cachedInventoryDate = Date()
        parts.append(inventoryContext)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Recipe Discovery (Enhanced with threshold)

    private func makeRecipeDiscoveryResponse(for text: String) -> RecipeDiscoveryResponse? {
        let normalizedPrompt = normalized(text)
        guard isRecipeSuggestionPrompt(normalizedPrompt) else { return nil }

        let pantryItems = (try? modelContext.fetch(FetchDescriptor<PantryItem>())) ?? []
        let pantryNames = pantryItems.map { normalized($0.name) }
        let wantsDessert = normalizedPrompt.contains("sobremesa") || normalizedPrompt.contains("doce")

        // Check for specific keywords beyond generic recipe request
        _ = detectSpecificRequest(normalizedPrompt)

        let thresholdPercent = Double(settings?.recipeCompatibilityThresholdPercentValue ?? 80) / 100.0

        let rankedRecipes = allRecipes
            .filter { recipe in
                guard wantsDessert else { return true }
                let category = normalized(recipe.category)
                let tags = recipe.tags.map(normalized)
                return category.contains("sobremesa") ||
                    category.contains("doce") ||
                    tags.contains(where: { $0.contains("sobremesa") || $0.contains("doce") })
            }
            .compactMap { recipe -> (Recipe, Int, Double)? in
                let ingredientNames = (recipe.ingredients ?? []).map { normalized($0.name) }
                guard !ingredientNames.isEmpty else { return nil }

                let score = ingredientNames.reduce(into: 0) { partialResult, ingredient in
                    if pantryNames.contains(where: { pantry in
                        pantry == ingredient || pantry.contains(ingredient) || ingredient.contains(pantry)
                    }) {
                        partialResult += 1
                    }
                }
                let ratio = Double(score) / Double(ingredientNames.count)
                guard score > 0 else { return nil }
                return (recipe, score, ratio)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.isFavorite != $1.0.isFavorite { return $0.0.isFavorite && !$1.0.isFavorite }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }

        // Filter by threshold
        let thresholdRecipes = rankedRecipes.filter { $0.2 >= thresholdPercent }
        let recipesToShow = thresholdRecipes.isEmpty ? rankedRecipes : thresholdRecipes

        if recipesToShow.isEmpty {
            let noResultLabel = wantsDessert ? "sobremesa" : "receita"
            let newRecipePrompt: String
            if pantryItems.count >= 3 {
                newRecipePrompt = wantsDessert
                    ? "Sugira novas receitas de sobremesa com base na minha despensa."
                    : "Sugira novas receitas com base na minha despensa."
            } else {
                newRecipePrompt = wantsDessert
                    ? "Sugira novas receitas de sobremesa."
                    : "Sugira novas receitas."
            }
            return RecipeDiscoveryResponse(
                content: "Não encontrei nenhuma \(noResultLabel) compatível com o que você tem na despensa e nas suas receitas salvas.",
                recipeIds: [],
                quickActions: [
                    QuickAction(
                        label: "🍳 Criar novas receitas",
                        prompt: newRecipePrompt
                    )
                ]
            )
        }

        let recipes = recipesToShow.prefix(6).map(\.0)
        let intro: String
        if thresholdRecipes.isEmpty {
            intro = wantsDessert
                ? "Não encontrei sobremesas com compatibilidade ideal, mas estas são as melhores opções com o que você tem:"
                : "Não encontrei receitas com compatibilidade ideal, mas estas são as melhores opções com o que você tem:"
        } else {
            intro = wantsDessert
                ? "A partir dos itens da sua despensa, essas são as sobremesas compatíveis:"
                : "A partir dos itens da sua despensa, essas são as receitas compatíveis:"
        }

        // Always offer to create new recipes
        let newRecipePrompt: String
        if pantryItems.count >= 3 {
            newRecipePrompt = wantsDessert
                ? "Sugira novas receitas de sobremesa com base na minha despensa."
                : "Sugira novas receitas com base na minha despensa."
        } else {
            newRecipePrompt = wantsDessert
                ? "Sugira novas receitas de sobremesa."
                : "Sugira novas receitas."
        }

        let quickActions = [
            QuickAction(
                label: "🍳 Criar novas receitas",
                prompt: newRecipePrompt
            )
        ]

        return RecipeDiscoveryResponse(
            content: intro,
            recipeIds: recipes.map(\.id),
            quickActions: quickActions
        )
    }

    /// Detects if the prompt has specific criteria beyond "what can I cook".
    private func detectSpecificRequest(_ text: String) -> Bool {
        let specificKeywords = [
            "chocolate", "morango", "frango", "carne", "peixe", "vegano",
            "vegetariano", "rapido", "facil", "saudavel", "fit",
            "low carb", "sem gluten", "sem lactose", "italiano", "japones",
            "mexicano", "brasileiro", "indiano", "thai", "arabe"
        ]
        return specificKeywords.contains(where: { text.contains($0) })
    }

    // MARK: - Helpers

    private func extractRecipeIds(from content: String) -> [UUID] {
        let lowered = content.lowercased()
        return allRecipes
            .filter { lowered.contains($0.name.lowercased()) }
            .map(\.id)
    }

    private func isRecipeSuggestionPrompt(_ text: String) -> Bool {
        if isRecipeManagementPrompt(text) { return false }
        // "Sugira novas receitas" should go to AI for generation, not local discovery
        let newRecipesCues = ["novas receitas", "receitas novas", "crie receitas", "criar receitas"]
        if newRecipesCues.contains(where: text.contains) { return false }

        let suggestionCues = [
            "o que posso", "posso fazer", "posso cozinhar", "me sugira", "sugira", "sugerir",
            "quais opcoes", "quais receitas", "opcoes disponiveis", "me mostre", "me mostra",
            "quero uma", "quero um", "com base na minha despensa"
        ]
        let recipeCues = [
            "receita", "receitas", "cozinhar", "fazer", "preparar", "sobremesa", "doce", "despensa"
        ]
        return suggestionCues.contains(where: text.contains) && recipeCues.contains(where: text.contains)
    }

    private func isRecipeManagementPrompt(_ text: String) -> Bool {
        let managementCues = [
            "adicione", "adicionar", "crie", "criar", "cadastre", "cadastrar",
            "salve", "salvar", "edite", "editar", "atualize", "atualizar",
            "exclua", "excluir", "apague", "apagar", "remova", "remover"
        ]
        let recipeTargets = ["receita", "receitas", "como fazer", "modo de preparo"]
        return managementCues.contains(where: text.contains) && recipeTargets.contains(where: text.contains)
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
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
            "create_recipe", "update_recipe", "delete_recipe",
            "add_pantry_item", "remove_pantry_item", "add_grocery_item",
            "create_category", "rename_category", "delete_category", "move_category"
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

    // MARK: - Display Helpers

    /// Returns a copy of the message with quickActions removed (for separate rendering).
    private func messageWithoutQuickActions(_ message: ChatMessage) -> ChatMessage {
        ChatMessage(
            role: message.role,
            content: message.content,
            attachedRecipeIds: message.attachedRecipeIds,
            conversationId: message.conversationId
        )
    }

    /// A standalone assistant text bubble (no quick actions).
    private func assistantTextBubble(_ text: String) -> some View {
        ChatBubbleView(
            message: ChatMessage(role: .assistant, content: text, conversationId: conversationId),
            onQuickAction: { _ in }
        )
    }

    /// Splits an AI message with recipe options into (intro text, options, trailing text).
    private func splitMessageAroundOptions(_ message: ChatMessage) -> (before: String, options: [RecipeOption], after: String)? {
        guard message.role == .assistant else { return nil }
        guard let options = parseRecipeOptions(from: message), !options.isEmpty else { return nil }

        let pattern = #"\*\*(.+?)\*\*\s*[—–\-]\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let lines = message.content.components(separatedBy: "\n")
        var firstOptionIndex: Int?
        var lastOptionIndex: Int?

        for (index, line) in lines.enumerated() {
            let range = NSRange(location: 0, length: (line as NSString).length)
            if regex.firstMatch(in: line, range: range) != nil {
                if firstOptionIndex == nil { firstOptionIndex = index }
                lastOptionIndex = index
            }
        }

        guard let first = firstOptionIndex, let last = lastOptionIndex else { return nil }

        let before = lines[0..<first].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let after = (last + 1 < lines.count)
            ? lines[(last + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        return (before: before, options: options, after: after)
    }

    /// Prominent "Criar novas receitas" button shown after recipe discovery cards.
    private func createNewRecipesButton(action: QuickAction) -> some View {
        Button {
            handleCreateNewRecipes(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label.replacingOccurrences(of: "🍳 ", with: ""))
                        .font(.subheadline.weight(.semibold))
                    Text("Receitas personalizadas com a IA")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    /// Handles "Criar novas receitas" button: shows clean user message, sends full instruction to AI.
    private func handleCreateNewRecipes(_ action: QuickAction) {
        let convId = ensureConversation()

        // Show clean user message (no technical instructions)
        let userMessage = ChatMessage(role: .user, content: action.prompt, conversationId: convId)
        insertMessage(userMessage)
        inputText = ""
        errorMessage = nil

        Task {
            await performAIChat(latestUserMessageID: userMessage.id, latestUserText: action.prompt)
        }
    }

    /// Parses a recipe detail card from a structured AI response.
    /// Format: **Title**\n_Subtitle_\n\n**Ingredientes**\n- ...\n\n**Modo de Preparo**\n1. ...
    private func parseRecipeDetailCard(from message: ChatMessage) -> RecipeCardData? {
        guard message.role == .assistant else { return nil }
        let content = message.content

        // Must have both ingredients and steps sections
        guard content.contains("**Ingredientes**"),
              content.contains("**Modo de Preparo**") else { return nil }

        // Parse title: first **bold** line
        let titlePattern = #"^\*\*(.+?)\*\*\s*$"#
        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: .anchorsMatchLines) else { return nil }
        let nsContent = content as NSString
        let titleMatch = titleRegex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length))
        guard let titleRange = titleMatch?.range(at: 1) else { return nil }
        let title = nsContent.substring(with: titleRange).trimmingCharacters(in: .whitespaces)

        // Don't match recipe option lists (multiple **Name** — Description lines)
        let optionPattern = #"\*\*(.+?)\*\*\s*[—–\-]\s*(.+)"#
        if let optionRegex = try? NSRegularExpression(pattern: optionPattern) {
            let optionMatches = optionRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            if optionMatches.count >= 2 { return nil }
        }

        // Parse subtitle (italic _text_)
        var subtitle: String?
        let subtitlePattern = #"^_(.+?)_\s*$"#
        if let subRegex = try? NSRegularExpression(pattern: subtitlePattern, options: .anchorsMatchLines),
           let subMatch = subRegex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length)) {
            subtitle = nsContent.substring(with: subMatch.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }

        // Parse ingredients section
        var ingredients: [(name: String, detail: String)] = []
        if let ingredientStart = content.range(of: "**Ingredientes**"),
           let stepsStart = content.range(of: "**Modo de Preparo**") {
            let ingredientBlock = String(content[ingredientStart.upperBound..<stepsStart.lowerBound])
            let ingredientLines = ingredientBlock.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("-") || $0.hasPrefix("•") }

            for line in ingredientLines {
                let cleaned = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                // Try to split: "200g de Farinha" → detail="200g", name="Farinha"
                let dePattern = #"^(.+?)\s+de\s+(.+)$"#
                if let deRegex = try? NSRegularExpression(pattern: dePattern, options: .caseInsensitive),
                   let match = deRegex.firstMatch(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length)),
                   match.numberOfRanges >= 3 {
                    let qty = (cleaned as NSString).substring(with: match.range(at: 1))
                    let name = (cleaned as NSString).substring(with: match.range(at: 2))
                    ingredients.append((name: name.capitalizingFirstLetter(), detail: qty))
                } else {
                    ingredients.append((name: cleaned.capitalizingFirstLetter(), detail: ""))
                }
            }
        }

        // Parse steps section
        var steps: [String] = []
        if let stepsStart = content.range(of: "**Modo de Preparo**") {
            let stepsBlock = String(content[stepsStart.upperBound...])
            let stepLines = stepsBlock.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let stepPattern = #"^\d+[\.\)]\s*(.+)$"#
            let stepRegex = try? NSRegularExpression(pattern: stepPattern)
            for line in stepLines {
                if let stepRegex,
                   let match = stepRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
                   match.numberOfRanges >= 2 {
                    steps.append((line as NSString).substring(with: match.range(at: 1)))
                }
            }
        }

        guard !ingredients.isEmpty, !steps.isEmpty else { return nil }

        return RecipeCardData(
            title: title,
            subtitle: subtitle,
            ingredients: ingredients,
            steps: steps
        )
    }

    /// Adds a recipe from an inline card using the create_recipe tool.
    private func addRecipeFromCard(_ card: RecipeCardData) {
        let convId = ensureConversation()

        let ingredientArgs: [[String: Any]] = card.ingredients.map { ing in
            var dict: [String: Any] = ["name": ing.name]
            // Try to parse quantity and unit from detail (e.g. "200g" or "2 un")
            let detailPattern = #"^([\d.,/]+)\s*(.*)$"#
            if let regex = try? NSRegularExpression(pattern: detailPattern),
               let match = regex.firstMatch(in: ing.detail, range: NSRange(location: 0, length: (ing.detail as NSString).length)),
               match.numberOfRanges >= 3 {
                let qtyStr = (ing.detail as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                if let qty = Double(qtyStr) {
                    dict["quantity"] = qty
                }
                let unit = (ing.detail as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                if !unit.isEmpty { dict["unit"] = unit }
            }
            return dict
        }

        let args: [String: Any] = [
            "name": card.title,
            "description": card.subtitle ?? "",
            "category": "Outros",
            "difficulty": "Fácil",
            "ingredients": ingredientArgs,
            "steps": card.steps
        ]

        let result = AITools.createRecipeFromArgs(args, context: modelContext)

        insertMessage(ChatMessage(
            role: .assistant,
            content: result.contains("sucesso") || result.contains("Receita")
                ? "✅ Receita \"\(card.title)\" adicionada às suas receitas!"
                : "Não foi possível adicionar a receita: \(result)",
            conversationId: convId
        ))
    }

    /// Parses recipe option suggestions from AI messages (format: **Name** — Description).
    private func parseRecipeOptions(from message: ChatMessage) -> [RecipeOption]? {
        guard message.role == .assistant else { return nil }
        let content = message.content

        // Look for lines matching "**Recipe Name** — Description" or "**Recipe Name** - Description"
        let pattern = #"\*\*(.+?)\*\*\s*[—–\-]\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        guard matches.count >= 2 else { return nil } // At least 2 options to show as buttons

        return matches.prefix(8).compactMap { match -> RecipeOption? in
            guard match.numberOfRanges >= 3 else { return nil }
            let name = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let description = nsContent.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let iconFilename = IconResolver.resolve(name)
            return RecipeOption(name: name, description: description, iconFilename: iconFilename)
        }
    }
}

// MARK: - Supporting Types

struct RecipeOption: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let iconFilename: String?
}

struct RecipeCardData {
    let title: String
    let subtitle: String?
    let ingredients: [(name: String, detail: String)]
    let steps: [String]
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
