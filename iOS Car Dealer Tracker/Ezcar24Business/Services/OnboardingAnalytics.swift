//
//  OnboardingAnalytics.swift
//  Ezcar24Business
//
//  PostHog onboarding funnel tracking.
//

import Foundation
import PostHog
import UIKit

@MainActor
enum OnboardingAnalytics {
    enum Event: String {
        case appLaunched = "onboarding_app_launched"
        case started = "onboarding_started"
        case regionSelected = "onboarding_region_selected"
        case authScreenViewed = "onboarding_auth_screen_viewed"
        case authModeChanged = "onboarding_auth_mode_changed"
        case authSubmitted = "onboarding_auth_submitted"
        case authCompleted = "onboarding_auth_completed"
        case authPendingConfirmation = "onboarding_auth_pending_confirmation"
        case authFailed = "onboarding_auth_failed"
        case guestStarted = "onboarding_guest_started"
        case passwordResetRequested = "onboarding_password_reset_requested"
    }

    private(set) static var isConfigured = false

    private static let defaultHost = "https://us.i.posthog.com"

    static func configure() {
        guard !isRunningTests else { return }
        guard !isConfigured else { return }
        guard let configuration = loadConfiguration() else { return }

        let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.sessionReplay = false
        config.errorTrackingConfig.autoCapture = false
        config.preloadFeatureFlags = false
        config.debug = ProcessInfo.processInfo.environment["POSTHOG_DEBUG"] == "1"

        PostHogSDK.shared.setup(config)
        isConfigured = true
        capture(.appLaunched)
    }

    static func capture(_ event: Event, properties: [String: Any] = [:]) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: commonProperties().merging(properties) { _, new in new })
    }

    static func identifyUser(_ id: UUID) {
        guard isConfigured else { return }
        PostHogSDK.shared.identify(id.uuidString, userProperties: commonProperties())
    }

    static func resetIdentity() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func commonProperties() -> [String: Any] {
        let regionSettings = RegionSettingsManager.shared
        return [
            "platform": "ios",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "region_id": regionSettings.selectedRegion.rawValue,
            "currency_code": regionSettings.selectedRegion.currencyCode,
            "language_id": regionSettings.selectedLanguage.rawValue,
            "has_selected_region": regionSettings.hasSelectedRegion,
            "uses_kilometers": regionSettings.selectedRegion.usesKilometers,
            "timezone": TimeZone.current.identifier,
            "device_locale": Locale.current.identifier
        ]
    }

    private static func loadConfiguration() -> Configuration? {
        let environment = ProcessInfo.processInfo.environment
        if let token = normalized(environment["POSTHOG_PROJECT_TOKEN"] ?? environment["POSTHOG_API_KEY"]) {
            return Configuration(
                projectToken: token,
                host: normalized(environment["POSTHOG_HOST"]) ?? defaultHost
            )
        }

        guard
            let fileURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: fileURL),
            let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let token = normalized(payload["posthogProjectToken"] as? String)
        else {
            return nil
        }

        return Configuration(
            projectToken: token,
            host: normalized(payload["posthogHost"] as? String) ?? defaultHost
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct Configuration {
        let projectToken: String
        let host: String
    }
}
