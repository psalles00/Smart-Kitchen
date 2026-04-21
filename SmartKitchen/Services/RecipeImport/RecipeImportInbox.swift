import Foundation
import Observation

/// Shared inbox for incoming recipe imports (from URL schemes, share extension,
/// or deep links). The app shell observes `pendingSource` and presents the
/// import host automatically whenever a new source is pushed.
@MainActor
@Observable
final class RecipeImportInbox {

    static let shared = RecipeImportInbox()

    var pendingSource: RecipeImportSource?

    private init() {}

    /// Parse a URL like `smartkitchen://import?url=<encoded>` and enqueue it.
    /// Also accepts plain `https?://` URLs (treated as direct web imports).
    func ingest(url: URL) -> Bool {
        RecipeImportLogger.info("inbox ingest url=\(url.absoluteString)")
        if url.scheme?.lowercased() == "smartkitchen" {
            return ingestCustomSchemeURL(url)
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            pendingSource = .url(url)
            RecipeImportLogger.info("inbox queued direct web url")
            return true
        }
        RecipeImportLogger.error("inbox unsupported url scheme=\(url.scheme ?? "-")")
        return false
    }

    /// Parse shared text: detect URL or fall back to `.text`.
    func ingest(text raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        RecipeImportLogger.info("inbox ingest text chars=\(trimmed.count)")
        if let url = Self.firstURL(in: trimmed) {
            pendingSource = .url(url)
            RecipeImportLogger.info("inbox detected URL inside text url=\(url.absoluteString)")
        } else {
            pendingSource = .text(trimmed)
            RecipeImportLogger.info("inbox queued raw text")
        }
    }

    func ingest(imageData: Data) {
        guard !imageData.isEmpty else { return }
        pendingSource = .image(imageData)
        RecipeImportLogger.info("inbox queued image bytes=\(imageData.count)")
    }

    func clear() {
        pendingSource = nil
        RecipeImportLogger.debug("inbox cleared")
    }

    // MARK: - Helpers

    private func ingestCustomSchemeURL(_ url: URL) -> Bool {
        // Support two shapes:
        //   smartkitchen://import?url=<encoded URL>
        //   smartkitchen://import?text=<encoded text>
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              (components.host?.lowercased() == "import" || components.path.contains("import")) else {
            return false
        }
        let items = components.queryItems ?? []

        if let encodedURL = items.first(where: { $0.name == "url" })?.value,
           let decoded = encodedURL.removingPercentEncoding ?? encodedURL as String?,
           let parsed = URL(string: decoded), parsed.host != nil {
            pendingSource = .url(parsed)
            RecipeImportLogger.info("inbox custom scheme queued url=\(parsed.absoluteString)")
            return true
        }

        if let encodedText = items.first(where: { $0.name == "text" })?.value,
           let decoded = encodedText.removingPercentEncoding {
            ingest(text: decoded)
            RecipeImportLogger.info("inbox custom scheme queued text")
            return true
        }
        RecipeImportLogger.error("inbox custom scheme missing import payload")
        return false
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }
}
