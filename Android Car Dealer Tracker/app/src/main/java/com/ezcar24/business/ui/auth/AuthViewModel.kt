package com.ezcar24.business.ui.auth

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AuthDeepLinkResult
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.repository.SignUpResult
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class AuthMode {
    SIGN_IN,
    SIGN_UP
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

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val accountRepository: AccountRepository,
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager
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
        _uiState.value = _uiState.value.copy(mode = mode, error = null, message = null)
    }

    fun login() {
        viewModelScope.launch {
            val currentState = _uiState.value
            _uiState.value = currentState.copy(isLoading = true, error = null, message = null)
            try {
                authRepository.login(
                    email = currentState.email.trim(),
                    password = currentState.password
                )
                authRepository.applyPendingPostAuthActions(
                    teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                )
                triggerSync()
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
                        authRepository.applyPendingPostAuthActions(
                            teamInviteCode = currentState.teamInviteCode.trim().ifBlank { null }
                        )
                        triggerSync()
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

    fun startGuestMode() {
        _uiState.value = AuthUiState(
            isGuestMode = true,
            isSuccess = true
        )
    }

    fun requestPasswordReset() {
        val email = _uiState.value.email.trim()
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
            } catch (_: Exception) {
            }
            _uiState.value = AuthUiState(
                referralCode = authRepository.getPendingReferralCode().orEmpty(),
                teamInviteCode = authRepository.getPendingTeamInviteCode().orEmpty()
            )
        }
    }

    private suspend fun triggerSync() {
        val dealerId = accountRepository.bootstrapActiveOrganization()
        if (dealerId != null) {
            CloudSyncEnvironment.currentDealerId = dealerId
            cloudSyncManager.syncAfterLogin(dealerId)
        }
    }
}

private const val TAG = "AuthViewModel"

private inline fun String.ifNotEmpty(block: (String) -> Unit) {
    if (isNotEmpty()) {
        block(this)
    }
}
