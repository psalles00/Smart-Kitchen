import SwiftUI
import SwiftData

/// Chat view embedded inline in the Assistente search tab.
/// Manages a single conversation with the AI, including tool execution, recipe discovery, and confirmation flows.
struct InlineChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openRecipeInRecipesTab) private var openRecipeInRecipesTab
    @Query private var settingsArray: [AppSettings]
    @Query private var nutritionProfiles: [NutritionProfile]
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

    // Recipe Ideas wizard state (apenas usado quando aiChatPreset == .recipeIdeas)
    /// Override por sessão do filtro "apenas itens da despensa". `nil` = usa AppSettings.
    @State private var wizardPantryFilterOverride: Bool? = nil
    /// Flag que mostra o loader enquanto buscamos ideias na EXA.
    @State private var isLoadingExaIdeas: Bool = false
    /// Seed incremental para "Gerar mais ideias".
    @State private var exaSearchSeed: Int = 0

    private var apiKey: String { APIConfig.openAIAPIKey }
    private let confirmPrompt = "__confirm_pending_ai_change__"
    private let cancelPrompt = "__cancel_pending_ai_change__"

    /// Optional initial query to auto-send on appear.
    let initialQuery: String?
    /// Called when the user taps back to return to search mode.
    let onDismiss: () -> Void
    /// Called when viewing conversation history.
    let onShowHistory: () -> Void
    /// Top inset reserved for the parent pinned header+gradient overlay.
    let topPinnedInset: CGFloat
    /// Shared search bar state — when provided, the unified search bar acts as input.
    var searchBarState: SearchBarState? = nil
    @Binding var isScrollAtTop: Bool
    /// External message to send (received from the unified search bar).
    @Binding var pendingExternalMessage: String?
    /// Called when a new conversation is created, so the parent can track the active ID.
    var onConversationCreated: ((UUID) -> Void)? = nil
    /// When `false`, tapping the empty area below the chat does NOT trigger
    /// `onDismiss()`. Used by the search-tab AI page where the only way out
    /// is the explicit "Voltar" button.
    var dismissOnEmptyTap: Bool = true

    /// Current conversation ID. Nil means a new conversation will be created on first message.
    @State private var conversationId: UUID?
    /// If set, we're viewing an existing conversation (can still continue it).
    let existingConversationId: UUID?

    @State private var messages: [ChatMessage] = []
    @State private var hasSentInitialQuery = false
    @State private var showScrollToBottom: Bool = false
    @State private var chatAreaHeight: CGFloat = 0
    @State private var pinnedUserMessageID: UUID?

    init(
        initialQuery: String? = nil,
        existingConversationId: UUID? = nil,
        onDismiss: @escaping () -> Void,
        onShowHistory: @escaping () -> Void,
        topPinnedInset: CGFloat = 0,
        searchBarState: SearchBarState? = nil,
        isScrollAtTop: Binding<Bool> = .constant(true),
        pendingExternalMessage: Binding<String?> = .constant(nil),
        onConversationCreated: ((UUID) -> Void)? = nil,
        dismissOnEmptyTap: Bool = true
    ) {
        self.initialQuery = initialQuery
        self.existingConversationId = existingConversationId
        self.onDismiss = onDismiss
        self.onShowHistory = onShowHistory
        self.topPinnedInset = topPinnedInset
        self.searchBarState = searchBarState
        self._isScrollAtTop = isScrollAtTop
        self._pendingExternalMessage = pendingExternalMessage
        self.onConversationCreated = onConversationCreated
        self.dismissOnEmptyTap = dismissOnEmptyTap
    }

    /// Whether this chat is in "AI Mode" (embedded with unified search bar) vs standalone assistant.
    private var isAIMode: Bool { searchBarState != nil }
    private var aiChatPreset: AIChatPreset { searchBarState?.aiChatPreset ?? .nutritionCoach }

    private var settings: AppSettings? { settingsArray.first }

    private var coachStarterPrompts: [String] {
        guard nutritionProfiles.first?.hasCompletedOnboarding == true,
              let goal = nutritionProfiles.first?.weightGoal else {
            return [
                "Qual é meu peso esperado em 30 dias?",
                "O que devo comer no jantar?",
                "Como bato minha meta?",
                "Como está minha tendência?"
            ]
        }

        switch goal {
        case .lose:
            return [
                "Qual é meu peso esperado em 30 dias?",
                "Como posso emagrecer mais rápido com segurança?",
                "Estou comendo demais?",
                "O que devo comer no jantar?"
            ]
        case .gain:
            return [
                "Qual é meu peso esperado em 30 dias?",
                "Como posso ganhar peso de forma saudável?",
                "Estou comendo o suficiente?",
                "Quais alimentos ricos em proteína posso adicionar?"
            ]
        case .maintain:
            return [
                "Estou mantendo meu peso?",
                "Qual é meu consumo médio?",
                "Sugestões de macros?",
                "Como está minha tendência?"
            ]
        }
    }

    private var recipeIdeasStarterPrompts: [String] {
        [
            "Sugira novas receitas de jantar rápido.",
            "Sugira novas receitas com frango e legumes.",
            "Sugira novas receitas vegetarianas simples.",
            "Sugira novas receitas de sobremesa."
        ]
    }

    private var aiModeDescription: String {
        switch aiChatPreset {
        case .nutritionCoach:
            return "Seu coach pode ver seu histórico de peso, consumo diário e metas. Pergunte sobre peso esperado, o que comer ou como atingir seu objetivo."
        case .recipeIdeas:
            return "Crie ideias novas partindo do zero ou com os ingredientes que você quiser usar."
        }
    }

    private var aiModeStarterPrompts: [String] {
        switch aiChatPreset {
        case .nutritionCoach:
            return coachStarterPrompts
        case .recipeIdeas:
            return recipeIdeasStarterPrompts
        }
    }

    private var aiToolDefinitions: [[String: Any]] {
        AITools.definitions(excluding: ["create_recipe"])
    }

    private var scrollTopThreshold: CGFloat {
        AssistantScrollMetrics.topThreshold(forTopPadding: isAIMode ? topPinnedInset : 12)
    }

    private var pinnedMessageRevealInset: CGFloat {
        isAIMode ? topPinnedInset : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hide own header when the parent panel provides one
            if searchBarState == nil {
                chatHeader
            }

            // Chat messages
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ScrollOffsetReader(coordinateSpace: "AssistantInlineChatScroll")

                            if messages.isEmpty && !aiService.isLoading && !isLoadingExaIdeas {
                                if isAIMode {
                                    aiModeEmptyState
                                } else {
                                    emptyState
                                }
                            }

                            if !messages.isEmpty && !isAIMode {
                                SuggestionChipsView { prompt in
                                    sendMessage(prompt)
                                }
                                .padding(.top, 8)
                            }

                            ForEach(messages) { message in
                                VStack(spacing: 0) {
                                    if pinnedUserMessageID == message.id {
                                        Color.clear
                                            .frame(height: pinnedMessageRevealInset)
                                            .id(pinnedMessageAnchorID(for: message.id))
                                    }

                                    VStack(spacing: 6) {
                                        if message.role == .system {
                                            // Skip system messages
                                        } else if let wizardKind = wizardSentinelKind(for: message) {
                                            wizardMessageView(message: message, kind: wizardKind)
                                        } else if parseRecipeDetailCard(from: message) != nil {
                                            if let card = parseRecipeDetailCard(from: message) {
                                                RecipeDetailCard(recipe: card) {
                                                    addRecipeFromCard(card)
                                                }
                                            }
                                        } else if !message.attachedRecipeIds.isEmpty {
                                            ChatBubbleView(
                                                message: message,
                                                onQuickAction: { _ in },
                                                hideQuickActions: true
                                            )
                                            RecipeCardMessage(recipeIds: message.attachedRecipeIds)
                                            if !isAIMode {
                                                ForEach(message.quickActions) { action in
                                                    createNewRecipesButton(action: action)
                                                }
                                            }
                                        } else if !isAIMode, let split = splitMessageAroundOptions(message) {
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
                                            ChatBubbleView(
                                                message: message,
                                                onQuickAction: { action in
                                                    sendMessage(action.prompt)
                                                },
                                                hideQuickActions: isAIMode
                                            )
                                        }
                                    }
                                }
                                .id(message.id)
                            }

                            if aiService.isLoading {
                                typingIndicator
                                    .id("typing")
                            }

                            if isLoadingExaIdeas {
                                typingIndicator
                                    .id("typingExa")
                            }

                            // Invisible bottom anchor for scroll tracking
                            Color.clear.frame(height: 1)
                                .id("bottomAnchor")
                                .onAppear { showScrollToBottom = false }
                                .onDisappear { showScrollToBottom = true }

                            // Bottom spacer — allows user messages to always scroll to the top
                            // of the chat area even when there isn't enough content below
                            Color.clear
                                .frame(height: max(chatAreaHeight - 80, 0))
                                .contentShape(Rectangle())
                                .modifier(
                                    ConditionalEmptyTapDismissModifier(
                                        enabled: dismissOnEmptyTap,
                                        onDismiss: onDismiss
                                    )
                                )
                        }
                        .padding(.top, isAIMode ? topPinnedInset : 12)
                        .padding(.bottom, 12)
                    }
                    .coordinateSpace(name: "AssistantInlineChatScroll")
                    .onScrollOffsetChange { offset in
                        isScrollAtTop = offset >= scrollTopThreshold
                    }
                    .onAppear {
                        isScrollAtTop = true
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chatAreaHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, newH in chatAreaHeight = newH }
                        }
                    )
                    .onChange(of: messages.count) { oldCount, newCount in
                        guard newCount > oldCount,
                              let pinnedUserMessageID,
                              messages.contains(where: { $0.id == pinnedUserMessageID }) else { return }

                        withAnimation(.snappy(duration: 0.28)) {
                            proxy.scrollTo(pinnedMessageAnchorID(for: pinnedUserMessageID), anchor: .top)
                        }
                    }

                    // Floating "scroll to bottom" button
                    if showScrollToBottom {
                        Button {
                            withAnimation(.easeOut(duration: 0.4)) {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                        .transition(.scale.combined(with: .opacity))
                    }
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
            RecipeDetailContainer(recipeID: id)
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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Como posso ajudar?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Pergunte sobre receitas, gerencie sua despensa ou descubra o que cozinhar com o que você tem.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            SuggestionChipsView { prompt in
                sendMessage(prompt)
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - AI Mode Empty State

    @ViewBuilder
    private var aiModeEmptyState: some View {
        if aiChatPreset == .recipeIdeas {
            recipeIdeasKickoffState
        } else {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(spacing: 8) {
                    Text("Modo IA")
                        .font(.title3.weight(.bold))

                    Text(aiModeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(aiModeStarterPrompts.enumerated()), id: \.offset) { index, prompt in
                        aiSuggestionRow(emoji: aiSuggestionEmoji(for: index), text: prompt)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)

                Spacer()
            }
        }
    }

    // MARK: - Recipe Ideas Wizard — Kickoff

    private var recipeIdeasKickoffState: some View {
        let occasions = RecipeIdeaOccasion.orderedForHour(Calendar.current.component(.hour, from: .now))
        let chips = occasions.map {
            RecipeIdeasChipsRow.Chip(id: $0.rawValue, label: $0.label, emoji: $0.emoji)
        }
        return VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 4)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(.linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemBackground), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("O que você quer preparar agora?")
                        .font(.subheadline.weight(.semibold))
                    Text("Toque uma opção ou escreva direto no campo abaixo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            RecipeIdeasChipsRow(chips: chips) { chip in
                guard let occasion = RecipeIdeaOccasion(rawValue: chip.id) else { return }
                handleOccasionTap(occasion)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func aiSuggestionRow(emoji: String, text: String) -> some View {
        Button {
            sendMessage(text)
        } label: {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.title3)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(neutralSurfaceColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func aiSuggestionEmoji(for index: Int) -> String {
        switch aiChatPreset {
        case .nutritionCoach:
            switch index {
            case 0: return "📈"
            case 1: return "🎯"
            case 2: return "🍽️"
            default: return "🥗"
            }
        case .recipeIdeas:
            switch index {
            case 0: return "⚡"
            case 1: return "🍗"
            case 2: return "🌿"
            default: return "🍰"
            }
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
        onConversationCreated?(conversation.id)
        return conversation.id
    }

    private func startNewConversation() {
        conversationId = nil
        messages = []
        pinnedUserMessageID = nil
        pendingToolExecution = nil
        errorMessage = nil
        cachedInventoryContext = nil
        cachedInventoryDate = nil
    }

    private func reloadMessages() {
        guard let conversationId else {
            messages = []
            pinnedUserMessageID = nil
            return
        }
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 200
        messages = (try? modelContext.fetch(descriptor)) ?? []
        pinnedUserMessageID = nil
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
        pinnedUserMessageID = userMessage.id
        inputText = ""
        errorMessage = nil

        if aiChatPreset == .recipeIdeas {
            // Texto livre vira customQuery direto na EXA.
            Task {
                await runRecipeIdeasSearch(
                    occasion: nil,
                    refinement: nil,
                    customQuery: text,
                    conversationId: convId
                )
            }
            return
        }

        if aiChatPreset != .recipeIdeas,
           let recipeDiscoveryResponse = makeRecipeDiscoveryResponse(for: text) {
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

        if aiChatPreset == .recipeIdeas {
            msgs.append([
                "role": "system",
                "content": "O usuário abriu o modo Ideias de receitas. Priorize sugerir receitas novas e criativas, em vez de listar apenas receitas já salvas. Não trate a despensa como restrição padrão; só use a despensa quando o usuário pedir isso explicitamente ou citar ingredientes que quer aproveitar."
            ])
        }

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
                Para buscar, editar e excluir receitas existentes, priorize as ferramentas de receita.
                NÃO mencione despensa, mercado, compatibilidade de ingredientes ou receitas existentes, a menos que o usuário tenha pedido isso explicitamente.
                Se o usuário pedir algo como "adicione uma receita de como fazer arroz", interprete isso como um pedido para montar uma receita nova para revisão, nunca para criá-la imediatamente no app.
                NÃO chame create_recipe nesse fluxo.
                Se houver dados suficientes, responda com a receita completa no formato do card para revisão.
                Se faltarem detalhes, faça uma pergunta objetiva antes de montar o card.
                """
            ])
        }

        return msgs
    }

    private func continueConversation(with messages: [[String: Any]], skipTools: Bool = false) async throws {
        var apiMessages = messages
        let response = try await aiService.sendChat(
            messages: apiMessages,
            tools: skipTools ? nil : aiToolDefinitions,
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
        let confirmationMessage = ChatMessage(role: .user, content: "Confirmar alteração", conversationId: convId)
        insertMessage(confirmationMessage)
        pinnedUserMessageID = confirmationMessage.id

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
        let cancellationMessage = ChatMessage(role: .user, content: "Cancelar alteração", conversationId: convId)
        insertMessage(cancellationMessage)
        pinnedUserMessageID = cancellationMessage.id
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
        4. Quando o usuário pedir para adicionar, criar ou salvar uma receita nova, NUNCA chame create_recipe durante a conversa. \
        Primeiro apresente a receita completa no formato de card descrito abaixo.
        5. O usuário só pode decidir criar/salvar a receita através do botão do card na interface. \
        Use as ferramentas de receita apenas para buscar, detalhar, editar ou excluir receitas já existentes.
        6. Antes de modificar qualquer informação do app, peça confirmação clara do usuário. \
        Só prossiga com alterações depois que o usuário confirmar explicitamente.
        7. Você também pode ler e editar categorias de despensa, mercado e receitas usando as ferramentas de categoria.
        8. Sempre formate listas de forma organizada. Use emojis quando apropriado.
        9. Se o usuário pedir para adicionar, criar, editar, atualizar, excluir, remover, apagar, cadastrar ou salvar algo, \
        trate isso como um fluxo de alteração, não como sugestão de receitas.
        10. Quando o usuário pedir para adicionar uma receita nova, NÃO baseie a resposta automaticamente na despensa. \
        Esse fluxo pode ser totalmente independente dos itens atuais do app e deve gerar uma receita-base revisável.
        11. Nunca diga que criou, salvou ou adicionou uma receita ao app antes de o usuário tocar no botão do card.
        12. Se não souber algo, diga que não sabe. Nunca invente informações.

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
        Sempre que for apresentar uma receita nova completa, seja após o usuário escolher uma opção ou após um pedido direto:
        - NÃO chame a ferramenta create_recipe. Apenas retorne o texto formatado abaixo.
        - NÃO diga que a receita já foi criada, salva ou adicionada.
        - O usuário decidirá se quer salvar a receita através de um botão no card da interface.
        - Use EXATAMENTE este formato:

        **Nome da Receita**
        _Descrição curta_
        Categoria: Nome do caderno

        **Ingredientes**
        - 200g de Ingrediente
        - 2 un de Outro Ingrediente

        **Modo de Preparo**
        1. Primeiro passo.
        2. Segundo passo.

        - Nomes dos ingredientes SEMPRE começam com letra maiúscula.
        - Inclua a linha "Categoria:" usando preferencialmente um dos cadernos existentes abaixo.
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

        let pantryDescriptor = FetchDescriptor<UnifiedItem>(sortBy: [SortDescriptor(\.category)])
        if let allItems = try? modelContext.fetch(pantryDescriptor) {
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

        inventoryParts.append(CategoryMutationService.recipeCategoryPromptSection(context: modelContext))
        inventoryParts.append(AssistantChatManager.nutritionPromptSection(context: modelContext))

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

        let pantryItems = (try? modelContext.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        let pantryNames = pantryItems.filter { $0.isPantry }.map { normalized($0.name) }
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

    private func pinnedMessageAnchorID(for messageID: UUID) -> String {
        "assistant-pinned-top-\(messageID.uuidString)"
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
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
        pinnedUserMessageID = userMessage.id
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

        var category: String?
        let categoryPattern = #"(?m)^Categoria:\s*(.+)$"#
        if let categoryRegex = try? NSRegularExpression(pattern: categoryPattern),
           let categoryMatch = categoryRegex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length)),
           categoryMatch.numberOfRanges >= 2 {
            category = nsContent.substring(with: categoryMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
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
            category: category,
            ingredients: ingredients,
            steps: steps
        )
    }

    /// Adds a recipe from an inline card using the local recipe creation flow.
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
            "category": card.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (card.category ?? "")
                : CategoryMutationService.defaultRecipeCategoryName(context: modelContext),
            "difficulty": "Fácil",
            "ingredients": ingredientArgs,
            "steps": card.steps
        ]

        let result = AITools.createRecipeFromArgs(args, context: modelContext)

        // Tenta extrair o id da nova receita do JSON retornado para abrir
        // imediatamente na aba Receitas.
        var newRecipeID: UUID? = nil
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let idStr = json["id"] as? String,
           let id = UUID(uuidString: idStr) {
            newRecipeID = id
        }

        let success = (newRecipeID != nil) || result.contains("success") || result.contains("Receita")
        insertMessage(ChatMessage(
            role: .assistant,
            content: success
                ? "✅ Receita \"\(card.title)\" adicionada às suas receitas!"
                : "Não foi possível adicionar a receita: \(result)",
            conversationId: convId
        ))

        if let newRecipeID {
            // Pequeno atraso permite a UI atualizar a bolha antes de navegar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                searchBarState?.dismiss()
                openRecipeInRecipesTab(newRecipeID)
            }
        }
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

    // MARK: - Recipe Ideas Wizard — Helpers

    /// Tipos de mensagens do wizard, identificados pelo prompt da primeira QuickAction.
    private enum WizardKind {
        case occasion                          // chips de ocasião
        case refinement(RecipeIdeaOccasion)    // chips de refinamento
        case results                           // resultados EXA + receitas locais
        case pantryBanner                      // banner de toggle inline
    }

    private func wizardSentinelKind(for message: ChatMessage) -> WizardKind? {
        guard message.role == .assistant,
              let prompt = message.quickActions.first?.prompt else { return nil }
        if prompt == RecipeIdeasSentinel.occasionPrefix { return .occasion }
        if let occ = RecipeIdeasSentinel.refinementOccasion(from: prompt) { return .refinement(occ) }
        if prompt == RecipeIdeasSentinel.resultsPrefix { return .results }
        if prompt == RecipeIdeasSentinel.pantryBannerPrefix { return .pantryBanner }
        return nil
    }

    @ViewBuilder
    private func wizardMessageView(message: ChatMessage, kind: WizardKind) -> some View {
        switch kind {
        case .occasion:
            // Sem fluxo atual a partir do histórico — mostramos apenas o texto.
            assistantTextBubble(message.content)
            let occasions = RecipeIdeaOccasion.orderedForHour(Calendar.current.component(.hour, from: .now))
            RecipeIdeasChipsRow(chips: occasions.map { .init(id: $0.rawValue, label: $0.label, emoji: $0.emoji) }) { chip in
                guard let occasion = RecipeIdeaOccasion(rawValue: chip.id) else { return }
                handleOccasionTap(occasion)
            }
        case .refinement(let occasion):
            assistantTextBubble(message.content)
            let refinements = occasion.refinements
            RecipeIdeasChipsRow(chips: refinements.map { .init(id: $0, label: $0) }) { chip in
                handleRefinementTap(chip.label, for: occasion)
            }
        case .results:
            recipeIdeasResultsView(for: message)
        case .pantryBanner:
            recipeIdeasPantryBanner(for: message)
        }
    }

    /// Tap em uma ocasião: registra mensagem do usuário, pergunta de refinamento
    /// (a menos que seja "Outro", que foca o teclado).
    private func handleOccasionTap(_ occasion: RecipeIdeaOccasion) {
        let convId = ensureConversation()

        if occasion == .outro {
            insertMessage(ChatMessage(role: .user, content: occasion.label, conversationId: convId))
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Pode escrever direto no campo abaixo o que você quer cozinhar.",
                conversationId: convId
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchBarState?.focusTrigger += 1
                isInputFocused = true
            }
            return
        }

        let userMsg = ChatMessage(role: .user, content: occasion.label, conversationId: convId)
        insertMessage(userMsg)
        pinnedUserMessageID = userMsg.id

        insertMessage(ChatMessage(
            role: .assistant,
            content: occasion.refinementQuestion,
            quickActions: [QuickAction(label: "_wizard", prompt: RecipeIdeasSentinel.refinementPrompt(for: occasion))],
            conversationId: convId
        ))
    }

    /// Tap em um refinamento: registra mensagem do usuário e dispara busca EXA.
    private func handleRefinementTap(_ refinement: String, for occasion: RecipeIdeaOccasion) {
        let convId = ensureConversation()

        if refinement == "Outro" {
            insertMessage(ChatMessage(role: .user, content: refinement, conversationId: convId))
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Diga no campo abaixo o que você procura (estilo, ingrediente principal, tempo, porções...).",
                conversationId: convId
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchBarState?.focusTrigger += 1
                isInputFocused = true
            }
            return
        }

        let userMsg = ChatMessage(role: .user, content: refinement, conversationId: convId)
        insertMessage(userMsg)
        pinnedUserMessageID = userMsg.id

        Task {
            await runRecipeIdeasSearch(
                occasion: occasion,
                refinement: refinement,
                customQuery: nil,
                conversationId: convId
            )
        }
    }

    /// Dispara busca na EXA + matching local; insere mensagem com resultados.
    private func runRecipeIdeasSearch(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?,
        conversationId: UUID
    ) async {
        isLoadingExaIdeas = true
        defer { isLoadingExaIdeas = false }

        let pantryItems = (try? modelContext.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        let pantryNames = pantryItems.filter { $0.isPantry }.map { $0.name }
        let filterEnabled = currentPantryFilterEnabled

        do {
            let results = try await EXARecipeIdeasService.shared.search(
                occasion: occasion,
                refinement: refinement,
                customQuery: customQuery,
                pantryItems: pantryNames,
                filterByPantry: filterEnabled,
                limit: 6,
                seed: exaSearchSeed
            )

            let localMatchedRecipeIDs = matchLocalRecipes(occasion: occasion, refinement: refinement, customQuery: customQuery)

            let payload = ResultsPayload(
                ideas: results,
                localRecipeIDs: localMatchedRecipeIDs,
                occasionRaw: occasion?.rawValue,
                refinement: refinement,
                customQuery: customQuery
            )

            insertMessage(ChatMessage(
                role: .assistant,
                content: payload.encoded(),
                quickActions: [QuickAction(label: "_wizard", prompt: RecipeIdeasSentinel.resultsPrefix)],
                conversationId: conversationId
            ))
        } catch let EXARecipeIdeasService.ServiceError.empty where filterEnabled && pantryNames.count <= 2 {
            // Pouca despensa + filtro ativo → oferece banner para desligar filtro.
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Não encontrei ideias usando só itens da despensa. Quer buscar sem essa restrição?",
                quickActions: [QuickAction(label: "_wizard", prompt: RecipeIdeasSentinel.pantryBannerPrefix)],
                conversationId: conversationId
            ))
        } catch {
            errorMessage = error.localizedDescription
            insertMessage(ChatMessage(
                role: .assistant,
                content: "Não consegui buscar ideias agora. \(error.localizedDescription)",
                conversationId: conversationId
            ))
        }
    }

    /// Filtro ativo (override de sessão > AppSettings).
    private var currentPantryFilterEnabled: Bool {
        if let override = wizardPantryFilterOverride { return override }
        return settings?.recipeIdeasFilterByPantry ?? true
    }

    /// Tenta encontrar receitas locais compatíveis com a ocasião/refinamento.
    private func matchLocalRecipes(
        occasion: RecipeIdeaOccasion?,
        refinement: String?,
        customQuery: String?
    ) -> [UUID] {
        let pantryItems = (try? modelContext.fetch(FetchDescriptor<UnifiedItem>())) ?? []
        let pantryNames = pantryItems.filter { $0.isPantry }.map { normalized($0.name) }

        var keywords: [String] = []
        if let occasion {
            switch occasion {
            case .cafeDaManha: keywords += ["cafe", "manha", "breakfast"]
            case .almoco: keywords += ["almoco", "lunch"]
            case .jantar: keywords += ["jantar", "dinner"]
            case .lancheRapido: keywords += ["lanche", "snack"]
            case .drinks: keywords += ["drink", "coquetel"]
            case .bebidas: keywords += ["bebida", "suco", "smoothie", "vitamina"]
            case .sobremesa: keywords += ["sobremesa", "doce", "dessert"]
            case .outro: break
            }
        }
        if let refinement { keywords.append(normalized(refinement)) }
        if let customQuery {
            customQuery.split(separator: " ").forEach { keywords.append(normalized(String($0))) }
        }

        let thresholdPercent = Double(settings?.recipeCompatibilityThresholdPercentValue ?? 80) / 100.0

        let scored: [(Recipe, Double, Int)] = allRecipes.compactMap { recipe in
            let category = normalized(recipe.category)
            let tags = recipe.tags.map(normalized)
            let name = normalized(recipe.name)
            let categoryMatches = keywords.contains(where: { kw in
                !kw.isEmpty && (category.contains(kw) || tags.contains(where: { $0.contains(kw) }) || name.contains(kw))
            })
            // Sem keywords (ocasião nil/customQuery vazio), aceita qualquer categoria.
            if !keywords.isEmpty && !categoryMatches { return nil }

            let ingredientNames = (recipe.ingredients ?? []).map { normalized($0.name) }
            guard !ingredientNames.isEmpty else { return nil }
            let score = ingredientNames.reduce(into: 0) { acc, ing in
                if pantryNames.contains(where: { $0 == ing || $0.contains(ing) || ing.contains($0) }) {
                    acc += 1
                }
            }
            let ratio = Double(score) / Double(ingredientNames.count)
            return (recipe, ratio, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }

        let filtered = scored.filter { $0.1 >= thresholdPercent }
        let chosen = filtered.isEmpty ? Array(scored.prefix(4)) : Array(filtered.prefix(4))
        return chosen.map(\.0.id)
    }

    // MARK: - Recipe Ideas Wizard — Results View

    @ViewBuilder
    private func recipeIdeasResultsView(for message: ChatMessage) -> some View {
        let payload = ResultsPayload.decode(message.content)
        VStack(alignment: .leading, spacing: 16) {
            if !payload.localRecipeIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Receitas suas")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    RecipeCardMessage(recipeIds: payload.localRecipeIDs)
                }
            }

            if !payload.ideas.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Novas ideias")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        ForEach(payload.ideas) { idea in
                            RecipeIdeaSuggestionCard(
                                title: idea.title,
                                summary: idea.summary,
                                sourceHost: idea.sourceHost,
                                heroImageURL: idea.heroImageURL,
                                mainIngredient: idea.mainIngredient
                            ) {
                                handleNewIdeaTap(idea, payload: payload)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Button {
                        handleGenerateMoreTap(payload: payload)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Gerar mais ideias")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.gradient, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            } else if payload.localRecipeIDs.isEmpty {
                Text("Não encontrei nenhuma ideia agora.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    /// Banner inline para desligar o filtro de despensa quando 0 resultados.
    @ViewBuilder
    private func recipeIdeasPantryBanner(for message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            assistantTextBubble(message.content)
            Button {
                wizardPantryFilterOverride = false
                let convId = message.conversationId ?? ensureConversation()
                Task {
                    await runRecipeIdeasSearch(
                        occasion: nil,
                        refinement: nil,
                        customQuery: lastWizardCustomContext(),
                        conversationId: convId
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "tray.full")
                    Text("Buscar sem restringir à despensa")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    /// Recupera, do histórico, a última intenção (occasion + refinement ou customQuery)
    /// para retomar a busca quando o usuário aciona o banner.
    private func lastWizardCustomContext() -> String? {
        // Heurística simples: pega as duas últimas mensagens .user e concatena.
        let userTexts = messages.filter { $0.role == .user }.suffix(2).map(\.content)
        return userTexts.isEmpty ? nil : userTexts.joined(separator: " ")
    }

    /// "Gerar mais ideias" — incrementa o seed e refaz a busca com o mesmo contexto.
    private func handleGenerateMoreTap(payload: ResultsPayload) {
        exaSearchSeed += 1
        let convId = ensureConversation()
        let occasion = payload.occasionRaw.flatMap(RecipeIdeaOccasion.init(rawValue:))
        Task {
            await runRecipeIdeasSearch(
                occasion: occasion,
                refinement: payload.refinement,
                customQuery: payload.customQuery,
                conversationId: convId
            )
        }
    }

    /// Tap em uma "Nova ideia": chama o estruturador (LLM), baixa a imagem hero
    /// em paralelo, salva como Recipe e abre na aba Receitas.
    private func handleNewIdeaTap(_ idea: RecipeIdeaResult, payload _: ResultsPayload) {
        let convId = ensureConversation()

        // Mensagem temporária de progresso.
        let loadingMessage = ChatMessage(
            role: .assistant,
            content: "✨ Escrevendo a receita \"\(idea.title)\"…",
            conversationId: convId
        )
        insertMessage(loadingMessage)
        let loadingId = loadingMessage.id

        Task {
            // Texto-base para a LLM: rawText sempre que houver, fallback para summary.
            let baseText: String = {
                if let raw = idea.rawText, !raw.isEmpty {
                    // Limita a ~6000 chars para controlar custo/latência.
                    return raw.count > 6000 ? String(raw.prefix(6000)) : raw
                }
                return idea.summary
            }()

            let hints = RecipeStructurer.Hints(
                title: idea.title,
                description: idea.summary.isEmpty ? nil : idea.summary,
                externalURL: idea.sourceURL.flatMap(URL.init(string:)),
                imageURL: idea.heroImageURL.flatMap(URL.init(string:)),
                sourceLabel: idea.sourceHost ?? "EXA"
            )

            // Estrutura + download da imagem em paralelo.
            async let structuredTask: RecipeDraft? = {
                do {
                    return try await RecipeStructurer().structure(text: baseText, hints: hints)
                } catch {
                    return nil
                }
            }()
            async let imageTask: Data? = ImageDownloader.fetch(idea.heroImageURL)

            let (draftOpt, imageData) = await (structuredTask, imageTask)

            await MainActor.run {
                // Remove mensagem de loading.
                if let idx = messages.firstIndex(where: { $0.id == loadingId }) {
                    messages.remove(at: idx)
                    try? modelContext.save()
                }

                guard var draft = draftOpt, !draft.name.isEmpty else {
                    insertMessage(ChatMessage(
                        role: .assistant,
                        content: "Não consegui estruturar essa receita agora. Tente outra ideia ou abra o link: \(idea.sourceURL ?? "—")",
                        conversationId: convId
                    ))
                    return
                }

                // Garante hero image: prioriza a baixada da EXA; senão usa a do site (já no draft.imageURL).
                if draft.imageData == nil, let data = imageData, !data.isEmpty {
                    draft.imageData = data
                }
                if draft.externalURLString.isEmpty, let url = idea.sourceURL {
                    draft.externalURLString = url
                }
                if draft.sourceLabel.isEmpty {
                    draft.sourceLabel = idea.sourceHost ?? "EXA"
                }

                let recipe = AITools.persistImportedDraft(draft, in: modelContext)
                let newRecipeID = recipe.id

                insertMessage(ChatMessage(
                    role: .assistant,
                    content: "✅ Receita \"\(recipe.name)\" adicionada às suas receitas!",
                    conversationId: convId
                ))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    searchBarState?.dismiss()
                    openRecipeInRecipesTab(newRecipeID)
                }
            }
        }
    }

    // MARK: - Results Payload (serialized into ChatMessage.content)

    private struct ResultsPayload: Codable {
        var ideas: [RecipeIdeaResult]
        var localRecipeIDs: [UUID]
        var occasionRaw: String?
        var refinement: String?
        var customQuery: String?

        func encoded() -> String {
            guard let data = try? JSONEncoder().encode(self),
                  let str = String(data: data, encoding: .utf8) else { return "{}" }
            return str
        }

        static func decode(_ raw: String) -> ResultsPayload {
            guard let data = raw.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(ResultsPayload.self, from: data) else {
                return ResultsPayload(ideas: [], localRecipeIDs: [], occasionRaw: nil, refinement: nil, customQuery: nil)
            }
            return payload
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
    let category: String?
    let ingredients: [(name: String, detail: String)]
    let steps: [String]
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}

private struct ConditionalEmptyTapDismissModifier: ViewModifier {
    let enabled: Bool
    let onDismiss: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture { onDismiss() }
        } else {
            content
        }
    }
}
