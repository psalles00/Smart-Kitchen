import StoreKit
import SwiftUI
import SwiftData

enum SettingsDestination: String, CaseIterable, Identifiable {
    case iCloud
    case familySharing
    case notifications
    case backup
    case appearance
    case lists
    case nutrition
    case data

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .iCloud:
            "iCloud"
        case .familySharing:
            "Compartilhamento Familiar"
        case .notifications:
            "Notificações"
        case .backup:
            "Backup"
        case .appearance:
            "Aparência e Performance"
        case .lists:
            "Listas e Receitas"
        case .nutrition:
            "Nutrição"
        case .data:
            "Gerenciar dados"
        }
    }

    var title: String {
        switch self {
        case .iCloud:
            String(localized: "iCloud")
        case .familySharing:
            String(localized: "Compartilhamento Familiar")
        case .notifications:
            String(localized: "Notificações")
        case .backup:
            String(localized: "Backup")
        case .appearance:
            String(localized: "Aparência e Performance")
        case .lists:
            String(localized: "Listas e Receitas")
        case .nutrition:
            String(localized: "Nutrição")
        case .data:
            String(localized: "Gerenciar dados")
        }
    }

    var systemImage: String {
        switch self {
        case .iCloud:
            "icloud"
        case .familySharing:
            "person.2"
        case .notifications:
            "bell"
        case .backup:
            "externaldrive.badge.timemachine"
        case .appearance:
            "paintbrush"
        case .lists:
            "list.bullet.rectangle"
        case .nutrition:
            "leaf"
        case .data:
            "externaldrive"
        }
    }
}

private struct OpenSettingsDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (SettingsDestination) -> Void)? = nil
}

extension EnvironmentValues {
    var openSettingsDestination: (@MainActor @Sendable (SettingsDestination) -> Void)? {
        get { self[OpenSettingsDestinationKey.self] }
        set { self[OpenSettingsDestinationKey.self] = newValue }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var placeholderAction: AboutPlaceholderAction?
    #if os(macOS)
    @State private var selectedMacDestination: SettingsDestination = .iCloud
    #endif

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
        Group {
            #if os(iOS)
            settingsForm
                .settingsNavigationTitle(String(localized: "Configurações"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
            #else
            macSettingsLayout
                .environment(\.openSettingsDestination) { destination in
                    selectedMacDestination = destination
                }
            #endif
        }
            .alert(item: $placeholderAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text("Em breve"),
                    dismissButton: .default(Text("OK"))
                )
            }
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
        .settingsFormStyle()
    }

    #if os(macOS)
    private var macSettingsLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            macSettingsSidebar
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)

            macSettingsDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var macSettingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Configurações"))
                        .font(.pageTitle)

                    Text(verbatim: "\(appName) \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                PlanCardView()
                    .padding(18)
                    .macSettingsInsetCardStyle()

                macSettingsSection(
                    title: "Conta e Sincronização",
                    destinations: [.iCloud, .familySharing, .notifications, .backup]
                )

                macSettingsSection(
                    title: "Preferências",
                    destinations: [.appearance, .lists, .nutrition]
                )

                macSettingsSection(
                    title: "Dados",
                    destinations: [.data]
                )

                macAboutSection
            }
            .padding(20)
        }
        .scrollIndicators(.never)
        .macSettingsPaneStyle()
    }

    private var macAboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sobre")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                placeholderAction = .restorePurchases
            } label: {
                SettingsRowLabel("Restaurar compras", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                placeholderAction = .feedbackSupport
            } label: {
                SettingsRowLabel("Feedback e suporte", systemImage: "questionmark.circle")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                requestReview()
            } label: {
                SettingsRowLabel("Avaliar na App Store", systemImage: "star")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            ShareLink(item: appName, subject: Text(verbatim: appName)) {
                SettingsRowLabel("Compartilhar app", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .macSettingsInsetCardStyle()
    }

    private func macSettingsSection(title: LocalizedStringKey, destinations: [SettingsDestination]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(destinations) { destination in
                    macSettingsDestinationButton(destination)
                }
            }
        }
        .padding(18)
        .macSettingsInsetCardStyle()
    }

    private func macSettingsDestinationButton(_ destination: SettingsDestination) -> some View {
        let isSelected = selectedMacDestination == destination

        return Button {
            selectedMacDestination = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.78) : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        isSelected ? Color.white : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                Text(destination.titleKey)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.16, green: 0.56, blue: 0.98), Color(red: 0.26, green: 0.77, blue: 0.68)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.04))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.10 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var macSettingsDetailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedMacDestination.titleKey)
                    .font(.sectionTitle)

                Text(String(localized: "Configurações"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            macSettingsDetailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macSettingsPaneStyle()
    }

    @ViewBuilder
    private var macSettingsDetailContent: some View {
        switch selectedMacDestination {
        case .iCloud:
            iCloudSettingsView()
        case .familySharing:
            FamilySharingSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .backup:
            BackupSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .lists:
            ListsSettingsView()
        case .nutrition:
            NutritionSettingsView()
        case .data:
            DataSettingsView()
        }
    }
    #endif
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
        .settingsFormStyle()
        .macSettingsContainer()
        .settingsNavigationTitle(String(localized: "Dados"))
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
        content
    }
}

private struct MacSettingsPaneModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
    }
}

private struct MacSettingsInsetCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func macSettingsContainer() -> some View {
        modifier(MacSettingsContainerModifier())
    }

    func macSettingsPaneStyle() -> some View {
        modifier(MacSettingsPaneModifier())
    }

    func macSettingsInsetCardStyle() -> some View {
        modifier(MacSettingsInsetCardModifier())
    }

    func settingsFormStyle() -> some View {
        self
    }
}
#else
extension View {
    func macSettingsContainer() -> some View {
        self
    }

    func settingsFormStyle() -> some View {
        formStyle(.grouped)
    }
}
#endif
