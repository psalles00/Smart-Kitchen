import Foundation
@preconcurrency import UserNotifications
import SwiftData

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Permission

    func requestPermissionIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if !granted {
                    // Authorization was denied or an error occurred
                    // Consider guiding the user to Settings if needed
                    // print("Notification authorization not granted")
                }
            }
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Schedule Expiry Notifications

    /// Reschedules all expiry notifications based on current pantry items and settings.
    func rescheduleExpiryNotifications(context: ModelContext, settings: AppSettings) {
        let center = UNUserNotificationCenter.current()

        // Remove all existing expiry notifications then reschedule
        Task { @MainActor in
            let existing = await center.pendingNotificationRequests()
            let expiryIDs = existing.filter { $0.identifier.hasPrefix("expiry-") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: expiryIDs)
            self.scheduleExpiryNotificationsInternal(context: context, settings: settings)
        }
    }

    private func scheduleExpiryNotificationsInternal(context: ModelContext, settings: AppSettings) {
        guard settings.notificationsEnabled, settings.expiryNotificationsEnabled else { return }

        let reminderDays = settings.expiryReminderDays.sorted(by: >)
        guard !reminderDays.isEmpty else { return }

        let hour = settings.expiryNotificationHour

        let descriptor = FetchDescriptor<UnifiedItem>(
            predicate: #Predicate<UnifiedItem> { $0.isPantry && $0.expirationDate != nil }
        )
        guard let items = try? context.fetch(descriptor) else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var scheduled = 0

        for item in items {
            guard let expirationDate = item.expirationDate else { continue }
            let expiryDay = calendar.startOfDay(for: expirationDate)

            for daysBefore in reminderDays {
                guard let notifyDate = calendar.date(byAdding: .day, value: -daysBefore, to: expiryDay) else { continue }

                // Only schedule future notifications
                if notifyDate < today { continue }

                // Limit to 60 total to stay within iOS limits
                if scheduled >= 60 { return }

                var dateComponents = calendar.dateComponents([.year, .month, .day], from: notifyDate)
                dateComponents.hour = hour
                dateComponents.minute = 0

                let content = UNMutableNotificationContent()
                content.sound = .default

                if daysBefore == 0 {
                    content.title = String(localized: "\(item.name) vence hoje!")
                    content.body = String(localized: "A validade de \(item.name) expira hoje. Confira sua despensa!")
                } else if daysBefore == 1 {
                    content.title = String(localized: "Validade de \(item.name) está prestes a expirar!")
                    content.body = String(localized: "\(item.name) vence amanhã. Hora de usar ou repor!")
                } else {
                    content.title = String(localized: "Validade de \(item.name) se aproxima")
                    content.body = String(localized: "\(item.name) vence em \(daysBefore) dias. Fique de olho!")
                }

                let identifier = "expiry-\(item.id.uuidString)-\(daysBefore)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request)
                scheduled += 1
            }
        }
    }

    // MARK: - Remove All

    func removeAllNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }
}
