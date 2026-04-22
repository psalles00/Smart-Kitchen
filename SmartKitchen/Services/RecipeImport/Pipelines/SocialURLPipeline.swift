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
            RecipeImportLogger.error("social pipeline received non-url source")
            throw RecipeImportError.unsupportedSource("Esperado URL social.")
        }
        RecipeImportLogger.info("social pipeline started url=\(url.absoluteString)")

        onStage(.fetching)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.fetching.title)")
        let metadata = try await fetchMetadata(url: url)
        RecipeImportLogger.info("social metadata platform=\(metadata.platformLabel) title=\(RecipeImportLogger.preview(metadata.title ?? "", limit: 80)) descriptionChars=\((metadata.description ?? "").count) imageURL=\(metadata.imageURL?.absoluteString ?? "-")")

        let caption = combineCaption(metadata)
        let hasIngredientSignals = Self.hasIngredientSignals(in: caption)
        let tooShort = caption.count < 60
        RecipeImportLogger.debug("social caption chars=\(caption.count) hasSignals=\(hasIngredientSignals)")

        if tooShort || !hasIngredientSignals {
            RecipeImportLogger.error("social insufficient content tooShort=\(tooShort) hasIngredientSignals=\(hasIngredientSignals)")
            throw RecipeImportError.insufficientContent(
                suggestion: "A legenda deste \(metadata.platformLabel) não traz ingredientes suficientes. Tente enviar um screenshot do vídeo ou cole a receita como texto."
            )
        }

        onStage(.organizingIngredients)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.organizingIngredients.title)")
        let structurer = RecipeStructurer()
        let hints = RecipeStructurer.Hints(
            title: metadata.title,
            description: metadata.description,
            externalURL: url,
            imageURL: metadata.imageURL,
            sourceLabel: metadata.platformLabel
        )
        var draft = try await structurer.structure(text: caption, hints: hints)
        RecipeImportLogger.info("social structured \(RecipeImportLogger.draftSummary(draft))")

        onStage(.finalizing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.finalizing.title)")
        if draft.imageData == nil, let imageURL = draft.imageURL ?? metadata.imageURL {
            draft.imageData = try? await fetchData(url: imageURL)
            if draft.imageURL == nil { draft.imageURL = imageURL }
            RecipeImportLogger.debug("social cover download bytes=\(draft.imageData?.count ?? 0)")
        }
        if draft.videoURL == nil {
            draft.videoURL = metadata.videoURL
            if let videoURL = metadata.videoURL {
                RecipeImportLogger.info("social detected videoURL=\(videoURL.absoluteString)")
            }
        }

        // Always attach the original source media so the user finds the raw
        // material under "Adicionar Fotos ou Vídeos". Prefer the video; fall
        // back to the cover image when the platform only exposes a thumbnail.
        if !draft.preparationMedia.contains(where: { $0.sourceOriginal }) {
            if let videoURL = draft.videoURL,
               let videoData = try? await fetchData(url: videoURL, maxBytes: 80 * 1024 * 1024) {
                let ext = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension.lowercased()
                draft.preparationMedia.append(
                    ImportDraftPreparationMedia(
                        type: .video,
                        data: videoData,
                        fileExtension: ext,
                        sourceOriginal: true
                    )
                )
                RecipeImportLogger.info("social downloaded video bytes=\(videoData.count) ext=\(ext)")
            } else if let imageData = draft.imageData {
                draft.preparationMedia.append(
                    ImportDraftPreparationMedia(
                        type: .photo,
                        data: imageData,
                        fileExtension: "jpg",
                        sourceOriginal: true
                    )
                )
                RecipeImportLogger.info("social fallback attached cover image as original media bytes=\(imageData.count)")
            }
        }

        if draft.externalURLString.isEmpty { draft.externalURLString = url.absoluteString }
        if draft.sourceLabel.isEmpty { draft.sourceLabel = metadata.platformLabel }
        RecipeImportLogger.info("social pipeline completed \(RecipeImportLogger.draftSummary(draft))")

        return draft
    }

    // MARK: - Metadata

    private struct SocialMetadata {
        var title: String?
        var description: String?
        var authorName: String?
        var imageURL: URL?
        var videoURL: URL?
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
        let videoString = ogResult["og:video:secure_url"]
            ?? ogResult["og:video:url"]
            ?? ogResult["og:video"]
            ?? ogResult["twitter:player:stream"]
        let thumb = thumbString.flatMap { URL(string: $0) }
        let video = videoString.flatMap { URL(string: $0) }

        return SocialMetadata(
            title: title,
            description: description,
            authorName: author,
            imageURL: thumb,
            videoURL: video,
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
        RecipeImportLogger.debug("social fetchData bytes=\(data.count) url=\(url.absoluteString)")
        return data
    }

    private func fetchData(url: URL, maxBytes: Int) async throws -> Data {
        let data = try await fetchData(url: url)
        guard data.count <= maxBytes else {
            RecipeImportLogger.info("social fetchData exceeded maxBytes bytes=\(data.count) max=\(maxBytes) url=\(url.absoluteString)")
            throw RecipeImportError.fetchFailed("Arquivo grande demais para anexar.")
        }
        return data
    }
}
