import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The action the user selected from the Command Bar.
enum CommandBarAction {
    case openPantryItem(UUID)
    case openGroceryItem(UUID)
    case openRecipe(UUID)
    case openUtensil(UUID)
    case editPantryItem(UUID)
    case editGroceryItem(UUID)
    case editRecipe(UUID)
    case editUtensil(UUID)
    case addPantryItem(prefill: String)
    case addGroceryItem(prefill: String)
    case addItem(prefill: String, iconFileName: String?, category: String?)
    case addRecipe(prefill: String)
    case addUtensil(prefill: String)
    case addCatalogItemToGrocery(name: String, iconFileName: String?, category: String?)
    case registerFood(prefill: String)
    case openWeightTracker
    case askAssistant(prefill: String)
    case openAssistant
    case openAIMode
    case movePantryToGrocery(UUID)
    case moveGroceryToPantry(UUID)
    case movePantryToGroceryByName(String)
    case moveGroceryToPantryByName(String)
}

// MARK: - Phrase Detection

private func looksLikeQuestion(_ query: String) -> Bool {
    AssistantSuggestionRanker.isQuestion(query)
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
                    suggestions: Array(searchService.suggestions.prefix(12)),
                    query: trimmedQuery
                ) { entry in
                    onAction(.addCatalogItemToGrocery(name: entry.preferredTitle(matching: trimmedQuery), iconFileName: entry.nomeDoArquivo, category: entry.categoria))
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

            Text("Sugestões")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            let actions = CommandBarHelpers.orderedActions(query: query, isQuestion: isQuestion)
            let activeActionID = actions.first?.id

            VStack(spacing: 4) {
                ForEach(actions) { item in
                    CommandBarHelpers.actionButton(
                        title: CommandBarHelpers.fullWidthActionButtonTitle(item: item),
                        icon: item.icon,
                        tint: item.tint,
                        isHighlighted: item.id == activeActionID
                    ) {
                        // Intercept ask-assistant to open inline chat
                        AssistantSuggestionRanker.shared.record(actionID: item.id, query: query)
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

            TextField("Digite aqui…", text: $query)
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
                        onAction(.openAIMode)
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
                    suggestions: Array(searchService.suggestions.prefix(12)),
                    query: trimmedQuery
                ) { entry in
                    onAction(.addCatalogItemToGrocery(name: entry.preferredTitle(matching: trimmedQuery), iconFileName: entry.nomeDoArquivo, category: entry.categoria))
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

            Text("Sugestões")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            let actions = CommandBarHelpers.orderedActions(query: query, isQuestion: isQuestion)
            let activeActionID = actions.first?.id

            VStack(spacing: 4) {
                ForEach(actions) { item in
                    CommandBarHelpers.actionButton(
                        title: CommandBarHelpers.fullWidthActionButtonTitle(item: item),
                        icon: item.icon,
                        tint: item.tint,
                        isHighlighted: item.id == activeActionID
                    ) {
                        AssistantSuggestionRanker.shared.record(actionID: item.id, query: query)
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
        } else if !trimmedQuery.isEmpty,
                  let first = CommandBarHelpers.orderedActions(query: trimmedQuery, isQuestion: isQuestion).first {
            AssistantSuggestionRanker.shared.record(actionID: first.id, query: trimmedQuery)
            first.perform(trimmedQuery, onAction)
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
        let imageName: String
        let imageHeight: CGFloat
        let imageOffset: CGSize
        let perform: (String, (CommandBarAction) -> Void) -> Void
    }

    /// Returns actions ordered by relevance. If the query looks like a question,
    /// "ask assistant" is promoted to first position.
    static func orderedActions(query: String, isQuestion: Bool) -> [ActionItem] {
        let askAssistant = ActionItem(
            id: "ask-assistant",
            title: query,
            icon: "sparkles",
            tint: .blue,
            imageName: "savorai",
            imageHeight: 84,
            imageOffset: CGSize(width: 16, height: 23)
        ) { q, action in action(.askAssistant(prefill: q)) }

        let addPantry = ActionItem(
            id: "add-pantry",
            title: query,
            icon: "plus.circle.fill",
            tint: .orange,
            imageName: "despensa",
            imageHeight: 78,
            imageOffset: CGSize(width: 14, height: 21)
        ) { q, action in action(.addPantryItem(prefill: q)) }

        let addGrocery = ActionItem(
            id: "add-grocery",
            title: query,
            icon: "plus.circle.fill",
            tint: .green,
            imageName: "mercado",
            imageHeight: 81,
            imageOffset: CGSize(width: 16, height: 21)
        ) { q, action in action(.addGroceryItem(prefill: q)) }

        let createRecipe = ActionItem(
            id: "create-recipe",
            title: query,
            icon: "book.badge.plus",
            tint: .red,
            imageName: "receitas",
            imageHeight: 78,
            imageOffset: CGSize(width: 14, height: 21)
        ) { q, action in action(.addRecipe(prefill: q)) }

        let registerFood = ActionItem(
            id: "register-food-text",
            title: query,
            icon: "character.cursor.ibeam",
            tint: PageTheme.nutrients.accentColor,
            imageName: "nutrientes",
            imageHeight: 78,
            imageOffset: CGSize(width: 14, height: 21)
        ) { q, action in action(.registerFood(prefill: q)) }

        let actions = [addPantry, addGrocery, createRecipe, askAssistant, registerFood]
        let orderedIDs = AssistantSuggestionRanker.shared.orderedIDs(query: query)
        return orderedIDs.compactMap { id in actions.first { $0.id == id } }
    }

    static func fullWidthActionButtonTitle(item: ActionItem, truncate: Bool = true) -> String {
        let title = truncate ? limitedSuggestionText(item.title, limit: 40) : item.title
        switch item.id {
        case "ask-assistant":
            return String(format: String(localized: "Perguntar \"%@\" à IA"), title)
        case "add-pantry":
            return String(format: String(localized: "Adicionar \"%@\" à Despensa"), title)
        case "add-grocery":
            return String(format: String(localized: "Adicionar \"%@\" ao Mercado"), title)
        case "create-recipe":
            return String(format: String(localized: "Criar receita \"%@\""), title)
        case "register-food-text":
            return String(format: String(localized: "Registrar alimento \"%@\""), title)
        default:
            return item.title
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

                Text(limitedSuggestionText(title, limit: 80))
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

    static func compactActionButton(item: ActionItem, isHighlighted: Bool = false, targetHeight: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: isHighlighted ? 18 : 13, weight: .bold))
                    .foregroundStyle(item.tint)

                Text(fullWidthActionButtonTitle(item: item))
                    .font(isHighlighted ? .subheadline.weight(.semibold) : .caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, isHighlighted ? 62 : 32)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: max(targetHeight ?? 0, isHighlighted ? 88 : 100), alignment: .center)
            .background(item.tint.opacity(isHighlighted ? 0.22 : 0.06), in: .rect(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(item.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: isHighlighted ? 76 : 48)
                    .offset(x: 8, y: 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if isHighlighted {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.tint)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(item.tint.opacity(isHighlighted ? 0.65 : 0.12), lineWidth: isHighlighted ? 2 : 1)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fullWidthActionButtonTitle(item: item, truncate: false))
        .accessibilityIdentifier("assistant-suggestion-" + item.id)
    }

    /// Limit only the visible label; the action always receives the complete request.
    static func limitedSuggestionText(_ text: String, limit: Int) -> String {
        let compact = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard compact.count > limit else { return compact }
        return String(compact.prefix(max(0, limit - 3))).trimmingCharacters(in: .whitespaces) + "..."
    }

    static func fullWidthActionButton(
        title: String,
        icon: String,
        tint: Color,
        imageName: String,
        imageHeight: CGFloat,
        imageOffset: CGSize,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 92)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: imageHeight)
                    .offset(imageOffset)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private static func activeActionBadge(tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "return")
            Text("Enter")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(activeActionBadgeBackground, in: .capsule)
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .padding(6)
    }

    private static var activeActionBadgeBackground: Color {
        #if os(iOS)
        Color(uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            }
            return UIColor(red: 248 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            }
            return NSColor(srgbRed: 248 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
        } ?? NSColor.windowBackgroundColor)
        #else
        Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255)
        #endif
    }

    private static func compactActionButtonTitle(item: ActionItem) -> AttributedString {
        let baseText = fullWidthActionButtonTitle(item: item)
        let boldRange = "\"\(item.title)\""

        var attributed = AttributedString(baseText)
        attributed.font = .caption

        if let range = attributed.range(of: boldRange) {
            attributed[range].font = .caption.bold()
        }

        return attributed
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

/// Local, bounded learning from actual selections. No food records or CloudKit schema changes.
@MainActor
final class AssistantSuggestionRanker {
    static let shared = AssistantSuggestionRanker()
    private static let historyKey = "Savoria.assistantSuggestionSelections.v1"
    private let defaults: UserDefaults

    private struct Selection: Codable {
        let actionID: String
        let keywords: [String]
        let lengthBucket: Int
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var history: [Selection] {
        guard let data = defaults.data(forKey: Self.historyKey),
              let saved = try? JSONDecoder().decode([Selection].self, from: data) else { return [] }
        return saved
    }

    func record(actionID: String, query: String) {
        guard Self.actionIDs.contains(actionID), !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let selection = Selection(actionID: actionID, keywords: Array(Self.keywords(query).sorted().prefix(20)), lengthBucket: Self.lengthBucket(query))
        if let data = try? JSONEncoder().encode(Array((history + [selection]).suffix(200))) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    private static let actionIDs = ["add-pantry", "add-grocery", "create-recipe", "ask-assistant", "register-food-text"]

    func orderedIDs(query: String) -> [String] {
        let normalized = Self.normalize(query)
        let words = Self.keywords(query)
        let bucket = Self.lengthBucket(query)
        let selections = history
        var scores: [String: Double] = ["add-pantry": 20, "add-grocery": 18, "create-recipe": 8, "ask-assistant": 4, "register-food-text": 12]
        if bucket >= 1 { scores["register-food-text", default: 0] += 18 }
        if bucket >= 2 { scores["ask-assistant", default: 0] += 16 }
        if normalized.range(of: #"\d\s*(?:g|kg|ml|l|cs|cc|colher|cup|tbsp|tsp)\b"#, options: .regularExpression) != nil {
            scores["register-food-text", default: 0] += 45
        }
        let intents: [(String, [String])] = [
            ("add-pantry", ["despensa", "pantry", "estoque", "stock", "vorrat", "dispensa", "garde manger", "パントリー"]),
            ("add-grocery", ["comprar", "compra", "mercado", "shopping", "buy", "grocery", "comprar", "acheter", "courses", "einkaufen", "kaufen", "comprare", "spesa", "買う", "買い物"]),
            ("create-recipe", ["receita", "recipe", "receta", "recette", "rezept", "ricetta", "レシピ"]),
            ("register-food-text", ["comi", "bebi", "almocei", "jantei", "consumi", "registrar", "log", "ate", "drank", "comi", "bebi", "mange", "bu", "gegessen", "getrunken", "mangiato", "bevuto", "食べた", "飲んだ"])
        ]
        for (id, terms) in intents where terms.contains(where: { Self.contains(term: $0, in: normalized) }) {
            scores[id, default: 0] += 120
        }
        if Self.isQuestion(query) { scores["ask-assistant", default: 0] += 160 }
        for id in Self.actionIDs {
            let matches = selections.filter { $0.actionID == id }
            let keywordMatches = matches.reduce(0) { $0 + Set($1.keywords).intersection(words).count }
            let sameLength = matches.filter { $0.lengthBucket == bucket }.count
            scores[id, default: 0] += min(16, Double(matches.count) * 0.6)
                + min(32, Double(keywordMatches) * 6 / Double(max(words.count, 1)))
                + min(14, Double(sameLength) * 1.2)
        }
        return Self.actionIDs.enumerated().sorted { lhs, rhs in
            let left = scores[lhs.element, default: 0], right = scores[rhs.element, default: 0]
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    static func isQuestion(_ query: String) -> Bool {
        let text = normalize(query)
        if query.contains("?") || query.contains("？") { return true }
        let starters = ["como", "qual", "quais", "onde", "quando", "porque", "por que", "o que", "quanto", "quantos", "quantas", "what", "how", "where", "when", "why", "which", "can", "que", "cual", "donde", "cuando", "comment", "quel", "quelle", "pourquoi", "combien", "wie", "was", "warum", "welche", "come", "quale", "quando", "perche"]
        return starters.contains { text == $0 || text.hasPrefix($0 + " ") }
            || ["どう", "なぜ", "何", "どこ"].contains { text.hasPrefix($0) }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func contains(term: String, in text: String) -> Bool {
        let tokens = text.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        return term.contains(" ") ? (" " + text + " ").contains(" " + term + " ") : tokens.contains(term) || (term.first?.isASCII == false && text.contains(term))
    }

    private static func keywords(_ text: String) -> Set<String> {
        let stopwords: Set<String> = ["com", "de", "da", "do", "das", "dos", "para", "uma", "um", "the", "with", "and", "con", "avec", "und", "mit"]
        return Set(normalize(text).components(separatedBy: .alphanumerics.inverted).filter { $0.count >= 3 && !stopwords.contains($0) && Double($0) == nil })
    }

    private static func lengthBucket(_ text: String) -> Int {
        let count = text.split(whereSeparator: { $0.isWhitespace }).count
        return count >= 12 || text.count > 100 ? 2 : (count >= 4 ? 1 : 0)
    }
}
