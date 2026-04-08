import SwiftUI

struct iCloudSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private var cloudSync = CloudSyncService.shared
    @State private var isTransitioning = false
    @State private var showDisableConfirm = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { cloudSync.syncEnabled },
                    set: { newValue in
                        if newValue {
                            enableSync()
                        } else {
                            showDisableConfirm = true
                        }
                    }
                )) {
                    Label("Sincronizar com iCloud", systemImage: "icloud")
                }
                .disabled(isTransitioning)

                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        if isTransitioning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Circle()
                                .fill(cloudSync.iCloudAvailable ? .green : .orange)
                                .frame(width: 8, height: 8)
                        }
                        Text(isTransitioning ? "Configurando…" : cloudSync.statusDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                if cloudSync.syncEnabled && !isTransitioning {
                    Button {
                        cloudSync.syncNow()
                    } label: {
                        HStack {
                            Label("Sincronizar Agora", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if cloudSync.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(cloudSync.isSyncing)

                    if let date = cloudSync.lastSyncDate {
                        HStack {
                            Text("Última sincronização")
                            Spacer()
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = cloudSync.syncError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            } header: {
                Text("Sincronização")
            } footer: {
                Text("Quando ativado, todos os dados do Smart Kitchen são sincronizados automaticamente entre seus dispositivos Apple via iCloud.")
            }

            if cloudSync.syncEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "checkmark.icloud", text: "Receitas, ingredientes e passos")
                        infoRow(icon: "checkmark.icloud", text: "Itens da despensa")
                        infoRow(icon: "checkmark.icloud", text: "Lista de compras")
                        infoRow(icon: "checkmark.icloud", text: "Categorias personalizadas")
                        infoRow(icon: "checkmark.icloud", text: "Histórico da IA")
                        infoRow(icon: "checkmark.icloud", text: "Configurações do app")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Dados sincronizados")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Certifique-se de que está conectado ao iCloud nas Configurações do sistema.")
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Label {
                        Text("A sincronização ocorre automaticamente em segundo plano quando há conexão com a internet.")
                    } icon: {
                        Image(systemName: "wifi")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Label {
                        Text("Alterações feitas em um dispositivo aparecerão nos outros em alguns instantes.")
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Informações")
            }
        }
        .macSettingsContainer()
        .navigationTitle("iCloud")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Desativar iCloud?", isPresented: $showDisableConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Desativar", role: .destructive) {
                disableSync()
            }
        } message: {
            Text("Seus dados serão mantidos localmente neste dispositivo, mas não serão mais sincronizados entre dispositivos.")
        }
        .alert("Erro", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func enableSync() {
        isTransitioning = true
        Task {
            do {
                try await cloudSync.enableCloudSync()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isTransitioning = false
        }
    }

    private func disableSync() {
        isTransitioning = true
        Task {
            do {
                try await cloudSync.disableCloudSync()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isTransitioning = false
        }
    }

    // MARK: - Subviews

    private func infoRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.subheadline)
        }
    }
}
