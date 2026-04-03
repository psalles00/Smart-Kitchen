import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum HapticStyle {
    case light, medium, heavy
}

enum HapticManager {
    static func impact(style: HapticStyle = .medium) {
        #if os(iOS)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        }
        UIImpactFeedbackGenerator(style: uiStyle).impactOccurred()
        #elseif os(macOS)
        let pattern: NSHapticFeedbackManager.FeedbackPattern = switch style {
        case .light: .alignment
        case .medium: .levelChange
        case .heavy: .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        #endif
    }
}
