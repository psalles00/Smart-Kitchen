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

enum SharedImportKind: String, Codable {
    case url
    case text
    case image
    case video
}

struct SharedImportItem: Identifiable, Equatable {
    let id: String
    let kind: SharedImportKind
    let url: URL?
    let text: String?
    let imageData: Data?
    let mediaFileURL: URL?
    let filename: String?

    static func == (lhs: SharedImportItem, rhs: SharedImportItem) -> Bool {
        lhs.id == rhs.id
    }

    var recipeImportSource: RecipeImportSource? {
        switch kind {
        case .url:
            return url.map(RecipeImportSource.url)
        case .text:
            guard let text else { return nil }
            return .text(text)
        case .image:
            guard let imageData else { return nil }
            return .image(imageData)
        case .video:
            return mediaFileURL.map(RecipeImportSource.videoFile)
        }
    }

    var displayTitle: String {
        switch kind {
        case .url:
            return url?.host ?? "Link compartilhado"
        case .text:
            return "Texto compartilhado"
        case .image:
            return filename ?? "Imagem compartilhada"
        case .video:
            return filename ?? mediaFileURL?.lastPathComponent ?? "Vídeo compartilhado"
        }
    }

    var detailText: String {
        switch kind {
        case .url:
            return url?.absoluteString ?? ""
        case .text:
            return RecipeImportLogger.preview(text ?? "", limit: 140)
        case .image:
            return "Escolha se essa imagem deve virar uma receita ou ficar reservada para o módulo de nutrientes."
        case .video:
            return "Podemos transcrever o áudio do vídeo e montar uma receita editável antes de salvar. O limite é de \(RecipeImportVideoPolicy.maxSharedVideoDurationMinutes) minutos."
        }
    }

    var assistantPrefill: String? {
        switch kind {
        case .url:
            guard let url else { return nil }
            return "Analise este link compartilhado e me diga a melhor ação no Smart Kitchen: \(url.absoluteString)"
        case .text:
            guard let text, !text.isEmpty else { return nil }
            return "Analise este conteúdo compartilhado e me diga como devo usá-lo no Smart Kitchen:\n\n\(text)"
        case .image, .video:
            return nil
        }
    }

    var foodCapture: SharedFoodCaptureItem? {
        guard kind == .image, let imageData else { return nil }
        return SharedFoodCaptureItem(imageData: imageData, filename: filename)
    }
}

struct SharedFoodCaptureItem: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    let filename: String?

    init(id: UUID = UUID(), imageData: Data, filename: String?) {
        self.id = id
        self.imageData = imageData
        self.filename = filename
    }
}

@MainActor
@Observable
final class SharedFoodCaptureInbox {

    static let shared = SharedFoodCaptureInbox()

    var pendingCapture: SharedFoodCaptureItem?

    private init() {}

    func capture(_ item: SharedFoodCaptureItem) {
        pendingCapture = item
    }

    func clear() {
        pendingCapture = nil
    }
}

@MainActor
@Observable
final class SharedImportInbox {

    static let shared = SharedImportInbox()

    var pendingItem: SharedImportItem?

    private var pendingFolderURL: URL?

    private init() {}

    @discardableResult
    func claimPendingFromBridge() -> Bool {
        guard let token = SharedImportBridge.pendingToken else {
            return false
        }

        if pendingItem?.id == token {
            RecipeImportLogger.info("shared inbox bridge token already active token=\(token)")
            return true
        }

        do {
            let loaded = try SharedImportStorage.loadItem(token: token)
            replacePendingItem(with: loaded.item, folderURL: loaded.folderURL)
            RecipeImportLogger.info("shared inbox claimed pending bridge token=\(token)")
            SharedImportBridge.log("app claimed pending token=\(token)")
            return true
        } catch {
            RecipeImportLogger.error("shared inbox failed claiming bridge token=\(token) error=\(error.localizedDescription)")
            SharedImportBridge.log("app failed to claim token=\(token) error=\(error.localizedDescription)")
            return false
        }
    }

    func ingest(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "smartkitchen",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "shared-import" || components.path.contains("shared-import") else {
            return false
        }

        guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            RecipeImportLogger.error("shared inbox missing token")
            return false
        }

        SharedImportBridge.setPendingToken(token)

        if pendingItem?.id == token {
            RecipeImportLogger.info("shared inbox ignored duplicate token=\(token)")
            return true
        }

        do {
            let loaded = try SharedImportStorage.loadItem(token: token)
            replacePendingItem(with: loaded.item, folderURL: loaded.folderURL)
            RecipeImportLogger.info("shared inbox queued kind=\(loaded.item.kind.rawValue) token=\(token)")
            return true
        } catch {
            RecipeImportLogger.error("shared inbox failed token=\(token) error=\(error.localizedDescription)")
            return false
        }
    }

    func clear(token: String? = nil) {
        guard token == nil || pendingItem?.id == token else {
            return
        }

        let tokenToClear = pendingItem?.id
        pendingItem = nil
        if let pendingFolderURL {
            try? FileManager.default.removeItem(at: pendingFolderURL)
        }
        pendingFolderURL = nil
        SharedImportBridge.clearPendingToken(matching: token ?? tokenToClear)
    }

    private func replacePendingItem(with item: SharedImportItem, folderURL: URL) {
        let previousFolderURL = pendingFolderURL
        pendingItem = item
        pendingFolderURL = folderURL
        SharedImportBridge.setPendingToken(item.id)

        if let previousFolderURL, previousFolderURL != folderURL {
            try? FileManager.default.removeItem(at: previousFolderURL)
        }
    }
}

private enum SharedImportBridge {
    static let appGroupIdentifier = SharedImportStorage.appGroupIdentifier
    static let pendingTokenKey = "SharedImport.PendingToken"
    static let debugTrailKey = "SharedImport.DebugTrail"
    static let maxTrailEntries = 40

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var pendingToken: String? {
        defaults?.string(forKey: pendingTokenKey)
    }

    static func setPendingToken(_ token: String) {
        defaults?.set(token, forKey: pendingTokenKey)
        log("bridge stored token=\(token)")
    }

    static func clearPendingToken(matching token: String?) {
        guard let token else { return }
        guard pendingToken == token else { return }
        defaults?.removeObject(forKey: pendingTokenKey)
        log("bridge cleared token=\(token)")
    }

    static func log(_ message: String) {
        let entry = "\(Date().timeIntervalSince1970) \(message)"
        var trail = defaults?.stringArray(forKey: debugTrailKey) ?? []
        trail.append(entry)
        if trail.count > maxTrailEntries {
            trail.removeFirst(trail.count - maxTrailEntries)
        }
        defaults?.set(trail, forKey: debugTrailKey)
        NSLog("[SharedImportBridge] %@", entry)
    }
}

private enum SharedImportStorage {
    static let appGroupIdentifier = "group.com.pedrosalles.smartkitchen.sync"
    static let inboxDirectoryName = "SharedImportInbox"

    struct LoadedItem {
        let item: SharedImportItem
        let folderURL: URL
    }

    struct Manifest: Codable {
        let kind: SharedImportKind
        let urlString: String?
        let text: String?
        let filename: String?
        let mediaFilename: String?
    }

    static func loadItem(token: String) throws -> LoadedItem {
        let folderURL = try folderURL(for: token)
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        let item = try makeItem(token: token, manifest: manifest, folderURL: folderURL)
        return LoadedItem(item: item, folderURL: folderURL)
    }

    private static func makeItem(token: String, manifest: Manifest, folderURL: URL) throws -> SharedImportItem {
        switch manifest.kind {
        case .url:
            guard let urlString = manifest.urlString, let url = URL(string: urlString) else {
                throw SharedImportStorageError.invalidManifest
            }
            return SharedImportItem(
                id: token,
                kind: .url,
                url: url,
                text: nil,
                imageData: nil,
                mediaFileURL: nil,
                filename: nil
            )

        case .text:
            return SharedImportItem(
                id: token,
                kind: .text,
                url: nil,
                text: manifest.text,
                imageData: nil,
                mediaFileURL: nil,
                filename: nil
            )

        case .image:
            guard let mediaFilename = manifest.mediaFilename else {
                throw SharedImportStorageError.invalidManifest
            }
            let imageURL = folderURL.appendingPathComponent(mediaFilename)
            let imageData = try Data(contentsOf: imageURL)
            return SharedImportItem(
                id: token,
                kind: .image,
                url: nil,
                text: nil,
                imageData: imageData,
                mediaFileURL: imageURL,
                filename: manifest.filename
            )

        case .video:
            guard let mediaFilename = manifest.mediaFilename else {
                throw SharedImportStorageError.invalidManifest
            }
            let videoURL = folderURL.appendingPathComponent(mediaFilename)
            return SharedImportItem(
                id: token,
                kind: .video,
                url: nil,
                text: nil,
                imageData: nil,
                mediaFileURL: videoURL,
                filename: manifest.filename
            )
        }
    }

    private static func folderURL(for token: String) throws -> URL {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedImportStorageError.containerUnavailable
        }
        return containerURL
            .appendingPathComponent(inboxDirectoryName, isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
    }
}

private enum SharedImportStorageError: LocalizedError {
    case containerUnavailable
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "O container compartilhado do app não está disponível."
        case .invalidManifest:
            return "O conteúdo compartilhado está inválido ou incompleto."
        }
    }
}
