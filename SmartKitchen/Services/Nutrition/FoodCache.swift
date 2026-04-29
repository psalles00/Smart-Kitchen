import Foundation

/// Per-100g nutritional payload, locale-tagged, used as the canonical exchange
/// format between Exa lookups, the Supabase cache, and the calculator.
struct Per100gNutrition: Codable, Sendable {
    var canonicalName: String
    var locale: String
    var displayName: String?

    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var sugar: Double?
    var addedSugar: Double?
    var fiber: Double?
    var saturatedFat: Double?
    var monounsaturatedFat: Double?
    var polyunsaturatedFat: Double?
    var cholesterol: Double?
    var sodium: Double?
    var potassium: Double?

    var emoji: String?

    /// `exa`, `llm`, or `manual`. Distinguishes citation-backed data from
    /// model estimates.
    var source: String

    /// First citation URL (Exa). `nil` for LLM-sourced rows.
    var citationURL: String?

    /// Server-assigned id (only present after persistence). Used by the voting
    /// flow.
    var id: UUID?

    var upvotes: Int
    var downvotes: Int

    /// True when `kcal/protein/carbs/fat` are all present (the minimum to
    /// produce a meaningful `FoodAnalysis`).
    var hasMacros: Bool {
        kcal != nil && protein != nil && carbs != nil && fat != nil
    }
}

/// Shared remote cache of canonical foods (per-100g) backed by Supabase.
///
/// Strategy: `lookup` first; on miss the orchestrator runs Exa/LLM and calls
/// `upsert`. Users can `vote` thumbs-up/down; the server-side RPC invalidates
/// entries that drop below the trust threshold.
///
/// Silently no-ops (returns nil/throws) when Supabase is not configured — the
/// caller should still produce a valid `FoodAnalysis` via Exa/LLM directly.
@MainActor
final class FoodCache {
    static let shared = FoodCache()

    private let supabase = SupabaseClient()
    private let table = "ai_food_cache"
    private let upsertRPC = "ai_upsert_food"
    private let voteRPC = "ai_cast_food_vote"

    private let deviceIDKey = "ai.smartkitchen.foodCache.deviceID"

    var isEnabled: Bool { supabase.isConfigured }

    // MARK: - Device ID

    /// Stable anonymous UUID identifying this install for vote dedup. Generated
    /// once and persisted in `UserDefaults`. Contains no PII.
    var deviceID: UUID {
        if let raw = UserDefaults.standard.string(forKey: deviceIDKey),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        let new = UUID()
        UserDefaults.standard.set(new.uuidString, forKey: deviceIDKey)
        return new
    }

    // MARK: - Lookup

    /// Returns the cached row for `name` (already canonicalized) in the given
    /// locale, or `nil` on miss / when caching is disabled.
    func lookup(canonicalName: String, locale: String = AppLocalization.current().nutritionCacheLocaleIdentifier) async -> Per100gNutrition? {
        guard isEnabled else { return nil }

        let escapedName = urlEncode(canonicalName)
        // Server-side RLS already filters `invalidated_at IS NULL`, but we add
        // it client-side for clarity.
        let query = "canonical_name=eq.\(escapedName)&locale=eq.\(locale)&invalidated_at=is.null&limit=1"

        do {
            let rows: [SupabaseFoodRow] = try await supabase.restGET(
                table: table, query: query, as: [SupabaseFoodRow].self
            )
            guard let row = rows.first else {
                LLMLog.info("FoodCache miss \(canonicalName)")
                return nil
            }
            LLMLog.info("FoodCache hit \(canonicalName) source=\(row.source) votes=\(row.upvotes)/\(row.downvotes)")
            return row.toModel()
        } catch {
            LLMLog.error("FoodCache lookup failed for \(canonicalName): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Upsert

    /// Persists (or refreshes) a per-100g entry. Returns the server-assigned
    /// `id` so the UI can attach votes. Throws on configuration/network errors;
    /// callers may treat this as best-effort.
    @discardableResult
    func upsert(_ food: Per100gNutrition) async throws -> UUID {
        guard isEnabled else { throw SupabaseClient.SupabaseError.notConfigured }

        let params: [String: Any] = [
            "p_canonical_name": food.canonicalName,
            "p_locale": food.locale,
            "p_display_name": food.displayName as Any? ?? NSNull(),
            "p_kcal":           food.kcal             as Any? ?? NSNull(),
            "p_protein":        food.protein          as Any? ?? NSNull(),
            "p_carbs":          food.carbs            as Any? ?? NSNull(),
            "p_fat":            food.fat              as Any? ?? NSNull(),
            "p_sugar":          food.sugar            as Any? ?? NSNull(),
            "p_added_sugar":    food.addedSugar       as Any? ?? NSNull(),
            "p_fiber":          food.fiber            as Any? ?? NSNull(),
            "p_sat_fat":        food.saturatedFat     as Any? ?? NSNull(),
            "p_mono_fat":       food.monounsaturatedFat as Any? ?? NSNull(),
            "p_poly_fat":       food.polyunsaturatedFat as Any? ?? NSNull(),
            "p_cholesterol":    food.cholesterol      as Any? ?? NSNull(),
            "p_sodium":         food.sodium           as Any? ?? NSNull(),
            "p_potassium":      food.potassium        as Any? ?? NSNull(),
            "p_source":         food.source,
            "p_citation_url":   food.citationURL      as Any? ?? NSNull(),
            "p_emoji":          food.emoji            as Any? ?? NSNull()
        ]

        // RPC returns a uuid scalar; PostgREST wraps it as a JSON string.
        let id: UUID = try await supabase.rpc(upsertRPC, params: params, as: UUID.self)
        LLMLog.info("FoodCache upsert ok \(food.canonicalName) id=\(id) source=\(food.source)")
        return id
    }

    // MARK: - Voting

    enum Vote: Int {
        case up   =  1
        case down = -1
    }

    /// Sends a thumbs up/down for `foodID`. The server is idempotent per
    /// `(food_id, device_id)`; calling again replaces the previous vote.
    func vote(foodID: UUID, _ vote: Vote) async throws {
        guard isEnabled else { throw SupabaseClient.SupabaseError.notConfigured }
        let params: [String: Any] = [
            "p_food_id": foodID.uuidString,
            "p_device_id": deviceID.uuidString,
            "p_vote": vote.rawValue
        ]
        try await supabase.rpc(voteRPC, params: params, as: VoidResult.self)
        LLMLog.info("FoodCache vote \(vote.rawValue) -> \(foodID)")
    }

    // MARK: - Local vote memo

    private let votedFoodsKey = "ai.smartkitchen.foodCache.votedFoods"

    /// Records that this device has already voted on `foodID`, so the UI can
    /// hide the buttons. We keep this separate from the server roundtrip
    /// because we want optimistic UX.
    func rememberVote(_ vote: Vote, for foodID: UUID) {
        var dict = (UserDefaults.standard.dictionary(forKey: votedFoodsKey) as? [String: Int]) ?? [:]
        dict[foodID.uuidString] = vote.rawValue
        UserDefaults.standard.set(dict, forKey: votedFoodsKey)
    }

    /// Returns the previously cast vote for `foodID` on this device, if any.
    func recordedVote(for foodID: UUID) -> Vote? {
        guard let dict = UserDefaults.standard.dictionary(forKey: votedFoodsKey) as? [String: Int],
              let raw = dict[foodID.uuidString] else { return nil }
        return Vote(rawValue: raw)
    }

    // MARK: - Helpers

    /// Canonicalize a free-form food name into the cache key. Lower-cased,
    /// no diacritics, single-spaced, trimmed. Plural-stripping is intentionally
    /// minimal (only trailing 's') — a more robust normalizer can come later.
    static func canonicalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocalization.current().foldingLocale)
        let collapsed = folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

// MARK: - Wire model

/// Mirrors the `foods` table column layout. Decoupled from `Per100gNutrition`
/// so the public model can evolve independently.
private struct SupabaseFoodRow: Decodable {
    let id: String
    let canonical_name: String
    let locale: String
    let display_name: String?

    let kcal_per_100g: Double?
    let protein_per_100g: Double?
    let carbs_per_100g: Double?
    let fat_per_100g: Double?

    let sugar_per_100g: Double?
    let added_sugar_per_100g: Double?
    let fiber_per_100g: Double?
    let saturated_fat_per_100g: Double?
    let monounsaturated_fat_per_100g: Double?
    let polyunsaturated_fat_per_100g: Double?
    let cholesterol_per_100g: Double?
    let sodium_per_100g: Double?
    let potassium_per_100g: Double?

    let source: String
    let citation_url: String?
    let emoji: String?

    let upvotes: Int
    let downvotes: Int

    func toModel() -> Per100gNutrition {
        Per100gNutrition(
            canonicalName: canonical_name,
            locale: locale,
            displayName: display_name,
            kcal: kcal_per_100g,
            protein: protein_per_100g,
            carbs: carbs_per_100g,
            fat: fat_per_100g,
            sugar: sugar_per_100g,
            addedSugar: added_sugar_per_100g,
            fiber: fiber_per_100g,
            saturatedFat: saturated_fat_per_100g,
            monounsaturatedFat: monounsaturated_fat_per_100g,
            polyunsaturatedFat: polyunsaturated_fat_per_100g,
            cholesterol: cholesterol_per_100g,
            sodium: sodium_per_100g,
            potassium: potassium_per_100g,
            emoji: emoji,
            source: source,
            citationURL: citation_url,
            id: UUID(uuidString: id),
            upvotes: upvotes,
            downvotes: downvotes
        )
    }
}
