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
import SceneKit

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

// MARK: - SCNView Display Scale

extension SCNView {
    var displayScale: CGFloat {
        #if os(iOS)
        window?.windowScene?.screen.scale ?? 2.0
        #elseif os(macOS)
        window?.backingScaleFactor ?? 2.0
        #endif
    }
}

// MARK: - Clipboard Image Paste

/// Reads an image from the system clipboard and returns its data via completion.
func pasteImageFromClipboard(completion: @escaping (Data?) -> Void) {
    #if canImport(UIKit)
    if let image = UIPasteboard.general.image, let data = image.pngData() {
        completion(data)
    } else {
        completion(nil)
    }
    #elseif canImport(AppKit)
    let pasteboard = NSPasteboard.general
    // Try reading TIFF data first (most common on macOS clipboard)
    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData),
       let pngData = image.pngData() {
        completion(pngData)
    // Try PNG directly
    } else if let pngData = pasteboard.data(forType: .png) {
        completion(pngData)
    // Try reading file URLs from clipboard
    } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first,
              let data = try? Data(contentsOf: url),
              NSImage(data: data) != nil {
        completion(data)
    // Fallback: try NSImage(pasteboard:)
    } else if let image = NSImage(pasteboard: pasteboard),
              let data = image.pngData() {
        completion(data)
    } else {
        completion(nil)
    }
    #endif
}
