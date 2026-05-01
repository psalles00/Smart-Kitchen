import SwiftUI
import CloudKit

struct FamilySharingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private var cloudSync = CloudSyncService.shared
    private var sharingService = SharingService.shared

    @State private var selectedScope: SharingScope = SharingService.shared.shareScope
    @State private var showInviteSheet = false
    @State private var showStopConfirm = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var shareForController: CKShare?

    var body: some View {
        Form {
            // MARK: - Prerequisite
            if !cloudSync.syncEnabled {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sincronização iCloud necessária")
                                .font(.subheadline.weight(.medium))
                            Text("Ative a sincronização iCloud antes de usar o compartilhamento familiar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    NavigationLink {
                        iCloudSettingsView()
                    } label: {
                        Label("Configurar iCloud", systemImage: "icloud")
                    }
                }
            }

            // MARK: - Sharing Toggle
            Section {
                if sharingService.isSharing {
                    HStack {
                        Label("Compartilhamento Ativo", systemImage: "person.2.fill")
                        Spacer()
                        HStack(spacing: 6) {
                            if sharingService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                            Text(sharingService.isLoading ? "Atualizando…" : "Ativo")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showStopConfirm = true
                    } label: {
                        Label("Parar Compartilhamento", systemImage: "person.2.slash")
                    }
                    .disabled(sharingService.isLoading)
                } else {
                    Button {
                        startSharing()
                    } label: {
                        Label {
                            Text("Iniciar Compartilhamento")
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.purple)
                        }
                    }
                    .disabled(!cloudSync.syncEnabled || sharingService.isLoading)
                }
            } header: {
                Text("Compartilhamento Familiar")
            } footer: {
                Text("Compartilhe dados do Savoria com familiares ou parceiros. Todos os participantes podem visualizar e editar os dados compartilhados.")
            }

            // MARK: - Scope
            if sharingService.isSharing || !cloudSync.syncEnabled == false {
                Section {
                    Picker("Escopo", selection: $selectedScope) {
                        ForEach(SharingScope.allCases) { scope in
                            Label(scope.displayName, systemImage: scope.icon)
                                .tag(scope)
                        }
                    }
                    .onChange(of: selectedScope) { _, newValue in
                        sharingService.shareScope = newValue
                    }

                    Text(selectedScope.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("O que compartilhar")
                } footer: {
                    Text("Define quais dados são relevantes para a colaboração. Todos os participantes terão acesso de leitura e escrita.")
                }
            }

            // MARK: - Invite
            if sharingService.isSharing {
                Section {
                    Button {
                        presentSharingController()
                    } label: {
                        Label("Convidar Participante", systemImage: "person.badge.plus")
                    }
                    .disabled(sharingService.isLoading)
                } header: {
                    Text("Convidar")
                }
            }

            // MARK: - Participants
            if sharingService.isSharing && !sharingService.participants.isEmpty {
                Section {
                    ForEach(sharingService.participants, id: \.userIdentity.userRecordID) { participant in
                        ParticipantRowView(participant: participant) {
                            removeParticipant(participant)
                        }
                    }
                } header: {
                    Text("Participantes")
                }
            }

            // MARK: - Error
            if let error = sharingService.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // MARK: - Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "person.2", text: String(localized: "Ideal para casais e famílias que compartilham a mesma cozinha."))
                    infoRow(icon: "pencil.and.outline", text: String(localized: "Todos os participantes podem adicionar, editar e remover itens."))
                    infoRow(icon: "icloud", text: String(localized: "Requer que todos os participantes tenham iCloud ativado."))
                    infoRow(icon: "lock.shield", text: String(localized: "Configurações pessoais e histórico da IA nunca são compartilhados."))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Informações")
            }
        }
        .macSettingsContainer()
        .modalNavigationTitle(String(localized: "Compartilhamento Familiar"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            selectedScope = sharingService.shareScope
        }
        .alert("Parar compartilhamento?", isPresented: $showStopConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Parar", role: .destructive) {
                stopSharing()
            }
        } message: {
            Text("Todos os participantes perderão acesso aos dados compartilhados. Seus dados locais serão mantidos.")
        }
        .alert("Erro", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showInviteSheet) {
            if let share = shareForController {
                CloudSharingControllerView(
                    share: share,
                    container: sharingService.cloudKitContainer
                )
            }
        }
    }

    // MARK: - Actions

    private func startSharing() {
        Task {
            do {
                let share = try await sharingService.createShare(scope: selectedScope)
                shareForController = share
                showInviteSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func stopSharing() {
        Task {
            do {
                try await sharingService.stopSharing()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func presentSharingController() {
        Task {
            do {
                if let share = sharingService.activeShare {
                    shareForController = share
                } else {
                    let share = try await sharingService.createShare(scope: selectedScope)
                    shareForController = share
                }
                showInviteSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func removeParticipant(_ participant: CKShare.Participant) {
        Task {
            do {
                try await sharingService.removeParticipant(participant)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Subviews

    private func infoRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }
}

// MARK: - Participant Row

struct ParticipantRowView: View {
    let participant: CKShare.Participant
    let onRemove: () -> Void

    private var displayName: String {
        let components = participant.userIdentity.nameComponents
        if let components, let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default, options: []) as String? {
            return formatted
        }
        return participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? String(localized: "Participante")
    }

    private var statusText: String {
        switch participant.acceptanceStatus {
        case .accepted: String(localized: "Aceito")
        case .pending: String(localized: "Pendente")
        case .removed: String(localized: "Removido")
        case .unknown: String(localized: "Desconhecido")
        @unknown default: String(localized: "Desconhecido")
        }
    }

    private var statusColor: Color {
        switch participant.acceptanceStatus {
        case .accepted: .green
        case .pending: .orange
        default: .secondary
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "person.badge.minus")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
