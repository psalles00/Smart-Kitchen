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

                    #if os(iOS)
                    HStack(spacing: 8) {
                        Text("Mostrar Para depois")
                        SectionInfoButton(
                            title: "Para depois",
                            message: "Guarde itens que acabaram, mas que você ainda não decidiu comprar novamente. Ao marcar um item na Despensa, ele vai para Para depois; nesta lista, vai para o Mercado; no Mercado, volta à Despensa. Desativar a opção apenas oculta a lista, sem apagar seus itens."
                        )
                        .accessibilityIdentifier("savoria.lists.reserve.info")
                        Spacer(minLength: 8)
                        Toggle("Mostrar Para depois", isOn: Binding(
                            get: { settings.showReserve },
                            set: { settings.showReserve = $0 }
                        ))
                        .labelsHidden()
                        .accessibilityIdentifier("savoria.lists.reserve.enabled")
                    }
                    #else
                    Toggle("Mostrar Para depois", isOn: Binding(
                        get: { settings.showReserve },
                        set: { settings.showReserve = $0 }
                    ))
                    .accessibilityIdentifier("savoria.lists.reserve.enabled")
                    #endif

                    Toggle("Mostrar utensílios", isOn: Binding(
                        get: { settings.showUtensils },
                        set: { settings.showUtensils = $0 }
                    ))
                }
            } header: {
                Text("Despensa e mercado")
            } footer: {
                #if !os(iOS)
                Text("Itens finalizados vão para Para depois quando habilitada. Marque-os para enviar ao Mercado. Ocultar a lista preserva seus itens.")
                #endif
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
