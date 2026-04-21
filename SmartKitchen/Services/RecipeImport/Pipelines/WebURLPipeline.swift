import Foundation

/// Pipeline for generic web URLs (blogs, recipe sites).
///
/// Flow:
///   • fetch HTML
///   • parse JSON-LD Recipe schema (highest fidelity)
///   • if schema missing: send cleaned HTML text to the AI structurer
///   • enrich with OG metadata
///   • fetch cover image if one was declared
@MainActor
struct WebURLPipeline: RecipeImportPipeline {

    let name = "web-url"

    func canHandle(_ source: RecipeImportSource) -> Bool {
        if case .url = source { return true }
        return false
    }

    func run(
        source: RecipeImportSource,
        onStage: @MainActor (RecipeImportStage) -> Void
    ) async throws -> RecipeDraft {
        guard case let .url(url) = source else {
            RecipeImportLogger.error("web pipeline received non-url source")
            throw RecipeImportError.unsupportedSource("Esperado URL.")
        }
        RecipeImportLogger.info("web pipeline started url=\(url.absoluteString)")

        onStage(.fetching)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.fetching.title)")
        let html = try await fetchHTML(url: url)
        RecipeImportLogger.debug("web html fetched chars=\(html.count)")

        onStage(.extractingText)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.extractingText.title)")
        let result = HTMLRecipeExtractor.extract(html: html, sourceURL: url)
        RecipeImportLogger.info("extractor result schemaDraft=\(result.draft != nil) cleanedChars=\(result.cleanedText.count) ogTitle=\(RecipeImportLogger.preview(result.ogTitle ?? "", limit: 80))")

        var draft: RecipeDraft
        if let schemaDraft = result.draft,
           !schemaDraft.ingredients.isEmpty,
           !schemaDraft.steps.isEmpty {
            draft = schemaDraft
            RecipeImportLogger.info("using JSON-LD schema draft")
        } else {
            // Fall back to AI structuring using the cleaned HTML body.
            onStage(.organizingIngredients)
            RecipeImportLogger.debug("stage=\(RecipeImportStage.organizingIngredients.title)")
            let structurer = RecipeStructurer()
            let hints = RecipeStructurer.Hints(
                title: result.ogTitle,
                description: result.ogDescription,
                externalURL: url,
                imageURL: result.ogImageURL,
                sourceLabel: url.host ?? "Web"
            )
            let truncated = String(result.cleanedText.prefix(16_000))
            RecipeImportLogger.info("falling back to AI structurer with cleanedChars=\(truncated.count)")
            draft = try await structurer.structure(text: truncated, hints: hints)
        }

        // Download cover image if we have a URL but no data yet.
        onStage(.finalizing)
        RecipeImportLogger.debug("stage=\(RecipeImportStage.finalizing.title)")
        if draft.imageData == nil, let imageURL = draft.imageURL {
            RecipeImportLogger.debug("downloading cover image url=\(imageURL.absoluteString)")
            draft.imageData = try? await fetchData(url: imageURL)
            RecipeImportLogger.debug("cover image bytes=\(draft.imageData?.count ?? 0)")
        }

        if draft.externalURLString.isEmpty { draft.externalURLString = url.absoluteString }
        if draft.sourceLabel.isEmpty { draft.sourceLabel = url.host ?? "Web" }
        RecipeImportLogger.info("web pipeline completed \(RecipeImportLogger.draftSummary(draft))")

        return draft
    }

    // MARK: - Networking

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 25

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RecipeImportError.fetchFailed("Resposta inválida do servidor.")
            }
            RecipeImportLogger.debug("fetchHTML status=\(http.statusCode) bytes=\(data.count)")
            guard (200...299).contains(http.statusCode) else {
                throw RecipeImportError.fetchFailed("Status HTTP \(http.statusCode).")
            }
            let encoding = encoding(from: http) ?? .utf8
            if let html = String(data: data, encoding: encoding) { return html }
            return String(decoding: data, as: UTF8.self)
        } catch let error as RecipeImportError {
            RecipeImportLogger.error("fetchHTML recipeError=\(error.localizedDescription)")
            throw error
        } catch {
            RecipeImportLogger.error("fetchHTML error=\(error.localizedDescription)")
            throw RecipeImportError.fetchFailed(error.localizedDescription)
        }
    }

    private func fetchData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 25
        let (data, _) = try await URLSession.shared.data(for: request)
        RecipeImportLogger.debug("fetchData bytes=\(data.count) url=\(url.absoluteString)")
        return data
    }

    private func encoding(from response: HTTPURLResponse) -> String.Encoding? {
        guard let ct = response.value(forHTTPHeaderField: "Content-Type") else { return nil }
        guard let range = ct.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let charset = ct[range.upperBound...].split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
