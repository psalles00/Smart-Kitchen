import SwiftUI
import SwiftData

/// Página unificada que reúne preferências visuais (modo claro/escuro)
/// e de performance (fundos animados).
struct AppearanceSettingsView: View {
    @Query private var settingsArray: [AppSettings]

    @AppStorage(PerformancePreferences.backgroundShadersEnabledKey)
    private var backgroundShadersEnabled = true

    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        Form {
            #if os(iOS)
            Section {
                if let settings {
                    Picker("Aparência", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { settings.appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            } header: {
                Text("Tema")
            } footer: {
                Text("Define se o app segue a aparência do sistema ou força um modo claro ou escuro.")
            }
            #endif

            Section {
                Toggle("Fundos animados", isOn: $backgroundShadersEnabled)
                Toggle("Capas ilustradas das receitas", isOn: $recipeIllustratedPlaceholdersEnabled)
            } header: {
                Text("Performance")
            } footer: {
                Text("Ao desativar, Home, Listas, Receitas e Nutrição passam a usar degradês estáticos. Desativar as capas ilustradas faz receitas sem foto usarem uma capa simples, útil para testar uma navegação mais leve em Receitas.")
            }

            Section {
                Label("Mantém as cores e o caráter visual de cada tema", systemImage: "paintpalette")
                Label("A alteração é aplicada imediatamente", systemImage: "switch.2")
            } header: {
                Text("O que muda")
            }
        }
        .formStyle(.grouped)
        .macSettingsContainer()
        .modalNavigationTitle(String(localized: "Aparência e Performance"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
