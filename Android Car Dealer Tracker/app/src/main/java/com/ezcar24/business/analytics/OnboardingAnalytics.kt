package com.ezcar24.business.analytics

import android.content.Context
import com.ezcar24.business.BuildConfig
import com.ezcar24.business.util.AppRegion
import com.ezcar24.business.util.RegionSettingsState
import com.posthog.PersonProfiles
import com.posthog.PostHog
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import java.util.Locale
import java.util.TimeZone

object OnboardingAnalytics {
    private const val DEFAULT_HOST = "https://us.i.posthog.com"

    private var isConfigured = false
    private var currentRegionState: RegionSettingsState? = null

    fun configure(context: Context, regionState: RegionSettingsState) {
        currentRegionState = regionState
        if (isConfigured) return

        val token = BuildConfig.POSTHOG_PROJECT_TOKEN.trim()
        if (token.isEmpty()) return

        val config = PostHogAndroidConfig(
            apiKey = token,
            host = BuildConfig.POSTHOG_HOST.ifBlank { DEFAULT_HOST }
        ).apply {
            captureApplicationLifecycleEvents = true
            captureScreenViews = false
            captureDeepLinks = false
            sessionReplay = false
            errorTrackingConfig.autoCapture = false
            preloadFeatureFlags = false
            personProfiles = PersonProfiles.IDENTIFIED_ONLY
            debug = BuildConfig.POSTHOG_DEBUG
        }

        PostHogAndroid.setup(context, config)
        isConfigured = true
        capture(Event.APP_LAUNCHED)
    }

    fun updateRegionState(regionState: RegionSettingsState) {
        currentRegionState = regionState
    }

    fun trackStarted(step: String) {
        capture(Event.STARTED, mapOf("step" to step))
    }

    fun trackRegionSelected(region: AppRegion) {
        capture(
            Event.REGION_SELECTED,
            mapOf(
                "selected_region_id" to region.name,
                "selected_currency_code" to region.currencyCode,
                "selected_uses_kilometers" to region.usesKilometers
            )
        )
    }

    fun trackAuthScreenViewed(mode: String) {
        capture(Event.AUTH_SCREEN_VIEWED, mapOf("auth_mode" to mode))
    }

    fun trackAuthModeChanged(mode: String) {
        capture(Event.AUTH_MODE_CHANGED, mapOf("auth_mode" to mode))
    }

    fun trackAuthSubmitted(mode: String, method: String, hasReferralCode: Boolean, hasTeamInviteCode: Boolean, hasPhone: Boolean = false) {
        capture(Event.AUTH_SUBMITTED, authProperties(mode, method, hasReferralCode, hasTeamInviteCode, hasPhone))
    }

    fun trackAuthCompleted(mode: String, method: String, distinctId: String?, hasReferralCode: Boolean, hasTeamInviteCode: Boolean, hasPhone: Boolean = false) {
        if (!isConfigured) return
        distinctId?.let { PostHog.identify(distinctId = it, userProperties = commonProperties()) }
        capture(Event.AUTH_COMPLETED, authProperties(mode, method, hasReferralCode, hasTeamInviteCode, hasPhone))
    }

    fun trackAuthPendingConfirmation(mode: String, hasReferralCode: Boolean, hasTeamInviteCode: Boolean, hasPhone: Boolean) {
        capture(Event.AUTH_PENDING_CONFIRMATION, authProperties(mode, "email", hasReferralCode, hasTeamInviteCode, hasPhone))
    }

    fun trackAuthFailed(mode: String, method: String, hasReferralCode: Boolean, hasTeamInviteCode: Boolean, hasPhone: Boolean = false) {
        capture(Event.AUTH_FAILED, authProperties(mode, method, hasReferralCode, hasTeamInviteCode, hasPhone))
    }

    fun trackPasswordResetRequested(hasEmail: Boolean) {
        capture(Event.PASSWORD_RESET_REQUESTED, mapOf("has_email" to hasEmail))
    }

    fun trackGuestStarted() {
        resetIdentity()
        capture(Event.GUEST_STARTED)
    }

    fun resetIdentity() {
        if (!isConfigured) return
        PostHog.reset()
    }

    private fun capture(event: Event, properties: Map<String, Any> = emptyMap()) {
        if (!isConfigured) return
        PostHog.capture(event = event.value, properties = commonProperties() + properties)
    }

    private fun authProperties(mode: String, method: String, hasReferralCode: Boolean, hasTeamInviteCode: Boolean, hasPhone: Boolean): Map<String, Any> {
        return mapOf(
            "auth_mode" to mode,
            "auth_method" to method,
            "has_referral_code" to hasReferralCode,
            "has_team_invite_code" to hasTeamInviteCode,
            "has_phone" to hasPhone
        )
    }

    private fun commonProperties(): Map<String, Any> {
        val state = currentRegionState
        return buildMap {
            put("platform", "android")
            put("app_version", BuildConfig.VERSION_NAME)
            put("app_build", BuildConfig.VERSION_CODE.toString())
            put("timezone", TimeZone.getDefault().id)
            put("device_locale", Locale.getDefault().toLanguageTag())
            state?.let {
                put("region_id", it.selectedRegion.name)
                put("currency_code", it.selectedRegion.currencyCode)
                put("language_id", it.selectedLanguage.tag)
                put("has_selected_region", it.hasSelectedRegion)
                put("uses_kilometers", it.selectedRegion.usesKilometers)
            }
        }
    }

    private enum class Event(val value: String) {
        APP_LAUNCHED("onboarding_app_launched"),
        STARTED("onboarding_started"),
        REGION_SELECTED("onboarding_region_selected"),
        AUTH_SCREEN_VIEWED("onboarding_auth_screen_viewed"),
        AUTH_MODE_CHANGED("onboarding_auth_mode_changed"),
        AUTH_SUBMITTED("onboarding_auth_submitted"),
        AUTH_COMPLETED("onboarding_auth_completed"),
        AUTH_PENDING_CONFIRMATION("onboarding_auth_pending_confirmation"),
        AUTH_FAILED("onboarding_auth_failed"),
        GUEST_STARTED("onboarding_guest_started"),
        PASSWORD_RESET_REQUESTED("onboarding_password_reset_requested")
    }
}
