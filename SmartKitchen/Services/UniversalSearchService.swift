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
    /// ItemDatabase suggestions update immediately. SwiftData queries remain
    /// briefly debounced so typing stays responsive while the catalog feels
    /// instant.
    func search(query: String, context: ModelContext, showUtensils: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cancel any in-flight debounced search.
        debounceTask?.cancel()

        guard !trimmed.isEmpty else {
            results = []
            suggestions = []
            isSearching = false
            return
        }

        let suggestionStart = DispatchTime.now()
        suggestions = ItemDatabase.shared.search(query: trimmed, limit: 20)
        let suggestionMs = Self.elapsedMilliseconds(since: suggestionStart)
        PerformanceLogger.event(
            .assistant,
            "catalog suggestions ready",
            metadata: "flow=assistantSearch query=\(trimmed) count=\(suggestions.count) tookMs=\(String(format: "%.1f", suggestionMs))"
        )

        isSearching = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }

            let searchStart = DispatchTime.now()
            let found = self.performSearch(query: trimmed, context: context, showUtensils: showUtensils)
            guard !Task.isCancelled else { return }

            self.results = found
            self.isSearching = false
            let searchMs = Self.elapsedMilliseconds(since: searchStart)
            PerformanceLogger.event(
                .assistant,
                "swiftdata results ready",
                metadata: "flow=assistantSearch query=\(trimmed) count=\(found.count) tookMs=\(String(format: "%.1f", searchMs))"
            )
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

        // 1. Unified items (pantry / grocery / utensil)
        let itemFD = FetchDescriptor<UnifiedItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let items = (try? context.fetch(itemFD)) ?? []
        for item in items {
            // Skip utensil-only items when utensils are hidden
            if !showUtensils && item.isUtensil && !item.isPantry && !item.isGrocery { continue }

            guard let score = Self.matchScore(normalized, against: item.name) else { continue }
            let recencyBoost = Self.recencyBoost(item.addedAt)

            // Determine primary type & subtitle
            let primaryType: SearchResultType
            let icon: String
            var subtitle = item.localizedCategoryDisplayName
            if item.isPantry {
                primaryType = .pantryItem
                icon = "refrigerator"
                let qty = item.formattedQuantity
                if !qty.isEmpty { subtitle = "\(item.localizedCategoryDisplayName) · \(qty)" }
            } else if item.isGrocery {
                primaryType = .groceryItem
                icon = "cart"
                if item.isChecked { subtitle = "✓ \(item.localizedCategoryDisplayName)" }
            } else {
                primaryType = .utensil
                icon = "fork.knife"
            }

            var result = SearchResult(
                id: "item-\(item.id)",
                title: item.name,
                subtitle: subtitle,
                icon: icon,
                type: primaryType,
                score: score + recencyBoost,
                objectID: item.id,
                iconFilename: item.iconName,
                imageData: nil
            )
            result.isAlsoInOtherList = item.activeFlags.count > 1
            var types: [SearchResultType] = []
            if item.isPantry { types.append(.pantryItem) }
            if item.isGrocery { types.append(.groceryItem) }
            if item.isUtensil { types.append(.utensil) }
            result.listTypes = types
            all.append(result)
        }

        // 2. Recipes
        let recipeFD = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let recipes = (try? context.fetch(recipeFD)) ?? []
        for recipe in recipes {
            if let score = Self.matchScore(normalized, against: recipe.name) {
                let recencyBoost = Self.recencyBoost(recipe.updatedAt)
                all.append(SearchResult(
                    id: "recipe-\(recipe.id)",
                    title: recipe.name,
                    subtitle: recipe.totalTime > 0 ? "\(recipe.localizedCategorySummary) · \(recipe.totalTime) min" : recipe.localizedCategorySummary,
                    icon: "book.closed",
                    type: .recipe,
                    score: score + recencyBoost,
                    objectID: recipe.id,
                    iconFilename: nil,
                    imageData: recipe.imageData
                ))
            }
        }

        return all.sorted { $0.score > $1.score }
    }

    // MARK: - Scoring

    /// Returns a match score (0–100) or nil if no match.
    private static func matchScore(_ query: String, against name: String) -> Double? {
        let normalizedName = normalize(name)
        if normalizedName == query { return 100 }          // exact
        if normalizedName.hasPrefix(query) { return 80 }   // prefix

        // Check individual words
        let words = normalizedName.split(separator: " ")
        for word in words {
            if word.hasPrefix(query) { return 60 }         // word-prefix
        }

        // For short queries (< 4 chars), skip substring-contains to avoid noise
        if query.count >= 4 && normalizedName.contains(query) { return 50 }

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

    private static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000.0
    }
}
