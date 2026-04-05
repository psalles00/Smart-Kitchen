import Foundation
import SwiftData

/// Cross-model search engine with ranked results for the Command Bar.
@MainActor
final class UniversalSearchService: ObservableObject {

    @Published var results: [SearchResult] = []
    @Published var suggestions: [ItemEntry] = []
    @Published var isSearching = false

    private var debounceTask: Task<Void, Never>?

    /// Perform a search across all data sources.
    /// SwiftData queries are debounced; ItemDatabase results are immediate.
    func search(query: String, context: ModelContext, showUtensils: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Immediate: ItemDatabase suggestions (in-memory, very fast)
        suggestions = ItemDatabase.shared.search(query: trimmed, limit: 20)

        // Debounce SwiftData queries
        debounceTask?.cancel()
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            let found = performSearch(query: trimmed, context: context, showUtensils: showUtensils)
            guard !Task.isCancelled else { return }
            self.results = found
            self.isSearching = false
        }
    }

    func clear() {
        debounceTask?.cancel()
        results = []
        suggestions = []
        isSearching = false
    }

    // MARK: - Private

    private func performSearch(query: String, context: ModelContext, showUtensils: Bool) -> [SearchResult] {
        let normalized = Self.normalize(query)
        var all: [SearchResult] = []

        // 1. Pantry items
        let pantryFD = FetchDescriptor<PantryItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let pantryItems = (try? context.fetch(pantryFD)) ?? []
        for item in pantryItems {
            if let score = Self.matchScore(normalized, against: item.name) {
                let recencyBoost = Self.recencyBoost(item.addedAt)
                all.append(SearchResult(
                    id: "pantry-\(item.id)",
                    title: item.name,
                    subtitle: item.formattedQuantity.isEmpty ? item.category : "\(item.category) · \(item.formattedQuantity)",
                    icon: "refrigerator",
                    type: .pantryItem,
                    score: score + recencyBoost,
                    objectID: item.id,
                    iconFilename: item.iconName
                ))
            }
        }

        // 2. Grocery items
        let groceryFD = FetchDescriptor<GroceryItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let groceryItems = (try? context.fetch(groceryFD)) ?? []
        for item in groceryItems {
            if let score = Self.matchScore(normalized, against: item.name) {
                let recencyBoost = Self.recencyBoost(item.addedAt)
                all.append(SearchResult(
                    id: "grocery-\(item.id)",
                    title: item.name,
                    subtitle: item.isChecked ? "✓ \(item.category)" : item.category,
                    icon: "cart",
                    type: .groceryItem,
                    score: score + recencyBoost,
                    objectID: item.id,
                    iconFilename: item.iconName
                ))
            }
        }

        // 3. Recipes
        let recipeFD = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let recipes = (try? context.fetch(recipeFD)) ?? []
        for recipe in recipes {
            if let score = Self.matchScore(normalized, against: recipe.name) {
                let recencyBoost = Self.recencyBoost(recipe.updatedAt)
                all.append(SearchResult(
                    id: "recipe-\(recipe.id)",
                    title: recipe.name,
                    subtitle: recipe.totalTime > 0 ? "\(recipe.category) · \(recipe.totalTime) min" : recipe.category,
                    icon: "book.closed",
                    type: .recipe,
                    score: score + recencyBoost,
                    objectID: recipe.id,
                    iconFilename: nil
                ))
            }
        }

        // 4. Utensils (if enabled)
        if showUtensils {
            let utensilFD = FetchDescriptor<UtensilItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
            let utensils = (try? context.fetch(utensilFD)) ?? []
            for item in utensils {
                if let score = Self.matchScore(normalized, against: item.name) {
                    all.append(SearchResult(
                        id: "utensil-\(item.id)",
                        title: item.name,
                        subtitle: item.category,
                        icon: "fork.knife",
                        type: .utensil,
                        score: score,
                        objectID: item.id,
                        iconFilename: item.iconName
                    ))
                }
            }
        }

        // Sort by score descending
        return all.sorted { $0.score > $1.score }
    }

    // MARK: - Scoring

    /// Returns a match score (0–100) or nil if no match.
    private static func matchScore(_ query: String, against name: String) -> Double? {
        let normalizedName = normalize(name)
        if normalizedName == query { return 100 }          // exact
        if normalizedName.hasPrefix(query) { return 80 }   // prefix
        if normalizedName.contains(query) { return 50 }    // contains

        // Check individual words
        let words = normalizedName.split(separator: " ")
        for word in words {
            if word.hasPrefix(query) { return 60 }         // word-prefix
        }

        return nil
    }

    /// Small boost (0–5) for recently added/modified items.
    private static func recencyBoost(_ date: Date) -> Double {
        let hours = abs(date.timeIntervalSinceNow) / 3600
        if hours < 1 { return 5 }
        if hours < 24 { return 3 }
        if hours < 168 { return 1 } // 7 days
        return 0
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
