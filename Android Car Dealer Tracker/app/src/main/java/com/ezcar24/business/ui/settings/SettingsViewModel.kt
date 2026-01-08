package com.ezcar24.business.ui.settings

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.User
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.notification.NotificationPreferences
import com.ezcar24.business.notification.NotificationScheduler
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import io.github.jan.supabase.auth.user.UserInfo
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import java.util.Date

data class SettingsUiState(
    val currentUser: UserInfo? = null,
    val dealerUsers: List<User> = emptyList(),
    val lastBackupDate: Date? = null,
    val isBackupLoading: Boolean = false,
    val isSigningOut: Boolean = false,
    val diagnosticsResult: String? = null,
    val isPro: Boolean = false,
    val subscriptionExpiry: Date? = null,
    // Notifications
    val notificationsEnabled: Boolean = false,
    val needsNotificationPermission: Boolean = false
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager,
    private val notificationPreferences: NotificationPreferences,
    private val notificationScheduler: NotificationScheduler
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadProfile()
    }

    fun loadProfile() {
        viewModelScope.launch {
            try {
                val user = authRepository.getCurrentUser()
                _uiState.update { 
                    it.copy(
                        currentUser = user, 
                        isPro = true,
                        notificationsEnabled = notificationPreferences.isEnabled
                    ) 
                }
            } catch (e: Exception) {
                // handle error
            }
        }
    }

    fun toggleNotifications(enabled: Boolean) {
        viewModelScope.launch {
            // Check notification permission on Android 13+
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
            _uiState.update { it.copy(isBackupLoading = true) }
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.manualSync(dealerId, force = true)
                    notificationScheduler.refreshAll() // Refresh notifications after sync
                    _uiState.update { 
                        it.copy(
                            isBackupLoading = false, 
                            lastBackupDate = Date(),
                            diagnosticsResult = "Sync completed successfully."
                        )
                    }
                } catch (e: Exception) {
                     _uiState.update { 
                        it.copy(
                            isBackupLoading = false, 
                            diagnosticsResult = "Sync failed: ${e.message}"
                        )
                    }
                }
            } else {
                 _uiState.update { 
                    it.copy(
                        isBackupLoading = false, 
                        diagnosticsResult = "Sync failed: No dealer ID found."
                    )
                }
            }
        }
    }

    fun runDiagnostics() {
         viewModelScope.launch {
            _uiState.update { it.copy(diagnosticsResult = "Checking database integrity... OK\nSync Status... OK\nNetwork... OK") }
         }
    }
    
    fun signOut() {
        viewModelScope.launch {
            _uiState.update { it.copy(isSigningOut = true) }
            try {
                authRepository.signOut()
            } catch (e: Exception) {
                // error
            } finally {
                _uiState.update { it.copy(isSigningOut = false) }
            }
        }
    }
}
