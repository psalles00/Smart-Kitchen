import SwiftUI
import SwiftData

// MARK: - Inline Search Results View

/// Search results & AI chat rendered inline inside the content area of ExpandedPageLayout.
/// Appears as an overlay when the user starts typing in the UnifiedSearchBar.
struct InlineSearchResultsView: View {
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService
    let onAction: (CommandBarAction) -> Void
    let topPinnedInset: CGFloat
    @Binding var isScrollAtTop: Bool

    // Inline chat state
    @State private var showInlineChat = false
    @State private var chatInitialQuery: String? = nil
    @State private var chatExistingConversationId: UUID? = nil
    @State private var showConversationHistory = false
    /// Relay for pending external messages — each request carries a unique ID so
    /// repeated sends with equal text are still delivered exactly once.
    @State private var pendingExternalChatRequest: PendingChatMessageRequest? = nil
    /// Relay for triggering a new conversation reset on the InlineChatView when
    /// it is already presented (the global `pendingNewConversation` only opens
    /// the chat or resets state at this layer).
    @State private var newConversationRelay: Bool = false
    @State private var lastHandledNewConversationToken: Int
    @State private var lastHandledHistoryToken: Int

    /// External trigger to open chat.
    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool
    /// When true, suppress the empty-area tap-to-dismiss in the results list and
    /// in the inline chat. Used by the search-tab AI page.
    var disableEmptyTapDismiss: Bool = false

    private var scrollTopThreshold: CGFloat {
        AssistantScrollMetrics.topThreshold(forTopPadding: topPinnedInset)
    }

    init(
        searchBarState: SearchBarState,
        searchService: UniversalSearchService,
        onAction: @escaping (CommandBarAction) -> Void,
        topPinnedInset: CGFloat,
        isScrollAtTop: Binding<Bool> = .constant(true),
        pendingChatQuery: Binding<String?>,
        pendingOpenChat: Binding<Bool>,
        pendingNewConversation: Binding<Bool>,
        pendingShowHistory: Binding<Bool>,
        disableEmptyTapDismiss: Bool = false
    ) {
        self.searchBarState = searchBarState
        self.searchService = searchService
        self.onAction = onAction
        self.topPinnedInset = topPinnedInset
        _isScrollAtTop = isScrollAtTop
        _pendingChatQuery = pendingChatQuery
        _pendingOpenChat = pendingOpenChat
        _pendingNewConversation = pendingNewConversation
        _pendingShowHistory = pendingShowHistory
        self.disableEmptyTapDismiss = disableEmptyTapDismiss

        let shouldShowHistory = pendingShowHistory.wrappedValue
        let shouldOpenChat = searchBarState.mode == .aiChat
            || pendingOpenChat.wrappedValue
            || pendingNewConversation.wrappedValue
            || pendingChatQuery.wrappedValue != nil

        _showConversationHistory = State(initialValue: shouldShowHistory)
        _showInlineChat = State(initialValue: shouldOpenChat && !shouldShowHistory)
        _chatInitialQuery = State(initialValue: pendingChatQuery.wrappedValue)
        _lastHandledNewConversationToken = State(initialValue: searchBarState.aiNewConversationRequestToken)
        _lastHandledHistoryToken = State(initialValue: searchBarState.aiHistoryRequestToken)
    }

    var body: some View {
        Group {
            if showConversationHistory {
                conversationHistoryContent
            } else if showInlineChat {
                inlineChatContent
            } else {
                searchResultsList
            }
        }
        .onChange(of: pendingChatQuery) { _, newValue in
            if let query = newValue {
                chatInitialQuery = query
                chatExistingConversationId = nil
                showConversationHistory = false
                showInlineChat = true
                searchBarState.mode = .aiChat
                pendingChatQuery = nil
            }
        }
        .onChange(of: pendingOpenChat) { _, newValue in
            if newValue {
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showConversationHistory = false
                showInlineChat = true
                searchBarState.mode = .aiChat
                pendingOpenChat = false
            }
        }
        .onChange(of: searchBarState.pendingChatMessageRequest) { _, newValue in
            if let request = newValue {
                searchBarState.pendingChatMessageRequest = nil
                if showInlineChat {
                    // Chat already open — relay via @State Binding
                    pendingExternalChatRequest = request
                } else {
                    // Open the inline chat when the unified search bar sends a pending chat message
                    chatInitialQuery = request.text
                    chatExistingConversationId = nil
                    showConversationHistory = false
                    showInlineChat = true
                    searchBarState.mode = .aiChat
                }
            }
        }
        .onChange(of: searchBarState.submitTrigger) { _, _ in
            executeTopResult()
        }
        .onChange(of: searchBarState.aiNewConversationRequestToken) { _, newValue in
            guard newValue != lastHandledNewConversationToken else { return }
            lastHandledNewConversationToken = newValue
            handleNewConversationRequest(source: "searchBarState token \(newValue)")
        }
        .onChange(of: searchBarState.aiHistoryRequestToken) { _, newValue in
            guard newValue != lastHandledHistoryToken else { return }
            lastHandledHistoryToken = newValue
            handleHistoryRequest(source: "searchBarState token \(newValue)")
        }
        .onChange(of: searchBarState.mode) { _, newMode in
            if newMode == .aiChat && !showInlineChat && !showConversationHistory {
                // Ensure chat view is shown whenever mode enters AI chat
                showInlineChat = true
            } else if newMode != .aiChat && showInlineChat {
                showInlineChat = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
            }
        }
        .onChange(of: pendingNewConversation) { _, newValue in
            if newValue {
                pendingNewConversation = false
                handleNewConversationRequest(source: "legacy pendingNewConversation")
            }
        }
        .onChange(of: pendingShowHistory) { _, newValue in
            if newValue {
                pendingShowHistory = false
                handleHistoryRequest(source: "legacy pendingShowHistory")
            }
        }
        .onAppear {
            // Handle pending flags that were set before the view appeared
            // (.onChange doesn't fire for values already set at appearance time)
            if pendingOpenChat {
                pendingOpenChat = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showConversationHistory = false
                showInlineChat = true
                searchBarState.mode = .aiChat
            }
            if let query = pendingChatQuery {
                pendingChatQuery = nil
                chatInitialQuery = query
                chatExistingConversationId = nil
                showConversationHistory = false
                showInlineChat = true
                searchBarState.mode = .aiChat
            }
            if pendingNewConversation {
                pendingNewConversation = false
                handleNewConversationRequest(source: "onAppear legacy pendingNewConversation")
            }
            if pendingShowHistory {
                pendingShowHistory = false
                handleHistoryRequest(source: "onAppear legacy pendingShowHistory")
            }
        }
    }

    private var conversationHistoryContent: some View {
        ConversationHistoryView(
            showsHeader: false,
            topPinnedInset: topPinnedInset,
            isScrollAtTop: $isScrollAtTop,
            onSelect: handleConversationSelection,
            onDismiss: closeConversationHistory
        )
    }

    private var inlineChatContent: some View {
        InlineChatView(
            initialQuery: chatInitialQuery,
            existingConversationId: chatExistingConversationId,
            onDismiss: dismissInlineChat,
            onShowHistory: presentConversationHistory,
            topPinnedInset: topPinnedInset,
            searchBarState: searchBarState,
            isScrollAtTop: $isScrollAtTop,
            pendingExternalMessage: $pendingExternalChatRequest,
            pendingNewConversationTrigger: $newConversationRelay,
            onConversationCreated: { id in
                chatExistingConversationId = id
            },
            dismissOnEmptyTap: !disableEmptyTapDismiss
        )
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        let trimmedQuery = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)
        let isTyping = searchBarState.searchText != searchBarState.debouncedSearchText

        return GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollOffsetReader(coordinateSpace: "AssistantSearchResultsScroll")

                    // Loading indicator while debouncing
                    if (isTyping || searchService.isSearching) && !trimmedQuery.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Buscando resultados…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }

                    // Results
                    if !searchService.results.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resultados")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.6))
                                .padding(.horizontal, 16)

                            ForEach(Array(searchService.results.prefix(10).enumerated()), id: \.element.id) { index, result in
                                CommandBarResultRow(
                                    result: result,
                                    isPreSelected: index == 0,
                                    action: {
                                        executeResult(result)
                                    },
                                    onNavigate: navigateActionForResult(result),
                                    onQuickAction: quickActionForResult(result)
                                )
                                .id(result.id)
                                .padding(.horizontal, 4)
                            }
                        }
                    }

                    // Action buttons
                    actionButtonsSection(query: trimmedQuery, isQuestion: isQuestion)

                    // Suggestions from item database
                    if !searchService.suggestions.isEmpty && !isQuestion {
                        CommandBarSuggestionChips(
                            suggestions: Array(searchService.suggestions.prefix(12)),
                            query: trimmedQuery
                        ) { entry in
                            onAction(.addCatalogItemToGrocery(name: entry.preferredTitle(matching: trimmedQuery), iconFileName: entry.nomeDoArquivo, category: entry.categoria))
                            searchBarState.selectResult()
                        }
                    }

                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .modifier(
                            ConditionalEmptyTapDismissResultsModifier(
                                enabled: !disableEmptyTapDismiss,
                                onDismiss: { searchBarState.dismiss() }
                            )
                        )
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .padding(.top, topPinnedInset)
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: "AssistantSearchResultsScroll")
            .onScrollOffsetChange { offset in
                isScrollAtTop = offset >= scrollTopThreshold
            }
            .onAppear {
                isScrollAtTop = true
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Action Buttons

    private func actionButtonsSection(query: String, isQuestion: Bool) -> some View {
        let hasResults = !searchService.results.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            if !hasResults && !query.isEmpty {
                Text("Nenhum resultado encontrado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if !query.isEmpty {
                Text("Ações")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 16)

                let actions = CommandBarHelpers.orderedActions(query: query, isQuestion: isQuestion)
                let activeActionID = hasResults && !isQuestion ? nil : actions.first?.id

                actionPairRows(actions: actions, activeActionID: activeActionID, query: query)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Helpers

    private func actionPairRows(
        actions: [CommandBarHelpers.ActionItem],
        activeActionID: String?,
        query: String
    ) -> some View {
        let rows = stride(from: 0, to: actions.count, by: 2).map { index in
            Array(actions[index..<min(index + 2, actions.count)])
        }

        return VStack(spacing: 6) {
            ForEach(rows, id: \.first!.id) { pair in
                CompactActionPairRow(items: pair, activeActionID: activeActionID) { item in
                    handleActionSelection(item, query: query)
                }
                .id(actionPairIdentity(for: pair, query: query, activeActionID: activeActionID))
            }
        }
    }

    private func handleActionSelection(_ item: CommandBarHelpers.ActionItem, query: String) {
        if item.id == "ask-assistant" {
            openChat(initialQuery: query)
        } else {
            item.perform(query, onAction)
            searchBarState.selectResult()
        }
    }

    private func actionPairIdentity(
        for pair: [CommandBarHelpers.ActionItem],
        query: String,
        activeActionID: String?
    ) -> String {
        pair.map(\.id).joined(separator: "|") + "|" + query + "|" + (activeActionID ?? "")
    }

    private func openChat(initialQuery: String? = nil) {
        searchBarState.resignFocus()
        chatInitialQuery = initialQuery
        chatExistingConversationId = nil
        showConversationHistory = false
        showInlineChat = true
        searchBarState.aiChatPreset = .nutritionCoach
        searchBarState.mode = .aiChat
        searchBarState.searchText = ""
    }

    private func presentConversationHistory() {
        #if DEBUG
        print("[AIModeUI] Presenting conversation history. showInlineChat=\(showInlineChat)")
        #endif
        showConversationHistory = true
        showInlineChat = false
    }

    private func closeConversationHistory() {
        #if DEBUG
        print("[AIModeUI] Closing conversation history. mode=\(searchBarState.mode)")
        #endif
        showConversationHistory = false
        if searchBarState.mode == .aiChat {
            showInlineChat = true
        }
    }

    private func handleNewConversationRequest(source: String) {
        #if DEBUG
        print("[AIModeUI] Handling new conversation request from \(source). showInlineChat=\(showInlineChat) showConversationHistory=\(showConversationHistory)")
        #endif
        chatInitialQuery = nil
        chatExistingConversationId = nil
        searchBarState.mode = .aiChat
        searchBarState.searchText = ""
        showConversationHistory = false

        if showInlineChat {
            newConversationRelay = true
        } else {
            showInlineChat = true
        }
    }

    private func handleHistoryRequest(source: String) {
        #if DEBUG
        print("[AIModeUI] Handling history request from \(source). showInlineChat=\(showInlineChat) showConversationHistory=\(showConversationHistory)")
        #endif
        searchBarState.mode = .aiChat
        presentConversationHistory()
    }

    private func handleConversationSelection(_ conversationId: UUID) {
        chatExistingConversationId = conversationId
        chatInitialQuery = nil
        showConversationHistory = false
        showInlineChat = true
        searchBarState.aiChatPreset = .nutritionCoach
        searchBarState.mode = .aiChat
    }

    private func dismissInlineChat() {
        showInlineChat = false
        chatInitialQuery = nil
        chatExistingConversationId = nil
        searchBarState.dismiss()
    }

    private func quickActionForResult(_ result: SearchResult) -> (() -> Void)? {
        guard let objectID = result.objectID else { return nil }
        switch result.type {
        case .pantryItem:
            return { onAction(.movePantryToGrocery(objectID)) }
        case .groceryItem:
            return { onAction(.moveGroceryToPantry(objectID)) }
        default:
            return nil
        }
    }

    private func executeResult(_ result: SearchResult) {
        RecentActionsStore.shared.record(RecentAction(
            title: result.title,
            type: result.type,
            objectID: result.objectID,
            iconName: result.iconFilename
        ))
        guard let objectID = result.objectID else { return }
        switch result.type {
        case .pantryItem:  onAction(.editPantryItem(objectID))
        case .groceryItem: onAction(.editGroceryItem(objectID))
        case .recipe:      onAction(.openRecipe(objectID))
        case .utensil:     onAction(.editUtensil(objectID))
        case .suggestion:  onAction(.addPantryItem(prefill: result.title))
        case .action:      break
        }
        searchBarState.selectResult()
    }

    private func navigateActionForResult(_ result: SearchResult) -> (() -> Void)? {
        guard let objectID = result.objectID else { return nil }
        switch result.type {
        case .pantryItem:
            return { onAction(.openPantryItem(objectID)); searchBarState.selectResult() }
        case .groceryItem:
            return { onAction(.openGroceryItem(objectID)); searchBarState.selectResult() }
        case .recipe:
            return { onAction(.openRecipe(objectID)); searchBarState.selectResult() }
        case .utensil:
            return { onAction(.openUtensil(objectID)); searchBarState.selectResult() }
        default:
            return nil
        }
    }

    /// Execute the top (pre-selected) result when user presses Enter.
    private func executeTopResult() {
        let trimmedQuery = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)

        if !searchService.results.isEmpty && !isQuestion {
            executeResult(searchService.results[0])
        } else if isQuestion && !trimmedQuery.isEmpty {
            openChat(initialQuery: trimmedQuery)
        } else if !trimmedQuery.isEmpty {
            if let suggestion = searchService.suggestions.first ?? ItemDatabase.shared.search(query: trimmedQuery, limit: 1).first {
                onAction(.addCatalogItemToGrocery(name: suggestion.preferredTitle(matching: trimmedQuery), iconFileName: suggestion.nomeDoArquivo, category: suggestion.categoria))
                searchBarState.selectResult()
                return
            }

            let actions = CommandBarHelpers.orderedActions(query: trimmedQuery, isQuestion: false)
            if let first = actions.first {
                first.perform(trimmedQuery, onAction)
            }
            searchBarState.selectResult()
        }
    }
}

private struct CompactActionPairRow: View {
    let items: [CommandBarHelpers.ActionItem]
    let activeActionID: String?
    let onSelect: (CommandBarHelpers.ActionItem) -> Void

    @State private var rowHeight: CGFloat?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(items) { item in
                CommandBarHelpers.compactActionButton(
                    item: item,
                    isHighlighted: item.id == activeActionID,
                    targetHeight: rowHeight
                ) {
                    onSelect(item)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: CompactActionRowHeightPreferenceKey.self, value: [item.id: proxy.size.height])
                    }
                }
            }

            if items.count == 1 {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .onPreferenceChange(CompactActionRowHeightPreferenceKey.self) { heights in
            if let tallest = heights.values.max(), rowHeight == nil || abs(tallest - (rowHeight ?? 0)) > 0.5 {
                rowHeight = tallest
            }
        }
    }
}

private struct CompactActionRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { current, new in
            max(current, new)
        }
    }
}

// MARK: - Question Detection

private func looksLikeQuestion(_ query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("?") { return true }
    let words = trimmed.split(separator: " ")
    if words.count >= 4 { return true }
    let questionStarters = ["como", "qual", "quais", "onde", "quando", "porque",
                            "por que", "o que", "quanto", "quantos", "quantas",
                            "what", "how", "where", "when", "why", "which", "can"]
    let lower = trimmed.lowercased()
    for starter in questionStarters {
        if lower.hasPrefix(starter + " ") || lower.hasPrefix(starter + ",") { return true }
    }
    return false
}

private struct ConditionalEmptyTapDismissResultsModifier: ViewModifier {
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
