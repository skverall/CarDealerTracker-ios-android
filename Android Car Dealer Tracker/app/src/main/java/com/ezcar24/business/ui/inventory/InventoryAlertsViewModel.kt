package com.ezcar24.business.ui.inventory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.Date
import java.util.UUID
import javax.inject.Inject

data class InventoryAlertsUiState(
    val isLoading: Boolean = false,
    val alerts: List<AlertWithVehicle> = emptyList(),
    val selectedSeverity: String? = null,
    val selectedType: InventoryAlertType? = null,
    val unreadCount: Int = 0
)

data class AlertWithVehicle(
    val alert: InventoryAlert,
    val vehicle: Vehicle?
)

@HiltViewModel
class InventoryAlertsViewModel @Inject constructor(
    private val inventoryAlertDao: InventoryAlertDao,
    private val vehicleDao: VehicleDao
) : ViewModel() {

    private val tag = "InventoryAlertsViewModel"
    private val _uiState = MutableStateFlow(InventoryAlertsUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadAlerts()
    }

    fun loadAlerts() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            inventoryAlertDao.getAllAlerts().collect { alerts ->
                val alertsWithVehicles = alerts.map { alert ->
                    AlertWithVehicle(
                        alert = alert,
                        vehicle = vehicleDao.getById(alert.vehicleId)
                    )
                }
                
                val unread = alerts.count { !it.isRead }
                
                _uiState.update { currentState ->
                    currentState.copy(
                        isLoading = false,
                        alerts = alertsWithVehicles,
                        unreadCount = unread
                    )
                }
                
                applyFilters()
            }
        }
    }

    fun setSeverityFilter(severity: String?) {
        _uiState.update { it.copy(selectedSeverity = severity) }
        applyFilters()
    }

    fun setTypeFilter(type: InventoryAlertType?) {
        _uiState.update { it.copy(selectedType = type) }
        applyFilters()
    }

    private fun applyFilters() {
        val currentState = _uiState.value
        val allAlerts = currentState.alerts
        
        var filtered = allAlerts
        
        currentState.selectedSeverity?.let { severity ->
            filtered = filtered.filter { it.alert.severity == severity }
        }
        
        currentState.selectedType?.let { type ->
            filtered = filtered.filter { it.alert.alertType == type }
        }
        
        _uiState.update { it.copy(alerts = filtered) }
    }

    fun markAsRead(alertId: UUID) {
        viewModelScope.launch {
            inventoryAlertDao.markAsRead(alertId)
        }
    }

    fun markAllAsRead() {
        viewModelScope.launch {
            _uiState.value.alerts.forEach { alertWithVehicle ->
                inventoryAlertDao.markAsRead(alertWithVehicle.alert.id)
            }
        }
    }

    fun dismissAlert(alertId: UUID) {
        viewModelScope.launch {
            inventoryAlertDao.dismiss(alertId, Date())
        }
    }

    fun dismissAllAlerts() {
        viewModelScope.launch {
            _uiState.value.alerts.forEach { alertWithVehicle ->
                inventoryAlertDao.dismiss(alertWithVehicle.alert.id, Date())
            }
        }
    }

    fun deleteAlert(alertId: UUID) {
        viewModelScope.launch {
            val alert = _uiState.value.alerts.find { it.alert.id == alertId }?.alert
            alert?.let {
                inventoryAlertDao.delete(it)
            }
        }
    }

    fun refresh() {
        loadAlerts()
    }

    fun getSeverityCount(severity: String): Int {
        return _uiState.value.alerts.count { it.alert.severity == severity }
    }

    fun getTypeCount(type: InventoryAlertType): Int {
        return _uiState.value.alerts.count { it.alert.alertType == type }
    }
}
