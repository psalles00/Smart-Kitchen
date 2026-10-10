#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif

import SwiftUI
import UniformTypeIdentifiers

// MARK: - SwiftUI Image Initializer

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - NSImage UIImage-Compatible Extensions

#if canImport(AppKit)
extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRep = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffRep) else { return nil }
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        guard let tiffRep = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffRep) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }

    convenience init?(contentsOfFile path: String) {
        self.init(contentsOf: URL(fileURLWithPath: path))
    }
}

// MARK: - NSColor UIKit System Color Equivalents

extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemBackground: NSColor { .underPageBackgroundColor }
    static var systemFill: NSColor { .quaternaryLabelColor }
    static var secondarySystemFill: NSColor { .separatorColor }
    static var tertiarySystemFill: NSColor { .quaternaryLabelColor }
    static var systemGray4: NSColor { .systemGray.withAlphaComponent(0.45) }
    static var systemGray5: NSColor { .systemGray.withAlphaComponent(0.3) }
}
#endif

// MARK: - Average Color Extraction

extension PlatformImage {
    /// Returns the average color of the image by downsampling to 1×1.
    func averageColor() -> Color {
        #if canImport(UIKit)
        guard let cgImage = self.cgImage else { return .gray }
        #elseif canImport(AppKit)
        guard let tiff = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else { return .gray }
        #endif

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &pixelData,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Double(pixelData[0]) / 255.0
        let g = Double(pixelData[1]) / 255.0
        let b = Double(pixelData[2]) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Cross-Platform Toolbar Placement

extension ToolbarItemPlacement {
    static var adaptiveTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    static var adaptiveLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}

// MARK: - Clipboard Image Paste

/// Reads an image from the system clipboard and returns its data via completion.
@MainActor
func pasteImageFromClipboard(completion: @escaping (Data?) -> Void) {
    #if canImport(UIKit)
    if let image = UIPasteboard.general.image, let data = image.pngData() {
        completion(data)
    } else {
        completion(nil)
    }
    #elseif canImport(AppKit)
    let pasteboard = NSPasteboard.general

    // 1. NSImage(pasteboard:) — Apple's recommended all-in-one initializer.
    //    Handles TIFF, PNG, PDF, PICT, EPS, bitmap data, and file URL references.
    if let image = NSImage(pasteboard: pasteboard),
       let data = image.pngData() {
        completion(data)
        return
    }

    // 2. readObjects(forClasses: [NSImage.self]) — uses NSPasteboardReading protocol.
    if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
       let image = images.first,
       let data = image.pngData() {
        completion(data)
        return
    }

    // 3. Try file URLs with image content type filter.
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier]
    ]) as? [URL],
       let url = urls.first,
       let image = NSImage(contentsOf: url),
       let data = image.pngData() {
        completion(data)
        return
    }

    completion(nil)
    #endif
}

#if os(iOS)
import ImageIO

/// Decodes a bounded thumbnail off the UI actor; never runs inside a view body.
enum SavoriaImagePalette {
    @concurrent
    nonisolated static func averageRGB(from data: Data) async -> SIMD3<Double>? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 48,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered, pixel[3] > 0 else { return nil }
        let alpha = Double(pixel[3])
        return SIMD3(Double(pixel[0]) / alpha, Double(pixel[1]) / alpha, Double(pixel[2]) / alpha)
    }
}
#endif
