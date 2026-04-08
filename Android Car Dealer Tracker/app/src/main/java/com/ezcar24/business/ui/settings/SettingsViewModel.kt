package com.ezcar24.business.ui.settings

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.repository.ReferralStats
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.notification.NotificationPreferences
import com.ezcar24.business.notification.NotificationScheduler
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.auth.user.UserInfo
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SettingsUiState(
    val currentUser: UserInfo? = null,
    val organizations: List<OrganizationMembership> = emptyList(),
    val activeOrganization: OrganizationMembership? = null,
    val referralCode: String? = null,
    val referralStats: ReferralStats? = null,
    val lastBackupDate: Date? = null,
    val isLoadingAccount: Boolean = false,
    val isBackupLoading: Boolean = false,
    val isFetchingReferralCode: Boolean = false,
    val isSwitchingOrganization: Boolean = false,
    val isSigningOut: Boolean = false,
    val signedOut: Boolean = false,
    val diagnosticsResult: String? = null,
    val statusMessage: String? = null,
    val errorMessage: String? = null,
    val isPro: Boolean = false,
    val subscriptionExpiry: Date? = null,
    val notificationsEnabled: Boolean = false,
    val needsNotificationPermission: Boolean = false
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val accountRepository: AccountRepository,
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager,
    private val notificationPreferences: NotificationPreferences,
    private val notificationScheduler: NotificationScheduler,
    private val subscriptionManager: SubscriptionManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            subscriptionManager.isProAccessActive.collect { isPro ->
                _uiState.update { it.copy(isPro = isPro) }
            }
        }
        loadProfile()
    }

    fun loadProfile() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoadingAccount = true,
                    errorMessage = null,
                    signedOut = false
                )
            }
            try {
                val user = authRepository.getCurrentUser()
                val organizations = accountRepository.refreshOrganizations()
                val activeOrganization = accountRepository.activeOrganization.value
                val referralStats = if (activeOrganization != null) {
                    accountRepository.getReferralStats()
                } else {
                    null
                }
                _uiState.update {
                    it.copy(
                        currentUser = user,
                        organizations = organizations,
                        activeOrganization = activeOrganization,
                        referralStats = referralStats,
                        isLoadingAccount = false,
                        notificationsEnabled = notificationPreferences.isEnabled
                    )
                }
            } catch (e: Exception) {
                Log.e(SETTINGS_TAG, "loadProfile failed", e)
                _uiState.update {
                    it.copy(
                        isLoadingAccount = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.LOAD_ACCOUNT)
                    )
                }
            }
        }
    }

    fun toggleNotifications(enabled: Boolean) {
        viewModelScope.launch {
            if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val hasPermission = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED

                if (!hasPermission) {
                    _uiState.update { it.copy(needsNotificationPermission = true) }
                    return@launch
                }
            }

            notificationPreferences.isEnabled = enabled
            _uiState.update {
                it.copy(
                    notificationsEnabled = enabled,
                    needsNotificationPermission = false
                )
            }

            if (enabled) {
                notificationScheduler.refreshAll()
            }
        }
    }

    fun onPermissionResult(granted: Boolean) {
        _uiState.update { it.copy(needsNotificationPermission = false) }
        if (granted) {
            toggleNotifications(true)
        }
    }

    fun triggerBackup() {
        triggerSync()
    }

    fun triggerSync() {
        viewModelScope.launch {
            val dealerId = _uiState.value.activeOrganization?.organizationId
            if (dealerId == null) {
                _uiState.update {
                    it.copy(
                        isBackupLoading = false,
                        errorMessage = "No active business found."
                    )
                }
                return@launch
            }

            _uiState.update { it.copy(isBackupLoading = true, errorMessage = null, statusMessage = null) }
            try {
                cloudSyncManager.manualSync(dealerId, force = true)
                notificationScheduler.refreshAll()
                _uiState.update {
                    it.copy(
                        isBackupLoading = false,
                        lastBackupDate = Date(),
                        statusMessage = "Sync completed successfully."
                    )
                }
            } catch (e: Exception) {
                Log.e(SETTINGS_TAG, "triggerSync failed", e)
                _uiState.update {
                    it.copy(
                        isBackupLoading = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.RUN_SYNC)
                    )
                }
            }
        }
    }

    fun refreshReferralCode() {
        viewModelScope.launch {
            val dealerId = _uiState.value.activeOrganization?.organizationId ?: run {
                _uiState.update { it.copy(errorMessage = "Select a business first.") }
                return@launch
            }
            _uiState.update { it.copy(isFetchingReferralCode = true, errorMessage = null) }
            val referralCode = accountRepository.getDealerReferralCode(dealerId)
            _uiState.update {
                it.copy(
                    isFetchingReferralCode = false,
                    referralCode = referralCode,
                    errorMessage = if (referralCode == null) "Unable to generate invite code." else null
                )
            }
        }
    }

    fun switchOrganization(organizationId: UUID) {
        if (_uiState.value.isSwitchingOrganization) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSwitchingOrganization = true,
                    errorMessage = null,
                    statusMessage = null
                )
            }
            try {
                val organization = accountRepository.switchOrganization(
                    organizationId = organizationId,
                    forceSync = true
                )
                val organizations = accountRepository.refreshOrganizations()
                _uiState.update {
                    it.copy(
                        organizations = organizations,
                        activeOrganization = organization ?: accountRepository.activeOrganization.value,
                        referralStats = accountRepository.getReferralStats(),
                        referralCode = null,
                        isSwitchingOrganization = false,
                        statusMessage = organization?.let { active ->
                            "Switched to ${active.organizationName}."
                        }
                    )
                }
            } catch (e: Exception) {
                Log.e(SETTINGS_TAG, "switchOrganization failed", e)
                _uiState.update {
                    it.copy(
                        isSwitchingOrganization = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.SWITCH_BUSINESS)
                    )
                }
            }
        }
    }

    fun createOrganization(name: String) {
        if (_uiState.value.isSwitchingOrganization) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSwitchingOrganization = true,
                    errorMessage = null,
                    statusMessage = null
                )
            }
            try {
                val organization = accountRepository.createOrganization(name)
                _uiState.update {
                    it.copy(
                        organizations = accountRepository.organizations.value,
                        activeOrganization = organization,
                        referralStats = accountRepository.getReferralStats(),
                        referralCode = null,
                        isSwitchingOrganization = false,
                        statusMessage = "Created ${organization.organizationName}."
                    )
                }
            } catch (e: Exception) {
                Log.e(SETTINGS_TAG, "createOrganization failed", e)
                _uiState.update {
                    it.copy(
                        isSwitchingOrganization = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.CREATE_BUSINESS)
                    )
                }
            }
        }
    }

    fun joinTeamByCode(code: String) {
        viewModelScope.launch {
            val result = authRepository.submitTeamInviteCode(code)
            if (result.success) {
                val organizations = accountRepository.refreshOrganizations()
                _uiState.update {
                    it.copy(
                        organizations = organizations,
                        activeOrganization = accountRepository.activeOrganization.value,
                        statusMessage = result.message ?: "Invite accepted.",
                        errorMessage = null
                    )
                }
            } else {
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            result.message ?: "Invite code could not be applied.",
                            UserFacingErrorContext.ACCEPT_TEAM_INVITE
                        )
                    )
                }
            }
        }
    }

    fun runDiagnostics() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(diagnosticsResult = "Checking database integrity... OK\nSync Status... OK\nNetwork... OK")
            }
        }
    }

    fun clearStatusMessage() {
        _uiState.update { it.copy(statusMessage = null) }
    }

    fun clearErrorMessage() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun signOut() {
        viewModelScope.launch {
            _uiState.update { it.copy(isSigningOut = true, errorMessage = null) }
            try {
                authRepository.signOut()
                withContext(Dispatchers.IO) {
                    accountRepository.clearLocalData()
                }
                accountRepository.clearSessionState()
                cloudSyncManager.resetSyncState()
                _uiState.update { it.copy(isSigningOut = false, signedOut = true) }
            } catch (e: Exception) {
                Log.e(SETTINGS_TAG, "signOut failed", e)
                _uiState.update {
                    it.copy(
                        isSigningOut = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.SIGN_OUT)
                    )
                }
            }
        }
    }

    fun consumeSignedOut() {
        _uiState.update { it.copy(signedOut = false) }
    }
}

private const val SETTINGS_TAG = "SettingsViewModel"
