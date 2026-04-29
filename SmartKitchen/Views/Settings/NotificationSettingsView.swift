import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]

    @State private var systemPermission: UNAuthorizationStatus = .notDetermined

    private var settings: AppSettings? { settingsArray.first }

    var body: some View {
        Form {
            permissionSection

            if let settings, systemPermission == .authorized {
                expirySection(settings)
            }
        }
        .formStyle(.grouped)
        .modalNavigationTitle(String(localized: "Notificações"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await refreshPermission()
        }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        Section {
            if systemPermission == .authorized {
                if let settings {
                    Toggle("Notificações ativadas", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { newValue in
                            settings.notificationsEnabled = newValue
                            reschedule()
                        }
                    ))
                }
            } else if systemPermission == .denied {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Notificações bloqueadas", systemImage: "bell.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("As notificações estão desativadas nas Configurações do sistema. Toque para abrir e permitir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    openSystemSettings()
                }
            } else {
                Button {
                    requestPermission()
                } label: {
                    Label("Permitir  Notificações", systemImage: "bell.badge")
                }
            }
        } footer: {
            if systemPermission == .authorized, settings?.notificationsEnabled == true {
                Text("Notificações serão enviadas localmente com base nos seus itens de despensa.")
            }
        }
    }

    // MARK: - Expiry Notifications

    private func expirySection(_ settings: AppSettings) -> some View {
        Section("Validade dos itens") {
            Toggle("Avisar sobre validade próxima", isOn: Binding(
                get: { settings.expiryNotificationsEnabled },
                set: { newValue in
                    settings.expiryNotificationsEnabled = newValue
                    reschedule()
                }
            ))

            if settings.expiryNotificationsEnabled {
                Picker("Horário do lembrete", selection: Binding(
                    get: { settings.expiryNotificationHour },
                    set: { settings.expiryNotificationHour = $0; reschedule() }
                )) {
                    ForEach(6..<23) { hour in
                        Text(formattedHour(hour)).tag(hour)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quando avisar")
                        .font(.subheadline.weight(.medium))

                    let currentDays = settings.expiryReminderDays

                    ForEach(availableReminderOptions, id: \.days) { option in
                        let isOn = currentDays.contains(option.days)
                        Toggle(option.label, isOn: Binding(
                            get: { isOn },
                            set: { newValue in
                                var days = settings.expiryReminderDays
                                if newValue {
                                    if !days.contains(option.days) { days.append(option.days) }
                                } else {
                                    days.removeAll { $0 == option.days }
                                }
                                settings.expiryReminderDays = days
                                reschedule()
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private struct ReminderOption {
        let days: Int
        let label: String
    }

    private var availableReminderOptions: [ReminderOption] {
        [
            ReminderOption(days: 7, label: "7 dias antes"),
            ReminderOption(days: 3, label: "3 dias antes"),
            ReminderOption(days: 1, label: "1 dia antes"),
            ReminderOption(days: 0, label: "No dia do vencimento"),
        ]
    }

    private func formattedHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemPermission = settings.authorizationStatus
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                await refreshPermission()
                if granted {
                    settings?.notificationsEnabled = true
                    reschedule()
                }
            }
        }
    }

    private func reschedule() {
        guard let settings else { return }
        NotificationService.shared.rescheduleExpiryNotifications(context: modelContext, settings: settings)
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
