import SwiftUI
import SwiftData

/// Página dedicada às preferências de listas (despensa, mercado) e receitas.
struct ListsSettingsView: View {
    @Query private var settingsArray: [AppSettings]
    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        Form {
            Section {
                if let settings {
                    Picker("Modo da despensa", selection: Binding(
                        get: { settings.pantryDetailLevel },
                        set: { settings.pantryDetailLevel = $0 }
                    )) {
                        ForEach(PantryDetailLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    Stepper(
                        "Avisar validade com \(settings.expiringItemsLeadDays) dias de antecedência",
                        value: Binding(
                            get: { settings.expiringItemsLeadDays },
                            set: { settings.expiringItemsLeadDays = $0 }
                        ),
                        in: 1...180
                    )

                    Toggle("Mostrar Para depois", isOn: Binding(
                        get: { settings.showReserve },
                        set: { settings.showReserve = $0 }
                    ))
                    .accessibilityIdentifier("savoria.lists.reserve.enabled")

                    Toggle("Mostrar utensílios", isOn: Binding(
                        get: { settings.showUtensils },
                        set: { settings.showUtensils = $0 }
                    ))
                }
            } header: {
                Text("Despensa e mercado")
            } footer: {
                Text("Itens finalizados vão para Para depois quando habilitada. Marque-os para enviar ao Mercado. Ocultar a lista preserva seus itens.")
            }

            Section {
                if let settings {
                    Picker("Visualização padrão", selection: Binding(
                        get: { settings.recipeViewMode },
                        set: { settings.recipeViewMode = $0 }
                    )) {
                        ForEach(RecipeViewMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }

                    Stepper(
                        "Compatível a partir de \(settings.recipeCompatibilityThresholdPercent)%",
                        value: Binding(
                            get: { settings.recipeCompatibilityThresholdPercent },
                            set: { settings.recipeCompatibilityThresholdPercent = $0 }
                        ),
                        in: 10...100,
                        step: 5
                    )

                    Toggle("Ideias só com itens da despensa", isOn: Binding(
                        get: { settings.recipeIdeasFilterByPantry },
                        set: { settings.recipeIdeasFilterByPantry = $0 }
                    ))
                }
            } header: {
                Text("Receitas")
            } footer: {
                Text("Define como receitas aparecem inicialmente, o limite mínimo para considerar uma receita compatível e se sugestões usam apenas o que já está na despensa.")
            }
        }
        .settingsFormStyle()
        .macSettingsContainer()
        .settingsNavigationTitle(String(localized: "Listas e Receitas"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
