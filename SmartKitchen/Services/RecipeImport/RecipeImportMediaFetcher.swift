import Foundation

/// Shared video resolution + download helpers used by recipe import pipelines
/// and the post-preview improver. The goal is to guarantee that when a recipe
/// is imported from TikTok / Instagram / direct video URLs, the video bytes
/// are downloaded and persisted alongside the recipe (media library), not
/// just scraped for metadata.
enum RecipeImportMediaFetcher {

    /// Maximum number of bytes we are willing to attach to a recipe as
    /// `RecipePreparationMedia`. Keeps SwiftData/CloudKit payloads bounded.
    static let maxAttachableVideoBytes: Int = 100 * 1024 * 1024 // 100 MB

    /// Resolves a direct video URL (mp4/m3u8/etc) from a social / generic
    /// page URL. Supports TikTok (`playAddr`/`downloadAddr`), Instagram
    /// (`/embed/captioned/`, `video_url`, `contentUrl`), and generic pages
    /// (`og:video`, `<video src>`, `<source src>`). Returns `nil` if nothing
    /// could be located.
    static func resolveVideoURL(from pageURL: URL) async -> URL? {
        // If the URL itself already points at a media file, use it directly.
        if let direct = directMediaURL(from: pageURL.absoluteString) {
            return direct
        }

        RecipeImportLogger.debug("mediaFetcher resolveVideoURL page=\(pageURL.absoluteString)")
        let host = pageURL.host?.lowercased() ?? ""

        if host.contains("instagram") {
            for embedURL in instagramEmbedCandidateURLs(for: pageURL) {
                RecipeImportLogger.debug("mediaFetcher trying instagram embed=\(embedURL.absoluteString)")
                if let embedHTML = try? await fetchHTML(url: embedURL) {
                    if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
                    if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"contentUrl\\"\s*:\s*\\"([^"]+\.mp4[^"]*)\\""#) { return url }
                    if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"shortcode_media\\".*?\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
                    if let url = extractFirstMatch(in: embedHTML, pattern: #""video_url"\s*:\s*"([^"]+)""#) { return url }
                    if let url = extractFirstMatch(in: embedHTML, pattern: #""contentUrl"\s*:\s*"([^"]+\.mp4[^"]*)""#) { return url }
                    if let url = extractFirstMatch(in: embedHTML, pattern: #""shortcode_media".*?"video_url"\s*:\s*"([^"]+)""#) { return url }
                }
            }
        }

        guard let html = try? await fetchHTML(url: pageURL) else {
            RecipeImportLogger.debug("mediaFetcher resolveVideoURL could not fetch page")
            return nil
        }

        if host.contains("tiktok") {
            if let url = extractFirstMatch(in: html, pattern: #""playAddr"\s*:\s*"([^"]+)""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""downloadAddr"\s*:\s*"([^"]+)""#) { return url }
        }
        if host.contains("instagram") {
            if let url = extractFirstMatch(in: html, pattern: #"\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #"\\"contentUrl\\"\s*:\s*\\"([^"]+\.mp4[^"]*)\\""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""video_url"\s*:\s*"([^"]+)""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""contentUrl"\s*:\s*"([^"]+\.mp4[^"]*)""#) { return url }
        }

        // Generic fallbacks across any page.
        if let url = extractFirstMatch(in: html, pattern: #"<meta[^>]+property=["']og:video(?::secure_url|:url)?["'][^>]+content=["']([^"']+)["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:video(?::secure_url|:url)?["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<video[^>]+src=["']([^"']+\.(?:mp4|m4v|webm|m3u8)[^"']*)["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<source[^>]+src=["']([^"']+\.(?:mp4|m4v|webm|m3u8)[^"']*)["']"#) { return url }

        RecipeImportLogger.debug("mediaFetcher resolveVideoURL not found")
        return nil
    }

    /// Returns a direct media URL when the given string already points at a
    /// media file by extension (mp4/mov/m4v/webm/m3u8).
    static func directMediaURL(from rawExternalURL: String) -> URL? {
        let trimmed = rawExternalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let ext = url.pathExtension.lowercased()
        let directExts = ["mp4", "mov", "m4v", "webm", "m3u8"]
        return directExts.contains(ext) ? url : nil
    }

    /// Downloads a video from the given URL (with optional Referer) to a
    /// temporary file. Caller is responsible for removing the file after
    /// use. Throws on HTTP errors / network failures.
    static func downloadVideoToTempFile(from url: URL, referer: URL? = nil) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RecipeImportError.fetchFailed("Falha ao baixar vídeo (\((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }

        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension.lowercased()
        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-video-\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: tempURL, to: finalURL)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? NSNumber)?.intValue ?? 0
        RecipeImportLogger.debug("mediaFetcher video downloaded bytes=\(bytes) url=\(url.absoluteString)")
        return finalURL
    }

    /// Downloads a video and returns its bytes as `Data`, subject to
    /// `maxAttachableVideoBytes`. Returns `nil` when download fails or the
    /// payload exceeds the cap.
    static func downloadVideoData(from url: URL, referer: URL? = nil) async -> Data? {
        do {
            let fileURL = try await downloadVideoToTempFile(from: url, referer: referer)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty, data.count <= maxAttachableVideoBytes else {
                RecipeImportLogger.info("mediaFetcher video rejected bytes=\(data.count) max=\(maxAttachableVideoBytes) url=\(url.absoluteString)")
                return nil
            }
            return data
        } catch {
            RecipeImportLogger.info("mediaFetcher video download failed url=\(url.absoluteString) error=\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private helpers

    private static func instagramEmbedCandidateURLs(for pageURL: URL) -> [URL] {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return []
        }
        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanPath.isEmpty else { return [] }
        components.query = nil
        components.fragment = nil

        var urls: [URL] = []
        components.path = "/\(cleanPath)/embed/captioned/"
        if let url = components.url { urls.append(url) }
        components.path = "/\(cleanPath)/embed/"
        if let url = components.url { urls.append(url) }
        return urls
    }

    private static func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RecipeImportError.fetchFailed("Não foi possível carregar a página do vídeo.")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func extractFirstMatch(in html: String, pattern: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
        let decoded = decodeEscapedString(raw)
        guard let url = URL(string: decoded), url.scheme?.hasPrefix("http") == true else { return nil }
        RecipeImportLogger.debug("mediaFetcher match=\(url.absoluteString)")
        return url
    }

    private static func decodeEscapedString(_ input: String) -> String {
        var decoded = input
        for _ in 0..<4 {
            let quoted = "\"\(decoded.replacingOccurrences(of: "\"", with: "\\\""))\""
            guard let data = quoted.data(using: .utf8),
                  let unescaped = try? JSONDecoder().decode(String.self, from: data),
                  unescaped != decoded else {
                break
            }
            decoded = unescaped
        }
        decoded = decoded.replacingOccurrences(of: #"\u0026"#, with: "&")
        decoded = decoded.replacingOccurrences(of: #"\u002F"#, with: "/")
        decoded = decoded.replacingOccurrences(of: #"\u003D"#, with: "=")
        decoded = decoded.replacingOccurrences(of: #"\u0025"#, with: "%")
        decoded = decoded.replacingOccurrences(of: "\\\\/", with: "\\/")
        decoded = decoded.replacingOccurrences(of: "\\/", with: "/")
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        return decoded
    }
}
