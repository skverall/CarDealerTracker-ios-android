import CoreData
import Foundation
import UIKit
import UserNotifications

enum NotificationPreference {
    static let enabledKey = "notificationsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }
}

final class LocalNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func refreshAll(context: NSManagedObjectContext) async {
        guard NotificationPreference.isEnabled else {
            await clearAll()
            return
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            await clearAll()
            return
        }

        await clearAllPending()

        let now = Date()
        let reminders: [ClientReminder] = await context.perform {
            let request: NSFetchRequest<ClientReminder> = ClientReminder.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == NO AND dueDate != nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClientReminder.dueDate, ascending: true)]
            return (try? context.fetch(request)) ?? []
        }

        for reminder in reminders {
            guard let dueDate = reminder.dueDate, dueDate > now else { continue }
            await scheduleClientReminder(reminder)
        }

        let debts: [Debt] = await context.perform {
            let request: NSFetchRequest<Debt> = Debt.fetchRequest()
            request.predicate = NSPredicate(format: "dueDate != nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Debt.dueDate, ascending: true)]
            return (try? context.fetch(request)) ?? []
        }

        for debt in debts {
            guard let dueDate = debt.dueDate, dueDate > now, !debt.isPaid else { continue }
            await scheduleDebtDue(debt)
        }
        
        await scheduleDailyExpenseReminder()
    }

    func clearAll() async {
        await clearAllPending()
        center.removeAllDeliveredNotifications()
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // MARK: - Scheduling

    private func scheduleDailyExpenseReminder() async {
        let identifier = NotificationIdentifier.dailyReminder
        let content = UNMutableNotificationContent()
        
        // Fetch localized strings on MainActor
        let title = await MainActor.run { "daily_expense_reminder_title".localizedString }
        let body = await MainActor.run { "daily_expense_reminder_body".localizedString }
        
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 20 // 8 PM
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func scheduleClientReminder(_ reminder: ClientReminder) async {
        guard let id = reminder.id, let dueDate = reminder.dueDate else { return }
        let identifier = NotificationIdentifier.clientReminder(id: id)
        let content = UNMutableNotificationContent()
        let clientName = reminder.client?.name ?? "Client"
        content.title = "Client Reminder"
        content.body = "\(clientName) • \(reminder.title ?? "Follow up")"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate),
            repeats: false
        )

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func scheduleDebtDue(_ debt: Debt) async {
        guard let id = debt.id, let dueDate = debt.dueDate else { return }
        let identifier = NotificationIdentifier.debtDue(id: id)
        let content = UNMutableNotificationContent()
        let name = debt.counterpartyName ?? "Counterparty"
        let amount = debt.outstandingAmount.asCurrencyFallback()
        content.title = debt.directionEnum == .owedToMe ? "Debt Collection Due" : "Debt Payment Due"
        content.body = "\(name) • \(amount)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate),
            repeats: false
        )

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func clearAllPending() async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests
            .map { $0.identifier }
            .filter { $0.hasPrefix(NotificationIdentifier.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

enum NotificationIdentifier {
    static let prefix = "ezcar24.notification"
    static let dailyReminder = "\(prefix).dailyReminder"

    static func clientReminder(id: UUID) -> String {
        "\(prefix).client.\(id.uuidString)"
    }

    static func debtDue(id: UUID) -> String {
        "\(prefix).debt.\(id.uuidString)"
    }
}
