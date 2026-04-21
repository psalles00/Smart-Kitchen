import UIKit
import UniformTypeIdentifiers
import Social

/// Minimal Share Extension: extracts URL / text from the share and hands it off
/// to the main app via the `smartkitchen://import?url=...` URL scheme.
///
/// No App Group is required — we pass the payload through the URL query string.
@objc(SmartKitchenShareViewController)
class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
            if let url = await loadURL(from: provider) {
                await open(url: url)
                return
            }
            if let text = await loadText(from: provider) {
                await open(text: text)
                return
            }
        }

        await finish(with: nil)
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

    // MARK: - Hand-off

    @MainActor
    private func open(url: URL) async {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let deepLink = URL(string: "smartkitchen://import?url=\(encoded)") else {
            await finish(with: nil)
            return
        }
        await openDeepLink(deepLink)
    }

    @MainActor
    private func open(text: String) async {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let deepLink = URL(string: "smartkitchen://import?text=\(encoded)") else {
            await finish(with: nil)
            return
        }
        await openDeepLink(deepLink)
    }

    @MainActor
    private func openDeepLink(_ url: URL) async {
        // Walk up the responder chain to find an object that can call `open(_:)`.
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                break
            }
            // Private selector available on UIApplication via responder chain.
            if current.responds(to: Selector(("openURL:"))) {
                _ = current.perform(Selector(("openURL:")), with: url)
                break
            }
            responder = current.next
        }
        await finish(with: nil)
    }

    @MainActor
    private func finish(with error: Error?) async {
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
