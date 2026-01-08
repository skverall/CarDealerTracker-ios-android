package com.ezcar24.business.ui.main

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel(), DefaultLifecycleObserver {

    private val _startDestination = MutableStateFlow<String?>(null)
    val startDestination = _startDestination.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading = _isLoading.asStateFlow()

    private val _isGuestMode = MutableStateFlow(false)
    val isGuestMode = _isGuestMode.asStateFlow()

    // Periodic sync interval (5 minutes, matching iOS)
    private val periodicSyncIntervalMs = 5 * 60 * 1000L
    private var periodicSyncJob: Job? = null
    private var currentDealerId: UUID? = null

    init {
        checkSession()
    }

    private fun checkSession() {
        viewModelScope.launch {
            authRepository.awaitInitialization()
            val user = authRepository.getCurrentUser()
            if (user != null) {
                val dealerIdStr = authRepository.getDealerId()
                if (dealerIdStr != null) {
                    try {
                        val dealerId = UUID.fromString(dealerIdStr)
                        currentDealerId = dealerId
                        CloudSyncEnvironment.currentDealerId = dealerId
                        // Initial sync after bootstrap (matching iOS)
                        launch {
                            cloudSyncManager.syncAfterLogin(dealerId)
                        }
                        _startDestination.value = "home"
                        // Start periodic sync
                        startPeriodicSync()
                    } catch (e: Exception) {
                        e.printStackTrace()
                        _startDestination.value = "login"
                    }
                } else {
                    _startDestination.value = "login"
                }
            } else {
                _startDestination.value = "login"
            }
            _isLoading.value = false
        }
    }

    fun onLoginSuccess() {
        _isGuestMode.value = false
        checkSession()
    }

    fun onGuestMode() {
        _isGuestMode.value = true
        stopPeriodicSync()
        _startDestination.value = "home"
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
            cloudSyncManager.manualSync(dealerId)
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
                cloudSyncManager.manualSync(dealerId)
            }
        }
    }

    private fun stopPeriodicSync() {
        periodicSyncJob?.cancel()
        periodicSyncJob = null
    }

    fun refreshPeriodicSync() {
        if (_isGuestMode.value) {
            stopPeriodicSync()
            return
        }
        if (currentDealerId == null) {
            stopPeriodicSync()
            return
        }
        startPeriodicSync()
    }

    override fun onCleared() {
        super.onCleared()
        stopPeriodicSync()
    }
}
