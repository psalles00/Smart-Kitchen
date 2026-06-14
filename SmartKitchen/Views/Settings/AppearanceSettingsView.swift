import SwiftUI
import SwiftData

/// Página unificada que reúne preferências visuais (modo claro/escuro)
/// e de performance.
struct AppearanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var settingsArray: [AppSettings]

    @AppStorage(PerformancePreferences.recipeIllustratedPlaceholdersEnabledKey)
    private var recipeIllustratedPlaceholdersEnabled = true

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        Form {
            Section {
                if let settings {
                    Picker("Aparência", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { newMode in
                            settings.appearanceMode = newMode
                            newMode.persistForLaunch()
                            try? modelContext.save()
                            #if os(iOS)
                            NotificationCenter.default.post(name: .appearanceModeChanged, object: nil)
                            #endif
                        }
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

            Section {
                Toggle("Capas ilustradas das receitas", isOn: $recipeIllustratedPlaceholdersEnabled)
            } header: {
                Text("Performance")
            }

            Section {
                Label("Mantém as cores e o caráter visual de cada tema", systemImage: "paintpalette")
                Label("A alteração é aplicada imediatamente", systemImage: "switch.2")
            } header: {
                Text("O que muda")
            }
        }
        .settingsFormStyle()
        .macSettingsContainer()
        .settingsNavigationTitle(String(localized: "Aparência e Performance"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
