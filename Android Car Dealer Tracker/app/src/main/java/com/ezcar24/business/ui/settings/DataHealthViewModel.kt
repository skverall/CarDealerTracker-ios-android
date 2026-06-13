package com.ezcar24.business.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.data.sync.SyncDiagnosticsReport
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class DataHealthUiState(
    val report: SyncDiagnosticsReport? = null,
    val isRunning: Boolean = false,
    val isRefreshing: Boolean = false,
    val errorMessage: String? = null
)

@HiltViewModel
class DataHealthViewModel @Inject constructor(
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(DataHealthUiState())
    val uiState = _uiState.asStateFlow()

    fun runDiagnostics() {
        if (_uiState.value.isRunning || _uiState.value.isRefreshing) return

        viewModelScope.launch {
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId == null) {
                _uiState.update { it.copy(errorMessage = "No active business found.") }
                return@launch
            }

            _uiState.update { it.copy(isRunning = true, errorMessage = null) }
            try {
                val report = cloudSyncManager.runDiagnostics(dealerId)
                _uiState.update { it.copy(report = report, isRunning = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isRunning = false, errorMessage = e.message ?: "Diagnostics failed") }
            }
        }
    }

    fun runFullRefresh() {
        if (_uiState.value.isRunning || _uiState.value.isRefreshing) return

        viewModelScope.launch {
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId == null) {
                _uiState.update { it.copy(errorMessage = "No active business found.") }
                return@launch
            }

            _uiState.update { it.copy(isRefreshing = true, errorMessage = null) }
            try {
                cloudSyncManager.manualSync(dealerId, force = true)
                val report = cloudSyncManager.runDiagnostics(dealerId)
                _uiState.update { it.copy(report = report, isRefreshing = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isRefreshing = false, errorMessage = e.message ?: "Refresh failed") }
            }
        }
    }
}
