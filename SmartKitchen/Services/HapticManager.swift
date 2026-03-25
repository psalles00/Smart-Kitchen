import Foundation

#if os(iOS)
import UIKit
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
        #endif
    }
}
