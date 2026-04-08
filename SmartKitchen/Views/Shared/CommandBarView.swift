import SwiftUI
import SwiftData

/// The action the user selected from the Command Bar.
enum CommandBarAction {
    case openPantryItem(UUID)
    case openGroceryItem(UUID)
    case openRecipe(UUID)
    case openUtensil(UUID)
    case addPantryItem(prefill: String)
    case addGroceryItem(prefill: String)
    case addItem(prefill: String, iconFileName: String?, category: String?)
    case addRecipe(prefill: String)
    case addUtensil(prefill: String)
    case askAssistant(prefill: String)
    case openAssistant
}

// MARK: - Phrase Detection

/// Heuristic: if the query has 4+ words or contains question markers, treat it as a question.
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

// MARK: - iOS Native Search Tab Content

/// View displayed inside the iOS 26 native search tab. Receives query from `.searchable()` binding.
struct CommandBarSearchContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissSearch) private var dismissSearch
    @Query private var settingsArray: [AppSettings]

    @Binding var query: String
    @ObservedObject var searchService: UniversalSearchService
    let onAction: (CommandBarAction) -> Void
    var onDismiss: (() -> Void)? = nil

    /// External trigger to open inline chat (set by ContentView when navigating from Home or command bar).
    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool

    @State private var selectedIndex = 0

    // Inline chat state
    @State var showInlineChat = false
    @State var chatInitialQuery: String? = nil
    @State var chatExistingConversationId: UUID? = nil
    @State var showConversationHistory = false

    private var settings: AppSettings? { settingsArray.first }

    init(
        query: Binding<String>,
        searchService: UniversalSearchService,
        onAction: @escaping (CommandBarAction) -> Void,
        onDismiss: (() -> Void)? = nil,
        pendingChatQuery: Binding<String?> = .constant(nil),
        pendingOpenChat: Binding<Bool> = .constant(false)
    ) {
        self._query = query
        self.searchService = searchService
        self.onAction = onAction
        self.onDismiss = onDismiss
        self._pendingChatQuery = pendingChatQuery
        self._pendingOpenChat = pendingOpenChat
    }

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
                    },
                    onShowHistory: {
                        showConversationHistory = true
                    }
                )
            } else {
                searchContent
            }
        }
        .onChange(of: pendingChatQuery) { _, newValue in
            if let query = newValue {
                chatInitialQuery = query
                chatExistingConversationId = nil
                showInlineChat = true
                pendingChatQuery = nil
            }
        }
        .onChange(of: pendingOpenChat) { _, newValue in
            if newValue {
                chatInitialQuery = nil
                chatExistingConversationId = nil
                showInlineChat = true
                pendingOpenChat = false
            }
        }
    }

    private var searchContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        assistantHeader
                        emptyStateContent
                    } else {
                        searchResultsContent
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if !searchService.results.isEmpty && newIndex < searchService.results.count {
                    proxy.scrollTo(searchService.results[newIndex].id, anchor: .center)
                }
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    /// Opens the inline chat, optionally with an initial query.
    func openChat(initialQuery: String? = nil, existingConversationId: UUID? = nil) {
        chatInitialQuery = initialQuery
        chatExistingConversationId = existingConversationId
        showInlineChat = true
    }

    // MARK: - Assistant Header

    private var assistantHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Assistente")
                .font(.title2.bold())
            Text("Adicione ou busque itens e receitas, ou converse com a IA.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            let recentActions = RecentActionsStore.shared.actions
            if !recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recentes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    VStack(spacing: 2) {
                        ForEach(recentActions.prefix(5)) { recent in
                            Button {
                                handleRecentAction(recent)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: CommandBarHelpers.recentIcon(for: recent.type))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(CommandBarHelpers.recentTint(for: recent.type))
                                        .frame(width: 30, height: 30)
                                        .background(CommandBarHelpers.recentTint(for: recent.type).opacity(0.12), in: .rect(cornerRadius: 8))

                                    Text(recent.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(CommandBarHelpers.recentTypeLabel(for: recent.type))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Ações rápidas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 4) {
                    CommandBarHelpers.quickActionRow(title: "Novo Item da Despensa", icon: "refrigerator", tint: .orange) {
                        onAction(.addPantryItem(prefill: ""))
                    }
                    CommandBarHelpers.quickActionRow(title: "Novo Item do Mercado", icon: "cart.badge.plus", tint: .green) {
                        onAction(.addGroceryItem(prefill: ""))
                    }
                    CommandBarHelpers.quickActionRow(title: "Nova Receita", icon: "book.badge.plus", tint: .red) {
                        onAction(.addRecipe(prefill: ""))
                    }
                    CommandBarHelpers.quickActionRow(title: "Conversar com IA", icon: "sparkles", tint: .blue) {
                        openChat()
                    }
                }
            }

        }
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)

        return VStack(alignment: .leading, spacing: 16) {
            // Results
            if !searchService.results.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resultados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    ForEach(Array(searchService.results.prefix(10).enumerated()), id: \.element.id) { index, result in
                        CommandBarResultRow(
                            result: result,
                            isPreSelected: index == selectedIndex
                        ) {
                            executeResult(result)
                        }
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
                }
            }
        }
    }

    private func actionButtonsSection(query: String, isQuestion: Bool) -> some View {
        let hasResults = !searchService.results.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            if !hasResults {
                Text("Nenhum resultado encontrado")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }

            Text("Ações")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            let actions = CommandBarHelpers.orderedActions(query: query, isQuestion: isQuestion)

            VStack(spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    let isFirst = index == 0 && !hasResults
                    CommandBarHelpers.actionButton(
                        title: item.title,
                        icon: item.icon,
                        tint: item.tint,
                        isHighlighted: isFirst
                    ) {
                        // Intercept ask-assistant to open inline chat
                        if item.id == "ask-assistant" {
                            openChat(initialQuery: query)
                        } else {
                            item.perform(query, onAction)
                        }
                    }
                }
            }
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
        case .pantryItem:  onAction(.openPantryItem(objectID))
        case .groceryItem: onAction(.openGroceryItem(objectID))
        case .recipe:      onAction(.openRecipe(objectID))
        case .utensil:     onAction(.openUtensil(objectID))
        case .suggestion:  onAction(.addPantryItem(prefill: result.title))
        case .action:      break
        }
    }

    private func handleRecentAction(_ recent: RecentAction) {
        guard let objectID = recent.objectID,
              let type = SearchResultType(rawValue: recent.type) else { return }
        switch type {
        case .pantryItem:  onAction(.openPantryItem(objectID))
        case .groceryItem: onAction(.openGroceryItem(objectID))
        case .recipe:      onAction(.openRecipe(objectID))
        case .utensil:     onAction(.openUtensil(objectID))
        default: break
        }
    }
}

// MARK: - macOS Command Bar (sheet-based)

/// macOS-only Command Bar presented as a sheet/overlay.
struct CommandBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]

    @StateObject private var searchService = UniversalSearchService()

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isTextFieldFocused: Bool

    let onAction: (CommandBarAction) -> Void

    private var settings: AppSettings? { settingsArray.first }
    private var showUtensils: Bool { settings?.showUtensils == true }

    var body: some View {
        VStack(spacing: 0) {
            macInputBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emptyStateContent
                    } else {
                        searchResultsContent
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 40, y: 12)
        .onAppear {
            isTextFieldFocused = true
        }
        #if os(macOS)
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        #endif
    }

    private var macInputBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Buscar, adicionar ou perguntar…", text: $query)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit { executeTopResult() }
                .onChange(of: query) { _, newValue in
                    selectedIndex = 0
                    searchService.search(query: newValue, context: modelContext, showUtensils: showUtensils)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    searchService.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            let recentActions = RecentActionsStore.shared.actions
            if !recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recentes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    VStack(spacing: 2) {
                        ForEach(recentActions.prefix(5)) { recent in
                            Button {
                                handleRecentAction(recent)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: CommandBarHelpers.recentIcon(for: recent.type))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(CommandBarHelpers.recentTint(for: recent.type))
                                        .frame(width: 30, height: 30)
                                        .background(CommandBarHelpers.recentTint(for: recent.type).opacity(0.12), in: .rect(cornerRadius: 8))

                                    Text(recent.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(CommandBarHelpers.recentTypeLabel(for: recent.type))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Ações rápidas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 4) {
                    CommandBarHelpers.quickActionRow(title: "Novo Item da Despensa", icon: "refrigerator", tint: .orange) {
                        onAction(.addPantryItem(prefill: ""))
                        dismiss()
                    }
                    CommandBarHelpers.quickActionRow(title: "Novo Item do Mercado", icon: "cart.badge.plus", tint: .green) {
                        onAction(.addGroceryItem(prefill: ""))
                        dismiss()
                    }
                    CommandBarHelpers.quickActionRow(title: "Nova Receita", icon: "book.badge.plus", tint: .red) {
                        onAction(.addRecipe(prefill: ""))
                        dismiss()
                    }
                    CommandBarHelpers.quickActionRow(title: "Conversar com IA", icon: "sparkles", tint: .blue) {
                        onAction(.openAssistant)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)

        return VStack(alignment: .leading, spacing: 16) {
            if !searchService.results.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resultados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    ForEach(Array(searchService.results.prefix(10).enumerated()), id: \.element.id) { index, result in
                        CommandBarResultRow(
                            result: result,
                            isPreSelected: index == selectedIndex
                        ) {
                            executeResult(result)
                        }
                        .id(result.id)
                        .padding(.horizontal, 4)
                    }
                }
            }

            actionButtonsSection(query: trimmedQuery, isQuestion: isQuestion)

            if !searchService.suggestions.isEmpty && !isQuestion {
                CommandBarSuggestionChips(
                    suggestions: Array(searchService.suggestions.prefix(12))
                ) { entry in
                    onAction(.addItem(prefill: entry.preferredTitle(), iconFileName: entry.nomeDoArquivo, category: entry.categoria))
                    dismiss()
                }
            }
        }
    }

    private func actionButtonsSection(query: String, isQuestion: Bool) -> some View {
        let hasResults = !searchService.results.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            if !hasResults {
                Text("Nenhum resultado encontrado")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
            }

            Text("Ações")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            let actions = CommandBarHelpers.orderedActions(query: query, isQuestion: isQuestion)

            VStack(spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    let isFirst = index == 0 && !hasResults
                    CommandBarHelpers.actionButton(
                        title: item.title,
                        icon: item.icon,
                        tint: item.tint,
                        isHighlighted: isFirst
                    ) {
                        item.perform(query, onAction)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Execution

    private func executeTopResult() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = looksLikeQuestion(trimmedQuery)

        if !searchService.results.isEmpty && !isQuestion {
            let index = min(selectedIndex, searchService.results.count - 1)
            executeResult(searchService.results[index])
        } else if isQuestion && !trimmedQuery.isEmpty {
            onAction(.askAssistant(prefill: trimmedQuery))
            dismiss()
        } else if !trimmedQuery.isEmpty {
            let actions = CommandBarHelpers.orderedActions(query: trimmedQuery, isQuestion: false)
            if let first = actions.first {
                first.perform(trimmedQuery, onAction)
            }
            dismiss()
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
        case .pantryItem:  onAction(.openPantryItem(objectID))
        case .groceryItem: onAction(.openGroceryItem(objectID))
        case .recipe:      onAction(.openRecipe(objectID))
        case .utensil:     onAction(.openUtensil(objectID))
        case .suggestion:  onAction(.addPantryItem(prefill: result.title))
        case .action:      break
        }
        dismiss()
    }

    private func moveSelection(_ delta: Int) {
        let count = searchService.results.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func handleRecentAction(_ recent: RecentAction) {
        guard let objectID = recent.objectID,
              let type = SearchResultType(rawValue: recent.type) else { return }
        switch type {
        case .pantryItem:  onAction(.openPantryItem(objectID))
        case .groceryItem: onAction(.openGroceryItem(objectID))
        case .recipe:      onAction(.openRecipe(objectID))
        case .utensil:     onAction(.openUtensil(objectID))
        default: break
        }
        dismiss()
    }
}

// MARK: - Shared Helpers

/// Shared UI components and logic for both iOS and macOS command bar.
@MainActor
enum CommandBarHelpers {

    struct ActionItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        let perform: (String, (CommandBarAction) -> Void) -> Void
    }

    /// Returns actions ordered by relevance. If the query looks like a question,
    /// "ask assistant" is promoted to first position.
    static func orderedActions(query: String, isQuestion: Bool) -> [ActionItem] {
        let askAssistant = ActionItem(
            id: "ask-assistant",
            title: "Perguntar à IA sobre \"\(query)\"",
            icon: "sparkles",
            tint: .blue
        ) { q, action in action(.askAssistant(prefill: q)) }

        let addPantry = ActionItem(
            id: "add-pantry",
            title: "Adicionar \"\(query)\" à Despensa",
            icon: "plus.circle.fill",
            tint: .orange
        ) { q, action in action(.addPantryItem(prefill: q)) }

        let addGrocery = ActionItem(
            id: "add-grocery",
            title: "Adicionar \"\(query)\" ao Mercado",
            icon: "plus.circle.fill",
            tint: .green
        ) { q, action in action(.addGroceryItem(prefill: q)) }

        let createRecipe = ActionItem(
            id: "create-recipe",
            title: "Criar receita com \"\(query)\"",
            icon: "book.badge.plus",
            tint: .red
        ) { q, action in action(.addRecipe(prefill: q)) }

        if isQuestion {
            return [askAssistant, addPantry, addGrocery, createRecipe]
        } else {
            return [addPantry, addGrocery, createRecipe, askAssistant]
        }
    }

    static func quickActionRow(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 8))

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    static func actionButton(title: String, icon: String, tint: Color, isHighlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isHighlighted ? .white : tint)

                Text(title)
                    .font(.subheadline.weight(isHighlighted ? .bold : .medium))
                    .foregroundStyle(isHighlighted ? .white : .primary)
                    .lineLimit(1)

                Spacer()

                if isHighlighted {
                    Image(systemName: "return")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isHighlighted ? 12 : 10)
            .background(
                isHighlighted ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.06)),
                in: .rect(cornerRadius: isHighlighted ? 12 : 10)
            )
            .padding(.horizontal, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    static func recentIcon(for type: String) -> String {
        switch type {
        case "pantryItem":  "refrigerator"
        case "groceryItem": "cart"
        case "recipe":      "book.closed"
        case "utensil":     "fork.knife"
        default:            "clock"
        }
    }

    static func recentTint(for type: String) -> Color {
        switch type {
        case "pantryItem":  .orange
        case "groceryItem": .green
        case "recipe":      .red
        case "utensil":     .purple
        default:            .secondary
        }
    }

    static func recentTypeLabel(for type: String) -> String {
        switch type {
        case "pantryItem":  "Despensa"
        case "groceryItem": "Mercado"
        case "recipe":      "Receita"
        case "utensil":     "Utensílio"
        default:            ""
        }
    }
}
