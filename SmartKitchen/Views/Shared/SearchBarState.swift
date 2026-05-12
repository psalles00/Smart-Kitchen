import SwiftUI
import Combine

// MARK: - Search Mode

enum SearchMode: Equatable {
    case idle
    case searching
    case aiChat
}

enum AIChatPreset: Equatable {
    case nutritionCoach
    case recipeIdeas

    var searchPlaceholder: String {
        switch self {
        case .nutritionCoach:
            return String(localized: "Converse com a IA…")
        case .recipeIdeas:
            return String(localized: "Peça ideias de receitas…")
        }
    }
}

// MARK: - Page Context for Search Prioritization

enum SearchPageContext: Equatable {
    case home
    case lists
    case recipes
    case nutrients
}

struct PendingChatMessageRequest: Equatable, Identifiable {
    let id: UUID
    let text: String
    let source: String

    init(text: String, source: String) {
        self.id = UUID()
        self.text = text
        self.source = source
    }
}

// MARK: - Search Bar State

/// Observable state shared across all pages for the unified search bar.
@MainActor
final class SearchBarState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var searchText: String = ""
    @Published var mode: SearchMode = .idle
    @Published var aiChatPreset: AIChatPreset = .nutritionCoach
    @Published var pageContext: SearchPageContext = .home

    /// Debounced version of searchText for expensive operations (search, filtering).
    /// Updates 1000ms after the user stops typing — heavy work (filters,
    /// compatibility scoring, global search) must observe THIS instead of
    /// `searchText` to avoid stalling the main thread on every keystroke.
    @Published var debouncedSearchText: String = ""

    /// `true` while the user is actively typing and `debouncedSearchText` has
    /// not caught up to `searchText` yet. Consumers can use this to display a
    /// "Buscando resultados…" indicator while the debounce window runs.
    var isDebouncing: Bool { searchText != debouncedSearchText }

    /// Triggers defocus on the TextField (incremented each time we dismiss).
    @Published var defocusTrigger: Int = 0

    /// Triggers focus request on the TextField (incremented each time we reveal).
    @Published var focusTrigger: Int = 0

    /// Triggers "execute top result" when user presses Enter (incremented each submit).
    @Published var submitTrigger: Int = 0

    /// Event-like chat send request emitted by the unified search bar in AI mode.
    /// A unique ID is required so repeated sends with the same text are never lost.
    @Published var pendingChatMessageRequest: PendingChatMessageRequest? = nil

    /// Incrementing event tokens for AI Mode header actions. Tokens are more
    /// reliable than transient booleans because repeated taps cannot be lost
    /// in a true/false race across multiple view layers.
    @Published var aiNewConversationRequestToken: Int = 0
    @Published var aiHistoryRequestToken: Int = 0

    /// Quando não-nil, a raiz do app apresenta a sheet de registro de refeição correspondente.
    @Published var pendingNutritionSheet: NutritionEntrySheet? = nil

    private var debounceCancellable: AnyCancellable?
    private var emptyResetCancellable: AnyCancellable?

    init() {
        // PERF: Debounce typing by 1000ms so heavy consumers (recipe filter,
        // global search, compatibility recomputes) stay off the typing
        // critical path. Empty-string updates are flushed immediately below
        // so clearing the field instantly restores the "all results" view.
        debounceCancellable = $searchText
            .debounce(for: .milliseconds(1000), scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.debouncedSearchText = value
            }

        // When the field becomes empty, bypass the debounce and reset the
        // debounced value right away.
        emptyResetCancellable = $searchText
            .filter { $0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.debouncedSearchText = ""
            }
    }

    /// Reveal the search bar with animation and immediate focus.
    func reveal(mode requestedMode: SearchMode? = nil) {
        if let requestedMode {
            mode = requestedMode
        }

        guard !isVisible else {
            focusTrigger += 1
            return
        }

        HapticManager.searchReveal()
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
            isVisible = true
        }
        focusTrigger += 1

        // Retry after the morph and once more after any tab/navigation switch
        // triggered by opening the assistant from another page.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isVisible else { return }
            self.focusTrigger += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, self.isVisible else { return }
            self.focusTrigger += 1
        }
    }

    /// Dismiss the search bar, clear text, and reset mode.
    func dismiss() {
        defocusTrigger += 1
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            isVisible = false
        }
        // Clear after animation starts so the text doesn't flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.searchText = ""
            self?.debouncedSearchText = ""
            self?.mode = .idle
            self?.aiChatPreset = .nutritionCoach
        }
    }

    /// Called when user selects a search result — immediate dismiss.
    func selectResult() {
        defocusTrigger += 1
        isVisible = false
        searchText = ""
        debouncedSearchText = ""
        mode = .idle
        aiChatPreset = .nutritionCoach
    }

    func requestAINewConversation(source: String) {
        aiNewConversationRequestToken += 1
        print("[AIModeUI] New conversation tapped from \(source). token=\(aiNewConversationRequestToken)")
    }

    func requestAIHistory(source: String) {
        aiHistoryRequestToken += 1
        print("[AIModeUI] History tapped from \(source). token=\(aiHistoryRequestToken)")
    }

    func requestAIChatSend(_ text: String, source: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        pendingChatMessageRequest = PendingChatMessageRequest(text: trimmedText, source: source)
        print("[AIModeUI] Chat send requested from \(source). requestId=\(pendingChatMessageRequest?.id.uuidString ?? "nil")")
    }
}
