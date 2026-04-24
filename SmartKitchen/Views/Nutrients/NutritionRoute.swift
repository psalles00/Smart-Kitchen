import SwiftUI
import SwiftData

/// Rotas empurradas dentro da `NavigationStack` da aba Nutrição.
enum NutritionRoute: Hashable {
    case progress
}

/// Tipos de sheet disparados pelo menu "+" do header.
enum NutritionEntrySheet: Identifiable {
    case manual
    case recents
    case capturePhoto
    case captureLabel
    case captureText
    case captureVoice
    case comingSoon(title: String)

    var id: String {
        switch self {
        case .manual:            "manual"
        case .recents:           "recents"
        case .capturePhoto:      "capture-photo"
        case .captureLabel:      "capture-label"
        case .captureText:       "capture-text"
        case .captureVoice:      "capture-voice"
        case .comingSoon(let t): "coming-\(t)"
        }
    }
}
