import Foundation
import ImageIO
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// In-memory thumbnail cache for recipe (and other) images.
///
/// Renders a downsampled `PlatformImage` from raw `Data` using ImageIO,
/// so list/grid cells never pay the cost of decoding the full-resolution
/// photo every frame. Cache is keyed per-recipe + target pixel size.
///
/// IMPORTANT: This cache is purely runtime / in-memory. It does NOT modify
/// any persisted `Recipe.imageData`, schema, SwiftData store or CloudKit
/// state — it only accelerates rendering.
///
/// `NSCache` is thread-safe, so the wrapper is a plain final class usable
/// from any concurrency context.
final class RecipeImageCache: @unchecked Sendable {
    static let shared = RecipeImageCache()

    private final class Entry {
        let image: PlatformImage
        init(_ image: PlatformImage) { self.image = image }
    }

    private let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        c.countLimit = 300
        // Rough cap on decoded pixel memory (bytes). NSCache will evict
        // automatically under memory pressure regardless of this value.
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    /// Synchronous cache lookup. `NSCache` is thread-safe.
    func cachedThumbnail(key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)?.image
    }

    /// Returns a downsampled thumbnail for `data`, using cache when possible.
    /// Decoding/resizing runs off the main thread.
    func thumbnail(key: String, data: Data, maxPixel: CGFloat) async -> PlatformImage? {
        if let hit = cache.object(forKey: key as NSString)?.image {
            return hit
        }
        // Hop to a detached task so image decoding never blocks the caller.
        let image = await Task.detached(priority: .userInitiated) { [data, maxPixel] in
            RecipeImageCache.downsample(data: data, maxPixel: maxPixel)
        }.value
        if let image {
            let cost = RecipeImageCache.estimatedCost(for: image)
            cache.setObject(Entry(image), forKey: key as NSString, cost: cost)
        }
        return image
    }

    /// Build a cache key that invalidates automatically if the underlying
    /// image bytes change (e.g. user replaces the photo). `dataCount` acts
    /// as a lightweight fingerprint — good enough for UI-level caching
    /// without hashing megabytes of data on every body eval.
    static func key(recipeID: UUID, dataCount: Int, maxPixel: CGFloat) -> String {
        "\(recipeID.uuidString)#\(dataCount)@\(Int(maxPixel))"
    }

    // MARK: - Downsampling

    static func downsample(data: Data, maxPixel: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: .zero)
        #endif
    }

    private static func estimatedCost(for image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let size = image.size
        let scale = image.scale
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        #else
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        #endif
        return max(1, w * h * 4)
    }
}
