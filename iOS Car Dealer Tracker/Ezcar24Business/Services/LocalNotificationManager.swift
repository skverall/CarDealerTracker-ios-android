import CoreData
import Foundation
import UIKit
import UserNotifications

enum NotificationPreference {
    static let enabledKey = "notificationsEnabled"
    static let inventoryStaleThresholdKey = "inventoryStaleThresholdDays"
    static let inventoryDigestLastSignatureKey = "inventoryDigestLastSignature"
    static let inventoryDigestLastSnapshotDayKey = "inventoryDigestLastSnapshotDay"
    static let defaultInventoryStaleThreshold = 40

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }
    
    static var inventoryStaleThreshold: Int {
        let value = UserDefaults.standard.integer(forKey: inventoryStaleThresholdKey)
        return value == 0 ? defaultInventoryStaleThreshold : value
    }
    
    static func setInventoryStaleThreshold(_ value: Int) {
        UserDefaults.standard.set(value, forKey: inventoryStaleThresholdKey)
    }

    static var inventoryDigestLastSignature: String? {
        UserDefaults.standard.string(forKey: inventoryDigestLastSignatureKey)
    }

    static var inventoryDigestLastSnapshotDay: String? {
        UserDefaults.standard.string(forKey: inventoryDigestLastSnapshotDayKey)
    }

    static func setInventoryDigestLastSignature(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: inventoryDigestLastSignatureKey)
        } else {
            UserDefaults.standard.removeObject(forKey: inventoryDigestLastSignatureKey)
        }
    }

    static func setInventoryDigestLastSnapshotDay(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: inventoryDigestLastSnapshotDayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: inventoryDigestLastSnapshotDayKey)
        }
    }

    static func clearInventoryDigestSnapshot() {
        setInventoryDigestLastSignature(nil)
        setInventoryDigestLastSnapshotDay(nil)
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
            request.predicate = NSPredicate(format: "deletedAt == nil AND isCompleted == NO AND dueDate != nil AND client.deletedAt == nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClientReminder.dueDate, ascending: true)]
            return (try? context.fetch(request)) ?? []
        }

        for reminder in reminders {
            guard let dueDate = reminder.dueDate, dueDate > now else { continue }
            await scheduleClientReminder(reminder)
        }

        let debts: [Debt] = await context.perform {
            let request: NSFetchRequest<Debt> = Debt.fetchRequest()
            request.predicate = NSPredicate(format: "deletedAt == nil AND dueDate != nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Debt.dueDate, ascending: true)]
            return (try? context.fetch(request)) ?? []
        }

        for debt in debts {
            guard let dueDate = debt.dueDate, dueDate > now, !debt.isPaid else { continue }
            await scheduleDebtDue(debt)
        }
        
        let vehicles: [Vehicle] = await context.perform {
            let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
            request.predicate = NSPredicate(format: "deletedAt == nil AND status != %@", "sold")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchaseDate, ascending: true)]
            return (try? context.fetch(request)) ?? []
        }
        
        let inventoryThreshold = NotificationPreference.inventoryStaleThreshold
        
        var staleVehicles: [(vehicle: Vehicle, days: Int)] = []

        for vehicle in vehicles {
            let days = HoldingCostCalculator.calculateDaysInInventory(vehicle: vehicle)
            guard HoldingCostCalculator.isHoldingCostEligible(vehicle: vehicle) else { continue }
            guard days >= inventoryThreshold else { continue }
            staleVehicles.append((vehicle, days))
        }

        guard !staleVehicles.isEmpty else {
            NotificationPreference.clearInventoryDigestSnapshot()
            await scheduleDailyExpenseReminder()
            return
        }

        let digestSignature = inventoryDigestSignature(staleVehicles)
        if shouldSendInventoryDigest(currentSignature: digestSignature, now: now) {
            await scheduleInventoryDigestAlert(staleVehicles, threshold: inventoryThreshold)
        }
        rememberInventoryDigestSnapshot(signature: digestSignature, date: now)
        
        await scheduleDailyExpenseReminder()
    }

    func clearAll() async {
        await clearAllPending()
        center.removeAllDeliveredNotifications()
        try? await center.setBadgeCount(0)
        NotificationPreference.clearInventoryDigestSnapshot()
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
    
    private func scheduleInventoryDigestAlert(
        _ staleVehicles: [(vehicle: Vehicle, days: Int)],
        threshold: Int
    ) async {
        guard !staleVehicles.isEmpty else { return }

        let identifier = NotificationIdentifier.inventoryDigest
        let content = UNMutableNotificationContent()
        
        let title = await MainActor.run { "inventory_alert_title".localizedString }
        let defaultVehicleName = await MainActor.run { "vehicle".localizedString }

        let sortedVehicles = staleVehicles.sorted { $0.days > $1.days }
        let criticalThreshold = max(90, threshold + 30)
        let criticalCount = sortedVehicles.filter { $0.days >= criticalThreshold }.count
        let topVehicles = sortedVehicles
            .prefix(3)
            .map { "\(vehicleDisplayName(for: $0.vehicle, defaultName: defaultVehicleName)) (\($0.days)d)" }
            .joined(separator: ", ")
        let body = inventoryDigestBody(
            totalCount: sortedVehicles.count,
            threshold: threshold,
            criticalCount: criticalCount,
            criticalThreshold: criticalThreshold,
            topVehicles: topVehicles
        )
        
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: sortedVehicles.count)
        
        let triggerDate = nextInventoryAlertDate()
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )
        
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func vehicleDisplayName(for vehicle: Vehicle, defaultName: String) -> String {
        let name = [vehicle.make, vehicle.model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? defaultName : name
    }

    private func inventoryDigestBody(
        totalCount: Int,
        threshold: Int,
        criticalCount: Int,
        criticalThreshold: Int,
        topVehicles: String
    ) -> String {
        let languageCode = Locale.current.identifier.lowercased()

        if languageCode.hasPrefix("ru") {
            return "\(totalCount) авто > \(threshold) дн.; \(criticalCount) авто > \(criticalThreshold) дн. Топ: \(topVehicles)"
        }

        return "\(totalCount) vehicles over \(threshold)d; \(criticalCount) over \(criticalThreshold)d. Top: \(topVehicles)"
    }

    private func inventoryDigestSignature(_ staleVehicles: [(vehicle: Vehicle, days: Int)]) -> String {
        staleVehicles
            .map { $0.vehicle.id?.uuidString ?? $0.vehicle.objectID.uriRepresentation().absoluteString }
            .sorted()
            .joined(separator: ",")
    }

    private func shouldSendInventoryDigest(currentSignature: String, now: Date) -> Bool {
        guard let previousSignature = NotificationPreference.inventoryDigestLastSignature,
              let previousSnapshotDay = NotificationPreference.inventoryDigestLastSnapshotDay else {
            return true
        }

        guard previousSignature == currentSignature else {
            return true
        }

        return previousSnapshotDay != dayString(for: calendarDate(byAddingDays: -1, from: now))
    }

    private func rememberInventoryDigestSnapshot(signature: String, date: Date) {
        NotificationPreference.setInventoryDigestLastSignature(signature)
        NotificationPreference.setInventoryDigestLastSnapshotDay(dayString(for: date))
    }

    private func calendarDate(byAddingDays days: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private func dayString(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    private func nextInventoryAlertDate() -> Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        
        let todayAtNine = Calendar.current.date(from: components) ?? now
        if todayAtNine > now {
            return todayAtNine
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: todayAtNine) ?? now.addingTimeInterval(3600)
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
    static let inventoryDigest = "\(prefix).inventory.digest"

    static func clientReminder(id: UUID) -> String {
        "\(prefix).client.\(id.uuidString)"
    }

    static func debtDue(id: UUID) -> String {
        "\(prefix).debt.\(id.uuidString)"
    }
    
}
