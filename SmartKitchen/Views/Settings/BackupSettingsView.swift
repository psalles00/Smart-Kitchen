import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]
    @State private var backupManager = BackupManager.shared

    @State private var showRestoreConfirm = false
    @State private var restoreTarget: BackupEntry?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    @State private var isExporting = false
    @State private var exportDocument = BackupZipDocument(data: Data())
    @State private var isImporting = false
    @State private var isPickingFolder = false

    private var settings: AppSettings? { settingsArray.first }

    private var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "SmartKitchen-Backup-\(formatter.string(from: .now))"
    }

    private var folderDisplayName: String? {
        guard let bookmark = settings?.autoBackupBookmarkData else { return nil }
        var isStale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try? URL(resolvingBookmarkData: bookmark, relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        if isStale { return nil }
        return url?.lastPathComponent
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

            // MARK: - Backup automático em pasta
            Section {
                if let settings {
                    Toggle(isOn: Binding(
                        get: { settings.autoDailyBackupEnabled },
                        set: { newValue in
                            settings.autoDailyBackupEnabled = newValue
                            if newValue && settings.autoBackupBookmarkData == nil {
                                isPickingFolder = true
                            }
                        }
                    )) {
                        Label("Backup automático diário", systemImage: "calendar.badge.clock")
                    }

                    if settings.autoDailyBackupEnabled {
                        if let folder = folderDisplayName {
                            HStack {
                                Label(folder, systemImage: "folder")
                                Spacer()
                                Button("Trocar") { isPickingFolder = true }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        } else {
                            Button {
                                isPickingFolder = true
                            } label: {
                                Label("Escolher pasta de destino…", systemImage: "folder.badge.plus")
                            }
                        }
                    }
                }
            } header: {
                Text("Automático em pasta")
            } footer: {
                Text("Quando ativado, o app cria uma cópia diária do backup na pasta escolhida (recomendamos uma pasta no iCloud Drive). Mantém até 7 cópias mais recentes; arquivos do mesmo dia são substituídos.")
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
                Text("O backup exportado é um arquivo .zip que contém o conteúdo em CSV e Markdown legíveis sem o aplicativo, além das mídias originais. Pode ser importado neste mesmo formato ou no formato anterior.")
            }
        }
        .macSettingsContainer()
        .modalNavigationTitle(String(localized: "Backup"))
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
                        presentAlert(title: String(localized: "Backup restaurado"), message: String(localized: "Os dados foram restaurados com sucesso."))
                    } else {
                        presentAlert(title: String(localized: "Falha"), message: String(localized: "Não foi possível restaurar o backup."))
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
                presentAlert(title: String(localized: "Falha ao exportar"), message: error.localizedDescription)
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
                presentAlert(title: String(localized: "Falha ao importar"), message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                saveAutoBackupFolder(url)
            case .failure(let error):
                if let settings, settings.autoBackupBookmarkData == nil {
                    settings.autoDailyBackupEnabled = false
                }
                presentAlert(title: String(localized: "Falha ao escolher pasta"), message: error.localizedDescription)
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
            presentAlert(title: String(localized: "Falha ao exportar"), message: error.localizedDescription)
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
            presentAlert(title: String(localized: "Backup importado"), message: String(localized: "Os dados do aplicativo foram restaurados com sucesso."))
        } catch {
            presentAlert(title: String(localized: "Falha ao importar"), message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func saveAutoBackupFolder(_ url: URL) {
        guard let settings else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            #if os(macOS)
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            settings.autoBackupBookmarkData = bookmark
            settings.autoDailyBackupEnabled = true
        } catch {
            settings.autoDailyBackupEnabled = false
            presentAlert(title: String(localized: "Falha ao salvar pasta"), message: error.localizedDescription)
        }
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
