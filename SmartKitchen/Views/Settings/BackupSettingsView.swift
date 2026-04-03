import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var backupManager = BackupManager.shared

    @State private var showRestoreConfirm = false
    @State private var restoreTarget: BackupEntry?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    @State private var isExporting = false
    @State private var exportDocument = BackupZipDocument(data: Data())
    @State private var isImporting = false

    private var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "SmartKitchen-Backup-\(formatter.string(from: .now))"
    }

    var body: some View {
        Form {
            // MARK: - Backups automáticos
            Section {
                if backupManager.isWorking {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processando…")
                            .foregroundStyle(.secondary)
                    }
                }

                if backupManager.backups.isEmpty && !backupManager.isWorking {
                    Text("Nenhum backup disponível")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backupManager.backups) { entry in
                        backupRow(entry)
                    }
                }

                Button {
                    Task {
                        await backupManager.createBackup(context: modelContext)
                    }
                } label: {
                    Label("Fazer backup agora", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(backupManager.isWorking)
            } header: {
                Text("Backups Automáticos")
            } footer: {
                Text("O app mantém até 7 backups diários. Backups antigos são removidos automaticamente.")
            }

            // MARK: - Exportar/Importar
            Section {
                Button("Exportar backup (.zip)", systemImage: "square.and.arrow.up") {
                    exportBackup()
                }

                Button("Importar backup (.zip)", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
            } header: {
                Text("Transferência Manual")
            } footer: {
                Text("Use estas opções para transferir backups entre dispositivos ou guardar uma cópia externa.")
            }
        }
        .navigationTitle("Backup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            backupManager.loadBackupList()
        }
        .confirmationDialog(
            "Restaurar backup?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restaurar", role: .destructive) {
                guard let target = restoreTarget else { return }
                Task {
                    let success = await backupManager.restore(from: target, context: modelContext)
                    if success {
                        presentAlert(title: "Backup restaurado", message: "Os dados foram restaurados com sucesso.")
                    } else {
                        presentAlert(title: "Falha", message: "Não foi possível restaurar o backup.")
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                restoreTarget = nil
            }
        } message: {
            if let target = restoreTarget {
                Text("Todos os dados atuais serão substituídos pelo backup de \(target.formattedDate).")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .smartKitchenZip,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let error) = result {
                presentAlert(title: "Falha ao exportar", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.smartKitchenZip]
        ) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                presentAlert(title: "Falha ao importar", message: error.localizedDescription)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Subviews

    private func backupRow(_ entry: BackupEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.dayLabel)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(entry.date, style: .time)
                    Text("·")
                    Text(entry.formattedSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Restaurar") {
                restoreTarget = entry
                showRestoreConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    private func exportBackup() {
        do {
            exportDocument = BackupZipDocument(data: try backupManager.exportCurrentData(context: modelContext))
            isExporting = true
        } catch {
            presentAlert(title: "Falha ao exportar", message: error.localizedDescription)
        }
    }

    private func importBackup(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try backupManager.importBackup(from: data, context: modelContext)
            presentAlert(title: "Backup importado", message: "Os dados do aplicativo foram restaurados com sucesso.")
        } catch {
            presentAlert(title: "Falha ao importar", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Zip Document

private struct BackupZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.smartKitchenZip] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension UTType {
    static let smartKitchenZip = UTType(filenameExtension: "zip") ?? .data
}
