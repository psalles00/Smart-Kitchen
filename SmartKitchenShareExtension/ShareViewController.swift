import UIKit
import UniformTypeIdentifiers
import Social
import AVFoundation

private enum SharedVideoImportPolicy {
    static let maxDurationMinutes = 20
    static let maxDurationSeconds = Double(maxDurationMinutes * 60)
    static let durationLimitMessage = String(localized: "Vídeos enviados devem ter no máximo 20 minutos.")
}

private enum SharedPayloadKind: String, Codable {
    case url
    case text
    case image
    case video
}

private enum SharedPayload {
    case url(URL)
    case text(String)
    case image(Data, filename: String?)
    case video(URL, filename: String?)
}

private enum SharedPayloadStoreError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return String(localized: "O container compartilhado do Smart Kitchen não está disponível.")
        }
    }
}

private enum SharedPayloadValidationError: LocalizedError {
    case videoTooLong

    var errorDescription: String? {
        switch self {
        case .videoTooLong:
            return SharedVideoImportPolicy.durationLimitMessage
        }
    }
}

private enum SharedPayloadStore {
    static let appGroupIdentifier = "group.com.pedrosalles.smartkitchen.sync"
    static let inboxDirectoryName = "SharedImportInbox"

    struct Manifest: Codable {
        let kind: SharedPayloadKind
        let urlString: String?
        let text: String?
        let filename: String?
        let mediaFilename: String?
    }

    static func save(_ payload: SharedPayload) throws -> String {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedPayloadStoreError.containerUnavailable
        }

        let token = UUID().uuidString
        let inboxURL = containerURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        let folderURL = inboxURL.appendingPathComponent(token, isDirectory: true)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        do {
            let manifest = try makeManifest(for: payload, in: folderURL)
            let manifestURL = folderURL.appendingPathComponent("manifest.json")
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestURL, options: [.atomic])
            return token
        } catch {
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    private static func makeManifest(for payload: SharedPayload, in folderURL: URL) throws -> Manifest {
        switch payload {
        case .url(let url):
            return Manifest(
                kind: .url,
                urlString: url.absoluteString,
                text: nil,
                filename: nil,
                mediaFilename: nil
            )

        case .text(let text):
            return Manifest(
                kind: .text,
                urlString: nil,
                text: text,
                filename: nil,
                mediaFilename: nil
            )

        case .image(let data, let filename):
            let fileExtension = sanitizedExtension(from: filename, fallback: "jpg")
            let mediaFilename = "payload.\(fileExtension)"
            let mediaURL = folderURL.appendingPathComponent(mediaFilename)
            try data.write(to: mediaURL, options: [.atomic])
            return Manifest(
                kind: .image,
                urlString: nil,
                text: nil,
                filename: filename,
                mediaFilename: mediaFilename
            )

        case .video(let url, let filename):
            let fileExtension = sanitizedExtension(from: filename ?? url.lastPathComponent, fallback: url.pathExtension.isEmpty ? "mov" : url.pathExtension)
            let mediaFilename = "payload.\(fileExtension)"
            let mediaURL = folderURL.appendingPathComponent(mediaFilename)
            try FileManager.default.copyItem(at: url, to: mediaURL)
            return Manifest(
                kind: .video,
                urlString: nil,
                text: nil,
                filename: filename ?? url.lastPathComponent,
                mediaFilename: mediaFilename
            )
        }
    }

    private static func sanitizedExtension(from filename: String?, fallback: String) -> String {
        guard let filename, !filename.isEmpty else { return fallback }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }
}

private enum SharedImportBridge {
    static let appGroupIdentifier = SharedPayloadStore.appGroupIdentifier
    static let pendingTokenKey = "SharedImport.PendingToken"
    static let debugTrailKey = "SharedImport.DebugTrail"
    static let maxTrailEntries = 40

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func setPendingToken(_ token: String) {
        defaults?.set(token, forKey: pendingTokenKey)
        log("share extension stored pending token=\(token)")
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

/// Share Extension: extracts URL, text, image or video from the host app,
/// persists it into a shared inbox, and opens the main app with a token.
@objc(SmartKitchenShareViewController)
class ShareViewController: UIViewController {

    private var hasStartedProcessing = false
    private var hasCompletedRequest = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStartedProcessing else { return }
        hasStartedProcessing = true
        Task { await processIncoming() }
    }

    // MARK: - Processing

    private func processIncoming() async {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let attachments = item.attachments else {
            await finish(with: nil)
            return
        }

        for provider in attachments {
            do {
                if let payload = try await loadSharedPayload(from: provider) {
                    await open(payload: payload)
                    return
                }
            } catch {
                await presentErrorAndFinish(message: error.localizedDescription)
                return
            }
        }

        await finish(with: nil)
    }

    private func loadSharedPayload(from provider: NSItemProvider) async throws -> SharedPayload? {
        if let movie = try await loadMovie(from: provider) {
            return movie
        }

        if let image = await loadImage(from: provider) {
            return image
        }

        if let url = await loadURL(from: provider) {
            return .url(url)
        }

        if let text = await loadText(from: provider) {
            return .text(text)
        }

        if let filePayload = try await loadSupportedFile(from: provider) {
            return filePayload
        }

        return nil
    }

    private func loadMovie(from provider: NSItemProvider) async throws -> SharedPayload? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
            return nil
        }

        let suggestedName = provider.suggestedName

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                Task {
                    do {
                        let payload = try await Self.prepareVideoPayload(
                            from: url,
                            suggestedName: suggestedName ?? url.lastPathComponent
                        )
                        continuation.resume(returning: payload)
                    } catch let error as SharedPayloadValidationError {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> SharedPayload? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        let suggestedName = provider.suggestedName

        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: .image(data, filename: suggestedName))
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data, let str = String(data: data, encoding: .utf8), let url = URL(string: str) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let str = item as? String {
                        continuation.resume(returning: str)
                    } else if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: str)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
    }

    private func loadSupportedFile(from provider: NSItemProvider) async throws -> SharedPayload? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }

        let suggestedName = provider.suggestedName

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolvedURL: URL?
                if let url = item as? URL {
                    resolvedURL = url
                } else if let data = item as? Data,
                          let rawPath = String(data: data, encoding: .utf8) {
                    resolvedURL = URL(fileURLWithPath: rawPath)
                } else {
                    resolvedURL = nil
                }

                guard let resolvedURL else {
                    continuation.resume(returning: nil)
                    return
                }

                let accessed = resolvedURL.startAccessingSecurityScopedResource()
                let stopAccessing: () -> Void = {
                    if accessed {
                        resolvedURL.stopAccessingSecurityScopedResource()
                    }
                }

                let type = UTType(filenameExtension: resolvedURL.pathExtension)
                if type?.conforms(to: .movie) == true {
                    Task {
                        defer { stopAccessing() }

                        do {
                            let payload = try await Self.prepareVideoPayload(
                                from: resolvedURL,
                                suggestedName: suggestedName ?? resolvedURL.lastPathComponent
                            )
                            continuation.resume(returning: payload)
                        } catch let error as SharedPayloadValidationError {
                            continuation.resume(throwing: error)
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                    return
                }

                defer { stopAccessing() }

                if type?.conforms(to: .image) == true,
                   let data = try? Data(contentsOf: resolvedURL),
                   !data.isEmpty {
                    continuation.resume(returning: .image(data, filename: suggestedName ?? resolvedURL.lastPathComponent))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private static func prepareVideoPayload(from sourceURL: URL, suggestedName: String?) async throws -> SharedPayload {
        try await validateVideoDuration(at: sourceURL)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let copiedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-video-\(UUID().uuidString).\(fileExtension)")

        try? FileManager.default.removeItem(at: copiedURL)
        try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
        return .video(copiedURL, filename: suggestedName)
    }

    private static func validateVideoDuration(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        guard seconds.isFinite else { return }
        if seconds > SharedVideoImportPolicy.maxDurationSeconds {
            throw SharedPayloadValidationError.videoTooLong
        }
    }

    // MARK: - Hand-off

    @MainActor
    private func open(payload: SharedPayload) async {
        do {
            let token = try SharedPayloadStore.save(payload)
            SharedImportBridge.setPendingToken(token)
            SharedImportBridge.log("share extension saved payload kind=\(payloadKindLabel(payload)) token=\(token)")

            if case .video(let localURL, _) = payload {
                try? FileManager.default.removeItem(at: localURL)
            }

            guard let deepLink = URL(string: "smartkitchen://shared-import") else {
                await finish(with: nil)
                return
            }

            await openDeepLink(deepLink)
        } catch {
            await finish(with: error)
        }
    }

    @MainActor
    private func openDeepLink(_ url: URL) async {
        SharedImportBridge.log("share extension handoff start url=\(url.absoluteString)")
        completeRequestIfNeeded { [weak self] expired in
            guard let self else { return }
            guard !expired else {
                SharedImportBridge.log("share extension completion expired before open")
                return
            }

            DispatchQueue.main.async {
                let opened = self.openURLViaResponderChain(url)
                SharedImportBridge.log("share extension responder open attempted opened=\(opened) url=\(url.absoluteString)")
            }
        }
    }

    @MainActor
    private func presentErrorAndFinish(message: String) async {
        let alert = UIAlertController(title: String(localized: "Não foi possível compartilhar"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
            self?.completeRequestIfNeeded()
        })
        present(alert, animated: true)
    }

    @MainActor
    private func finish(with error: Error?) async {
        if let error {
            SharedImportBridge.log("share extension finish error=\(error.localizedDescription)")
        } else {
            SharedImportBridge.log("share extension finish success")
        }
        completeRequestIfNeeded()
    }

    private func openURLViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return true
            }
            if current.responds(to: Selector(("openURL:"))) {
                _ = current.perform(Selector(("openURL:")), with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func completeRequestIfNeeded(completionHandler: (@Sendable (Bool) -> Void)? = nil) {
        guard !hasCompletedRequest else { return }
        hasCompletedRequest = true
        extensionContext?.completeRequest(returningItems: nil, completionHandler: completionHandler)
    }

    private func payloadKindLabel(_ payload: SharedPayload) -> String {
        switch payload {
        case .url:
            return "url"
        case .text:
            return "text"
        case .image:
            return "image"
        case .video:
            return "video"
        }
    }
}
