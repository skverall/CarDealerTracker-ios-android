package com.ezcar24.business.ui.vehicle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientDao
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
import com.ezcar24.business.data.local.VehicleInventoryStatsDao
import com.ezcar24.business.data.local.InventoryAlert
import com.ezcar24.business.data.local.InventoryAlertDao
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.SaleDao
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
import kotlinx.coroutines.flow.first
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

data class VehiclePhotoItem(
    val id: String,
    val url: String,
    val sortOrder: Int,
    val storagePath: String
)

data class VehicleDetailUiState(
    val vehicle: Vehicle? = null,
    val sale: Sale? = null,
    val saleAccount: FinancialAccount? = null,
    val expenses: List<Expense> = emptyList(),
    val financialSummary: VehicleFinancialSummary = VehicleFinancialSummary(),
    val inventoryStats: VehicleInventoryStats? = null,
    val alerts: List<InventoryAlert> = emptyList(),
    val holdingCostSettings: HoldingCostSettings? = null,
    val photoUrls: List<String> = emptyList(),
    val photoItems: List<VehiclePhotoItem> = emptyList(),
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
    private val saleDao: SaleDao,
    private val clientDao: ClientDao,
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

    suspend fun completeQuickSale(
        vehicleId: UUID,
        salePrice: BigDecimal,
        saleDate: Date,
        buyerName: String,
        buyerPhone: String,
        paymentMethod: String,
        accountId: UUID
    ): Result<Unit> = runCatching {
        require(salePrice > BigDecimal.ZERO) { "Sale price must be greater than zero." }

        val normalizedBuyerName = buyerName.trim().takeIf { it.isNotEmpty() }
            ?: error("Buyer name is required.")
        val normalizedBuyerPhone = buyerPhone.trim().takeIf { it.isNotEmpty() }
        val normalizedPaymentMethod = paymentMethod.trim().takeIf { it.isNotEmpty() } ?: "Cash"

        val vehicle = vehicleDao.getById(vehicleId) ?: error("Vehicle not found.")
        val account = financialAccountDao.getById(accountId) ?: error("Financial account not found.")
        val now = Date()

        val sale = Sale(
            id = UUID.randomUUID(),
            amount = salePrice,
            date = saleDate,
            buyerName = normalizedBuyerName,
            buyerPhone = normalizedBuyerPhone,
            paymentMethod = normalizedPaymentMethod,
            createdAt = now,
            updatedAt = now,
            vehicleId = vehicle.id,
            accountId = account.id
        )
        val updatedVehicle = vehicle.copy(
            status = "sold",
            salePrice = salePrice,
            saleDate = saleDate,
            buyerName = normalizedBuyerName,
            buyerPhone = normalizedBuyerPhone,
            paymentMethod = normalizedPaymentMethod,
            updatedAt = now
        )
        val updatedAccount = account.copy(
            balance = account.balance.add(salePrice),
            updatedAt = now
        )
        val client = Client(
            id = UUID.randomUUID(),
            name = normalizedBuyerName,
            phone = normalizedBuyerPhone,
            email = null,
            notes = buildClientPurchaseNote(vehicle),
            requestDetails = null,
            preferredDate = null,
            status = "purchased",
            createdAt = now,
            updatedAt = now,
            vehicleId = vehicle.id,
            leadStage = LeadStage.closed_won,
            leadCreatedAt = now,
            lastContactAt = now
        )

        cloudSyncManager.upsertSale(sale)
        cloudSyncManager.upsertVehicle(updatedVehicle)
        cloudSyncManager.upsertFinancialAccount(updatedAccount)
        cloudSyncManager.upsertClient(client)
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
                vehicleInventoryStatsDao.getAllFlow()
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
                        val sale = saleDao.getByVehicleId(vehicle.id)
                        val saleAccount = sale?.accountId?.let { financialAccountDao.getById(it) }
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
                                sale = sale,
                                saleAccount = saleAccount,
                                expenses = expenses,
                                financialSummary = financialSummary,
                                inventoryStats = inventoryStats,
                                alerts = alerts,
                                holdingCostSettings = effectiveSettings,
                                isLoading = false
                            )
                        }

                        _uiState.update { it.copy(selectedVehicle = vehicle) }
                        loadVehiclePhotos(vehicle.id)
                    } else {
                        _detailUiState.update {
                            it.copy(
                                vehicle = null,
                                sale = null,
                                saleAccount = null,
                                photoUrls = emptyList(),
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

    private fun loadVehiclePhotos(vehicleId: UUID) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            val photos = cloudSyncManager.fetchVehiclePhotos(dealerId, vehicleId)
            val items = photos.map {
                VehiclePhotoItem(
                    id = it.id,
                    url = CloudSyncEnvironment.vehiclePhotoUrl(it.storagePath),
                    sortOrder = it.sortOrder,
                    storagePath = it.storagePath
                )
            }
            _detailUiState.update { it.copy(photoUrls = items.map { item -> item.url }, photoItems = items) }
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

    suspend fun createVehicleShareLink(vehicleId: UUID): String? {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return null
        return cloudSyncManager.createVehicleShareLink(
            vehicleId = vehicleId,
            dealerId = dealerId,
            contactPhone = null,
            contactWhatsApp = null
        )
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

    suspend fun saveVehicle(
        id: String?,
        vin: String,
        make: String,
        model: String,
        year: Int?,
        mileage: Int,
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
        reportURL: String? = null,
        saleAccountId: UUID? = null
    ): Result<UUID> = runCatching {
        val now = Date()
        val normalizedNotes = notes.trim().takeIf { it.isNotEmpty() }
        val normalizedBuyerName = buyerName?.trim()?.takeIf { it.isNotEmpty() }
        val normalizedBuyerPhone = buyerPhone?.trim()?.takeIf { it.isNotEmpty() }
        val normalizedPaymentMethod = paymentMethod?.trim()?.takeIf { it.isNotEmpty() }
        val normalizedReportUrl = reportURL?.trim()?.takeIf { it.isNotEmpty() }
        val vehicleId = id?.let(UUID::fromString) ?: UUID.randomUUID()
        val existingVehicle = id?.let { vehicleDao.getById(vehicleId) }
        if (id != null && existingVehicle == null) {
            error("Vehicle not found.")
        }
        val existingSale = saleDao.getByVehicleId(vehicleId)
        val existingClient = clientDao.getByVehicleId(vehicleId)
        val previousSaleAmount = existingSale?.amount ?: BigDecimal.ZERO
        val previousSaleAccount = existingSale?.accountId?.let { financialAccountDao.getById(it) }

        val vehicle = if (existingVehicle != null) {
            existingVehicle.copy(
                vin = vin,
                make = make,
                model = model,
                year = year,
                mileage = mileage,
                purchasePrice = purchasePrice,
                purchaseDate = purchaseDate,
                askingPrice = askingPrice,
                status = status,
                notes = normalizedNotes,
                salePrice = if (status == "sold") salePrice else null,
                saleDate = if (status == "sold") saleDate else null,
                buyerName = if (status == "sold") normalizedBuyerName else null,
                buyerPhone = if (status == "sold") normalizedBuyerPhone else null,
                paymentMethod = if (status == "sold") normalizedPaymentMethod else null,
                reportURL = normalizedReportUrl,
                updatedAt = now
            )
        } else {
            Vehicle(
                id = vehicleId,
                vin = vin,
                make = make,
                model = model,
                year = year,
                mileage = mileage,
                purchasePrice = purchasePrice,
                purchaseDate = purchaseDate,
                status = status,
                notes = normalizedNotes,
                askingPrice = askingPrice,
                createdAt = now,
                updatedAt = now,
                deletedAt = null,
                saleDate = if (status == "sold") saleDate else null,
                buyerName = if (status == "sold") normalizedBuyerName else null,
                buyerPhone = if (status == "sold") normalizedBuyerPhone else null,
                paymentMethod = if (status == "sold") normalizedPaymentMethod else null,
                salePrice = if (status == "sold") salePrice else null,
                reportURL = normalizedReportUrl
            )
        }

        cloudSyncManager.upsertVehicle(vehicle)

        if (status == "sold") {
            val normalizedSalePrice = salePrice?.takeIf { it > BigDecimal.ZERO }
                ?: error("Sale price is required.")
            val normalizedSaleDate = saleDate ?: error("Sale date is required.")
            val targetAccount = saleAccountId?.let { financialAccountDao.getById(it) }
                ?: previousSaleAccount
                ?: defaultSaleAccount()
                ?: error("A financial account is required for sold vehicles.")

            val sale = existingSale?.copy(
                amount = normalizedSalePrice,
                date = normalizedSaleDate,
                buyerName = normalizedBuyerName,
                buyerPhone = normalizedBuyerPhone,
                paymentMethod = normalizedPaymentMethod,
                updatedAt = now,
                deletedAt = null,
                vehicleId = vehicle.id,
                accountId = targetAccount.id
            ) ?: Sale(
                id = UUID.randomUUID(),
                amount = normalizedSalePrice,
                date = normalizedSaleDate,
                buyerName = normalizedBuyerName,
                buyerPhone = normalizedBuyerPhone,
                paymentMethod = normalizedPaymentMethod,
                createdAt = now,
                updatedAt = now,
                deletedAt = null,
                vehicleId = vehicle.id,
                accountId = targetAccount.id
            )

            when {
                existingSale == null -> {
                    cloudSyncManager.upsertFinancialAccount(
                        targetAccount.copy(
                            balance = targetAccount.balance.add(normalizedSalePrice),
                            updatedAt = now
                        )
                    )
                }
                previousSaleAccount?.id == targetAccount.id -> {
                    val delta = normalizedSalePrice.subtract(previousSaleAmount)
                    if (delta.compareTo(BigDecimal.ZERO) != 0) {
                        cloudSyncManager.upsertFinancialAccount(
                            targetAccount.copy(
                                balance = targetAccount.balance.add(delta),
                                updatedAt = now
                            )
                        )
                    }
                }
                else -> {
                    previousSaleAccount?.let { previousAccount ->
                        if (previousSaleAmount.compareTo(BigDecimal.ZERO) != 0) {
                            cloudSyncManager.upsertFinancialAccount(
                                previousAccount.copy(
                                    balance = previousAccount.balance.subtract(previousSaleAmount),
                                    updatedAt = now
                                )
                            )
                        }
                    }
                    cloudSyncManager.upsertFinancialAccount(
                        targetAccount.copy(
                            balance = targetAccount.balance.add(normalizedSalePrice),
                            updatedAt = now
                        )
                    )
                }
            }

            cloudSyncManager.upsertSale(sale)

            val clientName = normalizedBuyerName ?: existingClient?.name
            if (clientName != null) {
                val client = existingClient?.copy(
                    name = clientName,
                    phone = normalizedBuyerPhone,
                    notes = buildClientPurchaseNote(vehicle),
                    status = "purchased",
                    updatedAt = now,
                    vehicleId = vehicle.id,
                    leadStage = LeadStage.closed_won,
                    lastContactAt = now
                ) ?: Client(
                    id = UUID.randomUUID(),
                    name = clientName,
                    phone = normalizedBuyerPhone,
                    email = null,
                    notes = buildClientPurchaseNote(vehicle),
                    requestDetails = null,
                    preferredDate = null,
                    status = "purchased",
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null,
                    vehicleId = vehicle.id,
                    leadStage = LeadStage.closed_won,
                    leadCreatedAt = now,
                    lastContactAt = now
                )
                cloudSyncManager.upsertClient(client)
            }
        } else if (existingSale != null) {
            previousSaleAccount?.let { previousAccount ->
                if (previousSaleAmount.compareTo(BigDecimal.ZERO) != 0) {
                    cloudSyncManager.upsertFinancialAccount(
                        previousAccount.copy(
                            balance = previousAccount.balance.subtract(previousSaleAmount),
                            updatedAt = now
                        )
                    )
                }
            }
            cloudSyncManager.deleteSale(existingSale)
        }

        vehicle.id
    }

    private suspend fun defaultSaleAccount(): FinancialAccount? {
        val accounts = financialAccountDao.getAll().first()
        return accounts.firstOrNull { it.accountType.equals("cash", ignoreCase = true) }
            ?: accounts.firstOrNull { it.accountType.equals("bank", ignoreCase = true) }
            ?: accounts.firstOrNull()
    }

    private fun buildClientPurchaseNote(vehicle: Vehicle): String {
        val title = listOfNotNull(vehicle.year?.toString(), vehicle.make, vehicle.model)
            .joinToString(" ")
            .ifBlank { vehicle.vin }
        return "Purchased $title"
    }
    
    fun uploadVehicleImage(vehicleId: UUID, imageData: ByteArray) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                val existing = cloudSyncManager.fetchVehiclePhotos(dealerId, vehicleId)
                val sortOrder = existing.size
                val makePrimary = existing.isEmpty()
                cloudSyncManager.uploadVehiclePhoto(vehicleId, dealerId, imageData, makePrimary, sortOrder)
                Log.i(tag, "Uploaded vehicle photo for vehicleId=$vehicleId")
                loadVehiclePhotos(vehicleId)
            } catch (e: Exception) {
                Log.e(tag, "Failed to upload vehicle image: ${e.message}", e)
            }
        }
    }

    fun uploadVehicleImages(vehicleId: UUID, images: List<ByteArray>, replaceCover: Boolean) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        if (images.isEmpty()) return
        viewModelScope.launch {
            try {
                val existing = cloudSyncManager.fetchVehiclePhotos(dealerId, vehicleId)
                var sortOrder = existing.size
                val shouldSetCover = replaceCover || existing.isEmpty()
                var first = true
                for (data in images) {
                    cloudSyncManager.uploadVehiclePhoto(
                        vehicleId = vehicleId,
                        dealerId = dealerId,
                        imageData = data,
                        makePrimary = shouldSetCover && first,
                        sortOrder = sortOrder
                    )
                    sortOrder += 1
                    first = false
                }
                loadVehiclePhotos(vehicleId)
            } catch (e: Exception) {
                Log.e(tag, "Failed to upload vehicle images: ${e.message}", e)
            }
        }
    }

    fun deleteVehiclePhoto(vehicleId: UUID, photo: VehiclePhotoItem) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                cloudSyncManager.deleteVehiclePhoto(photoId = photo.id, dealerId = dealerId, storagePath = photo.storagePath)
                loadVehiclePhotos(vehicleId)
            } catch (e: Exception) {
                Log.e(tag, "Failed to delete vehicle photo: ${e.message}", e)
            }
        }
    }

    fun setCoverPhoto(vehicleId: UUID, photo: VehiclePhotoItem) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                cloudSyncManager.setVehiclePhotoAsCover(dealerId = dealerId, storagePath = photo.storagePath, vehicleId = vehicleId)
            } catch (e: Exception) {
                Log.e(tag, "Failed to set cover photo: ${e.message}", e)
            }
        }
    }

    fun updateVehiclePhotoOrder(vehicleId: UUID, ordered: List<VehiclePhotoItem>) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                ordered.forEachIndexed { index, photo ->
                    cloudSyncManager.updateVehiclePhotoOrder(photoId = photo.id, dealerId = dealerId, sortOrder = index)
                }
                loadVehiclePhotos(vehicleId)
            } catch (e: Exception) {
                Log.e(tag, "Failed to update vehicle photo order: ${e.message}", e)
            }
        }
    }

    fun deleteVehicleCover(vehicleId: UUID) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            cloudSyncManager.deleteVehicleImage(vehicleId, dealerId)
        }
    }
}
