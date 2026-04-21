import Foundation

/// Extracts recipe data from a fetched HTML document.
/// Strategy, in order:
///   1. Parse JSON-LD `<script type="application/ld+json">` blocks, look for schema.org Recipe.
///   2. Read OpenGraph / Twitter meta tags for title/description/image fallback.
///   3. Return a raw cleaned text representation for the AI structurer as a last resort.
struct HTMLRecipeExtractor {

    struct Result {
        /// `draft` is `nil` when the page has no Recipe schema — caller should
        /// fall back to the AI structurer using `cleanedText`.
        var draft: RecipeDraft?
        var ogTitle: String?
        var ogDescription: String?
        var ogImageURL: URL?
        var cleanedText: String
    }

    // MARK: - Entry

    static func extract(html: String, sourceURL: URL) -> Result {
        let jsonLDBlocks = findJSONLDBlocks(in: html)
        let ogTitle = findMetaContent(in: html, property: "og:title")
            ?? findMetaContent(in: html, name: "twitter:title")
        let ogDescription = findMetaContent(in: html, property: "og:description")
            ?? findMetaContent(in: html, name: "twitter:description")
        let ogImage = findMetaContent(in: html, property: "og:image")
            ?? findMetaContent(in: html, name: "twitter:image")

        var draft: RecipeDraft? = nil
        for block in jsonLDBlocks {
            if let parsed = parseRecipeFromJSONLD(block, sourceURL: sourceURL) {
                draft = parsed
                break
            }
        }

        // Enrich draft with OG fallback data if anything is missing.
        if var d = draft {
            if d.name.isEmpty, let t = ogTitle { d.name = t; d.nameConfidence = .medium }
            if d.descriptionText.isEmpty, let desc = ogDescription { d.descriptionText = desc; d.descriptionConfidence = .medium }
            if d.imageURL == nil, let raw = ogImage, let url = URL(string: raw) { d.imageURL = url }
            if d.externalURLString.isEmpty { d.externalURLString = sourceURL.absoluteString }
            d.sourceLabel = sourceURL.host ?? "Web"
            draft = d
        }

        return Result(
            draft: draft,
            ogTitle: ogTitle,
            ogDescription: ogDescription,
            ogImageURL: ogImage.flatMap(URL.init(string:)),
            cleanedText: cleanText(html: html)
        )
    }

    // MARK: - JSON-LD

    private static func findJSONLDBlocks(in html: String) -> [Any] {
        // Match both `<script type="application/ld+json">` and any combination of spaces/quotes.
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsHtml = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
        var results: [Any] = []
        for match in matches where match.numberOfRanges >= 2 {
            let body = nsHtml.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                results.append(obj)
            }
        }
        return results
    }

    private static func parseRecipeFromJSONLD(_ root: Any, sourceURL: URL) -> RecipeDraft? {
        // Root may be a Recipe, a graph `{ "@graph": [...] }`, or an array.
        let candidates = flattenJSONLD(root)
        for candidate in candidates {
            guard let dict = candidate as? [String: Any] else { continue }
            if isRecipeType(dict["@type"]) {
                return buildDraft(from: dict, sourceURL: sourceURL)
            }
        }
        return nil
    }

    private static func flattenJSONLD(_ value: Any) -> [Any] {
        if let dict = value as? [String: Any] {
            var out: [Any] = [dict]
            if let graph = dict["@graph"] {
                out.append(contentsOf: flattenJSONLD(graph))
            }
            return out
        }
        if let arr = value as? [Any] {
            return arr.flatMap { flattenJSONLD($0) }
        }
        return []
    }

    private static func isRecipeType(_ raw: Any?) -> Bool {
        if let s = raw as? String { return s.localizedCaseInsensitiveContains("Recipe") }
        if let arr = raw as? [String] { return arr.contains(where: { $0.localizedCaseInsensitiveContains("Recipe") }) }
        return false
    }

    private static func buildDraft(from dict: [String: Any], sourceURL: URL) -> RecipeDraft {
        var draft = RecipeDraft()
        draft.externalURLString = sourceURL.absoluteString
        draft.sourceLabel = sourceURL.host ?? "Web"

        draft.name = stripHTML(string(from: dict["name"])) ?? ""
        draft.nameConfidence = draft.name.isEmpty ? .low : .high

        draft.descriptionText = stripHTML(string(from: dict["description"])) ?? ""
        draft.descriptionConfidence = draft.descriptionText.isEmpty ? .low : .high

        if let s = firstString(from: dict["image"]) ?? stringInsideObject(dict["image"], key: "url") {
            draft.imageURL = URL(string: s)
        }

        if let servingsText = string(from: dict["recipeYield"]) {
            if let s = parseInt(servingsText) {
                draft.servings = max(1, s)
                draft.servingsConfidence = .high
            }
        }

        if let prep = parseISODuration(string(from: dict["prepTime"])) {
            draft.prepTime = prep
            draft.prepTimeConfidence = .high
        }
        if let cook = parseISODuration(string(from: dict["cookTime"])) {
            draft.cookTime = cook
            draft.cookTimeConfidence = .high
        }
        if draft.prepTime == 0 && draft.cookTime == 0,
           let total = parseISODuration(string(from: dict["totalTime"])) {
            draft.prepTime = total
            draft.prepTimeConfidence = .medium
        }

        if let cat = firstString(from: dict["recipeCategory"]) {
            draft.category = cat.capitalized
            draft.categoryConfidence = .medium
        }

        // Ingredients
        let ingredientStrings = stringArray(from: dict["recipeIngredient"])
            ?? stringArray(from: dict["ingredients"])
            ?? []
        draft.ingredients = ingredientStrings.enumerated().map { index, raw in
            IngredientDraft(
                name: stripHTML(raw) ?? raw,
                quantity: nil,
                unit: "",
                confidence: .medium
            )
        }

        // Steps
        if let rawInstructions = dict["recipeInstructions"] {
            draft.steps = parseInstructions(rawInstructions)
        }

        return draft
    }

    private static func parseInstructions(_ raw: Any) -> [StepDraft] {
        var results: [StepDraft] = []

        func append(_ text: String) {
            let cleaned = (stripHTML(text) ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            results.append(StepDraft(order: results.count + 1, instruction: cleaned, confidence: .high))
        }

        func walk(_ value: Any) {
            if let s = value as? String {
                // Some sites pack all steps into one string separated by newlines.
                for line in s.components(separatedBy: CharacterSet.newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    append(line)
                }
                return
            }
            if let arr = value as? [Any] {
                for item in arr { walk(item) }
                return
            }
            if let dict = value as? [String: Any] {
                let type = (dict["@type"] as? String) ?? ""
                if type.localizedCaseInsensitiveContains("HowToSection") {
                    if let steps = dict["itemListElement"] {
                        walk(steps)
                    }
                    return
                }
                if let text = dict["text"] as? String {
                    append(text)
                    return
                }
                if let name = dict["name"] as? String {
                    append(name)
                    return
                }
            }
        }

        walk(raw)
        return results
    }

    // MARK: - Meta tags

    private static func findMetaContent(in html: String, property: String? = nil, name: String? = nil) -> String? {
        let attr = property != nil ? "property" : "name"
        let value = property ?? name ?? ""
        let pattern = #"<meta[^>]*\#(attr)\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: value))["'][^>]*content\s*=\s*["']([^"']+)["']"#
        if let match = regexFirstMatch(pattern: pattern, in: html) {
            return decodeEntities(match)
        }
        // Reversed order: content before property
        let reversed = #"<meta[^>]*content\s*=\s*["']([^"']+)["'][^>]*\#(attr)\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: value))["']"#
        if let match = regexFirstMatch(pattern: reversed, in: html) {
            return decodeEntities(match)
        }
        return nil
    }

    // MARK: - Cleaning

    static func cleanText(html: String) -> String {
        var s = html
        // Remove scripts and styles including contents.
        s = removeBlocks(in: s, pattern: "<script[^>]*>[\\s\\S]*?</script>")
        s = removeBlocks(in: s, pattern: "<style[^>]*>[\\s\\S]*?</style>")
        s = removeBlocks(in: s, pattern: "<!--[\\s\\S]*?-->")
        // Collapse tags -> newlines on block-level.
        s = s.replacingOccurrences(of: #"</?(?:br|p|div|li|h[1-6]|section|article|tr)[^>]*>"#,
                                    with: "\n", options: .regularExpression)
        // Strip remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        // Collapse whitespace.
        s = s.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func string(from any: Any?) -> String? {
        if let s = any as? String { return s }
        if let arr = any as? [Any] { return arr.compactMap { $0 as? String }.first }
        if let dict = any as? [String: Any], let s = dict["@value"] as? String { return s }
        return nil
    }

    private static func firstString(from any: Any?) -> String? {
        if let s = any as? String { return s }
        if let arr = any as? [String] { return arr.first }
        if let arr = any as? [Any] {
            for item in arr {
                if let s = item as? String { return s }
                if let dict = item as? [String: Any], let s = dict["url"] as? String { return s }
            }
        }
        return nil
    }

    private static func stringInsideObject(_ any: Any?, key: String) -> String? {
        if let dict = any as? [String: Any], let s = dict[key] as? String { return s }
        return nil
    }

    private static func stringArray(from any: Any?) -> [String]? {
        if let arr = any as? [String] { return arr }
        if let arr = any as? [Any] {
            return arr.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let dict = item as? [String: Any] {
                    return (dict["text"] as? String) ?? (dict["name"] as? String)
                }
                return nil
            }
        }
        if let s = any as? String { return [s] }
        return nil
    }

    private static func parseInt(_ raw: String) -> Int? {
        let scanner = Scanner(string: raw)
        scanner.charactersToBeSkipped = .whitespaces
        var value: Int = 0
        if scanner.scanInt(&value) { return value }
        return nil
    }

    /// ISO-8601 duration `PT#H#M` -> minutes.
    private static func parseISODuration(_ raw: String?) -> Int? {
        guard let raw, raw.hasPrefix("P") else { return nil }
        var hours = 0
        var minutes = 0
        let pattern = #"(\d+)\s*H"#
        if let h = regexFirstMatch(pattern: pattern, in: raw), let v = Int(h) { hours = v }
        let pattern2 = #"(\d+)\s*M"#
        if let m = regexFirstMatch(pattern: pattern2, in: raw), let v = Int(m) { minutes = v }
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }

    private static func regexFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func removeBlocks(in text: String, pattern: String) -> String {
        text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    static func stripHTML(_ s: String?) -> String? {
        guard let s else { return nil }
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&ndash;": "–",
            "&mdash;": "—", "&hellip;": "…", "&ordm;": "º", "&ordf;": "ª",
            "&aacute;": "á", "&eacute;": "é", "&iacute;": "í", "&oacute;": "ó", "&uacute;": "ú",
            "&Aacute;": "Á", "&Eacute;": "É", "&Iacute;": "Í", "&Oacute;": "Ó", "&Uacute;": "Ú",
            "&atilde;": "ã", "&otilde;": "õ", "&ccedil;": "ç", "&Ccedil;": "Ç",
            "&Atilde;": "Ã", "&Otilde;": "Õ"
        ]
        for (k, v) in map {
            out = out.replacingOccurrences(of: k, with: v)
        }
        // Numeric entities &#123; and &#x1F;
        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = out as NSString
            let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches where match.numberOfRanges >= 2 {
                let code = ns.substring(with: match.range(at: 1))
                let scalar: UInt32?
                if code.lowercased().hasPrefix("x") {
                    scalar = UInt32(code.dropFirst(), radix: 16)
                } else {
                    scalar = UInt32(code)
                }
                if let scalar, let unicode = Unicode.Scalar(scalar) {
                    out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(unicode)))
                }
            }
        }
        return out
    }
}
