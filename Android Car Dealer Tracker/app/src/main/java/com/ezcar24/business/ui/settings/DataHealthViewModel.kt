package com.ezcar24.business.ui.settings

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.data.sync.SyncDiagnosticsReport
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
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
    val isDeduplicating: Boolean = false,
    val statusMessage: String? = null,
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

            _uiState.update { it.copy(isRunning = true, errorMessage = null, statusMessage = null) }
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

            _uiState.update { it.copy(isRefreshing = true, errorMessage = null, statusMessage = null) }
            try {
                cloudSyncManager.manualSync(dealerId, force = true)
                val report = cloudSyncManager.runDiagnostics(dealerId)
                _uiState.update { it.copy(report = report, isRefreshing = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isRefreshing = false, errorMessage = e.message ?: "Refresh failed") }
            }
        }
    }

    fun cleanUpDuplicates() {
        if (_uiState.value.isRunning || _uiState.value.isRefreshing || _uiState.value.isDeduplicating) return

        viewModelScope.launch {
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId == null) {
                _uiState.update { it.copy(errorMessage = "No active business found.", statusMessage = null) }
                return@launch
            }

            _uiState.update { it.copy(isDeduplicating = true, errorMessage = null, statusMessage = null) }
            try {
                cloudSyncManager.deduplicateData(dealerId)
                val report = cloudSyncManager.runDiagnostics(dealerId)
                _uiState.update {
                    it.copy(
                        report = report,
                        isDeduplicating = false,
                        statusMessage = "Duplicate records cleaned up successfully."
                    )
                }
            } catch (e: Exception) {
                Log.e(DATA_HEALTH_TAG, "cleanUpDuplicates failed", e)
                _uiState.update {
                    it.copy(
                        isDeduplicating = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.CLEAN_UP_DUPLICATES)
                    )
                }
            }
        }
    }
}

private const val DATA_HEALTH_TAG = "DataHealthViewModel"
