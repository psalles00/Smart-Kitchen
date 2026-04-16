import SwiftUI
import SwiftData

struct BackupSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Backup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configurações de Backup")
                        .font(.headline)
                    Text("Esta tela será expandida para permitir criar, restaurar e exportar backups dos seus dados.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Ações") {
                Button("Criar backup agora") {
                    // TODO: Integrar com BackupManager.shared.createBackup(context:)
                }
                .disabled(true)

                Button("Restaurar de um backup") {
                    // TODO: Integrar com seleção e restauração de BackupManager
                }
                .disabled(true)

                Button("Exportar backup") {
                    // TODO: Integrar com exportação via BackupManager
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Backup")
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
    }
}

#Preview {
    NavigationStack { BackupSettingsView() }
}
