import CoreData
import Foundation
import UIKit
import UserNotifications

enum NotificationPreference {
    static let enabledKey = "notificationsEnabled"
    static let inventoryStaleThresholdKey = "inventoryStaleThresholdDays"
    static let inventoryDigestLastSignatureKey = "inventoryDigestLastSignature"
    static let inventoryDigestLastSnapshotDayKey = "inventoryDigestLastSnapshotDay"
    static let feedbackNudgeLastOpenedKey = "feedbackNudgeLastOpenedAt"
    static let feedbackNudgeNextTriggerKey = "feedbackNudgeNextTriggerAt"
    static let defaultInventoryStaleThreshold = 40
    static let feedbackNudgeIntervalDays = 4

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

    static var feedbackNudgeLastOpenedAt: Date? {
        UserDefaults.standard.object(forKey: feedbackNudgeLastOpenedKey) as? Date
    }

    static var feedbackNudgeNextTriggerAt: Date? {
        UserDefaults.standard.object(forKey: feedbackNudgeNextTriggerKey) as? Date
    }

    static func setFeedbackNudgeLastOpenedAt(_ value: Date?) {
        if let value {
            UserDefaults.standard.set(value, forKey: feedbackNudgeLastOpenedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: feedbackNudgeLastOpenedKey)
        }
    }

    static func setFeedbackNudgeNextTriggerAt(_ value: Date?) {
        if let value {
            UserDefaults.standard.set(value, forKey: feedbackNudgeNextTriggerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: feedbackNudgeNextTriggerKey)
        }
    }
}

final class LocalNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationManager()

    /// Set when a notification is tapped and cleared once the deep link is consumed. Unlike a
    /// one-shot `NotificationCenter.default.post`, a `@Published` value keeps its current state
    /// for late subscribers — so a cold launch (where the view that would navigate hasn't
    /// mounted, or the session hasn't finished restoring, at the moment the tap is delivered)
    /// still gets picked up once the app is actually ready.
    @Published private(set) var pendingDeepLinkDestination: String?

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

    func refreshAll(context: NSManagedObjectContext, shouldScheduleFeedbackNudge: Bool = true) async {
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
            await scheduleFeedbackBoardNudgeIfNeeded(now: now, shouldSchedule: shouldScheduleFeedbackNudge)
            return
        }

        let digestSignature = inventoryDigestSignature(staleVehicles)
        if shouldSendInventoryDigest(currentSignature: digestSignature, now: now) {
            await scheduleInventoryDigestAlert(staleVehicles, threshold: inventoryThreshold)
        }
        rememberInventoryDigestSnapshot(signature: digestSignature, date: now)
        
        await scheduleDailyExpenseReminder()
        await scheduleFeedbackBoardNudgeIfNeeded(now: now, shouldSchedule: shouldScheduleFeedbackNudge)
    }

    func clearAll() async {
        await clearAllPending()
        center.removeAllDeliveredNotifications()
        try? await center.setBadgeCount(0)
        NotificationPreference.clearInventoryDigestSnapshot()
        NotificationPreference.setFeedbackNudgeNextTriggerAt(nil)
    }

    @MainActor
    func recordFeedbackBoardOpened() {
        NotificationPreference.setFeedbackNudgeLastOpenedAt(Date())
        NotificationPreference.setFeedbackNudgeNextTriggerAt(nil)
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIdentifier.feedbackBoardNudge])
    }

    @MainActor
    func clearPendingDeepLink() {
        pendingDeepLinkDestination = nil
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let destination = request.content.userInfo["destination"] as? String
        guard request.identifier == NotificationIdentifier.feedbackBoardNudge ||
                destination == NotificationDestination.feedbackBoard else { return }

        await MainActor.run {
            recordFeedbackBoardOpened()
            pendingDeepLinkDestination = NotificationDestination.feedbackBoard
        }
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

    private func scheduleFeedbackBoardNudgeIfNeeded(now: Date, shouldSchedule: Bool) async {
        guard shouldSchedule else {
            center.removePendingNotificationRequests(withIdentifiers: [NotificationIdentifier.feedbackBoardNudge])
            NotificationPreference.setFeedbackNudgeNextTriggerAt(nil)
            return
        }

        await scheduleFeedbackBoardNudge(now: now)
    }

    private func scheduleFeedbackBoardNudge(now: Date) async {
        let triggerDate = nextFeedbackNudgeDate(now: now)
        NotificationPreference.setFeedbackNudgeNextTriggerAt(triggerDate)

        let content = UNMutableNotificationContent()
        let title = await MainActor.run { "feedback_board_prompt_title".localizedString }
        let body = await MainActor.run { "feedback_board_prompt_subtitle".localizedString }

        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["destination": NotificationDestination.feedbackBoard]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )

        let identifier = NotificationIdentifier.feedbackBoardNudge
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func scheduleClientReminder(_ reminder: ClientReminder) async {
        guard let id = reminder.id, let dueDate = reminder.dueDate else { return }
        let identifier = NotificationIdentifier.clientReminder(id: id)
        let content = UNMutableNotificationContent()
        let clientName = reminder.client?.name ?? "client".localizedStringFallback
        content.title = "client_reminder".localizedStringFallback
        content.body = "\(clientName) • \(reminder.title ?? "follow_up".localizedStringFallback)"
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
        let name = debt.counterpartyName ?? "counterparty".localizedStringFallback
        let amount = debt.outstandingAmount.asCurrencyFallback()
        content.title = debt.directionEnum == .owedToMe ? "debt_collection_due".localizedStringFallback : "debt_payment_due".localizedStringFallback
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

        if languageCode.hasPrefix("id") {
            return "\(totalCount) kendaraan > \(threshold) hari; \(criticalCount) kendaraan > \(criticalThreshold) hari. Teratas: \(topVehicles)"
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

    private func nextFeedbackNudgeDate(now: Date) -> Date {
        let calendar = Calendar.current
        let minimumFromLastOpen = NotificationPreference.feedbackNudgeLastOpenedAt.flatMap {
            calendar.date(byAdding: .day, value: NotificationPreference.feedbackNudgeIntervalDays, to: $0)
        }

        if let storedDate = NotificationPreference.feedbackNudgeNextTriggerAt,
           storedDate > now,
           minimumFromLastOpen.map({ storedDate >= $0 }) ?? true {
            return storedDate
        }

        let defaultTarget = calendar.date(byAdding: .day, value: NotificationPreference.feedbackNudgeIntervalDays, to: now) ?? now.addingTimeInterval(4 * 24 * 60 * 60)
        let target = max(minimumFromLastOpen ?? defaultTarget, now)
        return feedbackNudgeDeliveryDate(onOrAfter: target, now: now)
    }

    private func feedbackNudgeDeliveryDate(onOrAfter date: Date, now: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 10
        components.minute = 30

        let candidate = Calendar.current.date(from: components) ?? date
        if candidate > now {
            return candidate
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? now.addingTimeInterval(3600)
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
    static let feedbackBoardNudge = "\(prefix).feedback.board.nudge"

    static func clientReminder(id: UUID) -> String {
        "\(prefix).client.\(id.uuidString)"
    }

    static func debtDue(id: UUID) -> String {
        "\(prefix).debt.\(id.uuidString)"
    }
    
}

enum NotificationDestination {
    static let feedbackBoard = "feedback_board"
}
