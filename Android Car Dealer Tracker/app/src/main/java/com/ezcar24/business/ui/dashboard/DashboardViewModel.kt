package com.ezcar24.business.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.SaleDao
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleInventoryStatsDao
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
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
enum class DashboardTimeRange(val displayLabel: String) {
    ONE_DAY("1D"),
    ONE_WEEK("1W"),
    ONE_MONTH("1M"),
    THREE_MONTHS("3M"),
    SIX_MONTHS("6M"),
    ALL_TIME("All");

    fun getStartDate(): Date {
        val cal = Calendar.getInstance()
        // Reset to end of today effectively for comparisons if needed, 
        // but typically we just want the start point to filter >=
        // For range exclusions we might need more logic, but let's stick to start date for now.
        
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        return when (this) {
            ONE_DAY -> cal.time // Today 00:00
            ONE_WEEK -> {
                cal.add(Calendar.DAY_OF_YEAR, -7)
                cal.time
            }
            ONE_MONTH -> {
                cal.add(Calendar.MONTH, -1)
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
            ALL_TIME -> {
                cal.time = Date(0) // Epoch
                cal.time
            }
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
            
            kotlinx.coroutines.flow.combine(
                vehicleDao.getAllActive(),
                financialAccountDao.getAll(),
                saleDao.getAll(),
                expenseDao.getAll(),
                vehicleInventoryStatsDao.getAllFlow()
            ) { vehicles, accounts, sales, allExpenses, inventoryStats ->
                val selectedRange = _uiState.value.selectedRange
                val rangeStartDate = selectedRange.getStartDate()

                // Filter expenses by selected range
                val filteredExpenses = allExpenses.filter { it.date >= rangeStartDate }
                
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
                    .filter { it.accountType.lowercase() == "cash" }
                    .sumOf { it.balance }
                val totalBank = accounts
                    .filter { it.accountType.lowercase() == "bank" }
                    .sumOf { it.balance }
                
                // Total Assets = Cash + Bank + Vehicle Value (matching iOS)
                val totalAssets = totalCash + totalBank + totalVehicleValue
                
                // Calculate Revenue (Total Sales Income) - ALWAYS ALL TIME (matching iOS)
                val totalRevenue = sales
                    .mapNotNull { it.amount }
                    .fold(BigDecimal.ZERO) { acc, amount -> acc.add(amount) }
                
                // Calculate Net Profit - ALWAYS ALL TIME (matching iOS)
                // Profit = Sum of (sale amount - vehicle cost - vehicle expenses) for each sale
                val netProfit = sales.fold(BigDecimal.ZERO) { acc, sale ->
                    val saleAmount = sale.amount ?: BigDecimal.ZERO
                    val vehicle = sale.vehicleId?.let { vid -> vehicles.find { it.id == vid } }
                    val vehicleCost = vehicle?.purchasePrice ?: BigDecimal.ZERO
                    val vehicleExpenses = vehicle?.let { v ->
                        allExpenses.filter { it.vehicleId == v.id }.sumOf { it.amount }
                    } ?: BigDecimal.ZERO
                    acc.add(saleAmount.subtract(vehicleCost).subtract(vehicleExpenses))
                }
                
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

                // 2. Trend Points (Cumulative with Fill)
                val points = mutableListOf<TrendPoint>()
                var runningTotal = BigDecimal.ZERO
                val cal = Calendar.getInstance()
                
                if (selectedRange == DashboardTimeRange.ONE_DAY) {
                    // Hourly buckets for Today
                    val hourlyTotals = filteredExpenses
                        .groupBy { 
                            cal.time = it.date
                            cal.get(Calendar.HOUR_OF_DAY)
                        }
                        .mapValues { (_, expenses) -> expenses.sumOf { it.amount } }
                    
                    cal.time = rangeStartDate
                    for (hour in 0..23) {
                        val dailySum = hourlyTotals[hour] ?: BigDecimal.ZERO
                        runningTotal = runningTotal.add(dailySum)
                        
                        cal.set(Calendar.HOUR_OF_DAY, hour)
                        cal.set(Calendar.MINUTE, 0)
                        points.add(TrendPoint(cal.time, runningTotal.toFloat()))
                    }
                } else {
                    // Daily buckets for Week/Month
                    val dailyTotals = filteredExpenses
                        .groupBy { 
                            cal.time = it.date
                            cal.set(Calendar.HOUR_OF_DAY, 0)
                            cal.set(Calendar.MINUTE, 0)
                            cal.set(Calendar.SECOND, 0)
                            cal.set(Calendar.MILLISECOND, 0)
                            cal.timeInMillis
                        }
                        .mapValues { (_, expenses) -> expenses.sumOf { it.amount } }
                    
                    cal.time = rangeStartDate
                    // Loop until today/tomorrow
                    val endCal = Calendar.getInstance()
                     // Reset endCal to start of day to avoid partial matches
                    endCal.set(Calendar.HOUR_OF_DAY, 0)
                    endCal.set(Calendar.MINUTE, 0)
                    endCal.set(Calendar.SECOND, 0)
                    endCal.set(Calendar.MILLISECOND, 0)
                    val endDate = endCal.time
                    
                    while (!cal.time.after(endDate)) {
                        // Reset cal to start of day for key matching
                        val currentKey = cal.apply {
                            set(Calendar.HOUR_OF_DAY, 0)
                            set(Calendar.MINUTE, 0)
                            set(Calendar.SECOND, 0)
                            set(Calendar.MILLISECOND, 0)
                        }.timeInMillis
                        
                        val dailySum = dailyTotals[currentKey] ?: BigDecimal.ZERO
                        runningTotal = runningTotal.add(dailySum)
                        
                        points.add(TrendPoint(Date(currentKey), runningTotal.toFloat()))
                        cal.add(Calendar.DAY_OF_YEAR, 1)
                    }
                }
                val trendPoints = points

                // 3. Period Change Percent
                // Calculate previous period expenses
                val (prevStart, prevEnd) = getPreviousPeriod(selectedRange)
                val prevExpenses = allExpenses.filter { it.date >= prevStart && it.date < prevEnd }
                val prevTotal = prevExpenses.sumOf { it.amount }
                
                val periodChangePercent = if (prevTotal > BigDecimal.ZERO) {
                    val diff = totalExpensesInPeriod.subtract(prevTotal)
                    diff.toDouble() / prevTotal.toDouble() * 100.0
                } else if (totalExpensesInPeriod > BigDecimal.ZERO) {
                    100.0 // 0 -> something is 100% increase
                } else {
                    null // 0 -> 0 is no change, or undefined
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
                        totalCash = totalCash,
                        totalBank = totalBank,
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

    private fun getPreviousPeriod(range: DashboardTimeRange): Pair<Date, Date> {
        val cal = Calendar.getInstance()
        val end = range.getStartDate() 
        
        cal.time = end
        when (range) {
            DashboardTimeRange.ONE_DAY -> cal.add(Calendar.DAY_OF_YEAR, -1)
            DashboardTimeRange.ONE_WEEK -> cal.add(Calendar.DAY_OF_YEAR, -7)
            DashboardTimeRange.ONE_MONTH -> cal.add(Calendar.MONTH, -1)
            DashboardTimeRange.THREE_MONTHS -> cal.add(Calendar.MONTH, -3)
            DashboardTimeRange.SIX_MONTHS -> cal.add(Calendar.MONTH, -6)
            DashboardTimeRange.ALL_TIME -> cal.add(Calendar.YEAR, -100) // Arbitrary long time
        }
        val start = cal.time
        return Pair(start, end)
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

data class DashboardUiState(
    val selectedRange: DashboardTimeRange = DashboardTimeRange.ONE_WEEK,
    val organizations: List<OrganizationMembership> = emptyList(),
    val activeOrganization: OrganizationMembership? = null,
    val totalAssets: BigDecimal = BigDecimal.ZERO,
    val totalCash: BigDecimal = BigDecimal.ZERO,
    val totalBank: BigDecimal = BigDecimal.ZERO,
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
