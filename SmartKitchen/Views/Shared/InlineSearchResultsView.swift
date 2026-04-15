import SwiftUI
import SwiftData

// MARK: - Inline Search Results View

/// Search results & AI chat rendered inline inside the content area of ExpandedPageLayout.
/// Appears as an overlay when the user starts typing in the UnifiedSearchBar.
struct InlineSearchResultsView: View {
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService
    let onAction: (CommandBarAction) -> Void

    // Inline chat state
    @State private var showInlineChat = false
    @State private var chatInitialQuery: String? = nil
    @State private var chatExistingConversationId: UUID? = nil
    @State private var showConversationHistory = false

    /// External trigger to open chat.
    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    var body: some View {
        Group {
            if showConversationHistory {
                ConversationHistoryView(
                    onSelect: { conversationId in
                        chatExistingConversationId = conversationId
                        chatInitialQuery = nil
                        showConversationHistory = false
                        showInlineChat = true
                    },
                    onDismiss: {
                        showConversationHistory = false
                    }
                )
            } else if showInlineChat {
                InlineChatView(
                    initialQuery: chatInitialQuery,
                    existingConversationId: chatExistingConversationId,
                    onDismiss: {
                        showInlineChat = false
                        chatInitialQuery = nil
                        chatExistingConversationId = nil
                        searchBarState.dismiss()
                    },
                    onShowHistory: {
                        showConversationHistory = true
                    },
                    searchBarState: searchBarState,
                    pendingExternalMessage: Binding(
                        get: { searchBarState.pendingChatMessage },
                        set: { searchBarState.pendingChatMessage = $0 }
                    )
                )
            } else {
                searchResultsList
            }
        }
        .onChange(of: pendingChatQuery) { _, newValue in
            if let query = newValue {
                chatInitialQuery = query
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
                pendingChatQuery = nil
            }
        }
        .onChange(of: pendingOpenChat) { _, newValue in
            if newValue {
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
                pendingOpenChat = false
            }
        }
        .onChange(of: searchBarState.submitTrigger) { _, _ in
            executeTopResult()
        }
        .onChange(of: searchBarState.mode) { _, newMode in
            if newMode != .aiChat && showInlineChat {
                showInlineChat = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
            }
        }
        .onChange(of: pendingNewConversation) { _, newValue in
            if newValue {
                pendingNewConversation = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
                searchBarState.searchText = ""
            }
        }
        .onChange(of: pendingShowHistory) { _, newValue in
            if newValue {
                pendingShowHistory = false
                showConversationHistory = true
            }
        }
        .onAppear {
            // Handle pending flags that were set before the view appeared
            // (.onChange doesn't fire for values already set at appearance time)
            if pendingOpenChat {
                pendingOpenChat = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
            }
            if let query = pendingChatQuery {
                pendingChatQuery = nil
                chatInitialQuery = query
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
            }
            if pendingNewConversation {
                pendingNewConversation = false
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showInlineChat = true
                searchBarState.mode = .aiChat
                searchBarState.searchText = ""
            }
            if pendingShowHistory {
                pendingShowHistory = false
                showConversationHistory = true
            }
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        let trimmedQuery = searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)
        let isTyping = searchBarState.searchText != searchBarState.debouncedSearchText

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Ask AI as first result when query looks like a question
                if isQuestion && !trimmedQuery.isEmpty {
                    Button {
                        openChat(initialQuery: trimmedQuery)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.purple)
                                .frame(width: 36, height: 36)
                                .background(Color.purple.opacity(0.12), in: .rect(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Perguntar à IA")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(trimmedQuery)
                                    .font(.caption)
                                    .foregroundStyle(.primary.opacity(0.55))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            ZStack {
                                Circle()
                                    .stroke(lineWidth: 3.5)
                                    .foregroundStyle(Color(.tertiarySystemFill))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "return")
                                    .font(.system(size: 30 * 0.38, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }

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
                                onQuickAction: quickActionForResult(result),
                                onReverseAction: reverseActionForResult(result)
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
                        suggestions: Array(searchService.suggestions.prefix(12))
                    ) { entry in
                        onAction(.addItem(prefill: entry.preferredTitle(), iconFileName: entry.nomeDoArquivo, category: entry.categoria))
                        searchBarState.selectResult()
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 70)
        }
        .scrollDismissesKeyboard(.interactively)
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

                let rows = stride(from: 0, to: actions.count, by: 2).map { i in
                    Array(actions[i..<min(i + 2, actions.count)])
                }
                VStack(spacing: 6) {
                    ForEach(rows, id: \.first!.id) { pair in
                        HStack(spacing: 6) {
                            ForEach(pair, id: \.id) { item in
                                CommandBarHelpers.compactActionButton(
                                    title: item.title,
                                    icon: item.icon,
                                    tint: item.tint
                                ) {
                                    if item.id == "ask-assistant" {
                                        openChat(initialQuery: query)
                                    } else {
                                        item.perform(query, onAction)
                                        searchBarState.selectResult()
                                    }
                                }
                            }
                            if pair.count == 1 {
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Helpers

    private func openChat(initialQuery: String? = nil) {
        chatInitialQuery = initialQuery
        chatExistingConversationId = nil
        showInlineChat = true
        searchBarState.mode = .aiChat
        searchBarState.searchText = ""
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

    /// Reverse action: move the item back by name (since the original UUID is gone after moves).
    private func reverseActionForResult(_ result: SearchResult) -> (() -> Void)? {
        let name = result.title
        switch result.type {
        case .pantryItem:
            // Was moved to grocery, now move back to pantry
            return { onAction(.moveGroceryToPantryByName(name)) }
        case .groceryItem:
            // Was moved to pantry, now move back to grocery
            return { onAction(.movePantryToGroceryByName(name)) }
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
            let actions = CommandBarHelpers.orderedActions(query: trimmedQuery, isQuestion: false)
            if let first = actions.first {
                first.perform(trimmedQuery, onAction)
            }
            searchBarState.selectResult()
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
