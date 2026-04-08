package com.ezcar24.business.ui.inventory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.calculator.InventoryMetricsCalculator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.UUID
import javax.inject.Inject

data class InventoryAnalyticsUiState(
    val isLoading: Boolean = false,
    val vehicles: List<Vehicle> = emptyList(),
    val inventoryStats: Map<String, VehicleInventoryStats> = emptyMap(),
    val alerts: List<InventoryAlert> = emptyList(),
    val selectedAgingBucket: String? = null,
    val selectedStatus: String? = null,
    val sortBy: InventorySortOption = InventorySortOption.DAYS_DESC,
    
    // Computed metrics
    val totalInventoryValue: BigDecimal = BigDecimal.ZERO,
    val averageDaysInInventory: Int = 0,
    val inventoryTurnoverRatio: Double = 0.0,
    val healthScore: Int = 100,
    val agingDistribution: Map<String, Int> = emptyMap(),
    val totalHoldingCost: BigDecimal = BigDecimal.ZERO,
    val vehiclesOver90Days: Int = 0
)

enum class InventorySortOption {
    DAYS_ASC, DAYS_DESC,
    ROI_ASC, ROI_DESC,
    PROFIT_ASC, PROFIT_DESC,
    TOTAL_COST_ASC, TOTAL_COST_DESC
}

@HiltViewModel
class InventoryAnalyticsViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val vehicleInventoryStatsDao: VehicleInventoryStatsDao,
    private val inventoryAlertDao: InventoryAlertDao,
    private val expenseDao: ExpenseDao,
    private val holdingCostSettingsDao: HoldingCostSettingsDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "InventoryAnalyticsViewModel"
    private val _uiState = MutableStateFlow(InventoryAnalyticsUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            combine(
                vehicleDao.getAllActive(),
                vehicleInventoryStatsDao.getAllFlow(),
                inventoryAlertDao.getAllAlerts(),
                holdingCostSettingsDao.getSettings()
            ) { vehicles, allStats, alerts, settings ->
                
                // Filter to inventory vehicles only (not sold)
                val inventoryVehicles = vehicles.filter { it.status != "sold" }
                
                // Create stats map
                val statsMap = allStats.associateBy { it.vehicleId.toString() }
                
                // Calculate or refresh stats for vehicles without them
                val updatedStatsMap = statsMap.toMutableMap()
                inventoryVehicles.forEach { vehicle ->
                    if (!statsMap.containsKey(vehicle.id.toString())) {
                        val expenses = expenseDao.getExpensesForVehicleSync(vehicle.id)
                        val effectiveSettings = settings ?: HoldingCostSettings(
                            id = UUID.randomUUID(),
                            dealerId = CloudSyncEnvironment.currentDealerId ?: UUID.randomUUID(),
                            createdAt = Date(),
                            updatedAt = Date()
                        )
                        
                        val stats = InventoryMetricsCalculator.calculateInventoryStats(
                            vehicle,
                            expenses,
                            effectiveSettings
                        )
                        updatedStatsMap[vehicle.id.toString()] = stats
                        vehicleInventoryStatsDao.upsert(stats)
                    }
                }
                
                // Calculate metrics
                val inventoryStatsList = inventoryVehicles.mapNotNull { 
                    updatedStatsMap[it.id.toString()] 
                }
                
                val totalValue = inventoryStatsList.fold(BigDecimal.ZERO) { acc, stats ->
                    acc.add(stats.totalCost)
                }
                
                val avgDays = if (inventoryStatsList.isNotEmpty()) {
                    inventoryStatsList.sumOf { it.daysInInventory } / inventoryStatsList.size
                } else 0
                
                val agingDist = InventoryMetricsCalculator.calculateAgingDistribution(inventoryStatsList)
                
                val health = InventoryMetricsCalculator.calculateInventoryHealthScore(
                    inventoryVehicles,
                    inventoryStatsList
                )
                
                val totalHolding = InventoryMetricsCalculator.calculateTotalHoldingCost(inventoryStatsList)
                
                val over90Days = inventoryStatsList.count { it.daysInInventory >= 90 }
                
                // Calculate turnover ratio (simplified: 365 / avg days)
                val turnoverRatio = if (avgDays > 0) {
                    365.0 / avgDays
                } else 0.0
                
                InventoryAnalyticsUiState(
                    isLoading = false,
                    vehicles = inventoryVehicles,
                    inventoryStats = updatedStatsMap,
                    alerts = alerts.filter { !it.isRead },
                    totalInventoryValue = totalValue,
                    averageDaysInInventory = avgDays,
                    inventoryTurnoverRatio = turnoverRatio,
                    healthScore = health,
                    agingDistribution = agingDist,
                    totalHoldingCost = totalHolding,
                    vehiclesOver90Days = over90Days
                )
            }.collect { state ->
                _uiState.value = state
                applyFilters()
            }
        }
    }

    fun setAgingBucketFilter(bucket: String?) {
        _uiState.update { it.copy(selectedAgingBucket = bucket) }
        applyFilters()
    }

    fun setStatusFilter(status: String?) {
        _uiState.update { it.copy(selectedStatus = status) }
        applyFilters()
    }

    fun setSortOption(option: InventorySortOption) {
        _uiState.update { it.copy(sortBy = option) }
        applyFilters()
    }

    private fun applyFilters() {
        val currentState = _uiState.value
        var filteredVehicles = currentState.vehicles
        
        // Apply aging bucket filter
        currentState.selectedAgingBucket?.let { bucket ->
            filteredVehicles = filteredVehicles.filter { vehicle ->
                currentState.inventoryStats[vehicle.id.toString()]?.agingBucket == bucket
            }
        }
        
        // Apply status filter
        currentState.selectedStatus?.let { status ->
            filteredVehicles = filteredVehicles.filter { it.status == status }
        }
        
        // Apply sorting
        filteredVehicles = when (currentState.sortBy) {
            InventorySortOption.DAYS_ASC -> filteredVehicles.sortedBy {
                currentState.inventoryStats[it.id.toString()]?.daysInInventory ?: 0
            }
            InventorySortOption.DAYS_DESC -> filteredVehicles.sortedByDescending {
                currentState.inventoryStats[it.id.toString()]?.daysInInventory ?: 0
            }
            InventorySortOption.ROI_ASC -> filteredVehicles.sortedBy {
                currentState.inventoryStats[it.id.toString()]?.roiPercent ?: BigDecimal.ZERO
            }
            InventorySortOption.ROI_DESC -> filteredVehicles.sortedByDescending {
                currentState.inventoryStats[it.id.toString()]?.roiPercent ?: BigDecimal.ZERO
            }
            InventorySortOption.PROFIT_ASC -> filteredVehicles.sortedBy {
                currentState.inventoryStats[it.id.toString()]?.profitEstimate ?: BigDecimal.ZERO
            }
            InventorySortOption.PROFIT_DESC -> filteredVehicles.sortedByDescending {
                currentState.inventoryStats[it.id.toString()]?.profitEstimate ?: BigDecimal.ZERO
            }
            InventorySortOption.TOTAL_COST_ASC -> filteredVehicles.sortedBy {
                currentState.inventoryStats[it.id.toString()]?.totalCost ?: BigDecimal.ZERO
            }
            InventorySortOption.TOTAL_COST_DESC -> filteredVehicles.sortedByDescending {
                currentState.inventoryStats[it.id.toString()]?.totalCost ?: BigDecimal.ZERO
            }
        }
        
        _uiState.update { it.copy(vehicles = filteredVehicles) }
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.manualSync(dealerId, force = true)
                } catch (e: Exception) {
                    android.util.Log.e(tag, "manualSync failed: ${e.message}", e)
                }
            }
            loadData()
        }
    }

    fun recalculateStats(vehicleId: UUID) {
        viewModelScope.launch {
            val vehicle = vehicleDao.getById(vehicleId) ?: return@launch
            val expenses = expenseDao.getExpensesForVehicleSync(vehicleId)
            val settings = holdingCostSettingsDao.getSettings().firstOrNull()
                ?: HoldingCostSettings(
                    id = UUID.randomUUID(),
                    dealerId = CloudSyncEnvironment.currentDealerId ?: UUID.randomUUID(),
                    createdAt = Date(),
                    updatedAt = Date()
                )
            
            val stats = InventoryMetricsCalculator.calculateInventoryStats(
                vehicle,
                expenses,
                settings
            )
            
            vehicleInventoryStatsDao.upsert(stats)
            
            // Generate alerts
            val alerts = InventoryMetricsCalculator.generateInventoryAlerts(stats, vehicle)
            alerts.forEach { alert ->
                inventoryAlertDao.upsert(alert)
            }
            
            loadData()
        }
    }
}
