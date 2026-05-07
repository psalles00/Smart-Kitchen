import SwiftUI

struct PerformanceSettingsView: View {
    @AppStorage(PerformancePreferences.backgroundShadersEnabledKey)
    private var backgroundShadersEnabled = true

    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Fundos animados", isOn: $backgroundShadersEnabled)
                Toggle("Capas ilustradas das receitas", isOn: $recipeIllustratedPlaceholdersEnabled)
            } footer: {
                Text("Ao desativar, Home, Listas, Receitas e Nutrição passam a usar degradês estáticos. Desativar as capas ilustradas faz receitas sem foto usarem uma capa simples, útil para testar uma navegação mais leve em Receitas.")
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