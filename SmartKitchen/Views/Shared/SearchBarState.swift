import SwiftUI
import Combine

// MARK: - Search Mode

enum SearchMode: Equatable {
    case idle
    case searching
    case aiChat
}

// MARK: - Page Context for Search Prioritization

enum SearchPageContext: Equatable {
    case home
    case lists
    case recipes
    case nutrients
}

// MARK: - Search Bar State

/// Observable state shared across all pages for the unified search bar.
@MainActor
final class SearchBarState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var searchText: String = ""
    @Published var mode: SearchMode = .idle
    @Published var pageContext: SearchPageContext = .home

    /// Debounced version of searchText for expensive operations (search, filtering).
    /// Updates 250ms after the user stops typing.
    @Published var debouncedSearchText: String = ""

    /// Triggers defocus on the TextField (incremented each time we dismiss).
    @Published var defocusTrigger: Int = 0

    /// Triggers focus request on the TextField (incremented each time we reveal).
    @Published var focusTrigger: Int = 0

    /// Triggers "execute top result" when user presses Enter (incremented each submit).
    @Published var submitTrigger: Int = 0

    /// Message to send to the AI chat (populated by the search bar in AI mode).
    @Published var pendingChatMessage: String? = nil

    private var debounceCancellable: AnyCancellable?

    init() {
        debounceCancellable = $searchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.debouncedSearchText = value
            }
    }

    /// Reveal the search bar with animation, haptic, and immediate focus.
    func reveal() {
        guard !isVisible else {
            // Already visible — just re-focus
            focusTrigger += 1
            return
        }
        HapticManager.searchReveal()
        isVisible = true
        focusTrigger += 1
        // Re-trigger focus after view transition completes (tab bar press timing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.focusTrigger += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.focusTrigger += 1
        }
    }

    /// Dismiss the search bar, clear text, and reset mode.
    func dismiss() {
        defocusTrigger += 1
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isVisible = false
        }
        // Clear after animation starts so the text doesn't flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.searchText = ""
            self?.debouncedSearchText = ""
            self?.mode = .idle
        }
    }

    /// Called when user selects a search result — immediate dismiss.
    func selectResult() {
        defocusTrigger += 1
        isVisible = false
        searchText = ""
        debouncedSearchText = ""
        mode = .idle
    }
}
