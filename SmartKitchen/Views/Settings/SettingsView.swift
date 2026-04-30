import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.2.6"
    }

    var body: some View {
        settingsForm
            .modalNavigationTitle(String(localized: "Configurações"))
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
            // MARK: - Plano
            Section {
                PlanCardView()
            }

            // MARK: - Conta e Sincronização
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
            } header: {
                Text("Conta e Sincronização")
            }

            // MARK: - Preferências
            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label {
                        Text("Aparência e Performance")
                    } icon: {
                        Image(systemName: "paintbrush.pointed")
                            .foregroundStyle(.indigo)
                    }
                }

                NavigationLink {
                    ListsSettingsView()
                } label: {
                    Label {
                        Text("Listas e Receitas")
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.teal)
                    }
                }

                NavigationLink {
                    NutritionSettingsView()
                } label: {
                    Label {
                        Text("Nutrição")
                    } icon: {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(PageTheme.nutrients.accentColor)
                    }
                }
            } header: {
                Text("Preferências")
            }

            // MARK: - Dados
            Section {
                NavigationLink {
                    DataSettingsView()
                } label: {
                    Label {
                        Text("Gerenciar dados")
                    } icon: {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Dados")
            }

            // MARK: - Sobre
            Section {
                LabeledContent("Versão") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Desenvolvido por") {
                    Text(verbatim: "Salles Tech")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sobre")
            }
        }
        .formStyle(.grouped)
    }
}

struct DataSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var cloudSync = CloudSyncService.shared
    @State private var isResettingAllData = false
    @State private var showFullResetConfirmation = false
    @State private var showResetError = false
    @State private var resetErrorMessage = ""

    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    restoreDemoData()
                } label: {
                    Label("Restaurar dados de demonstração", systemImage: "arrow.counterclockwise")
                }
                .disabled(isResettingAllData)

                Button(role: .destructive) {
                    showFullResetConfirmation = true
                } label: {
                    HStack {
                        Label("Apagar todos os dados locais e do iCloud", systemImage: "trash")
                        Spacer()
                        if isResettingAllData {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isResettingAllData)
            }
        }
        .formStyle(.grouped)
        .macSettingsContainer()
        .modalNavigationTitle(String(localized: "Dados"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Apagar todos os dados?", isPresented: $showFullResetConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar tudo", role: .destructive) {
                eraseAllData()
            }
        } message: {
            Text("Isso apagará receitas, listas, categorias, histórico da IA, backups internos e os dados sincronizados no iCloud deste app. A ação é irreversível.")
        }
        .alert("Erro", isPresented: $showResetError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetErrorMessage)
        }
    }

    private func restoreDemoData() {
        if let recipes = try? modelContext.fetch(FetchDescriptor<Recipe>()) {
            for recipe in recipes {
                modelContext.delete(recipe)
            }
        }
        try? modelContext.delete(model: UnifiedItem.self)
        try? modelContext.delete(model: PantryItem.self)
        try? modelContext.delete(model: GroceryItem.self)
        try? modelContext.delete(model: UtensilItem.self)
        try? modelContext.delete(model: Category.self)
        try? modelContext.delete(model: DeletedDefaultCategory.self)
        try? modelContext.delete(model: ChatMessage.self)
        try? modelContext.delete(model: AppSettings.self)
        DataSeeder.seedIfNeeded(context: modelContext)
        try? modelContext.save()
    }

    private func eraseAllData() {
        guard !isResettingAllData else { return }

        isResettingAllData = true
        Task { @MainActor in
            do {
                try await cloudSync.resetAllDataLocallyAndInICloud()
                dismiss()
            } catch {
                resetErrorMessage = error.localizedDescription
                showResetError = true
            }

            isResettingAllData = false
        }
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
