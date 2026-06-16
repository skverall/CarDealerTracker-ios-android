package com.ezcar24.business.ui.main

import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.repository.PermissionRepository
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

private const val MAIN_VIEW_MODEL_TAG = "MainViewModel"

@HiltViewModel
class MainViewModel @Inject constructor(
    private val accountRepository: AccountRepository,
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager,
    private val permissionRepository: PermissionRepository,
    private val subscriptionManager: SubscriptionManager
) : ViewModel(), DefaultLifecycleObserver {

    private val _startDestination = MutableStateFlow<String?>(null)
    val startDestination = _startDestination.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isGuestMode = MutableStateFlow(false)
    val isGuestMode = _isGuestMode.asStateFlow()

    val permissionState = permissionRepository.state

    // Periodic sync interval (5 minutes, matching iOS)
    private val periodicSyncIntervalMs = 5 * 60 * 1000L
    private var periodicSyncJob: Job? = null
    private var currentDealerId: UUID? = null

    init {
        observeActiveOrganization()
        checkSession()
    }

    private fun observeActiveOrganization() {
        viewModelScope.launch {
            accountRepository.activeOrganization.collectLatest { organization ->
                currentDealerId = organization?.organizationId
                CloudSyncEnvironment.currentDealerId = organization?.organizationId
                permissionRepository.activate(organization)
                cloudSyncManager.refreshLastSyncForCurrentOrg()
                refreshPeriodicSync()
            }
        }
    }

    private fun checkSession() {
        viewModelScope.launch {
            try {
                authRepository.awaitInitialization()
                val user = authRepository.getCurrentUser()
                if (user != null) {
                    subscriptionManager.logIn(user.id)
                    authRepository.applyPendingPostAuthActions()
                    val dealerId = accountRepository.bootstrapActiveOrganization()
                    if (dealerId != null) {
                        currentDealerId = dealerId
                        CloudSyncEnvironment.currentDealerId = dealerId
                        cloudSyncManager.refreshLastSyncForCurrentOrg()
                        launch {
                            try {
                                cloudSyncManager.syncAfterLogin(
                                    dealerId = dealerId,
                                    forceRefresh = cloudSyncManager.lastSyncAt == null
                                )
                            } catch (e: Exception) {
                                Log.e(MAIN_VIEW_MODEL_TAG, "syncAfterLogin failed: ${e.message}", e)
                            }
                        }
                        _startDestination.value = "home"
                        startPeriodicSync()
                    } else {
                        _startDestination.value = "login"
                    }
                } else {
                    subscriptionManager.logOut()
                    _startDestination.value = "login"
                }
            } catch (e: Exception) {
                Log.e(MAIN_VIEW_MODEL_TAG, "checkSession failed: ${e.message}", e)
                _startDestination.value = "login"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun onLoginSuccess() {
        _isGuestMode.value = false
        checkSession()
    }

    fun onGuestMode() {
        _isGuestMode.value = true
        subscriptionManager.logOut()
        permissionRepository.reset()
        stopPeriodicSync()
        _startDestination.value = "home"
        _isLoading.value = false
    }

    fun onSignedOut() {
        _isGuestMode.value = false
        subscriptionManager.logOut()
        permissionRepository.reset()
        accountRepository.clearSessionState()
        cloudSyncManager.resetSyncState()
        currentDealerId = null
        CloudSyncEnvironment.currentDealerId = null
        stopPeriodicSync()
        _startDestination.value = "login"
        _isLoading.value = false
    }

    // === Lifecycle-based sync (matching iOS scenePhase behavior) ===

    override fun onResume(owner: LifecycleOwner) {
        super.onResume(owner)
        triggerForegroundSync()
    }

    override fun onPause(owner: LifecycleOwner) {
        super.onPause(owner)
        // Optionally stop periodic sync when backgrounded (iOS continues in background)
    }

    /**
     * Trigger sync when app comes to foreground (matching iOS triggerForegroundSyncIfNeeded)
     */
    private fun triggerForegroundSync() {
        if (_isGuestMode.value) return
        val dealerId = currentDealerId ?: return

        viewModelScope.launch {
            try {
                cloudSyncManager.manualSync(dealerId)
            } catch (e: Exception) {
                Log.e(MAIN_VIEW_MODEL_TAG, "foreground sync failed: ${e.message}", e)
            }
        }
    }

    // === Periodic Sync (matching iOS startPeriodicSyncIfNeeded) ===

    private fun startPeriodicSync() {
        if (periodicSyncJob != null) return
        if (_isGuestMode.value) return
        val dealerId = currentDealerId ?: return

        periodicSyncJob = viewModelScope.launch {
            while (isActive) {
                delay(periodicSyncIntervalMs)
                if (!isActive) break
                if (_isGuestMode.value) continue
                try {
                    cloudSyncManager.manualSync(dealerId)
                } catch (e: Exception) {
                    Log.e(MAIN_VIEW_MODEL_TAG, "periodic sync failed: ${e.message}", e)
                }
            }
        }
    }

    private fun stopPeriodicSync() {
        periodicSyncJob?.cancel()
        periodicSyncJob = null
    }

    fun refreshPeriodicSync() {
        stopPeriodicSync()
        if (_isGuestMode.value) {
            return
        }
        if (currentDealerId == null) {
            return
        }
        startPeriodicSync()
    }

    fun refreshPermissions() {
        viewModelScope.launch {
            try {
                permissionRepository.refresh()
            } catch (e: Exception) {
                Log.e(MAIN_VIEW_MODEL_TAG, "refreshPermissions failed: ${e.message}", e)
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopPeriodicSync()
    }
}
