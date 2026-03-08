//
//  MonthlyReportSupport.swift
//  Ezcar24Business
//
//  Monthly report settings, delivery client, and recipient resolution.
//

import Foundation
import Combine
import Supabase

struct ReportMonth: Codable, Equatable, Hashable, Identifiable {
    let year: Int
    let month: Int

    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: startDate)
    }

    var startDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    var endDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate
    }

    var interval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    static func previousCalendarMonth(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> ReportMonth {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
        let components = calendar.dateComponents([.year, .month], from: previousMonthDate)
        return ReportMonth(
            year: components.year ?? calendar.component(.year, from: previousMonthDate),
            month: components.month ?? calendar.component(.month, from: previousMonthDate)
        )
    }
}

struct MonthlyReportPreferences: Codable, Equatable {
    static let storageVersion = 1

    var version: Int
    var isEnabled: Bool
    var timezoneIdentifier: String
    var deliveryDay: Int
    var deliveryHour: Int
    var deliveryMinute: Int

    init(
        version: Int = Self.storageVersion,
        isEnabled: Bool,
        timezoneIdentifier: String,
        deliveryDay: Int,
        deliveryHour: Int,
        deliveryMinute: Int
    ) {
        self.version = version
        self.isEnabled = isEnabled
        self.timezoneIdentifier = timezoneIdentifier
        self.deliveryDay = deliveryDay
        self.deliveryHour = deliveryHour
        self.deliveryMinute = deliveryMinute
    }

    static func `default`(timezoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier) -> MonthlyReportPreferences {
        MonthlyReportPreferences(
            isEnabled: false,
            timezoneIdentifier: timezoneIdentifier,
            deliveryDay: 2,
            deliveryHour: 9,
            deliveryMinute: 0
        )
    }
}

struct MonthlyReportRecipient: Identifiable, Equatable, Hashable {
    let email: String
    let role: String

    var id: String {
        email.lowercased()
    }
}

enum MonthlyReportDeliveryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Backend delivery is not connected yet."
        }
    }
}

protocol MonthlyReportDeliveryClient {
    func loadPreferences(for organizationId: UUID) async throws -> MonthlyReportPreferences
    func savePreferences(_ preferences: MonthlyReportPreferences, for organizationId: UUID) async throws
    func sendTestReport(for organizationId: UUID, month: ReportMonth) async throws
    func requestPreview(for organizationId: UUID, month: ReportMonth) async throws
}

final class SupabaseMonthlyReportDeliveryClient: MonthlyReportDeliveryClient {
    static let shared = SupabaseMonthlyReportDeliveryClient()

    private let client: SupabaseClient
    private let cache: CachedMonthlyReportDeliveryClient

    init(
        client: SupabaseClient = SupabaseClientProvider().client,
        cache: CachedMonthlyReportDeliveryClient = .shared
    ) {
        self.client = client
        self.cache = cache
    }

    func loadPreferences(for organizationId: UUID) async throws -> MonthlyReportPreferences {
        do {
            let preferences: MonthlyReportPreferences = try await client
                .rpc("get_monthly_report_preferences", params: ["p_organization_id": organizationId.uuidString])
                .execute()
                .value
            try? await cache.savePreferences(preferences, for: organizationId)
            return preferences
        } catch {
            return try await cache.loadPreferences(for: organizationId)
        }
    }

    func savePreferences(_ preferences: MonthlyReportPreferences, for organizationId: UUID) async throws {
        let params: [String: AnyJSON] = [
            "p_organization_id": .string(organizationId.uuidString),
            "p_version": .integer(preferences.version),
            "p_is_enabled": .bool(preferences.isEnabled),
            "p_timezone_identifier": .string(preferences.timezoneIdentifier),
            "p_delivery_day": .integer(preferences.deliveryDay),
            "p_delivery_hour": .integer(preferences.deliveryHour),
            "p_delivery_minute": .integer(preferences.deliveryMinute)
        ]

        let stored: MonthlyReportPreferences = try await client
            .rpc("upsert_monthly_report_preferences", params: params)
            .execute()
            .value

        try? await cache.savePreferences(stored, for: organizationId)
    }

    func sendTestReport(for organizationId: UUID, month: ReportMonth) async throws {
        struct DispatchPayload: Encodable {
            let mode: String
            let organizationId: String
            let month: ReportMonth
        }

        _ = try await client.functions.invoke(
            "monthly_report_dispatch",
            options: FunctionInvokeOptions(body: DispatchPayload(
                mode: "test",
                organizationId: organizationId.uuidString,
                month: month
            ))
        )
    }

    func requestPreview(for organizationId: UUID, month: ReportMonth) async throws {
        struct DispatchPayload: Encodable {
            let mode: String
            let organizationId: String
            let month: ReportMonth
        }

        _ = try await client.functions.invoke(
            "monthly_report_dispatch",
            options: FunctionInvokeOptions(body: DispatchPayload(
                mode: "preview",
                organizationId: organizationId.uuidString,
                month: month
            ))
        )
    }
}

final class CachedMonthlyReportDeliveryClient: MonthlyReportDeliveryClient {
    static let shared = CachedMonthlyReportDeliveryClient()

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keyPrefix = "monthly_report_preferences_v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadPreferences(for organizationId: UUID) async throws -> MonthlyReportPreferences {
        let key = storageKey(for: organizationId)
        guard let data = userDefaults.data(forKey: key) else {
            return .default()
        }

        let preferences = try decoder.decode(MonthlyReportPreferences.self, from: data)
        if preferences.version != MonthlyReportPreferences.storageVersion {
            return .default(timezoneIdentifier: preferences.timezoneIdentifier)
        }
        return preferences
    }

    func savePreferences(_ preferences: MonthlyReportPreferences, for organizationId: UUID) async throws {
        let key = storageKey(for: organizationId)
        let data = try encoder.encode(preferences)
        userDefaults.set(data, forKey: key)
    }

    func sendTestReport(for organizationId: UUID, month: ReportMonth) async throws {
        _ = organizationId
        _ = month
        throw MonthlyReportDeliveryError.unavailable
    }

    func requestPreview(for organizationId: UUID, month: ReportMonth) async throws {
        _ = organizationId
        _ = month
        throw MonthlyReportDeliveryError.unavailable
    }

    private func storageKey(for organizationId: UUID) -> String {
        "\(keyPrefix)_\(organizationId.uuidString.lowercased())"
    }
}

protocol MonthlyReportRecipientResolving {
    func resolveRecipients(for organizationId: UUID?) async throws -> [MonthlyReportRecipient]
}

final class SupabaseMonthlyReportRecipientResolver: MonthlyReportRecipientResolving {
    static let shared = SupabaseMonthlyReportRecipientResolver()

    private let client = SupabaseClientProvider().client

    private struct TeamMemberPayload: Decodable {
        let role: String
        let member_email: String?
    }

    func resolveRecipients(for organizationId: UUID?) async throws -> [MonthlyReportRecipient] {
        let members: [TeamMemberPayload]

        if let organizationId {
            members = try await client
                .rpc("get_team_members_secure", params: ["_org_id": organizationId.uuidString])
                .execute()
                .value
        } else {
            members = try await client
                .rpc("get_team_members_secure")
                .execute()
                .value
        }

        return members
            .compactMap { member in
                let role = member.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard role == "owner" || role == "admin" else { return nil }
                let email = member.member_email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !email.isEmpty else { return nil }
                return MonthlyReportRecipient(email: email, role: role)
            }
            .sorted {
                if $0.role != $1.role {
                    return $0.role == "owner"
                }
                return $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending
            }
    }
}

@MainActor
final class MonthlyReportSettingsViewModel: ObservableObject {
    @Published private(set) var preferences: MonthlyReportPreferences
    @Published private(set) var recipients: [MonthlyReportRecipient] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isSendingTest = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let deliveryClient: MonthlyReportDeliveryClient
    private let recipientResolver: MonthlyReportRecipientResolving
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        deliveryClient: MonthlyReportDeliveryClient = SupabaseMonthlyReportDeliveryClient.shared,
        recipientResolver: MonthlyReportRecipientResolving = SupabaseMonthlyReportRecipientResolver.shared,
        calendar: Calendar = .autoupdatingCurrent,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.deliveryClient = deliveryClient
        self.recipientResolver = recipientResolver
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.preferences = .default()
    }

    static func canAccess(role: String?) -> Bool {
        guard let role else { return false }
        let normalized = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "owner" || normalized == "admin"
    }

    var previewMonth: ReportMonth {
        ReportMonth.previousCalendarMonth(from: nowProvider(), calendar: calendar)
    }

    var recipientWarningMessage: String? {
        recipients.isEmpty ? "No owner or admin email address is available for delivery." : nil
    }

    var scheduleDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: preferences.timezoneIdentifier) ?? .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"

        let baseDate = calendar.date(from: DateComponents(
            year: 2000,
            month: 1,
            day: 1,
            hour: preferences.deliveryHour,
            minute: preferences.deliveryMinute
        )) ?? nowProvider()

        return "\(ordinal(preferences.deliveryDay)) day of each month at \(formatter.string(from: baseDate))"
    }

    var timezoneDescription: String {
        preferences.timezoneIdentifier
    }

    func load(organizationId: UUID?) async {
        errorMessage = nil
        infoMessage = nil

        guard let organizationId else {
            preferences = .default()
            recipients = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            preferences = try await deliveryClient.loadPreferences(for: organizationId)
        } catch {
            preferences = .default()
            errorMessage = error.localizedDescription
        }

        do {
            recipients = try await recipientResolver.resolveRecipients(for: organizationId)
        } catch {
            recipients = []
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateEnabled(_ isEnabled: Bool, organizationId: UUID?) async {
        preferences.isEnabled = isEnabled
        if preferences.timezoneIdentifier.isEmpty {
            preferences.timezoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        }
        await save(organizationId: organizationId, showConfirmation: false)
    }

    func save(organizationId: UUID?, showConfirmation: Bool = true) async {
        errorMessage = nil
        infoMessage = nil

        guard let organizationId else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await deliveryClient.savePreferences(preferences, for: organizationId)
            if showConfirmation {
                infoMessage = "Monthly report settings saved."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTest(organizationId: UUID?) async {
        errorMessage = nil
        infoMessage = nil

        guard let organizationId else { return }

        isSendingTest = true
        defer { isSendingTest = false }

        do {
            try await deliveryClient.sendTestReport(for: organizationId, month: previewMonth)
            infoMessage = "Test report request submitted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestPreview(organizationId: UUID?) async {
        errorMessage = nil
        infoMessage = nil

        guard let organizationId else { return }

        do {
            try await deliveryClient.requestPreview(for: organizationId, month: previewMonth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
