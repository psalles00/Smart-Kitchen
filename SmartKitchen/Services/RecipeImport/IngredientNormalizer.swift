import Foundation

/// Normalizes ingredient drafts post-extraction:
///   • Maps names to canonical pantry items via `ItemDatabase` (fuzzy Levenshtein ≤ 2).
///   • Canonicalizes units/states against `RecipeOptionCatalog`.
///   • Adjusts confidence based on match quality.
struct IngredientNormalizer {

    let itemDatabase: ItemDatabase
    let maxEditDistance: Int

    init(itemDatabase: ItemDatabase = .shared, maxEditDistance: Int = 2) {
        self.itemDatabase = itemDatabase
        self.maxEditDistance = maxEditDistance
    }

    func normalize(_ draft: RecipeDraft) -> RecipeDraft {
        RecipeImportLogger.info("normalizer start ingredients=\(draft.ingredients.count) utensils=\(draft.requiredUtensils.count)")
        var d = draft
        d.ingredients = d.ingredients.map {
            let normalized = normalize(ingredient: $0)
            RecipeImportLogger.debug("normalizer ingredient \(RecipeImportLogger.preview($0.name, limit: 40)) -> \(RecipeImportLogger.preview(normalized.name, limit: 40))")
            return normalized
        }
        d.requiredUtensils = d.requiredUtensils.map {
            let normalized = normalizeName($0)
            RecipeImportLogger.debug("normalizer utensil \(RecipeImportLogger.preview($0, limit: 40)) -> \(RecipeImportLogger.preview(normalized, limit: 40))")
            return normalized
        }
        RecipeImportLogger.info("normalizer completed")
        return d
    }

    // MARK: - Ingredient

    func normalize(ingredient: IngredientDraft) -> IngredientDraft {
        var i = ingredient

        // Unit normalization
        let unitRaw = i.unit.trimmingCharacters(in: .whitespaces)
        if !unitRaw.isEmpty,
           let resolved = RecipeOptionCatalog.resolve(unitRaw, for: .unit) {
            i.unit = resolved.fullName
        }

        // State normalization
        let stateRaw = i.preparationState.trimmingCharacters(in: .whitespaces)
        if !stateRaw.isEmpty,
           let resolved = RecipeOptionCatalog.resolve(stateRaw, for: .state) {
            i.preparationState = resolved.fullName
        }

        // Name → canonical entry
        let cleanedName = cleanIngredientName(i.name)
        if let exact = itemDatabase.exactMatch(for: cleanedName) {
            i.name = exact.preferredTitle(matching: cleanedName)
            i.iconName = exact.nomeDoArquivo
            i.confidence = max(i.confidence, .high)
            RecipeImportLogger.debug("normalizer exact match name=\(cleanedName)")
        } else if let match = bestFuzzyMatch(for: cleanedName) {
            i.name = match.entry.preferredTitle(matching: cleanedName)
            i.iconName = match.entry.nomeDoArquivo
            i.confidence = .medium
            RecipeImportLogger.debug("normalizer fuzzy match name=\(cleanedName) distance=\(match.distance)")
        } else {
            i.name = cleanedName.isEmpty ? i.name : cleanedName
            if i.confidence == .high { i.confidence = .medium }
            RecipeImportLogger.debug("normalizer no database match name=\(cleanedName)")
        }

        return i
    }

    // MARK: - Name cleanup

    /// Removes common "of" articles, leading measurements and filler words
    /// so matching against the database works better. Heuristic only.
    private func cleanIngredientName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip trailing punctuation.
        while let last = s.last,
              let scalar = last.unicodeScalars.first,
              CharacterSet.punctuationCharacters.contains(scalar) {
            s.removeLast()
        }

        // Remove leading articles ("de", "da", "do", "dos", "das", "of").
        let leading = ["de ", "da ", "do ", "dos ", "das ", "of "]
        var changed = true
        while changed {
            changed = false
            for prefix in leading {
                if s.lowercased().hasPrefix(prefix) {
                    s = String(s.dropFirst(prefix.count))
                    changed = true
                }
            }
        }

        // Remove parenthetical notes "(opcional)", "(a gosto)", etc.
        s = s.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fuzzy match (internal)

    struct FuzzyMatch {
        let entry: ItemEntry
        let distance: Int
    }

    func bestFuzzyMatch(for query: String) -> FuzzyMatch? {
        let normalizedQuery = Self.normalize(query)
        guard normalizedQuery.count >= 3 else { return nil }

        // Prefilter: search db for candidates sharing a prefix first.
        let candidates = itemDatabase.search(query: String(normalizedQuery.prefix(3)), limit: 50)
        var best: FuzzyMatch?

        for entry in candidates {
            for title in entry.titulos {
                let normalizedTitle = Self.normalize(title)
                // Early reject if length difference is already larger than tolerance.
                if abs(normalizedTitle.count - normalizedQuery.count) > maxEditDistance { continue }
                let distance = Self.levenshtein(normalizedQuery, normalizedTitle)
                if distance <= maxEditDistance {
                    if best == nil || distance < (best?.distance ?? Int.max) {
                        best = FuzzyMatch(entry: entry, distance: distance)
                    }
                }
            }
        }
        if let best {
            RecipeImportLogger.debug("fuzzy best query=\(query) distance=\(best.distance)")
        }
        return best
    }

    // MARK: - Utensil

    private func normalizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = itemDatabase.exactMatch(for: trimmed) {
            return exact.preferredTitle(matching: trimmed)
        }
        if let fuzzy = bestFuzzyMatch(for: trimmed) {
            return fuzzy.entry.preferredTitle(matching: trimmed)
        }
        return trimmed
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    /// Classic O(n*m) Levenshtein distance.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }

        var prev = Array(0...m)
        var curr = Array(repeating: 0, count: m + 1)

        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,
                    prev[j] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[m]
    }
}

// MARK: - FieldConfidence ordering

extension FieldConfidence: Comparable {
    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
    static func < (lhs: FieldConfidence, rhs: FieldConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}
