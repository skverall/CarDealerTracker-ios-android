package com.ezcar24.business.data.repository

import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.Log

import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.TimeZone

import javax.inject.Inject
import javax.inject.Singleton

import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.postgrest.postgrest

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.withContext

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

import com.ezcar24.business.BuildConfig
import com.ezcar24.business.util.RegionSettingsManager

private const val AUTH_PREFS = "ezcar24_auth"
private const val PENDING_INVITE_TOKEN = "pendingInviteToken"
private const val PENDING_INVITE_TOKEN_TIMESTAMP = "pendingInviteTokenTimestamp"
private const val PENDING_TEAM_INVITE_CODE = "pendingTeamInviteCode"
private const val PENDING_TEAM_INVITE_CODE_TIMESTAMP = "pendingTeamInviteCodeTimestamp"
private const val PENDING_REFERRAL_CODE = "pendingReferralCode"
private const val PENDING_REFERRAL_CODE_TIMESTAMP = "pendingReferralCodeTimestamp"
private const val INVITE_TOKEN_MAX_AGE_MS = 26L * 60L * 60L * 1000L
private const val TEAM_INVITE_MAX_AGE_MS = 7L * 24L * 60L * 60L * 1000L
private const val REFERRAL_MAX_AGE_MS = 30L * 24L * 60L * 60L * 1000L
private const val TAG = "AuthRepository"

enum class SignUpResult {
    AUTHENTICATED,
    EMAIL_CONFIRMATION_REQUIRED
}

enum class AuthDeepLinkResult {
    NONE,
    PASSWORD_RESET,
    INVITE_SAVED,
    INVITE_APPLIED,
    REFERRAL_SAVED,
    REFERRAL_APPLIED
}

data class InviteActionResult(
    val success: Boolean,
    val message: String? = null
)

@Serializable
private data class AcceptInviteRequest(
    @SerialName("invite_code") val inviteCode: String? = null,
    val token: String? = null
)

@Serializable
private data class FunctionErrorPayload(
    val error: String? = null
)

@Serializable
private data class DeleteAccountResponse(
    val success: Boolean = false
)

@Serializable
private data class AdminSignupAlertRequest(
    val event: String = "signup_completed",
    val source: String = "android",
    val platform: String = "Android",
    @SerialName("referral_code_present") val referralCodePresent: Boolean,
    @SerialName("team_invite_code_present") val teamInviteCodePresent: Boolean,
    @SerialName("app_version") val appVersion: String,
    @SerialName("app_build") val appBuild: String,
    @SerialName("app_region") val appRegion: String,
    @SerialName("app_language") val appLanguage: String,
    @SerialName("currency_code") val currencyCode: String,
    @SerialName("device_locale") val deviceLocale: String,
    @SerialName("device_country_code") val deviceCountryCode: String?,
    val timezone: String,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("os_version") val osVersion: String
)

@Singleton
class AuthRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
    private val regionSettingsManager: RegionSettingsManager
) {
    private val authPrefs = context.getSharedPreferences(AUTH_PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val _deepLinkEvents = MutableSharedFlow<AuthDeepLinkResult>(extraBufferCapacity = 4)

    val sessionStatus = client.auth.sessionStatus
    val deepLinkEvents = _deepLinkEvents.asSharedFlow()

    suspend fun awaitInitialization() {
        client.auth.awaitInitialization()
    }

    suspend fun login(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signUp(
        email: String,
        password: String,
        phone: String?,
        referralCode: String?
    ): SignUpResult {
        referralCode?.let(::savePendingReferralCode)
        client.auth.signUpWith(Email) {
            this.email = email
            this.password = password
        }

        val isAuthenticated = client.auth.currentUserOrNull() != null
        if (isAuthenticated && !phone.isNullOrBlank()) {
            Log.d(TAG, "Phone captured during sign-up and pending local profile sync.")
        }
        return if (isAuthenticated) {
            SignUpResult.AUTHENTICATED
        } else {
            SignUpResult.EMAIL_CONFIRMATION_REQUIRED
        }
    }

    suspend fun notifySignupCompleted(
        referralCode: String?,
        teamInviteCode: String?
    ) = withContext(Dispatchers.IO) {
        val accessToken = client.auth.currentAccessTokenOrNull()
        if (accessToken.isNullOrBlank()) {
            return@withContext
        }

        val regionState = regionSettingsManager.state.value
        val request = AdminSignupAlertRequest(
            referralCodePresent = !referralCode.isNullOrBlank(),
            teamInviteCodePresent = !teamInviteCode.isNullOrBlank(),
            appVersion = BuildConfig.VERSION_NAME,
            appBuild = BuildConfig.VERSION_CODE.toString(),
            appRegion = regionState.selectedRegion.displayName,
            appLanguage = regionState.selectedLanguage.tag,
            currencyCode = regionState.selectedRegion.currencyCode,
            deviceLocale = Locale.getDefault().toLanguageTag(),
            deviceCountryCode = Locale.getDefault().country.takeIf { it.isNotBlank() },
            timezone = TimeZone.getDefault().id,
            deviceModel = listOf(Build.MANUFACTURER, Build.MODEL)
                .filter { it.isNotBlank() }
                .joinToString(" "),
            osVersion = "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
        )
        val connection = (URL("${BuildConfig.SUPABASE_URL}/functions/v1/admin_alerts").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 5_000
            readTimeout = 5_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("apikey", BuildConfig.SUPABASE_ANON_KEY)
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write(json.encodeToString(request))
            }

            val statusCode = connection.responseCode
            if (statusCode !in 200..299) {
                val responseBody = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                Log.w(TAG, "admin_alerts failed ($statusCode): ${parseFunctionError(responseBody)}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "admin_alerts signup notification failed", e)
        } finally {
            connection.disconnect()
        }
    }

    suspend fun applyPendingPostAuthActions(teamInviteCode: String? = null) {
        teamInviteCode?.let(::savePendingTeamInviteCode)
        acceptPendingInviteTokenIfPossible()
        acceptPendingTeamInviteCodeIfPossible()
        claimPendingReferralIfPossible()
    }

    fun savePendingTeamInviteCode(code: String) {
        cachePendingTeamInviteCode(code)
    }

    fun getPendingTeamInviteCode(): String? {
        return readCode(
            key = PENDING_TEAM_INVITE_CODE,
            timestampKey = PENDING_TEAM_INVITE_CODE_TIMESTAMP,
            maxAgeMs = TEAM_INVITE_MAX_AGE_MS
        )
    }

    fun getPendingReferralCode(): String? {
        return readCode(
            key = PENDING_REFERRAL_CODE,
            timestampKey = PENDING_REFERRAL_CODE_TIMESTAMP,
            maxAgeMs = REFERRAL_MAX_AGE_MS
        )
    }

    suspend fun handleDeepLink(uri: Uri): AuthDeepLinkResult {
        val uriString = uri.toString().lowercase(Locale.US)

        val result = when {
            uriString.contains("reset-password") || uriString.contains("type=recovery") -> AuthDeepLinkResult.PASSWORD_RESET
            else -> handleReferralDeepLink(uri) ?: handleInviteDeepLink(uri) ?: AuthDeepLinkResult.NONE
        }

        if (result != AuthDeepLinkResult.NONE) {
            _deepLinkEvents.tryEmit(result)
        }
        return result
    }

    suspend fun resetPassword(email: String) {
        client.auth.resetPasswordForEmail(
            email = email,
            redirectUrl = "ezcar24business://reset-password"
        )
    }

    suspend fun updatePassword(newPassword: String) {
        client.auth.updateUser {
            password = newPassword
        }
    }

    suspend fun signOut() {
        client.auth.signOut()
    }

    suspend fun deleteAccount() = withContext(Dispatchers.IO) {
        val accessToken = client.auth.currentAccessTokenOrNull()
        if (accessToken.isNullOrBlank()) {
            throw IllegalStateException("Please sign in again and try again.")
        }

        val connection = (URL("${BuildConfig.SUPABASE_URL}/functions/v1/delete_account").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write("{}")
            }

            val statusCode = connection.responseCode
            val responseBody = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode !in 200..299) {
                throw IllegalStateException(parseFunctionError(responseBody))
            }

            val response = runCatching {
                json.decodeFromString<DeleteAccountResponse>(responseBody)
            }.getOrElse {
                DeleteAccountResponse(success = responseBody.contains("\"success\":true"))
            }

            if (!response.success) {
                throw IllegalStateException("Account deletion did not complete.")
            }

            try {
                client.auth.signOut()
            } catch (e: Exception) {
                Log.w(TAG, "delete_account succeeded but local sign out failed", e)
            }
        } finally {
            connection.disconnect()
        }
    }

    fun getCurrentUser() = client.auth.currentUserOrNull()

    suspend fun getDealerId(): String? {
        val user = client.auth.currentUserOrNull() ?: return null
        return user.id
    }

    suspend fun submitTeamInviteCode(code: String): InviteActionResult {
        savePendingTeamInviteCode(code)
        if (!isAuthenticated()) {
            return InviteActionResult(
                success = false,
                message = "Invite code saved. Sign in to apply."
            )
        }
        return acceptTeamInviteCode(code)
    }

    private suspend fun handleInviteDeepLink(uri: Uri): AuthDeepLinkResult? {
        val token = extractInviteToken(uri) ?: return null
        cachePendingInviteToken(token)
        val applied = if (isAuthenticated()) acceptInviteToken(token).success else false
        return if (applied) {
            AuthDeepLinkResult.INVITE_APPLIED
        } else {
            AuthDeepLinkResult.INVITE_SAVED
        }
    }

    private suspend fun handleReferralDeepLink(uri: Uri): AuthDeepLinkResult? {
        val code = extractReferralCode(uri) ?: return null
        savePendingReferralCode(code)
        val applied = if (isAuthenticated()) claimReferral(code) else false
        return if (applied) {
            AuthDeepLinkResult.REFERRAL_APPLIED
        } else {
            AuthDeepLinkResult.REFERRAL_SAVED
        }
    }

    private suspend fun acceptPendingInviteTokenIfPossible(): Boolean {
        val token = readCode(
            key = PENDING_INVITE_TOKEN,
            timestampKey = PENDING_INVITE_TOKEN_TIMESTAMP,
            maxAgeMs = INVITE_TOKEN_MAX_AGE_MS
        ) ?: return false
        return acceptInviteToken(token).success
    }

    private suspend fun acceptPendingTeamInviteCodeIfPossible(): Boolean {
        val code = getPendingTeamInviteCode() ?: return false
        return acceptTeamInviteCode(code).success
    }

    private suspend fun claimPendingReferralIfPossible(): Boolean {
        val code = getPendingReferralCode() ?: return false
        return claimReferral(code)
    }

    private suspend fun acceptInviteToken(token: String): InviteActionResult {
        return invokeAcceptInvite(
            request = AcceptInviteRequest(token = token),
            onSuccess = ::clearPendingInviteToken,
            shouldClear = ::shouldClearPendingInviteToken
        )
    }

    private suspend fun acceptTeamInviteCode(code: String): InviteActionResult {
        val normalizedCode = normalizeInviteCode(code)
        if (normalizedCode.isEmpty()) {
            return InviteActionResult(success = false, message = "Invite code is required.")
        }
        return invokeAcceptInvite(
            request = AcceptInviteRequest(inviteCode = normalizedCode),
            onSuccess = ::clearPendingTeamInviteCode,
            shouldClear = ::shouldClearPendingTeamInviteCode
        )
    }

    private suspend fun invokeAcceptInvite(
        request: AcceptInviteRequest,
        onSuccess: () -> Unit,
        shouldClear: (Int, String) -> Boolean
    ): InviteActionResult = withContext(Dispatchers.IO) {
        val accessToken = client.auth.currentAccessTokenOrNull()
        if (accessToken.isNullOrBlank()) {
            return@withContext InviteActionResult(
                success = false,
                message = "Please sign in to accept the invitation."
            )
        }

        val connection = (URL("${BuildConfig.SUPABASE_URL}/functions/v1/accept_invite").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            val payload = json.encodeToString(request)
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write(payload)
            }

            val statusCode = connection.responseCode
            val responseBody = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode in 200..299) {
                onSuccess()
                return@withContext InviteActionResult(
                    success = true,
                    message = "Invite accepted. Use the business switcher to change organizations."
                )
            }

            val message = parseFunctionError(responseBody)
            if (shouldClear(statusCode, message)) {
                onSuccess()
            }
            Log.w(TAG, "accept_invite failed ($statusCode): $message")
            InviteActionResult(success = false, message = message)
        } catch (e: Exception) {
            Log.e(TAG, "accept_invite failed", e)
            InviteActionResult(success = false, message = e.message)
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun claimReferral(code: String): Boolean = withContext(Dispatchers.IO) {
        val normalizedCode = code.trim().uppercase(Locale.US)
        if (normalizedCode.isEmpty() || !isAuthenticated()) {
            return@withContext false
        }

        return@withContext try {
            val params = buildJsonObject {
                put("p_code", normalizedCode)
            }
            val result = client.postgrest.rpc("claim_dealer_referral", params)
            val claimed = json.decodeFromString<Boolean>(result.data)
            if (claimed) {
                clearPendingReferralCode()
            }
            claimed
        } catch (e: Exception) {
            val message = e.message.orEmpty()
            if (shouldClearPendingReferralCode(message)) {
                clearPendingReferralCode()
            }
            Log.w(TAG, "claimReferral failed: $message", e)
            false
        }
    }

    private fun isAuthenticated(): Boolean {
        return !client.auth.currentAccessTokenOrNull().isNullOrBlank()
    }

    private fun cachePendingInviteToken(token: String) {
        val trimmed = token.trim()
        if (trimmed.isEmpty()) return
        authPrefs.edit()
            .putString(PENDING_INVITE_TOKEN, trimmed)
            .putLong(PENDING_INVITE_TOKEN_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    private fun cachePendingTeamInviteCode(code: String) {
        val normalized = normalizeInviteCode(code)
        if (normalized.isEmpty()) return
        authPrefs.edit()
            .putString(PENDING_TEAM_INVITE_CODE, normalized)
            .putLong(PENDING_TEAM_INVITE_CODE_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    private fun savePendingReferralCode(code: String) {
        val normalized = code.trim().uppercase(Locale.US)
        if (normalized.isEmpty()) return
        authPrefs.edit()
            .putString(PENDING_REFERRAL_CODE, normalized)
            .putLong(PENDING_REFERRAL_CODE_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    private fun clearPendingInviteToken() {
        authPrefs.edit()
            .remove(PENDING_INVITE_TOKEN)
            .remove(PENDING_INVITE_TOKEN_TIMESTAMP)
            .apply()
    }

    private fun clearPendingTeamInviteCode() {
        authPrefs.edit()
            .remove(PENDING_TEAM_INVITE_CODE)
            .remove(PENDING_TEAM_INVITE_CODE_TIMESTAMP)
            .apply()
    }

    private fun clearPendingReferralCode() {
        authPrefs.edit()
            .remove(PENDING_REFERRAL_CODE)
            .remove(PENDING_REFERRAL_CODE_TIMESTAMP)
            .apply()
    }

    private fun readCode(
        key: String,
        timestampKey: String,
        maxAgeMs: Long
    ): String? {
        val value = authPrefs.getString(key, null)?.takeIf { it.isNotBlank() } ?: return null
        val timestamp = authPrefs.getLong(timestampKey, 0L)
        if (timestamp == 0L || System.currentTimeMillis() - timestamp > maxAgeMs) {
            authPrefs.edit().remove(key).remove(timestampKey).apply()
            return null
        }
        return value
    }

    private fun extractInviteToken(uri: Uri): String? {
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        val path = uri.path?.lowercase(Locale.US).orEmpty()
        val isUniversalInvite = host.contains("ezcar24.com") && path.contains("accept-invite")
        val isCustomInvite = host.contains("accept-invite")
        if (!isUniversalInvite && !isCustomInvite) {
            return null
        }
        return uri.getQueryParameter("token")?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun extractReferralCode(uri: Uri): String? {
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        val path = uri.path?.lowercase(Locale.US).orEmpty()
        val code = uri.getQueryParameter("code")?.trim()
            ?: uri.getQueryParameter("ref")?.trim()
        if (code.isNullOrEmpty()) {
            return null
        }

        val isReferralPath = path.contains("dealer-invite") || path.contains("referral")
        val isUniversalHost = host.contains("ezcar24.com")
        val isCustomHost = host.contains("dealer-invite") || host.contains("referral")
        return if (isReferralPath || isUniversalHost || isCustomHost) code else null
    }

    private fun normalizeInviteCode(code: String): String {
        return code.trim().uppercase(Locale.US).replace("-", "").replace(" ", "")
    }

    private fun parseFunctionError(body: String): String {
        return try {
            json.decodeFromString<FunctionErrorPayload>(body).error?.trim().takeUnless { it.isNullOrEmpty() }
                ?: "Unexpected error"
        } catch (_: Exception) {
            body.ifBlank { "Unexpected error" }
        }
    }

    private fun shouldClearPendingInviteToken(statusCode: Int, message: String): Boolean {
        if (statusCode in 400..499) {
            return true
        }
        val normalized = message.lowercase(Locale.US)
        return normalized.contains("invalid") ||
            normalized.contains("expired") ||
            normalized.contains("already") ||
            normalized.contains("mismatch")
    }

    private fun shouldClearPendingTeamInviteCode(statusCode: Int, message: String): Boolean {
        if (statusCode in 400..499) {
            return true
        }
        val normalized = message.lowercase(Locale.US)
        return normalized.contains("invalid") ||
            normalized.contains("expired") ||
            normalized.contains("already") ||
            normalized.contains("revoked") ||
            normalized.contains("mismatch")
    }

    private fun shouldClearPendingReferralCode(message: String): Boolean {
        val normalized = message.lowercase(Locale.US)
        return normalized.contains("invalid") ||
            normalized.contains("expired") ||
            normalized.contains("self") ||
            normalized.contains("not allowed")
    }
}
