import SwiftUI
import SwiftData

struct iCloudSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]
    private var cloudSync = CloudSyncService.shared
    @State private var isTransitioning = false
    @State private var showDisableConfirm = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var pendingPaywallReason: PaywallSheet.Reason?
    @State private var gate = FeatureGate.shared

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { cloudSync.syncEnabled },
                    set: { newValue in
                        if newValue {
                            // DATA SAFETY: hard gate aplica-se apenas ao
                            // toggle ON inicial. Se sync já está ON
                            // (premium expirado), nunca desliga.
                            if !gate.canAccess(.iCloudSync) {
                                pendingPaywallReason = .hardGate(FeatureGate.HardFeature.iCloudSync.displayName)
                                return
                            }
                            enableSync()
                        } else {
                            showDisableConfirm = true
                        }
                    }
                )) {
                    HStack {
                        Label("Sincronizar com iCloud", systemImage: "icloud")
                        if !gate.canAccess(.iCloudSync) && !cloudSync.syncEnabled {
                            Spacer(minLength: 8)
                            premiumBadge
                        }
                    }
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
                        Text(isTransitioning ? String(localized: "Configurando…") : cloudSync.statusDescription)
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
                Text("Quando ativado, todos os dados do Savoria são sincronizados automaticamente entre seus dispositivos Apple via iCloud.")
            }

            if cloudSync.syncEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Receitas, ingredientes e passos"))
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Itens da despensa"))
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Lista de compras"))
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Categorias personalizadas"))
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Histórico da IA"))
                        infoRow(icon: "checkmark.icloud", text: String(localized: "Configurações do app"))
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Dados sincronizados")
                }

                Section {
                    if let settings {
                        Toggle(isOn: Binding(
                            get: { settings.syncRecipeMediaToCloud },
                            set: { settings.syncRecipeMediaToCloud = $0 }
                        )) {
                            Label("Sincronizar mídias de receitas", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                } header: {
                    Text("Mídias")
                } footer: {
                    Text("Quando ativo (padrão), fotos e vídeos das receitas são incluídos em backups e elegíveis para sincronização entre dispositivos. Ao desativar, novos backups e arquivos exportados deixam de incluir mídias para reduzir uso de armazenamento na nuvem.")
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
        .settingsFormStyle()
        .macSettingsContainer()
        .settingsNavigationTitle(String(localized: "iCloud"))
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
        .sheet(item: $pendingPaywallReason) { reason in
            PaywallSheet(reason: reason)
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

    private var premiumBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("Premium")
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.83, blue: 0.43),
                        Color(red: 0.82, green: 0.60, blue: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
    }
}
