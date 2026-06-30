package com.ezcar24.business.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.HoldingCostSettingsDao
import com.ezcar24.business.data.local.PartSaleDao
import com.ezcar24.business.data.local.PartSaleLineItemDao
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.SaleDao
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleInventoryStats
import com.ezcar24.business.data.local.VehicleInventoryStatsDao
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.calculator.DashboardMetricsCalculator
import com.ezcar24.business.util.FinancialAccountKind
import com.ezcar24.business.util.financialAccountKindFor
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Calendar
import java.util.Date
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

// Time range enum matching iOS DashboardTimeRange
// Time range enum matching iOS DashboardTimeRange
enum class DashboardTimeRange(val displayLabel: String, val periodValue: String) {
    ONE_DAY("1D", "today"),
    ONE_WEEK("1W", "week"),
    ONE_MONTH("1M", "month"),
    THREE_MONTHS("3M", "threeMonths"),
    SIX_MONTHS("6M", "sixMonths"),
    ALL_TIME("All", "all");

    fun getStartDate(): Date? {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        return when (this) {
            ONE_DAY -> cal.time
            ONE_WEEK -> {
                cal.add(Calendar.DAY_OF_YEAR, -6)
                cal.time
            }
            ONE_MONTH -> {
                cal.add(Calendar.DAY_OF_YEAR, -30)
                cal.time
            }
            THREE_MONTHS -> {
                cal.add(Calendar.MONTH, -3)
                cal.time
            }
            SIX_MONTHS -> {
                cal.add(Calendar.MONTH, -6)
                cal.time
            }
            ALL_TIME -> null
        }
    }

    fun getEndDate(): Date? {
        val cal = Calendar.getInstance()
        return when (this) {
            ONE_DAY -> {
                cal.set(Calendar.HOUR_OF_DAY, 0)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                cal.add(Calendar.DAY_OF_YEAR, 1)
                cal.time
            }
            ONE_WEEK, ONE_MONTH, THREE_MONTHS, SIX_MONTHS -> Date()
            ALL_TIME -> null
        }
    }
}

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val accountRepository: AccountRepository,
    private val vehicleDao: VehicleDao,
    private val financialAccountDao: FinancialAccountDao,
    private val expenseDao: ExpenseDao,
    private val saleDao: SaleDao,
    private val partSaleDao: PartSaleDao,
    private val partSaleLineItemDao: PartSaleLineItemDao,
    private val holdingCostSettingsDao: HoldingCostSettingsDao,
    private val clientDao: com.ezcar24.business.data.local.ClientDao,
    private val clientInteractionDao: com.ezcar24.business.data.local.ClientInteractionDao,
    private val vehicleInventoryStatsDao: VehicleInventoryStatsDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "DashboardViewModel"
    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()
    private var dataJob: Job? = null

    init {
        observeOrganizationState()
        loadData()
        observeSyncState()
    }

    private fun observeOrganizationState() {
        viewModelScope.launch {
            accountRepository.organizations.collectLatest { organizations ->
                _uiState.update { it.copy(organizations = organizations) }
            }
        }
        viewModelScope.launch {
            accountRepository.activeOrganization.collectLatest { organization ->
                _uiState.update { it.copy(activeOrganization = organization) }
            }
        }
        viewModelScope.launch {
            runCatching { accountRepository.refreshOrganizations() }
                .onFailure { error -> Log.w(tag, "Unable to refresh organizations: ${error.message}", error) }
        }
    }
    
    private fun observeSyncState() {
        viewModelScope.launch {
            cloudSyncManager.syncState.collect { state ->
                _uiState.update { 
                    it.copy(
                        syncState = state,
                        lastSyncTime = cloudSyncManager.lastSyncAt
                    ) 
                }
            }
        }
        viewModelScope.launch {
            cloudSyncManager.queueCount.collect { count ->
                _uiState.update { it.copy(queueCount = count) }
            }
        }
    }
    
    fun triggerSync() {
        viewModelScope.launch {
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.manualSync(dealerId, force = true)
                } catch (e: Exception) {
                    Log.e(tag, "triggerSync failed: ${e.message}", e)
                }
            } else {
                Log.w(tag, "triggerSync skipped: dealerId is null")
            }
            loadData()
        }
    }

    fun onTimeRangeChange(range: DashboardTimeRange) {
        _uiState.update { it.copy(selectedRange = range) }
        loadData()
    }

    fun loadData() {
        dataJob?.cancel()
        dataJob = viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            val coreDataFlow = kotlinx.coroutines.flow.combine(
                vehicleDao.getAllActive(),
                financialAccountDao.getAll(),
                saleDao.getAll(),
                expenseDao.getAll(),
                vehicleInventoryStatsDao.getAllFlow()
            ) { vehicles, accounts, sales, allExpenses, inventoryStats ->
                DashboardCoreData(
                    vehicles = vehicles,
                    accounts = accounts,
                    sales = sales,
                    allExpenses = allExpenses,
                    inventoryStats = inventoryStats
                )
            }

            val partSalesFlow = kotlinx.coroutines.flow.combine(
                partSaleDao.getAllActive(),
                partSaleLineItemDao.getAllActive()
            ) { partSales, partSaleLineItems ->
                partSales to partSaleLineItems
            }

            kotlinx.coroutines.flow.combine(
                coreDataFlow,
                partSalesFlow,
                holdingCostSettingsDao.getSettings()
            ) { coreData, partSaleData, holdingCostSettings ->
                val vehicles = coreData.vehicles
                val accounts = coreData.accounts
                val sales = coreData.sales
                val allExpenses = coreData.allExpenses
                val inventoryStats = coreData.inventoryStats
                val partSales = partSaleData.first
                val partSaleLineItems = partSaleData.second
                val selectedRange = _uiState.value.selectedRange
                val rangeStartDate = selectedRange.getStartDate()
                val rangeEndDate = selectedRange.getEndDate()

                val filteredExpenses = allExpenses.filter { expense ->
                    isInDashboardRange(expense.date, rangeStartDate, rangeEndDate)
                }
                
                // Calculate Vehicle Value - EXCLUDE sold vehicles (matching iOS logic)
                val totalVehicleValue = vehicles
                    .filter { it.status != "sold" }
                    .sumOf { vehicle ->
                        // Use sale price if available, otherwise purchase price + expenses
                        if (vehicle.salePrice != null && vehicle.salePrice > BigDecimal.ZERO) {
                            vehicle.salePrice
                        } else {
                            val vehicleExpenses = allExpenses
                                .filter { it.vehicleId == vehicle.id }
                                .sumOf { it.amount }
                                vehicle.purchasePrice + vehicleExpenses
                        }
                    }
                
                // Calculate account balances
                val totalCash = accounts
                    .filter { financialAccountKindFor(it.accountType) == FinancialAccountKind.CASH }
                    .sumOf { it.balance }
                val totalBank = accounts
                    .filter { financialAccountKindFor(it.accountType) == FinancialAccountKind.BANK }
                    .sumOf { it.balance }
                val totalCredit = accounts
                    .filter { financialAccountKindFor(it.accountType) == FinancialAccountKind.CREDIT_CARD }
                    .sumOf { it.balance }
                
                val totalAssets = totalCash + totalBank + totalVehicleValue
                
                val totalRevenue = DashboardMetricsCalculator.calculateTotalRevenue(
                    sales = sales,
                    partSales = partSales
                )

                val netProfit = DashboardMetricsCalculator.calculateSalesProfit(
                    sales = sales,
                    vehicles = vehicles,
                    allExpenses = allExpenses,
                    partSales = partSales,
                    partSaleLineItems = partSaleLineItems,
                    holdingCostSettings = holdingCostSettings
                )
                
                // Sold count - count vehicles with status="sold" (matching iOS logic)
                val soldCount = vehicles.count { it.status == "sold" }
                
                // Get today's expenses (for Today's Expenses section)
                val todayStart = getTodayStart()
                val tomorrowStart = getTomorrowStart()
                val todaysExpenses = allExpenses.filter { 
                    it.date >= todayStart && it.date < tomorrowStart 
                }
                
                // Get recent expenses (top 4, matching iOS)
                val recentExpenses = allExpenses.take(4)
                val vehicleTitlesById = vehicles.associate { vehicle ->
                    vehicle.id to formatDashboardVehicleTitle(vehicle)
                }
                
                // Calculate total expenses for the period
                val totalExpensesInPeriod = filteredExpenses.sumOf { it.amount }

                // --- New Logic for iOS Parity ---

                // 1. Category Stats
                val categoryStats = filteredExpenses
                    .groupBy { it.category ?: "Other" }
                    .map { (catKey, expenses) ->
                        val sum = expenses.sumOf { it.amount }
                        val percent = if (totalExpensesInPeriod > BigDecimal.ZERO) {
                            sum.toDouble() / totalExpensesInPeriod.toDouble() * 100.0
                        } else 0.0
                        
                        // Simple capitalization for title
                        val title = catKey.replaceFirstChar { if (it.isLowerCase()) it.titlecase(java.util.Locale.getDefault()) else it.toString() }
                        
                        CategoryStat(
                            key = catKey,
                            title = title,
                            amount = sum,
                            percent = percent
                        )
                    }
                    .sortedByDescending { it.amount }

                val trendPoints = buildExpenseTrendPoints(filteredExpenses, selectedRange)

                val previousPeriod = getPreviousPeriod(selectedRange, rangeStartDate, rangeEndDate)
                val prevTotal = previousPeriod?.let { (prevStart, prevEnd) ->
                    allExpenses
                        .filter { it.date >= prevStart && it.date < prevEnd }
                        .sumOf { it.amount }
                } ?: BigDecimal.ZERO
                
                val periodChangePercent = if (prevTotal > BigDecimal.ZERO) {
                    val diff = totalExpensesInPeriod.subtract(prevTotal)
                    diff.toDouble() / prevTotal.toDouble() * 100.0
                } else {
                    null
                }

                // Calculate CRM metrics
                val leadTodayStart = getTodayStart()
                val leadTomorrowStart = getTomorrowStart()
                val allClients = clientDao.getAllIncludingDeleted()
                val allInteractions = mutableListOf<com.ezcar24.business.data.local.ClientInteraction>()
                allClients.forEach { client ->
                    allInteractions.addAll(clientInteractionDao.getByClient(client.id))
                }
                
                // New leads today
                val newLeadsToday = allClients.count { 
                    (it.leadCreatedAt ?: it.createdAt) >= leadTodayStart &&
                    (it.leadCreatedAt ?: it.createdAt) < leadTomorrowStart
                }
                
                // Calls made today
                val callsMadeToday = allInteractions.count {
                    it.occurredAt >= leadTodayStart &&
                    it.occurredAt < leadTomorrowStart &&
                    it.interactionType?.lowercase()?.contains("call") == true
                }
                
                // Pipeline value (active leads only)
                val pipelineValue = com.ezcar24.business.util.calculator.LeadFunnelCalculator.calculatePipelineValue(allClients)
                
                // Conversion rate
                val wonLeads = allClients.count { it.leadStage == com.ezcar24.business.data.local.LeadStage.closed_won }
                val conversionRate = if (allClients.isNotEmpty()) {
                    (wonLeads.toDouble() / allClients.size * 100)
                } else 0.0

                // Calculate inventory summary metrics
                val inventoryVehicles = vehicles.filter { it.status != "sold" }
                val inventoryStatsList = inventoryVehicles.mapNotNull { vehicle ->
                    inventoryStats.find { it.vehicleId == vehicle.id }
                }
                
                val totalVehiclesInInventory = inventoryVehicles.size
                val averageDaysInInventory = if (inventoryStatsList.isNotEmpty()) {
                    inventoryStatsList.sumOf { it.daysInInventory } / inventoryStatsList.size
                } else 0
                val vehiclesOver90Days = inventoryStatsList.count { it.daysInInventory >= 90 }
                val inventoryHealthScore = com.ezcar24.business.util.calculator.InventoryMetricsCalculator.calculateInventoryHealthScore(
                    inventoryVehicles,
                    inventoryStatsList
                )

                _uiState.update { currentState ->
                    currentState.copy(
                        totalAssets = totalAssets,
                        totalVehicleValue = totalVehicleValue,
                        totalCash = totalCash,
                        totalBank = totalBank,
                        totalCredit = totalCredit,
                        totalRevenue = totalRevenue,
                        netProfit = netProfit,
                        soldCount = soldCount,
                        todaysExpenses = todaysExpenses,
                        recentExpenses = recentExpenses,
                        vehicleTitlesById = vehicleTitlesById,
                        totalExpensesInPeriod = totalExpensesInPeriod,
                        categoryStats = categoryStats,
                        trendPoints = trendPoints,
                        periodChangePercent = periodChangePercent,
                        newLeadsToday = newLeadsToday,
                        callsMadeToday = callsMadeToday,
                        pipelineValue = pipelineValue,
                        conversionRate = conversionRate,
                        totalVehiclesInInventory = totalVehiclesInInventory,
                        averageDaysInInventory = averageDaysInInventory,
                        vehiclesOver90Days = vehiclesOver90Days,
                        inventoryHealthScore = inventoryHealthScore,
                        isLoading = false
                    )
                }
            }.collect { }
        }
    }

    fun switchOrganization(organizationId: UUID) {
        if (_uiState.value.isSwitchingOrganization) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSwitchingOrganization = true,
                    statusMessage = null,
                    errorMessage = null
                )
            }
            try {
                val organization = accountRepository.switchOrganization(
                    organizationId = organizationId,
                    forceSync = true
                )
                val organizations = accountRepository.refreshOrganizations()
                _uiState.update {
                    it.copy(
                        organizations = organizations,
                        activeOrganization = organization ?: accountRepository.activeOrganization.value,
                        isSwitchingOrganization = false,
                        statusMessage = organization?.let { active ->
                            "Switched to ${active.organizationName}."
                        }
                    )
                }
                loadData()
            } catch (e: Exception) {
                Log.e(tag, "switchOrganization failed", e)
                _uiState.update {
                    it.copy(
                        isSwitchingOrganization = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.SWITCH_BUSINESS)
                    )
                }
            }
        }
    }

    fun createOrganization(name: String) {
        if (_uiState.value.isSwitchingOrganization) return
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isSwitchingOrganization = true,
                    statusMessage = null,
                    errorMessage = null
                )
            }
            try {
                val organization = accountRepository.createOrganization(name)
                _uiState.update {
                    it.copy(
                        organizations = accountRepository.organizations.value,
                        activeOrganization = organization,
                        isSwitchingOrganization = false,
                        statusMessage = "Created ${organization.organizationName}."
                    )
                }
                loadData()
            } catch (e: Exception) {
                Log.e(tag, "createOrganization failed", e)
                _uiState.update {
                    it.copy(
                        isSwitchingOrganization = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.CREATE_BUSINESS)
                    )
                }
            }
        }
    }

    fun clearStatusMessage() {
        _uiState.update { it.copy(statusMessage = null) }
    }

    fun clearErrorMessage() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    private fun getTodayStart(): Date {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.time
    }

    private fun getTomorrowStart(): Date {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.time
    }

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
            loadData()
        }
    }

    private fun isInDashboardRange(date: Date, start: Date?, end: Date?): Boolean {
        return (start == null || date >= start) && (end == null || date < end)
    }

    private fun getPreviousPeriod(range: DashboardTimeRange, currentStart: Date?, currentEnd: Date?): Pair<Date, Date>? {
        if (range == DashboardTimeRange.ALL_TIME || currentStart == null) return null
        val end = currentEnd ?: Date()
        val lengthMs = (end.time - currentStart.time).coerceAtLeast(0L)
        return Pair(Date(currentStart.time - lengthMs), currentStart)
    }

    private fun startOfDay(date: Date): Date {
        val cal = Calendar.getInstance()
        cal.time = date
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.time
    }

    private fun startOfMonth(date: Date): Date {
        val cal = Calendar.getInstance()
        cal.time = date
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.time
    }

    private fun alignedWeekStart(date: Date): Date {
        val cal = Calendar.getInstance()
        cal.time = startOfDay(date)
        val daysToSubtract = (cal.get(Calendar.DAY_OF_WEEK) - cal.firstDayOfWeek + 7) % 7
        cal.add(Calendar.DAY_OF_YEAR, -daysToSubtract)
        return cal.time
    }

    private fun trimTrailingZeroDeltas(points: List<Pair<TrendPoint, BigDecimal>>): List<TrendPoint> {
        val lastNonZero = points.indexOfLast { it.second.compareTo(BigDecimal.ZERO) != 0 }
        if (lastNonZero < 0) return emptyList()
        return points.take(lastNonZero + 1).map { it.first }
    }

    private fun buildExpenseTrendPoints(expenses: List<Expense>, range: DashboardTimeRange): List<TrendPoint> {
        if (expenses.isEmpty()) return emptyList()

        val cal = Calendar.getInstance()
        var runningTotal = BigDecimal.ZERO
        val points = mutableListOf<Pair<TrendPoint, BigDecimal>>()

        when (range) {
            DashboardTimeRange.ONE_DAY -> {
                val today = startOfDay(Date())
                val buckets = expenses
                    .filter { it.date >= today }
                    .groupBy {
                        cal.time = it.createdAt
                        cal.get(Calendar.HOUR_OF_DAY)
                    }
                    .mapValues { (_, items) -> items.sumOf { it.amount } }

                for (hour in 0..23) {
                    cal.time = today
                    cal.set(Calendar.HOUR_OF_DAY, hour)
                    val delta = buckets[hour] ?: BigDecimal.ZERO
                    runningTotal = runningTotal.add(delta)
                    points.add(TrendPoint(cal.time, runningTotal.toFloat()) to delta)
                }
            }
            DashboardTimeRange.ONE_WEEK -> {
                val today = startOfDay(Date())
                cal.time = today
                cal.add(Calendar.DAY_OF_YEAR, -6)
                val start = cal.time
                val buckets = expenses
                    .filter { it.date >= start }
                    .groupBy { startOfDay(it.date).time }
                    .mapValues { (_, items) -> items.sumOf { it.amount } }

                for (day in 0..6) {
                    cal.time = start
                    cal.add(Calendar.DAY_OF_YEAR, day)
                    val key = cal.time.time
                    val delta = buckets[key] ?: BigDecimal.ZERO
                    runningTotal = runningTotal.add(delta)
                    points.add(TrendPoint(Date(key), runningTotal.toFloat()) to delta)
                }
            }
            DashboardTimeRange.ONE_MONTH -> {
                val today = startOfDay(Date())
                cal.time = today
                cal.add(Calendar.DAY_OF_YEAR, -29)
                val start = cal.time
                val buckets = expenses
                    .filter { it.date >= start }
                    .groupBy { startOfDay(it.date).time }
                    .mapValues { (_, items) -> items.sumOf { it.amount } }

                for (day in 0..29) {
                    cal.time = start
                    cal.add(Calendar.DAY_OF_YEAR, day)
                    val key = cal.time.time
                    val delta = buckets[key] ?: BigDecimal.ZERO
                    runningTotal = runningTotal.add(delta)
                    points.add(TrendPoint(Date(key), runningTotal.toFloat()) to delta)
                }
            }
            DashboardTimeRange.THREE_MONTHS,
            DashboardTimeRange.SIX_MONTHS -> {
                val today = startOfDay(Date())
                cal.time = today
                cal.add(Calendar.MONTH, if (range == DashboardTimeRange.THREE_MONTHS) -3 else -6)
                val start = alignedWeekStart(cal.time)
                val buckets = expenses
                    .filter { it.date >= start }
                    .groupBy { alignedWeekStart(it.date).time }
                    .mapValues { (_, items) -> items.sumOf { it.amount } }

                cal.time = start
                while (!cal.time.after(today)) {
                    val key = cal.time.time
                    val delta = buckets[key] ?: BigDecimal.ZERO
                    runningTotal = runningTotal.add(delta)
                    points.add(TrendPoint(Date(key), runningTotal.toFloat()) to delta)
                    cal.add(Calendar.WEEK_OF_YEAR, 1)
                }
            }
            DashboardTimeRange.ALL_TIME -> {
                val today = startOfDay(Date())
                cal.time = today
                cal.add(Calendar.MONTH, -11)
                val start = startOfMonth(cal.time)
                val buckets = expenses
                    .filter { it.date >= start }
                    .groupBy { startOfMonth(it.date).time }
                    .mapValues { (_, items) -> items.sumOf { it.amount } }

                for (month in 0..11) {
                    cal.time = start
                    cal.add(Calendar.MONTH, month)
                    val key = cal.time.time
                    val delta = buckets[key] ?: BigDecimal.ZERO
                    runningTotal = runningTotal.add(delta)
                    points.add(TrendPoint(Date(key), runningTotal.toFloat()) to delta)
                }
            }
        }

        return trimTrailingZeroDeltas(points)
    }
}

private fun formatDashboardVehicleTitle(vehicle: Vehicle): String {
    val title = listOfNotNull(
        vehicle.year?.toString(),
        vehicle.make?.takeIf { it.isNullOrBlank().not() },
        vehicle.model?.takeIf { it.isNullOrBlank().not() }
    ).joinToString(" ")

    return title.ifBlank { vehicle.vin }
}

private data class DashboardCoreData(
    val vehicles: List<Vehicle>,
    val accounts: List<com.ezcar24.business.data.local.FinancialAccount>,
    val sales: List<Sale>,
    val allExpenses: List<Expense>,
    val inventoryStats: List<VehicleInventoryStats>
)

data class DashboardUiState(
    val selectedRange: DashboardTimeRange = DashboardTimeRange.ONE_WEEK,
    val organizations: List<OrganizationMembership> = emptyList(),
    val activeOrganization: OrganizationMembership? = null,
    val totalAssets: BigDecimal = BigDecimal.ZERO,
    val totalVehicleValue: BigDecimal = BigDecimal.ZERO,
    val totalCash: BigDecimal = BigDecimal.ZERO,
    val totalBank: BigDecimal = BigDecimal.ZERO,
    val totalCredit: BigDecimal = BigDecimal.ZERO,
    val totalRevenue: BigDecimal = BigDecimal.ZERO,
    val netProfit: BigDecimal = BigDecimal.ZERO,
    val soldCount: Int = 0,
    val todaysExpenses: List<Expense> = emptyList(),
    val recentExpenses: List<Expense> = emptyList(),
    val vehicleTitlesById: Map<UUID, String> = emptyMap(),
    val totalExpensesInPeriod: BigDecimal = BigDecimal.ZERO,
    val categoryStats: List<CategoryStat> = emptyList(),
    val trendPoints: List<TrendPoint> = emptyList(),
    val periodChangePercent: Double? = null,
    val isLoading: Boolean = true,
    // CRM fields
    val newLeadsToday: Int = 0,
    val callsMadeToday: Int = 0,
    val pipelineValue: BigDecimal = BigDecimal.ZERO,
    val conversionRate: Double = 0.0,
    // Sync state fields
    val syncState: com.ezcar24.business.data.sync.SyncState = com.ezcar24.business.data.sync.SyncState.Idle,
    val lastSyncTime: Date? = null,
    val queueCount: Int = 0,
    val isSwitchingOrganization: Boolean = false,
    val statusMessage: String? = null,
    val errorMessage: String? = null,
    // Inventory summary fields
    val totalVehiclesInInventory: Int = 0,
    val averageDaysInInventory: Int = 0,
    val vehiclesOver90Days: Int = 0,
    val inventoryHealthScore: Int = 100
)

data class CategoryStat(
    val key: String,
    val title: String,
    val amount: BigDecimal,
    val percent: Double
)

data class TrendPoint(
    val date: Date,
    val value: Float
)
