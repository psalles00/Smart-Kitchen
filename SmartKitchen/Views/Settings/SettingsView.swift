import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        settingsForm
            .navigationTitle("Configurações")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            #endif
            .macSettingsContainer()
    }

    private var settingsForm: some View {
        Form {
            // MARK: - iCloud
            Section {
                NavigationLink {
                    iCloudSettingsView()
                } label: {
                    Label {
                        Text("iCloud")
                    } icon: {
                        Image(systemName: "icloud")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink {
                    FamilySharingSettingsView()
                } label: {
                    Label {
                        Text("Compartilhamento Familiar")
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.purple)
                    }
                }

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label {
                        Text("Notificações")
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.red)
                    }
                }

                NavigationLink {
                    BackupSettingsView()
                } label: {
                    Label {
                        Text("Backup")
                    } icon: {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .foregroundStyle(.green)
                    }
                }
            }

            // MARK: - IA
            #if os(iOS)
            Section("Geral") {
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
            }
            #endif

            Section("IA") {
                LabeledContent("Modelo IA") {
                    Text("GPT-4.1 mini")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Listas
            Section("Listas") {
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

                    Toggle("Utensílios", isOn: Binding(
                        get: { settings.showUtensils },
                        set: { settings.showUtensils = $0 }
                    ))
                }
            }

            // MARK: - Receitas
            Section("Receitas") {
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
                }
            }

            // MARK: - Dados
            Section("Dados") {
                Button("Restaurar dados de demonstração", role: .destructive) {
                    resetData()
                }
            }

            // MARK: - Sobre
            Section("Sobre") {
                LabeledContent("Versão") {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Desenvolvido com") {
                    Text("SwiftUI + SwiftData")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetData() {
        try? modelContext.delete(model: Recipe.self)
        try? modelContext.delete(model: PantryItem.self)
        try? modelContext.delete(model: GroceryItem.self)
        try? modelContext.delete(model: UtensilItem.self)
        try? modelContext.delete(model: Category.self)
        try? modelContext.delete(model: ChatMessage.self)
        try? modelContext.delete(model: AppSettings.self)
        DataSeeder.seedIfNeeded(context: modelContext)
        try? modelContext.save()
    }
}

#if os(macOS)
struct MacSettingsContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            content
                .scrollContentBackground(.hidden)
                .padding(.top, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

extension View {
    func macSettingsContainer() -> some View {
        modifier(MacSettingsContainerModifier())
    }
}
#else
extension View {
    func macSettingsContainer() -> some View {
        self
    }
}
#endif
