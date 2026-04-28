import Foundation
import ImageIO
import CoreGraphics
import CryptoKit
#if canImport(UIKit)
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
#elseif canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

/// Two-tier thumbnail cache for recipe (and other) images.
///
/// Tier 1: in-memory `NSCache` of decoded `PlatformImage` (instant reuse).
/// Tier 2: on-disk JPEG thumbnails under `Library/Caches/RecipeThumbnails/`,
///         survive app relaunches and memory eviction.
///
/// Renders a downsampled `PlatformImage` from raw `Data` using ImageIO,
/// so list/grid cells never pay the cost of decoding the full-resolution
/// photo every frame. Cache is keyed per-recipe + target pixel size.
///
/// IMPORTANT: This cache is purely runtime. It does NOT modify any
/// persisted `Recipe.imageData`, schema, SwiftData store or CloudKit
/// state — it only accelerates rendering. Disk files live in
/// `Library/Caches`, which iOS may purge under disk pressure (safe).
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

    /// Lazily-resolved disk cache directory (`Library/Caches/RecipeThumbnails`).
    /// Creating the directory is a one-time op, guarded by `diskInitOnce`.
    private static let diskDirectory: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("RecipeThumbnails", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // Exclude from iCloud backup — these are reproducible from `imageData`.
            var resourceURL = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
        }
        return dir
    }()

    /// Synchronous cache lookup. `NSCache` is thread-safe.
    func cachedThumbnail(key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)?.image
    }

    /// Returns a downsampled thumbnail for `data`, using cache when possible.
    /// Decoding/resizing runs off the main thread.
    ///
    /// Lookup order:
    /// 1. In-memory cache (sync, ~free).
    /// 2. On-disk cache (decode small JPEG, ~milliseconds).
    /// 3. Fresh downsample from `data` (slow path), then persist to disk.
    func thumbnail(key: String, data: Data, maxPixel: CGFloat) async -> PlatformImage? {
        if let hit = cache.object(forKey: key as NSString)?.image {
            return hit
        }
        // Hop to a detached task so image decoding never blocks the caller.
        let result: (image: PlatformImage, fromDisk: Bool)? = await Task.detached(priority: .userInitiated) { [data, maxPixel, key] in
            // Tier 2: try the on-disk JPEG first. Guard against missing files
            // (cache pode ter sido purgada pelo iOS) para evitar logs de IIOImageSource.
            if let diskURL = RecipeImageCache.diskURL(for: key),
               FileManager.default.fileExists(atPath: diskURL.path),
               let diskImage = RecipeImageCache.loadFromDisk(url: diskURL, maxPixel: maxPixel) {
                return (diskImage, true)
            }
            // Tier 3: downsample the original.
            guard let image = RecipeImageCache.downsample(data: data, maxPixel: maxPixel) else {
                return nil
            }
            return (image, false)
        }.value

        guard let result else { return nil }

        let cost = RecipeImageCache.estimatedCost(for: result.image)
        cache.setObject(Entry(result.image), forKey: key as NSString, cost: cost)

        // Persist to disk in background only if it didn't come from disk.
        if !result.fromDisk {
            Task.detached(priority: .background) { [image = result.image, key] in
                RecipeImageCache.persistToDisk(image: image, key: key)
            }
        }

        return result.image
    }

    /// Pre-generate (and persist to disk) the thumbnail for the given data,
    /// without blocking the caller. Safe to call after saving a recipe image.
    func prewarm(key: String, data: Data, maxPixel: CGFloat) {
        // Skip if already cached in memory.
        if cache.object(forKey: key as NSString) != nil { return }
        Task.detached(priority: .utility) { [weak self, data, maxPixel, key] in
            // If disk already has it, just decode + populate memory.
            if let diskURL = RecipeImageCache.diskURL(for: key),
               FileManager.default.fileExists(atPath: diskURL.path),
               let diskImage = RecipeImageCache.loadFromDisk(url: diskURL, maxPixel: maxPixel) {
                let cost = RecipeImageCache.estimatedCost(for: diskImage)
                self?.cache.setObject(Entry(diskImage), forKey: key as NSString, cost: cost)
                return
            }
            guard let image = RecipeImageCache.downsample(data: data, maxPixel: maxPixel) else { return }
            let cost = RecipeImageCache.estimatedCost(for: image)
            self?.cache.setObject(Entry(image), forKey: key as NSString, cost: cost)
            RecipeImageCache.persistToDisk(image: image, key: key)
        }
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

    // MARK: - Disk Cache

    /// Maps a logical cache key (which can include arbitrary characters)
    /// to a safe filename via SHA-256. Same key always maps to same file.
    private static func diskURL(for key: String) -> URL? {
        guard let dir = diskDirectory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(hex).jpg", isDirectory: false)
    }

    /// Decode a previously-persisted thumbnail JPEG from disk.
    /// Uses ImageIO so we don't pay a full UIImage(contentsOfFile:) decode.
    private static func loadFromDisk(url: URL, maxPixel: CGFloat) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: .zero)
        #endif
    }

    /// Encode the given decoded image as JPEG and write it atomically to
    /// the cache directory. Failures are silently ignored — cache misses
    /// just trigger a re-downsample on next request.
    private static func persistToDisk(image: PlatformImage, key: String) {
        guard let url = diskURL(for: key) else { return }
        guard let cg: CGImage = {
            #if canImport(UIKit)
            return image.cgImage
            #elseif canImport(AppKit)
            var rect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            #else
            return nil
            #endif
        }() else { return }

        let typeID: CFString
        if #available(iOS 14.0, macOS 11.0, *) {
            typeID = UTType.jpeg.identifier as CFString
        } else {
            typeID = "public.jpeg" as CFString
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, typeID, 1, nil) else {
            return
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        _ = CGImageDestinationFinalize(dest)
    }
}
