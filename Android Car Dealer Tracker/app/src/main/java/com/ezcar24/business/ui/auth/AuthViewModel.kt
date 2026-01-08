package com.ezcar24.business.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

enum class AuthMode { SIGN_IN, SIGN_UP }

data class AuthUiState(
    val email: String = "",
    val password: String = "",
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
        get() = email.isNotBlank() && password.length >= 6
    
    val isPasswordResetValid: Boolean
        get() = newPassword.length >= 6 && newPassword == confirmPassword
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState = _uiState.asStateFlow()

    fun onEmailChange(email: String) {
        _uiState.value = _uiState.value.copy(email = email, error = null, message = null)
    }

    fun onPasswordChange(password: String) {
        _uiState.value = _uiState.value.copy(password = password, error = null, message = null)
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
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                authRepository.login(
                    email = _uiState.value.email.trim(),
                    password = _uiState.value.password
                )
                triggerSync()
                _uiState.value = _uiState.value.copy(isLoading = false, isSuccess = true)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun signUp() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                authRepository.signUp(
                    email = _uiState.value.email.trim(),
                    password = _uiState.value.password
                )
                triggerSync()
                _uiState.value = _uiState.value.copy(isLoading = false, isSuccess = true)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
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
        _uiState.value = _uiState.value.copy(
            isGuestMode = true,
            isSuccess = true
        )
    }

    fun requestPasswordReset() {
        val email = _uiState.value.email.trim()
        if (email.isEmpty()) {
            _uiState.value = _uiState.value.copy(
                error = "Please enter your email address to reset password."
            )
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null, message = null)
            try {
                authRepository.resetPassword(email)
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    message = "Password reset email sent! Check your inbox."
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
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
        if (!_uiState.value.isPasswordResetValid) {
            _uiState.value = _uiState.value.copy(error = "Passwords do not match or are too short")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                authRepository.updatePassword(_uiState.value.newPassword)
                authRepository.signOut()
                _uiState.value = AuthUiState(
                    message = "Password updated successfully. Please sign in with your new password."
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun cancelPasswordReset() {
        viewModelScope.launch {
            try {
                authRepository.signOut()
            } catch (_: Exception) { }
            _uiState.value = AuthUiState()
        }
    }

    private suspend fun triggerSync() {
        val dealerIdStr = authRepository.getDealerId()
        if (dealerIdStr != null) {
            val dealerId = UUID.fromString(dealerIdStr)
            CloudSyncEnvironment.currentDealerId = dealerId
            cloudSyncManager.syncAfterLogin(dealerId)
        }
    }
}
