import SwiftUI

struct PerformanceSettingsView: View {
    @AppStorage(PerformancePreferences.backgroundShadersEnabledKey)
    private var backgroundShadersEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Shaders animados de fundo", isOn: $backgroundShadersEnabled)
            } footer: {
                Text("Ao desativar, Home, Listas, Receitas e Nutrição passam a usar degradês estáticos equivalentes ao visual atual. Isso reduz uso contínuo de GPU e costuma deixar scroll e transições mais leves.")
            }

            Section("O que muda") {
                Label("Substitui SceneKit/Metal por fundos estáticos", systemImage: "bolt.slash")
                Label("Mantém as cores e o caráter visual de cada tema", systemImage: "paintpalette")
                Label("A alteração é aplicada imediatamente", systemImage: "switch.2")
            }
        }
        .navigationTitle("Performance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}