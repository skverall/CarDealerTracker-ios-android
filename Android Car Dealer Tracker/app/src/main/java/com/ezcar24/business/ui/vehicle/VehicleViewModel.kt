package com.ezcar24.business.ui.vehicle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.HoldingCostSettings
import com.ezcar24.business.data.local.HoldingCostSettingsDao
import com.ezcar24.business.data.local.VehicleInventoryStats
import com.ezcar24.business.data.local.InventoryAlert
import com.ezcar24.business.data.local.InventoryAlertDao
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.calculator.HoldingCostCalculator
import com.ezcar24.business.util.calculator.VehicleFinancialsCalculator
import com.ezcar24.business.util.calculator.InventoryMetricsCalculator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject
import java.util.UUID
import java.util.Date
import java.math.BigDecimal

data class VehicleFinancialSummary(
    val purchasePrice: BigDecimal = BigDecimal.ZERO,
    val totalExpenses: BigDecimal = BigDecimal.ZERO,
    val holdingCost: BigDecimal = BigDecimal.ZERO,
    val totalCost: BigDecimal = BigDecimal.ZERO,
    val expenseBreakdown: Map<com.ezcar24.business.data.local.ExpenseCategoryType, BigDecimal> = emptyMap(),
    val projectedROI: BigDecimal? = null,
    val actualROI: BigDecimal? = null,
    val breakEvenPrice: BigDecimal = BigDecimal.ZERO,
    val recommendedPrice: BigDecimal = BigDecimal.ZERO,
    val dailyHoldingCost: BigDecimal = BigDecimal.ZERO
)

data class VehicleDetailUiState(
    val vehicle: Vehicle? = null,
    val expenses: List<Expense> = emptyList(),
    val financialSummary: VehicleFinancialSummary = VehicleFinancialSummary(),
    val inventoryStats: VehicleInventoryStats? = null,
    val alerts: List<InventoryAlert> = emptyList(),
    val holdingCostSettings: HoldingCostSettings? = null,
    val isLoading: Boolean = false
)

data class VehicleUiState(
    val vehicles: List<VehicleWithFinancials> = emptyList(),
    val filteredVehicles: List<VehicleWithFinancials> = emptyList(),
    val isLoading: Boolean = false,
    val filterStatus: String? = null, // null = inventory (all active except sold), "sold" = sold vehicles only
    val searchQuery: String = "",
    val selectedVehicle: Vehicle? = null,
    val accounts: List<FinancialAccount> = emptyList(),
    val sortOrder: String = "newest",
    val agingBucketFilter: String? = null,
    val inventoryStats: Map<String, VehicleInventoryStats> = emptyMap()
)

@HiltViewModel
class VehicleViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val financialAccountDao: FinancialAccountDao,
    private val expenseDao: ExpenseDao,
    private val holdingCostSettingsDao: HoldingCostSettingsDao,
    private val inventoryAlertDao: InventoryAlertDao,
    private val vehicleInventoryStatsDao: VehicleInventoryStatsDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "VehicleViewModel"
    private val _uiState = MutableStateFlow(VehicleUiState())
    val uiState = _uiState.asStateFlow()

    private val _detailUiState = MutableStateFlow(VehicleDetailUiState())
    val detailUiState = _detailUiState.asStateFlow()

    init {
        loadVehicles()
        loadAccounts()
    }

    private fun loadAccounts() {
        viewModelScope.launch {
            financialAccountDao.getAll().collect { accounts ->
                _uiState.update { it.copy(accounts = accounts) }
            }
        }
    }

    fun setStatusFilter(status: String?) {
        _uiState.update { it.copy(filterStatus = status) }
        applyFilters()
    }

    fun onSearchQueryChanged(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFilters()
    }

    fun setSortOrder(order: String) {
        _uiState.update { it.copy(sortOrder = order) }
        applyFilters()
    }

    fun setAgingBucketFilter(bucket: String?) {
        _uiState.update { it.copy(agingBucketFilter = bucket) }
        applyFilters()
    }

    fun updateVehicleStatus(id: UUID, status: String) {
        viewModelScope.launch {
            val vehicle = vehicleDao.getById(id)
            if (vehicle != null) {
                val updated = vehicle.copy(
                    status = status,
                    updatedAt = Date(),
                    // If marking as sold, maybe set defaults? simplified for now
                    saleDate = if (status == "sold") Date() else vehicle.saleDate
                )
                vehicleDao.upsert(updated)
                // loadVehicles() removed - updates are automatic via Flow
            }
        }
    }

    private fun applyFilters() {
        val currentState = _uiState.value
        val allVehicles = currentState.vehicles
        val status = currentState.filterStatus
        val query = currentState.searchQuery.trim().lowercase()
        val sort = currentState.sortOrder
        val agingBucket = currentState.agingBucketFilter
        val statsMap = currentState.inventoryStats

        var filtered = allVehicles.filter { item ->
            // Status Filter - matches iOS VehicleStatusDashboard logic
            val matchesStatus = when (status) {
                "sold" -> item.vehicle.status == "sold"
                "on_sale" -> item.vehicle.status == "on_sale"
                "owned" -> item.vehicle.status == "owned" || item.vehicle.status == "under_service"
                "in_transit" -> item.vehicle.status == "in_transit"
                "all" -> item.vehicle.status != "sold" // All inventory (non-sold)
                null -> item.vehicle.status != "sold" // Default: show inventory
                else -> item.vehicle.status != "sold"
            }

            // Search Filter
            val matchesSearch = if (query.isEmpty()) true else {
                val v = item.vehicle
                (v.make?.lowercase()?.contains(query) == true) ||
                (v.model?.lowercase()?.contains(query) == true) ||
                (v.vin.lowercase().contains(query)) ||
                (v.year?.toString()?.contains(query) == true)
            }

            // Aging Bucket Filter
            val matchesAgingBucket = agingBucket?.let {
                val vehicleStats = statsMap[item.vehicle.id.toString()]
                vehicleStats?.agingBucket == it
            } ?: true

            matchesStatus && matchesSearch && matchesAgingBucket
        }
        
        // Apply Sorting
        filtered = when (sort) {
            "price_asc" -> filtered.sortedBy { it.vehicle.purchasePrice }
            "price_desc" -> filtered.sortedByDescending { it.vehicle.purchasePrice }
            "year_desc" -> filtered.sortedByDescending { it.vehicle.year ?: 0 }
            "year_asc" -> filtered.sortedBy { it.vehicle.year ?: 0 }
            "days_asc" -> filtered.sortedBy { statsMap[it.vehicle.id.toString()]?.daysInInventory ?: 0 }
            "days_desc" -> filtered.sortedByDescending { statsMap[it.vehicle.id.toString()]?.daysInInventory ?: 0 }
            "roi_asc" -> filtered.sortedBy { statsMap[it.vehicle.id.toString()]?.roiPercent ?: BigDecimal.ZERO }
            "roi_desc" -> filtered.sortedByDescending { statsMap[it.vehicle.id.toString()]?.roiPercent ?: BigDecimal.ZERO }
            "oldest" -> filtered.sortedBy { it.vehicle.createdAt }
            else -> filtered.sortedByDescending { it.vehicle.createdAt } // Default: Newest first
        }
        
        _uiState.update { it.copy(filteredVehicles = filtered) }
    }

    fun loadVehicles() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            // Combine vehicles with their inventory stats
            combine(
                vehicleDao.getAllActiveWithFinancialsFlow(),
                vehicleInventoryStatsDao.getAllIncludingDeleted()
            ) { vehicles, stats ->
                val statsMap = stats.associateBy { it.vehicleId.toString() }
                Pair(vehicles, statsMap)
            }.collect { (vehicles, statsMap) ->
                _uiState.update { it.copy(
                    vehicles = vehicles, 
                    inventoryStats = statsMap,
                    isLoading = false
                ) }
                applyFilters()
            }
        }
    }

    // loadAccounts() removed - duplicate, exists in init block helper if needed but already collected there.
    // Actually, looking at the code, init calls loadAccounts() which is defined at line 50.
    // This duplicate at line 143 was error prone. Removing it.

    fun refresh(force: Boolean = true) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.manualSync(dealerId, force = force)
                } catch (e: Exception) {
                    Log.e(tag, "manualSync failed: ${e.message}", e)
                }
            } else {
                Log.w(tag, "refresh skipped: dealerId is null")
            }
            // loadVehicles() removed - Flow remains active
        }
    }

    fun selectVehicle(id: String) {
        viewModelScope.launch {
            try {
                val uuid = UUID.fromString(id)
                _detailUiState.update { it.copy(isLoading = true) }

                combine(
                    flow { emit(vehicleDao.getById(uuid)) },
                    expenseDao.getByVehicleId(uuid),
                    holdingCostSettingsDao.getSettings()
                ) { vehicle, expenses, settings ->
                    Triple(vehicle, expenses, settings)
                }.collect { (vehicle, expenses, settings) ->
                    if (vehicle != null) {
                        val effectiveSettings = settings ?: HoldingCostSettings(
                            id = UUID.randomUUID(),
                            dealerId = CloudSyncEnvironment.currentDealerId ?: UUID.randomUUID(),
                            createdAt = Date(),
                            updatedAt = Date()
                        )

                        val holdingCost = HoldingCostCalculator.calculateAccumulatedHoldingCost(
                            vehicle,
                            effectiveSettings,
                            expenses
                        )

                        val dailyHoldingCost = HoldingCostCalculator.calculateDailyHoldingCost(
                            vehicle,
                            effectiveSettings,
                            HoldingCostCalculator.getImprovementExpenses(expenses)
                        )

                        val totalCost = VehicleFinancialsCalculator.calculateTotalCost(
                            vehicle,
                            expenses,
                            holdingCost
                        )

                        val totalExpenses = expenses
                            .filter { it.deletedAt == null }
                            .map { it.amount }
                            .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }

                        val expenseBreakdown = VehicleFinancialsCalculator.calculateExpenseBreakdown(expenses)

                        val projectedROI = vehicle.askingPrice?.let { askingPrice ->
                            VehicleFinancialsCalculator.calculateROI(askingPrice, totalCost)
                        }

                        val actualROI = vehicle.salePrice?.let { salePrice ->
                            VehicleFinancialsCalculator.calculateROI(salePrice, totalCost)
                        }

                        val breakEvenPrice = VehicleFinancialsCalculator.calculateBreakEvenPrice(
                            vehicle,
                            expenses,
                            holdingCost
                        )

                        val recommendedPrice = VehicleFinancialsCalculator.calculateRecommendedAskingPrice(
                            vehicle,
                            expenses,
                            holdingCost
                        )

                        val inventoryStats = InventoryMetricsCalculator.calculateInventoryStats(
                            vehicle,
                            expenses,
                            effectiveSettings
                        )

                        val alerts = InventoryMetricsCalculator.generateInventoryAlerts(
                            inventoryStats,
                            vehicle
                        )

                        val financialSummary = VehicleFinancialSummary(
                            purchasePrice = vehicle.purchasePrice,
                            totalExpenses = totalExpenses,
                            holdingCost = holdingCost,
                            totalCost = totalCost,
                            expenseBreakdown = expenseBreakdown,
                            projectedROI = projectedROI,
                            actualROI = actualROI,
                            breakEvenPrice = breakEvenPrice,
                            recommendedPrice = recommendedPrice,
                            dailyHoldingCost = dailyHoldingCost
                        )

                        _detailUiState.update {
                            it.copy(
                                vehicle = vehicle,
                                expenses = expenses,
                                financialSummary = financialSummary,
                                inventoryStats = inventoryStats,
                                alerts = alerts,
                                holdingCostSettings = effectiveSettings,
                                isLoading = false
                            )
                        }

                        _uiState.update { it.copy(selectedVehicle = vehicle) }
                    } else {
                        _detailUiState.update {
                            it.copy(
                                vehicle = null,
                                isLoading = false
                            )
                        }
                        _uiState.update { it.copy(selectedVehicle = null) }
                    }
                }
            } catch (e: Exception) {
                Log.e(tag, "Failed to select vehicle", e)
                _uiState.update { it.copy(selectedVehicle = null) }
                _detailUiState.update { it.copy(vehicle = null, isLoading = false) }
            }
        }
    }

    fun clearSelection() {
        _uiState.update { it.copy(selectedVehicle = null) }
        _detailUiState.update { VehicleDetailUiState() }
    }

    fun refreshFinancialCalculations() {
        val vehicle = _detailUiState.value.vehicle
        if (vehicle != null) {
            selectVehicle(vehicle.id.toString())
        }
    }

    fun updateAskingPrice(newPrice: BigDecimal) {
        viewModelScope.launch {
            val vehicle = _detailUiState.value.vehicle
            if (vehicle != null) {
                val updatedVehicle = vehicle.copy(
                    askingPrice = newPrice,
                    updatedAt = Date()
                )
                vehicleDao.upsert(updatedVehicle)
                cloudSyncManager.upsertVehicle(updatedVehicle)
                refreshFinancialCalculations()
            }
        }
    }

    fun deleteVehicle(id: UUID) {
        viewModelScope.launch {
            val vehicle = vehicleDao.getById(id)
            if (vehicle != null) {
                // Soft delete by setting deletedAt
                val deleted = vehicle.copy(deletedAt = Date(), updatedAt = Date())
                vehicleDao.upsert(deleted)
                // For now, reload list.
                // loadVehicles() removed - updates are automatic
                _uiState.update { it.copy(selectedVehicle = null) }
            }
        }
    }

    fun saveVehicle(
        id: String?,
        vin: String,
        make: String,
        model: String,
        year: Int?,
        purchasePrice: BigDecimal,
        purchaseDate: Date,
        askingPrice: BigDecimal?,
        status: String,
        notes: String,
        salePrice: BigDecimal? = null,
        saleDate: Date? = null,
        buyerName: String? = null,
        buyerPhone: String? = null,
        paymentMethod: String? = null,
        reportURL: String? = null
    ) {
        viewModelScope.launch {
            val now = Date()
            val vehicle = if (id != null) {
                // Update
                val existing = vehicleDao.getById(UUID.fromString(id)) ?: return@launch
                existing.copy(
                    vin = vin,
                    make = make,
                    model = model,
                    year = year,
                    purchasePrice = purchasePrice,
                    purchaseDate = purchaseDate,
                    askingPrice = askingPrice,
                    status = status,
                    notes = notes,
                    salePrice = if (status == "sold") salePrice else null,
                    saleDate = if (status == "sold") saleDate else null,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    reportURL = reportURL,
                    updatedAt = now
                )
            } else {
                // Create
                Vehicle(
                    id = UUID.randomUUID(),
                    vin = vin,
                    make = make,
                    model = model,
                    year = year,
                    purchasePrice = purchasePrice,
                    purchaseDate = purchaseDate,
                    status = status,
                    notes = notes,
                    askingPrice = askingPrice,
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null,
                    saleDate = if (status == "sold") saleDate else null,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    salePrice = if (status == "sold") salePrice else null,
                    reportURL = reportURL
                )
            }
            vehicleDao.upsert(vehicle)
            // loadVehicles() removed - updates are automatic
            
            // Return the vehicle ID so caller can upload image if needed
            vehicle.id
        }
    }
    
    fun uploadVehicleImage(vehicleId: UUID, imageData: ByteArray) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                cloudSyncManager.uploadVehicleImage(vehicleId, dealerId, imageData)
                Log.i(tag, "Uploaded vehicle image for vehicleId=$vehicleId")
            } catch (e: Exception) {
                Log.e(tag, "Failed to upload vehicle image: ${e.message}", e)
            }
        }
    }
}

