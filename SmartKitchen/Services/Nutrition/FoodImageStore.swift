import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Armazena imagens de FoodEntry em disco (Application Support/sk-food-images/).
/// Nunca persistimos bytes no modelo SwiftData/CloudKit — apenas `imageFilename`.
final class FoodImageStore: @unchecked Sendable {
    static let shared = FoodImageStore()

    private let folderName = "sk-food-images"
    private let compressionQuality: CGFloat = 0.8
    private let maxDimension: CGFloat = 1024

    private init() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Paths

    var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(folderName, isDirectory: true)
    }

    func fileURL(for filename: String) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    // MARK: - Save

    /// Comprime a imagem para JPEG (≤1024px maior lado) e grava em disco. Retorna o nome do arquivo gerado.
    @discardableResult
    func save(image: PlatformImage) -> String? {
        let resized = resize(image, maxDimension: maxDimension) ?? image
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else { return nil }
        return save(data: data)
    }

    /// Grava bytes já codificados (assume JPEG/PNG válido) em disco.
    @discardableResult
    func save(data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let url = fileURL(for: filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            NSLog("FoodImageStore save failed: %@", String(describing: error))
            return nil
        }
    }

    // MARK: - Load

    func loadData(filename: String) -> Data? {
        try? Data(contentsOf: fileURL(for: filename))
    }

    func loadImage(filename: String) -> PlatformImage? {
        guard let data = loadData(filename: filename) else { return nil }
        return PlatformImage(data: data)
    }

    // MARK: - Delete

    func delete(filename: String) {
        try? FileManager.default.removeItem(at: fileURL(for: filename))
    }

    // MARK: - Resize helper

    private func resize(_ image: PlatformImage, maxDimension: CGFloat) -> PlatformImage? {
        #if canImport(UIKit)
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        #elseif canImport(AppKit)
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
        #else
        return image
        #endif
    }
}
