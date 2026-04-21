import Foundation

/// Pipeline for social media URLs (Instagram, TikTok, YouTube).
/// Uses oEmbed + OpenGraph metadata to pull caption/title/description,
/// then hands the text to the RecipeStructurer. Video transcription is
/// out of scope for now — the pipeline throws `.insufficientContent`
/// with a suggestion to send a screenshot when the caption is too weak.
@MainActor
struct SocialURLPipeline: RecipeImportPipeline {

    let name = "social-url"

    func canHandle(_ source: RecipeImportSource) -> Bool {
        guard case let .url(url) = source else { return false }
        return Self.isSocialURL(url)
    }

    static func isSocialURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return socialHosts.contains(where: { trimmed == $0 || trimmed.hasSuffix("." + $0) })
    }

    private static let socialHosts: Set<String> = [
        "instagram.com",
        "tiktok.com",
        "youtube.com",
        "youtu.be",
        "facebook.com",
        "fb.watch"
    ]

    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        guard case let .url(url) = source else {
            throw RecipeImportError.unsupportedSource("Esperado URL social.")
        }

        onStage(.fetching)
        let metadata = try await fetchMetadata(url: url)

        let caption = combineCaption(metadata)
        let hasIngredientSignals = Self.hasIngredientSignals(in: caption)
        let tooShort = caption.count < 60

        if tooShort || !hasIngredientSignals {
            throw RecipeImportError.insufficientContent(
                suggestion: "A legenda deste \(metadata.platformLabel) não traz ingredientes suficientes. Tente enviar um screenshot do vídeo ou cole a receita como texto."
            )
        }

        onStage(.organizingIngredients)
        let structurer = RecipeStructurer()
        let hints = RecipeStructurer.Hints(
            title: metadata.title,
            description: metadata.description,
            externalURL: url,
            imageURL: metadata.imageURL,
            sourceLabel: metadata.platformLabel
        )
        var draft = try await structurer.structure(text: caption, hints: hints)

        onStage(.finalizing)
        if draft.imageData == nil, let imageURL = draft.imageURL ?? metadata.imageURL {
            draft.imageData = try? await fetchData(url: imageURL)
            if draft.imageURL == nil { draft.imageURL = imageURL }
        }
        if draft.externalURLString.isEmpty { draft.externalURLString = url.absoluteString }
        if draft.sourceLabel.isEmpty { draft.sourceLabel = metadata.platformLabel }

        return draft
    }

    // MARK: - Metadata

    private struct SocialMetadata {
        var title: String?
        var description: String?
        var authorName: String?
        var imageURL: URL?
        let platformLabel: String
    }

    private func fetchMetadata(url: URL) async throws -> SocialMetadata {
        let platform = Self.platformLabel(for: url)
        async let oembed = fetchOEmbed(for: url)
        async let og = fetchOpenGraph(url: url)

        let oembedResult = (try? await oembed) ?? [:]
        let ogResult = (try? await og) ?? [:]

        let title = (ogResult["og:title"] ?? oembedResult["title"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (ogResult["og:description"] ?? oembedResult["description"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (oembedResult["author_name"] ?? ogResult["og:site_name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbString = oembedResult["thumbnail_url"] ?? ogResult["og:image"]
        let thumb = thumbString.flatMap { URL(string: $0) }

        return SocialMetadata(
            title: title,
            description: description,
            authorName: author,
            imageURL: thumb,
            platformLabel: platform
        )
    }

    private func combineCaption(_ meta: SocialMetadata) -> String {
        var parts: [String] = []
        if let title = meta.title, !title.isEmpty { parts.append(title) }
        if let description = meta.description, !description.isEmpty, description != meta.title {
            parts.append(description)
        }
        return parts.joined(separator: "\n\n")
    }

    private static func hasIngredientSignals(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let lower = text.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "pt_BR"))
        let keywords = [
            "ingredientes", "ingredient", "modo de preparo", "preparo",
            "xicara", "xícara", "colher", "gramas", " g ", " ml ", " kg ",
            "receita", "recipe", "passo", "misture", "bata", "asse",
            "adicione", "leve ao forno"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    private static func platformLabel(for url: URL) -> String {
        guard let host = url.host?.lowercased() else { return "Rede social" }
        if host.contains("instagram") { return "Instagram" }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("youtube") || host.contains("youtu.be") { return "YouTube" }
        if host.contains("facebook") || host.contains("fb.watch") { return "Facebook" }
        return host
    }

    // MARK: - oEmbed

    private func fetchOEmbed(for url: URL) async throws -> [String: String] {
        guard let endpoint = oEmbedEndpoint(for: url) else {
            throw RecipeImportError.unsupportedSource("oEmbed indisponível.")
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return [:]
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (key, value) in json {
            if let str = value as? String { out[key] = str }
        }
        return out
    }

    private func oEmbedEndpoint(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
        if host.contains("youtube") || host.contains("youtu.be") {
            return URL(string: "https://www.youtube.com/oembed?format=json&url=\(encoded)")
        }
        if host.contains("tiktok") {
            return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
        }
        // Instagram + Facebook oEmbed require app tokens; we skip and rely on OG.
        return nil
    }

    // MARK: - OpenGraph

    private func fetchOpenGraph(url: URL) async throws -> [String: String] {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        var out: [String: String] = [:]
        // Crude regex for <meta property="og:xxx" content="yyy"> (and name= variant).
        let pattern = #"<meta[^>]+?(?:property|name)=["']([^"']+)["'][^>]+?content=["']([^"']*)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return out
        }
        let ns = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges == 3 else { return }
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let value = ns.substring(with: match.range(at: 2))
            out[key] = decodeHTMLEntities(value)
        }
        // Also try reverse order (content first, property second).
        let pattern2 = #"<meta[^>]+?content=["']([^"']*)["'][^>]+?(?:property|name)=["']([^"']+)["'][^>]*>"#
        if let regex2 = try? NSRegularExpression(pattern: pattern2, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            regex2.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges == 3 else { return }
                let value = ns.substring(with: match.range(at: 1))
                let key = ns.substring(with: match.range(at: 2)).lowercased()
                if out[key] == nil { out[key] = decodeHTMLEntities(value) }
            }
        }
        return out
    }

    private func decodeHTMLEntities(_ input: String) -> String {
        var s = input
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    private func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
