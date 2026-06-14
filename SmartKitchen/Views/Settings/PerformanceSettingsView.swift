import SwiftUI

struct PerformanceSettingsView: View {
    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Capas ilustradas das receitas", isOn: $recipeIllustratedPlaceholdersEnabled)
            }

            Section("O que muda") {
                Label("Mantém as cores e o caráter visual de cada tema", systemImage: "paintpalette")
                Label("A alteração é aplicada imediatamente", systemImage: "switch.2")
            }
        }
        .settingsNavigationTitle(String(localized: "Performance"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
