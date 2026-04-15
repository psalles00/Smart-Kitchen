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

    /// Triggers focus request on the TextField (incremented each time we reveal).
    @Published var focusTrigger: Int = 0

    /// Triggers "execute top result" when user presses Enter (incremented each submit).
    @Published var submitTrigger: Int = 0

    /// Reveal the search bar with animation, haptic, and immediate focus.
    func reveal() {
        guard !isVisible else {
            // Already visible — just re-focus
            focusTrigger += 1
            return
        }
        HapticManager.searchReveal()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            isVisible = true
        }
        // Delay focus so the TextField is in the hierarchy when focus fires
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.focusTrigger += 1
        }
        // Second attempt in case the first was too early (e.g. tab bouncing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.focusTrigger += 1
        }
    }

    /// Dismiss the search bar, clear text, and reset mode.
    func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isVisible = false
        }
        // Clear after animation starts so the text doesn't flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.searchText = ""
            self?.mode = .idle
        }
    }

    /// Called when user selects a search result — immediate dismiss.
    func selectResult() {
        isVisible = false
        searchText = ""
        mode = .idle
    }
}
