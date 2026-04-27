import SwiftUI
import SwiftData

/// Rotas empurradas dentro da `NavigationStack` da aba Nutrição.
enum NutritionRoute: Hashable {
    case progress
}

/// Tipos de sheet disparados pelo menu "+" do header.
enum NutritionEntrySheet: Identifiable {
    case manual(prefillName: String? = nil, prefillMealType: MealType? = nil)
    case recents
    case capturePhotoCamera
    case capturePhotoGallery
    case captureLabel
    case captureText(prefillText: String?, autoAnalyze: Bool)
    case captureVoice
    case comingSoon(title: String)

    var prefersFullScreenPresentation: Bool {
        if case .manual = self {
            return true
        }

        return false
    }

    var id: String {
        switch self {
        case .manual:            "manual"
        case .recents:           "recents"
        case .capturePhotoCamera:"capture-photo-camera"
        case .capturePhotoGallery:"capture-photo-gallery"
        case .captureLabel:      "capture-label"
        case .captureText:       "capture-text"
        case .captureVoice:      "capture-voice"
        case .comingSoon(let t): "coming-\(t)"
        }
    }
}
