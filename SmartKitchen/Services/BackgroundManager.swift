import SwiftUI
import Observation

// MARK: - Background Type

enum BackgroundType: String, Codable, CaseIterable, Identifiable {
    case original = "original"
    case texturedGradient = "texturedGradient"
    case waves = "waves"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return String(localized: "Original")
        case .texturedGradient: return String(localized: "Textured Gradient")
        case .waves: return String(localized: "Ondas")
        }
    }
}

// MARK: - Background Selection

struct BackgroundSelection: Codable, Equatable {
    var type: BackgroundType
    var texturedPreset: TexturedGradientPreset?

    static var original: BackgroundSelection {
        BackgroundSelection(type: .original, texturedPreset: nil)
    }

    static func textured(_ preset: TexturedGradientPreset) -> BackgroundSelection {
        BackgroundSelection(type: .texturedGradient, texturedPreset: preset)
    }

    static var waves: BackgroundSelection {
        BackgroundSelection(type: .waves, texturedPreset: nil)
    }
}

// MARK: - Background Manager

@MainActor
@Observable
class BackgroundManager {
    static let shared = BackgroundManager()

    private let userDefaultsKey = "customBackgrounds"

    var homeBackground: BackgroundSelection {
        didSet { save() }
    }
    var listsBackground: BackgroundSelection {
        didSet { save() }
    }
    var recipesBackground: BackgroundSelection {
        didSet { save() }
    }
    var nutrientsBackground: BackgroundSelection {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let stored = try? JSONDecoder().decode(StoredBackgrounds.self, from: data) {
            homeBackground = stored.home
            listsBackground = stored.lists
            recipesBackground = stored.recipes
            nutrientsBackground = stored.nutrients
        } else {
            homeBackground = .original
            listsBackground = .original
            recipesBackground = .original
            nutrientsBackground = .original
        }
    }

    func background(for theme: PageTheme) -> BackgroundSelection {
        switch theme {
        case .home: return homeBackground
        case .lists: return listsBackground
        case .recipes: return recipesBackground
        case .nutrients: return nutrientsBackground
        }
    }

    func setBackground(_ selection: BackgroundSelection, for theme: PageTheme) {
        switch theme {
        case .home: homeBackground = selection
        case .lists: listsBackground = selection
        case .recipes: recipesBackground = selection
        case .nutrients: nutrientsBackground = selection
        }
    }

    private func save() {
        let stored = StoredBackgrounds(
            home: homeBackground,
            lists: listsBackground,
            recipes: recipesBackground,
            nutrients: nutrientsBackground
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

// MARK: - Storage Model

private struct StoredBackgrounds: Codable {
    var home: BackgroundSelection
    var lists: BackgroundSelection
    var recipes: BackgroundSelection
    var nutrients: BackgroundSelection
}
