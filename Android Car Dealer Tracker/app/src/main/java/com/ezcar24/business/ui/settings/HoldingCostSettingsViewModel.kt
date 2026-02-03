package com.ezcar24.business.ui.settings

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.HoldingCostSettingsDao
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HoldingCostSettingsUiState(
    val isEnabled: Boolean = true,
    val annualRatePercent: String = "15.00",
    val dailyRatePercent: BigDecimal = BigDecimal("0.04109589"),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val saveSuccess: Boolean = false,
    val errorMessage: String? = null
)

@HiltViewModel
class HoldingCostSettingsViewModel @Inject constructor(
    private val holdingCostSettingsDao: HoldingCostSettingsDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(HoldingCostSettingsUiState())
    val uiState: StateFlow<HoldingCostSettingsUiState> = _uiState.asStateFlow()

    private val tag = "HoldingCostSettingsVM"

    init {
        loadSettings()
    }

    private fun loadSettings() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val dealerId = CloudSyncEnvironment.currentDealerId
                if (dealerId == null) {
                    _uiState.update { 
                        it.copy(
                            isLoading = false,
                            errorMessage = "Dealer ID not available"
                        )
                    }
                    return@launch
                }

                val settings = holdingCostSettingsDao.getByDealerId(dealerId)
                if (settings != null) {
                    _uiState.update {
                        it.copy(
                            isEnabled = settings.isEnabled,
                            annualRatePercent = settings.annualRatePercent.toString(),
                            dailyRatePercent = settings.dailyRatePercent,
                            isLoading = false
                        )
                    }
                } else {
                    // Create default settings
                    val defaultSettings = createDefaultSettings(dealerId)
                    holdingCostSettingsDao.upsert(defaultSettings)
                    _uiState.update {
                        it.copy(
                            isEnabled = defaultSettings.isEnabled,
                            annualRatePercent = defaultSettings.annualRatePercent.toString(),
                            dailyRatePercent = defaultSettings.dailyRatePercent,
                            isLoading = false
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(tag, "Error loading settings: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Failed to load settings"
                    )
                }
            }
        }
    }

    private fun createDefaultSettings(dealerId: UUID): HoldingCostSettings {
        val annualRate = BigDecimal("15.00")
        val dailyRate = calculateDailyRate(annualRate)
        return HoldingCostSettings(
            id = UUID.randomUUID(),
            dealerId = dealerId,
            annualRatePercent = annualRate,
            dailyRatePercent = dailyRate,
            isEnabled = true,
            createdAt = Date(),
            updatedAt = Date()
        )
    }

    fun toggleEnabled(enabled: Boolean) {
        _uiState.update { it.copy(isEnabled = enabled, saveSuccess = false) }
    }

    fun updateAnnualRate(rateString: String) {
        // Allow only valid decimal input
        val filtered = rateString.filter { it.isDigit() || it == '.' }
        val parts = filtered.split('.')
        val sanitized = if (parts.size > 2) {
            parts[0] + "." + parts.drop(1).joinToString("")
        } else {
            filtered
        }

        _uiState.update { 
            it.copy(
                annualRatePercent = sanitized,
                dailyRatePercent = calculateDailyRate(sanitized),
                saveSuccess = false
            )
        }
    }

    private fun calculateDailyRate(annualRate: String): BigDecimal {
        return try {
            val rate = BigDecimal(annualRate)
            calculateDailyRate(rate)
        } catch (e: NumberFormatException) {
            BigDecimal.ZERO
        }
    }

    private fun calculateDailyRate(annualRate: BigDecimal): BigDecimal {
        // Daily rate = Annual rate / 365
        return annualRate.divide(BigDecimal("365"), 8, RoundingMode.HALF_UP)
    }

    fun saveSettings() {
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, errorMessage = null) }
            try {
                val dealerId = CloudSyncEnvironment.currentDealerId
                if (dealerId == null) {
                    _uiState.update {
                        it.copy(
                            isSaving = false,
                            errorMessage = "Dealer ID not available"
                        )
                    }
                    return@launch
                }

                val annualRate = BigDecimal(uiState.value.annualRatePercent)
                val dailyRate = calculateDailyRate(annualRate)

                val settings = HoldingCostSettings(
                    id = UUID.randomUUID(),
                    dealerId = dealerId,
                    annualRatePercent = annualRate,
                    dailyRatePercent = dailyRate,
                    isEnabled = uiState.value.isEnabled,
                    createdAt = Date(),
                    updatedAt = Date()
                )

                holdingCostSettingsDao.upsert(settings)

                // Sync to cloud
                cloudSyncManager.upsertHoldingCostSettings(settings)

                _uiState.update {
                    it.copy(
                        isSaving = false,
                        saveSuccess = true,
                        dailyRatePercent = dailyRate
                    )
                }
            } catch (e: Exception) {
                Log.e(tag, "Error saving settings: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        errorMessage = "Failed to save settings"
                    )
                }
            }
        }
    }

    fun dismissError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun resetSaveSuccess() {
        _uiState.update { it.copy(saveSuccess = false) }
    }
}
