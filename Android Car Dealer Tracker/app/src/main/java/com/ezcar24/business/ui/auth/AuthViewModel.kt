package com.ezcar24.business.ui.auth

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.BuildConfig
import com.ezcar24.business.analytics.OnboardingAnalytics
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.repository.AuthDeepLinkResult
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.repository.SignUpResult
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.security.SecureRandom
import javax.inject.Inject

enum class AuthMode {
    SIGN_IN,
    SIGN_UP
}

val AuthMode.analyticsName: String
    get() = when (this) {
        AuthMode.SIGN_IN -> "sign_in"
        AuthMode.SIGN_UP -> "sign_up"
    }

data class AuthUiState(
    val email: String = "",
    val password: String = "",
    val phone: String = "",
    val referralCode: String = "",
    val teamInviteCode: String = "",
    val mode: AuthMode = AuthMode.SIGN_IN,
    val isLoading: Boolean = false,
    val isGuestMode: Boolean = false,
    val showPasswordReset: Boolean = false,
    val newPassword: String = "",
    val confirmPassword: String = "",
    val error: String? = null,
    val message: String? = null,
    val isSuccess: Boolean = false
) {
    val isFormValid: Boolean
        get() = email.trim().isNotEmpty() && password.length >= 6

    val isPasswordResetValid: Boolean
        get() = newPassword.length >= 6 && newPassword == confirmPassword

    val hasOptionalCodes: Boolean
        get() = referralCode.trim().isNotEmpty() || teamInviteCode.trim().isNotEmpty()

    val hasReferralCode: Boolean
        get() = referralCode.trim().isNotEmpty()

    val hasTeamInviteCode: Boolean
        get() = teamInviteCode.trim().isNotEmpty()

    val hasPhone: Boolean
        get() = phone.trim().isNotEmpty()

    val pendingInviteMessage: String?
        get() {
            if (teamInviteCode.trim().isEmpty()) return null
            return if (mode == AuthMode.SIGN_IN) {
                "Team access will be applied after you sign in."
            } else {
                "This sign-up is ready to join a team automatically."
            }
    }
}

private data class GoogleCredentialResult(
    val idToken: String,
    val nonce: String
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val subscriptionManager: SubscriptionManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        AuthUiState(
            referralCode = authRepository.getPendingReferralCode().orEmpty(),
            teamInviteCode = authRepository.getPendingTeamInviteCode().orEmpty()
        )
    )
    val uiState = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            authRepository.deepLinkEvents.collect { result ->
                when (result) {
                    AuthDeepLinkResult.NONE,
                    AuthDeepLinkResult.PASSWORD_RESET -> Unit

                    AuthDeepLinkResult.INVITE_SAVED -> {
                        refreshPendingInputs("Invitation link saved. Sign in to accept.")
                    }

                    AuthDeepLinkResult.INVITE_APPLIED -> {
                        refreshPendingInputs("Invitation accepted.")
                    }

                    AuthDeepLinkResult.REFERRAL_SAVED -> {
                        refreshPendingInputs("Referral code saved. Sign up to claim.")
                    }

                    AuthDeepLinkResult.REFERRAL_APPLIED -> {
                        refreshPendingInputs("Referral applied. Thanks for joining.")
                    }
                }
            }
        }
    }

    private fun refreshPendingInputs(message: String? = null) {
        _uiState.value = _uiState.value.copy(
            referralCode = authRepository.getPendingReferralCode().orEmpty(),
            teamInviteCode = authRepository.getPendingTeamInviteCode().orEmpty(),
            message = message ?: _uiState.value.message,
            error = null
        )
    }

    fun onEmailChange(email: String) {
        _uiState.value = _uiState.value.copy(email = email, error = null, message = null)
    }

    fun onPasswordChange(password: String) {
        _uiState.value = _uiState.value.copy(password = password, error = null, message = null)
    }

    fun onPhoneChange(phone: String) {
        _uiState.value = _uiState.value.copy(phone = phone, error = null, message = null)
    }

    fun onReferralCodeChange(referralCode: String) {
        _uiState.value = _uiState.value.copy(referralCode = referralCode.uppercase(), error = null, message = null)
    }

    fun onTeamInviteCodeChange(teamInviteCode: String) {
        _uiState.value = _uiState.value.copy(teamInviteCode = teamInviteCode.uppercase(), error = null, message = null)
    }

    fun onNewPasswordChange(password: String) {
        _uiState.value = _uiState.value.copy(newPassword = password, error = null)
    }

    fun onConfirmPasswordChange(password: String) {
        _uiState.value = _uiState.value.copy(confirmPassword = password, error = null)
    }

    fun onModeChange(mode: AuthMode) {
        OnboardingAnalytics.trackAuthModeChanged(mode.analyticsName)
        _uiState.value = _uiState.value.copy(mode = mode, error = null, message = null)
    }

    fun login() {
        viewModelScope.launch {
            val currentState = _uiState.value
            OnboardingAnalytics.trackAuthSubmitted(
                mode = AuthMode.SIGN_IN.analyticsName,
                method = "email",
                hasReferralCode = currentState.hasReferralCode,
                hasTeamInviteCode = currentState.hasTeamInviteCode
            )
            _uiState.value = currentState.copy(isLoading = true, error = null, message = null)
            try {
                authRepository.login(
                    email = currentState.email.trim(),
                    password = currentState.password
                )
                authRepository.applyPendingPostAuthActions(
                    teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                )
                val dealerId = authRepository.getDealerId()
                subscriptionManager.logIn(dealerId)
                OnboardingAnalytics.trackAuthCompleted(
                    mode = AuthMode.SIGN_IN.analyticsName,
                    method = "email",
                    distinctId = dealerId,
                    hasReferralCode = currentState.hasReferralCode,
                    hasTeamInviteCode = currentState.hasTeamInviteCode
                )
                _uiState.value = currentState.copy(
                    password = "",
                    phone = "",
                    referralCode = "",
                    teamInviteCode = "",
                    isLoading = false,
                    isGuestMode = false,
                    isSuccess = true,
                    error = null,
                    message = null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Sign in failed", e)
                OnboardingAnalytics.trackAuthFailed(
                    mode = AuthMode.SIGN_IN.analyticsName,
                    method = "email",
                    hasReferralCode = currentState.hasReferralCode,
                    hasTeamInviteCode = currentState.hasTeamInviteCode
                )
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.SIGN_IN)
                )
            }
        }
    }

    fun signUp() {
        viewModelScope.launch {
            val currentState = _uiState.value
            OnboardingAnalytics.trackAuthSubmitted(
                mode = AuthMode.SIGN_UP.analyticsName,
                method = "email",
                hasReferralCode = currentState.hasReferralCode,
                hasTeamInviteCode = currentState.hasTeamInviteCode,
                hasPhone = currentState.hasPhone
            )
            _uiState.value = currentState.copy(isLoading = true, error = null, message = null)
            try {
                when (
                    authRepository.signUp(
                        email = currentState.email.trim(),
                        password = currentState.password,
                        phone = currentState.phone.trim().ifBlank { null },
                        referralCode = currentState.referralCode.trim().ifBlank { null }
                    )
                ) {
                    SignUpResult.AUTHENTICATED -> {
                        viewModelScope.launch {
                            authRepository.notifySignupCompleted(
                                referralCode = currentState.referralCode.trim().ifBlank { null },
                                teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                            )
                        }
                        authRepository.applyPendingPostAuthActions(
                            teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                        )
                        val dealerId = authRepository.getDealerId()
                        subscriptionManager.logIn(dealerId)
                        OnboardingAnalytics.trackAuthCompleted(
                            mode = AuthMode.SIGN_UP.analyticsName,
                            method = "email",
                            distinctId = dealerId,
                            hasReferralCode = currentState.hasReferralCode,
                            hasTeamInviteCode = currentState.hasTeamInviteCode,
                            hasPhone = currentState.hasPhone
                        )
                        _uiState.value = currentState.copy(
                            password = "",
                            phone = "",
                            referralCode = "",
                            teamInviteCode = "",
                            isLoading = false,
                            isGuestMode = false,
                            isSuccess = true,
                            error = null,
                            message = null
                        )
                    }

                    SignUpResult.EMAIL_CONFIRMATION_REQUIRED -> {
                        currentState.teamInviteCode.trim().ifNotEmpty {
                            authRepository.savePendingTeamInviteCode(it)
                        }
                        OnboardingAnalytics.trackAuthPendingConfirmation(
                            mode = AuthMode.SIGN_UP.analyticsName,
                            hasReferralCode = currentState.hasReferralCode,
                            hasTeamInviteCode = currentState.hasTeamInviteCode,
                            hasPhone = currentState.hasPhone
                        )
                        _uiState.value = currentState.copy(
                            password = "",
                            isLoading = false,
                            error = null,
                            message = if (currentState.teamInviteCode.trim().isNotEmpty()) {
                                "Please confirm your email via the link sent before signing in. Your team access code has been saved."
                            } else {
                                "Please confirm your email via the link sent before signing in."
                            }
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Sign up failed", e)
                OnboardingAnalytics.trackAuthFailed(
                    mode = AuthMode.SIGN_UP.analyticsName,
                    method = "email",
                    hasReferralCode = currentState.hasReferralCode,
                    hasTeamInviteCode = currentState.hasTeamInviteCode,
                    hasPhone = currentState.hasPhone
                )
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.SIGN_UP)
                )
            }
        }
    }

    fun authenticate() {
        when (_uiState.value.mode) {
            AuthMode.SIGN_IN -> login()
            AuthMode.SIGN_UP -> signUp()
        }
    }

    fun signInWithGoogle(context: Context) {
        viewModelScope.launch {
            val currentState = _uiState.value
            OnboardingAnalytics.trackAuthSubmitted(
                mode = currentState.mode.analyticsName,
                method = "google",
                hasReferralCode = currentState.hasReferralCode,
                hasTeamInviteCode = currentState.hasTeamInviteCode,
                hasPhone = currentState.hasPhone
            )
            _uiState.value = currentState.copy(isLoading = true, error = null, message = null)
            try {
                if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank()) {
                    OnboardingAnalytics.trackAuthFailed(
                        mode = currentState.mode.analyticsName,
                        method = "google",
                        hasReferralCode = currentState.hasReferralCode,
                        hasTeamInviteCode = currentState.hasTeamInviteCode,
                        hasPhone = currentState.hasPhone
                    )
                    _uiState.value = currentState.copy(
                        isLoading = false,
                        error = "Google Sign-In is not configured yet."
                    )
                    return@launch
                }

                val credential = requestGoogleCredential(context)
                if (currentState.mode == AuthMode.SIGN_UP) {
                    currentState.referralCode.trim().ifNotEmpty(authRepository::savePendingReferralCode)
                }
                currentState.teamInviteCode.trim().ifNotEmpty(authRepository::savePendingTeamInviteCode)
                authRepository.loginWithGoogleIdToken(
                    idToken = credential.idToken,
                    nonce = credential.nonce
                )
                authRepository.applyPendingPostAuthActions(
                    teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                )
                val dealerId = authRepository.getDealerId()
                subscriptionManager.logIn(dealerId)
                OnboardingAnalytics.trackAuthCompleted(
                    mode = currentState.mode.analyticsName,
                    method = "google",
                    distinctId = dealerId,
                    hasReferralCode = currentState.hasReferralCode,
                    hasTeamInviteCode = currentState.hasTeamInviteCode,
                    hasPhone = currentState.hasPhone
                )
                _uiState.value = currentState.copy(
                    password = "",
                    phone = "",
                    referralCode = "",
                    teamInviteCode = "",
                    isLoading = false,
                    isGuestMode = false,
                    isSuccess = true,
                    error = null,
                    message = null
                )
            } catch (e: GetCredentialCancellationException) {
                Log.w(TAG, "Google credential flow did not complete", e)
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.SOCIAL_SIGN_IN),
                    message = null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Google sign-in failed", e)
                OnboardingAnalytics.trackAuthFailed(
                    mode = currentState.mode.analyticsName,
                    method = "google",
                    hasReferralCode = currentState.hasReferralCode,
                    hasTeamInviteCode = currentState.hasTeamInviteCode,
                    hasPhone = currentState.hasPhone
                )
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.SOCIAL_SIGN_IN)
                )
            }
        }
    }

    fun startGuestMode() {
        subscriptionManager.logOut()
        OnboardingAnalytics.trackGuestStarted()
        _uiState.value = AuthUiState(
            isGuestMode = true,
            isSuccess = true
        )
    }

    fun requestPasswordReset() {
        val email = _uiState.value.email.trim()
        OnboardingAnalytics.trackPasswordResetRequested(hasEmail = email.isNotEmpty())
        if (email.isEmpty()) {
            _uiState.value = _uiState.value.copy(
                error = "Please enter your email address to reset your password."
            )
            return
        }

        viewModelScope.launch {
            val currentState = _uiState.value
            _uiState.value = currentState.copy(isLoading = true, error = null, message = null)
            try {
                authRepository.resetPassword(email)
                _uiState.value = currentState.copy(
                    isLoading = false,
                    message = "Password reset email sent! Check your inbox.",
                    error = null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Password reset request failed", e)
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.PASSWORD_RESET_REQUEST)
                )
            }
        }
    }

    fun enterPasswordResetMode() {
        _uiState.value = _uiState.value.copy(
            showPasswordReset = true,
            newPassword = "",
            confirmPassword = "",
            error = null
        )
    }

    fun completePasswordReset() {
        val currentState = _uiState.value
        if (currentState.newPassword.length < 6) {
            _uiState.value = currentState.copy(error = "Password must be at least 6 characters long.")
            return
        }
        if (currentState.newPassword != currentState.confirmPassword) {
            _uiState.value = currentState.copy(error = "Passwords do not match.")
            return
        }

        viewModelScope.launch {
            _uiState.value = currentState.copy(isLoading = true, error = null)
            try {
                authRepository.updatePassword(_uiState.value.newPassword)
                authRepository.signOut()
                subscriptionManager.logOut()
                _uiState.value = AuthUiState(
                    message = "Password updated successfully. Please sign in with your new password."
                )
            } catch (e: Exception) {
                Log.e(TAG, "Password reset completion failed", e)
                _uiState.value = currentState.copy(
                    isLoading = false,
                    error = AuthErrorMapper.map(e, AuthFailureContext.PASSWORD_RESET_COMPLETE)
                )
            }
        }
    }

    fun cancelPasswordReset() {
        viewModelScope.launch {
            try {
                authRepository.signOut()
                subscriptionManager.logOut()
            } catch (_: Exception) {
            }
            _uiState.value = AuthUiState(
                referralCode = authRepository.getPendingReferralCode().orEmpty(),
                teamInviteCode = authRepository.getPendingTeamInviteCode().orEmpty()
            )
        }
    }

    private suspend fun requestGoogleCredential(context: Context): GoogleCredentialResult {
        val nonce = generateSecureRandomNonce()
        val signInWithGoogleOption = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setNonce(sha256(nonce))
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(signInWithGoogleOption)
            .build()

        val result = CredentialManager.create(context).getCredential(
            request = request,
            context = context
        )
        val credential = result.credential
        if (credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            try {
                val googleCredential = GoogleIdTokenCredential.createFrom(credential.data)
                return GoogleCredentialResult(idToken = googleCredential.idToken, nonce = nonce)
            } catch (e: GoogleIdTokenParsingException) {
                throw IllegalStateException("Google returned an invalid sign-in token.", e)
            }
        }

        throw IllegalStateException("Google returned an unsupported credential type.")
    }

    private fun generateSecureRandomNonce(byteLength: Int = 32): String {
        val randomBytes = ByteArray(byteLength)
        SecureRandom().nextBytes(randomBytes)
        return Base64.encodeToString(
            randomBytes,
            Base64.NO_WRAP or Base64.URL_SAFE or Base64.NO_PADDING
        )
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}

private const val TAG = "AuthViewModel"

private inline fun String.ifNotEmpty(block: (String) -> Unit) {
    if (isNotEmpty()) {
        block(this)
    }
}
