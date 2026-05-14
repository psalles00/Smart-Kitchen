import StoreKit
import SwiftUI
import SwiftData

enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
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
    @State private var selectedMacDestination: SettingsDestination? = .iCloud
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

    #if os(macOS)
    private var resolvedSelectedMacDestination: SettingsDestination {
        selectedMacDestination ?? .iCloud
    }
    #endif

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
        NavigationSplitView {
            macSettingsSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            macSettingsDetailPane
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var macSettingsSidebar: some View {
        List(selection: $selectedMacDestination) {
            Section {
                PlanCardView()
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

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

            Section("Sobre") {
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
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(String(localized: "Configurações"))
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: "\(appName) \(appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }

    private func macSettingsSection(title: LocalizedStringKey, destinations: [SettingsDestination]) -> some View {
        Section(title) {
            ForEach(destinations) { destination in
                Label(destination.titleKey, systemImage: destination.systemImage)
                    .tag(destination)
                    .contentShape(Rectangle())
            }
        }
    }

    private var macSettingsDetailPane: some View {
        macSettingsDetailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var macSettingsDetailContent: some View {
        switch resolvedSelectedMacDestination {
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

extension View {
    func macSettingsContainer() -> some View {
        modifier(MacSettingsContainerModifier())
    }

    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - MacSettingsExpandedPage

/// Settings page used by the macOS sidebar. Wraps the settings UI inside
/// `ExpandedPageLayout(pageTheme: .settings, ...)` — i.e. the same shell as
/// Listas / Nutrição, with the gray-tinted nebula shader as background.
///
/// Unlike the sheet variant (`SettingsView`), this view does NOT embed a
/// `NavigationSplitView` nor force a 1240pt minimum width — both of which
/// previously caused content to be clipped/shifted when Settings was hosted
/// inside the main sidebar's detail pane.
struct MacSettingsExpandedPage: View {
    @State private var selectedDestination: SettingsDestination = .iCloud
    @Environment(\.requestReview) private var requestReview
    @State private var placeholderAction: PlaceholderAction?

    private enum PlaceholderAction: Identifiable {
        case restorePurchases
        case feedbackSupport

        var id: String {
            switch self {
            case .restorePurchases: return "restore"
            case .feedbackSupport: return "feedback"
            }
        }

        var title: String {
            switch self {
            case .restorePurchases: return String(localized: "Restaurar compras")
            case .feedbackSupport: return String(localized: "Feedback e suporte")
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
        ExpandedPageLayout(
            pageTheme: .settings,
            header: { isInverted in
                PageHeader(title: String(localized: "Configurações"), isInverted: isInverted)
            },
            content: {
                HStack(spacing: 0) {
                    settingsListColumn
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                    Divider()
                    settingsDetailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .environment(\.openSettingsDestination) { destination in
                    selectedDestination = destination
                }
                .alert(item: $placeholderAction) { action in
                    Alert(
                        title: Text(action.title),
                        message: Text("Em breve"),
                        dismissButton: .default(Text("OK"))
                    )
                }
            },
            infoContent: { EmptyView() }
        )
    }

    @ViewBuilder
    private var settingsListColumn: some View {
        List(selection: $selectedDestination) {
            Section {
                PlanCardView()
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section("Conta e Sincronização") {
                ForEach([SettingsDestination.iCloud, .familySharing, .notifications, .backup]) { dest in
                    Label(dest.titleKey, systemImage: dest.systemImage).tag(dest)
                }
            }

            Section("Preferências") {
                ForEach([SettingsDestination.appearance, .lists, .nutrition]) { dest in
                    Label(dest.titleKey, systemImage: dest.systemImage).tag(dest)
                }
            }

            Section("Dados") {
                Label(SettingsDestination.data.titleKey, systemImage: SettingsDestination.data.systemImage)
                    .tag(SettingsDestination.data)
            }

            Section("Sobre") {
                Button {
                    placeholderAction = .restorePurchases
                } label: {
                    Label("Restaurar compras", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    placeholderAction = .feedbackSupport
                } label: {
                    Label("Feedback e suporte", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)

                Button {
                    requestReview()
                } label: {
                    Label("Avaliar na App Store", systemImage: "star")
                }
                .buttonStyle(.plain)

                ShareLink(item: appName, subject: Text(verbatim: appName)) {
                    Label("Compartilhar app", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: "\(appName) \(appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var settingsDetailColumn: some View {
        switch selectedDestination {
        case .iCloud:        iCloudSettingsView()
        case .familySharing: FamilySharingSettingsView()
        case .notifications: NotificationSettingsView()
        case .backup:        BackupSettingsView()
        case .appearance:    AppearanceSettingsView()
        case .lists:         ListsSettingsView()
        case .nutrition:     NutritionSettingsView()
        case .data:          DataSettingsView()
        }
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
