import StoreKit
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var placeholderAction: AboutPlaceholderAction?

    private enum AboutPlaceholderAction: Identifiable {
        case restorePurchases
        case feedbackSupport

        var id: String { title }

        var title: String {
            switch self {
            case .restorePurchases:
                String(localized: "Restaurar compras")
            case .feedbackSupport:
                String(localized: "Feedback e suporte")
            }
        }
    }

    private var appName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Savoria"
    }

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
            .alert(item: $placeholderAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text("Em breve"),
                    dismissButton: .default(Text("OK"))
                )
            }
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
                    SettingsRowLabel("iCloud", systemImage: "icloud")
                }

                NavigationLink {
                    FamilySharingSettingsView()
                } label: {
                    SettingsRowLabel("Compartilhamento Familiar", systemImage: "person.2")
                }

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsRowLabel("Notificações", systemImage: "bell")
                }

                NavigationLink {
                    BackupSettingsView()
                } label: {
                    SettingsRowLabel("Backup", systemImage: "externaldrive.badge.timemachine")
                }
            } header: {
                Text("Conta e Sincronização")
            }

            // MARK: - Preferências
            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRowLabel("Aparência e Performance", systemImage: "paintbrush")
                }

                NavigationLink {
                    ListsSettingsView()
                } label: {
                    SettingsRowLabel("Listas e Receitas", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    NutritionSettingsView()
                } label: {
                    SettingsRowLabel("Nutrição", systemImage: "leaf")
                }
            } header: {
                Text("Preferências")
            }

            // MARK: - Dados
            Section {
                NavigationLink {
                    DataSettingsView()
                } label: {
                    SettingsRowLabel("Gerenciar dados", systemImage: "externaldrive")
                }
            } header: {
                Text("Dados")
            }

            // MARK: - Sobre
            Section {
                Button {
                    placeholderAction = .restorePurchases
                } label: {
                    SettingsRowLabel("Restaurar compras", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    placeholderAction = .feedbackSupport
                } label: {
                    SettingsRowLabel("Feedback e suporte", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)

                Button {
                    requestReview()
                } label: {
                    SettingsRowLabel("Avaliar na App Store", systemImage: "star")
                }
                .buttonStyle(.plain)

                ShareLink(item: appName, subject: Text(verbatim: appName)) {
                    SettingsRowLabel("Compartilhar app", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Sobre")
            } footer: {
                Text(verbatim: "\(appName) \(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct DataSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var cloudSync = CloudSyncService.shared
    @State private var isResettingAllData = false
    @State private var showRedoOnboarding = false
    @State private var showFullResetConfirmation = false
    @State private var showResetError = false
    @State private var resetErrorMessage = ""

    var body: some View {
        Form {
            Section {
                Button {
                    showRedoOnboarding = true
                } label: {
                    Label("Refazer onboarding", systemImage: "arrow.counterclockwise")
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
        #if os(macOS)
        .sheet(isPresented: $showRedoOnboarding) {
            OnboardingFlowView {
                showRedoOnboarding = false
            }
            .interactiveDismissDisabled(true)
        }
        #else
        .fullScreenCover(isPresented: $showRedoOnboarding) {
            OnboardingFlowView {
                showRedoOnboarding = false
            }
            .interactiveDismissDisabled(true)
        }
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
