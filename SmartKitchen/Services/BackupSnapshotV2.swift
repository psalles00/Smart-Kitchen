import Foundation
import SwiftData

// MARK: - Backup v2
//
// Pragmatic v2 format:
// - ZIP contains:
//     • manifest.json                  (version, counts, timestamps)
//     • smart-kitchen-backup.json      (full v1-compatible JSON, used for import fidelity)
//     • recipes.csv                    (human-readable, RFC 4180)
//     • items.csv                      (pantry+grocery+utensils unified)
//     • categories.csv
//     • chat.md                        (chat conversations rendered as markdown)
//     • recipes/<recipe-id>.md         (each recipe formatted as readable markdown)
//     • media/<recipe-id>/<i>.<ext>    (original media files; only when included)
// - Import detects v2 via manifest.json and reads the embedded JSON for
//   identical restore semantics to v1. CSV/MD/media are write-only outputs
//   so the user can read backups without the app.

@MainActor
enum BackupSnapshotV2 {
    static let manifestFileName = "manifest.json"
    static let canonicalJSONName = "smart-kitchen-backup.json"
    static let recipesCSVName = "recipes.csv"
    static let itemsCSVName = "items.csv"
    static let categoriesCSVName = "categories.csv"
    static let chatMarkdownName = "chat.md"

    struct Manifest: Codable {
        let version: Int
        let exportedAt: Date
        let appVersion: String?
        let recipeCount: Int
        let itemCount: Int
        let categoryCount: Int
        let chatMessageCount: Int
        let mediaCount: Int
        let mediaIncluded: Bool
    }

    /// Build the v2 ZIP from the given context. `includeMedia` controls
    /// whether recipe preparation media is bundled.
    static func makeArchive(context: ModelContext, includeMedia: Bool) throws -> Data {
        let snapshot = try AppBackupSnapshot(context: context)

        // 1) Canonical JSON (drives lossless import)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(snapshot)

        var entries: [ZipFileEntry] = []
        entries.append(ZipFileEntry(path: canonicalJSONName, data: jsonData))

        // 2) Manifest
        let mediaCount = includeMedia ? snapshot.recipePreparationMedia.count : 0
        let manifest = Manifest(
            version: 2,
            exportedAt: snapshot.exportedAt,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            recipeCount: snapshot.recipes.count,
            itemCount: snapshot.unifiedItems.count,
            categoryCount: snapshot.categories.count,
            chatMessageCount: snapshot.chatMessages.count,
            mediaCount: mediaCount,
            mediaIncluded: includeMedia
        )
        let manifestData = try encoder.encode(manifest)
        entries.append(ZipFileEntry(path: manifestFileName, data: manifestData))

        // 3) CSVs
        entries.append(ZipFileEntry(path: recipesCSVName, data: Data(recipesCSV(snapshot).utf8)))
        entries.append(ZipFileEntry(path: itemsCSVName, data: Data(itemsCSV(snapshot).utf8)))
        entries.append(ZipFileEntry(path: categoriesCSVName, data: Data(categoriesCSV(snapshot).utf8)))

        // 4) Chat markdown
        if !snapshot.chatMessages.isEmpty {
            entries.append(ZipFileEntry(path: chatMarkdownName, data: Data(chatMarkdown(snapshot).utf8)))
        }

        // 5) Per-recipe markdown
        for recipe in snapshot.recipes {
            let md = recipeMarkdown(recipe: recipe, snapshot: snapshot)
            entries.append(ZipFileEntry(path: "recipes/\(recipe.id.uuidString).md", data: Data(md.utf8)))
        }

        // 6) Media files (optional)
        if includeMedia {
            // Group media by recipe id, sorted
            let groups = Dictionary(grouping: snapshot.recipePreparationMedia, by: { $0.recipeID })
            for (recipeID, media) in groups {
                let sorted = media.sorted { $0.sortOrder < $1.sortOrder }
                for (index, m) in sorted.enumerated() {
                    let ext = m.fileExtension.isEmpty ? "bin" : m.fileExtension
                    let path = "media/\(recipeID.uuidString)/\(index).\(ext)"
                    entries.append(ZipFileEntry(path: path, data: m.data))
                }
            }

            // Include recipe cover images too (one file per recipe with cover)
            for recipe in snapshot.recipes {
                if let imgData = recipe.imageData, !imgData.isEmpty {
                    let path = "media/\(recipe.id.uuidString)/cover.jpg"
                    entries.append(ZipFileEntry(path: path, data: imgData))
                }
            }
        }

        return try MultiFileZipArchive.archive(entries)
    }

    // MARK: - Import detection

    /// Returns true if `data` is a v2 ZIP (contains manifest.json with version >= 2).
    static func isV2Archive(_ data: Data) -> Bool {
        guard let files = try? MultiFileZipArchive.extractAll(from: data) else { return false }
        guard let manifestData = files[manifestFileName] else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData) else { return false }
        return manifest.version >= 2
    }

    /// Extract the canonical JSON payload from a v2 ZIP for import.
    static func extractCanonicalJSON(from archive: Data) throws -> Data {
        let files = try MultiFileZipArchive.extractAll(from: archive)
        guard let json = files[canonicalJSONName] else {
            throw BackupTransferError.missingBackupPayload
        }
        return json
    }

    // MARK: - CSV helpers

    private static func recipesCSV(_ s: AppBackupSnapshot) -> String {
        let header = ["id", "name", "description", "category", "tags", "prep_minutes", "cook_minutes", "servings", "calories", "difficulty", "is_favorite", "external_url", "created_at", "updated_at", "ingredient_count", "step_count"]
        var rows: [[String]] = [header]
        let ingredientsByRecipe = Dictionary(grouping: s.recipeIngredients, by: { $0.recipeID })
        let stepsByRecipe = Dictionary(grouping: s.recipeSteps, by: { $0.recipeID })

        for r in s.recipes {
            rows.append([
                r.id.uuidString,
                r.name,
                r.descriptionText,
                r.category,
                r.tags.joined(separator: "; "),
                String(r.prepTime),
                String(r.cookTime),
                String(r.servings),
                r.calories.map(String.init) ?? "",
                String(describing: r.difficulty),
                r.isFavorite ? "true" : "false",
                r.externalURLString,
                isoDate(r.createdAt),
                isoDate(r.updatedAt),
                String(ingredientsByRecipe[r.id]?.count ?? 0),
                String(stepsByRecipe[r.id]?.count ?? 0)
            ])
        }
        return CSV.encode(rows)
    }

    private static func itemsCSV(_ s: AppBackupSnapshot) -> String {
        let header = ["id", "type", "name", "description", "category", "quantity", "unit", "is_pantry", "is_grocery", "is_utensil", "is_checked", "is_fixed", "expiration_date", "added_at"]
        var rows: [[String]] = [header]

        for i in s.unifiedItems {
            let type: String
            if i.isUtensil { type = "utensil" }
            else if i.isPantry && i.isGrocery { type = "pantry+grocery" }
            else if i.isPantry { type = "pantry" }
            else if i.isGrocery { type = "grocery" }
            else { type = "other" }

            rows.append([
                i.id.uuidString,
                type,
                i.name,
                i.descriptionText,
                i.category,
                i.quantity.map { String($0) } ?? "",
                i.unit ?? "",
                i.isPantry ? "true" : "false",
                i.isGrocery ? "true" : "false",
                i.isUtensil ? "true" : "false",
                i.isChecked ? "true" : "false",
                i.isFixed ? "true" : "false",
                i.expirationDate.map(isoDate) ?? "",
                isoDate(i.addedAt)
            ])
        }
        return CSV.encode(rows)
    }

    private static func categoriesCSV(_ s: AppBackupSnapshot) -> String {
        let header = ["id", "name", "type", "icon", "sort_order"]
        var rows: [[String]] = [header]
        for c in s.categories {
            rows.append([
                c.id.uuidString,
                c.name,
                String(describing: c.type),
                c.iconName ?? "",
                String(c.sortOrder)
            ])
        }
        return CSV.encode(rows)
    }

    // MARK: - Markdown helpers

    private static func recipeMarkdown(recipe r: RecipeRecord, snapshot s: AppBackupSnapshot) -> String {
        var md = "# \(r.name)\n\n"
        if !r.descriptionText.isEmpty {
            md += "\(r.descriptionText)\n\n"
        }

        md += "**ID:** `\(r.id.uuidString)`  \n"
        md += "**Categoria:** \(r.category)  \n"
        if !r.tags.isEmpty {
            md += "**Tags:** \(r.tags.joined(separator: ", "))  \n"
        }
        md += "**Porções:** \(r.servings)  \n"
        md += "**Tempo de preparo:** \(r.prepTime) min  \n"
        md += "**Tempo de cocção:** \(r.cookTime) min  \n"
        if let cal = r.calories {
            md += "**Calorias:** \(cal) kcal  \n"
        }
        md += "**Dificuldade:** \(String(describing: r.difficulty))  \n"
        md += "**Favorita:** \(r.isFavorite ? "Sim" : "Não")  \n"
        md += "**Criada em:** \(isoDate(r.createdAt))  \n"
        md += "**Atualizada em:** \(isoDate(r.updatedAt))\n\n"

        // Ingredients
        let ingredients = s.recipeIngredients
            .filter { $0.recipeID == r.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let sections = s.recipeIngredientSections
            .filter { $0.recipeID == r.id }
            .sorted { $0.sortOrder < $1.sortOrder }

        if !ingredients.isEmpty {
            md += "## Ingredientes\n\n"
            // group by sectionID
            let groups = Dictionary(grouping: ingredients, by: { $0.sectionID })
            // Default section first (nil)
            if let defaults = groups[nil], !defaults.isEmpty {
                for ing in defaults.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    md += ingredientLine(ing)
                }
                md += "\n"
            }
            for section in sections {
                guard let list = groups[section.id], !list.isEmpty else { continue }
                md += "### \(section.title)\n\n"
                if !section.subtitle.isEmpty {
                    md += "_\(section.subtitle)_\n\n"
                }
                for ing in list.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    md += ingredientLine(ing)
                }
                md += "\n"
            }
        }

        // Steps
        let steps = s.recipeSteps
            .filter { $0.recipeID == r.id }
            .sorted { $0.order < $1.order }
        if !steps.isEmpty {
            md += "## Modo de preparo\n\n"
            for step in steps {
                md += "\(step.order + 1). \(step.instruction)"
                if let dur = step.durationMinutes {
                    md += " _(≈ \(dur) min)_"
                }
                md += "\n"
            }
            md += "\n"
        }

        // Media reference
        let media = s.recipePreparationMedia
            .filter { $0.recipeID == r.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        if !media.isEmpty {
            md += "## Mídias\n\n"
            for (i, m) in media.enumerated() {
                let ext = m.fileExtension.isEmpty ? "bin" : m.fileExtension
                md += "- `media/\(r.id.uuidString)/\(i).\(ext)` (\(String(describing: m.mediaType)))\n"
            }
            md += "\n"
        }

        return md
    }

    private static func ingredientLine(_ ing: RecipeIngredientRecord) -> String {
        var line = "- "
        if let qty = ing.quantity {
            line += formatNumber(qty)
            if !ing.unit.isEmpty { line += " \(ing.unit)" }
            line += " "
        } else if !ing.unit.isEmpty {
            line += "\(ing.unit) "
        }
        line += ing.name
        if !ing.preparationState.isEmpty {
            line += " (\(ing.preparationState))"
        }
        line += "\n"
        return line
    }

    private static func chatMarkdown(_ s: AppBackupSnapshot) -> String {
        var md = "# Histórico do chat\n\n"
        let sorted = s.chatMessages.sorted { $0.timestamp < $1.timestamp }
        for msg in sorted {
            let role = String(describing: msg.role).capitalized
            md += "### \(role) — \(isoDate(msg.timestamp))\n\n"
            md += msg.content + "\n\n"
        }
        return md
    }

    // MARK: - Formatting

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}

// MARK: - CSV (RFC 4180)

enum CSV {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
