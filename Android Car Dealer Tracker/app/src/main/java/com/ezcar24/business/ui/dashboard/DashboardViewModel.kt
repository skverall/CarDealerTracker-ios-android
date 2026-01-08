package com.ezcar24.business.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.SaleDao
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Calendar
import java.util.Date
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
    private val vehicleDao: VehicleDao,
    private val financialAccountDao: FinancialAccountDao,
    private val expenseDao: ExpenseDao,
    private val saleDao: SaleDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "DashboardViewModel"
    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    init {
        loadData()
        observeSyncState()
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
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            kotlinx.coroutines.flow.combine(
                vehicleDao.getAllActive(),
                financialAccountDao.getAll(),
                saleDao.getAll(),
                expenseDao.getAll()
            ) { vehicles, accounts, sales, allExpenses ->
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
                        totalExpensesInPeriod = totalExpensesInPeriod,
                        categoryStats = categoryStats,
                        trendPoints = trendPoints,
                        periodChangePercent = periodChangePercent,
                        isLoading = false
                    )
                }
            }.collect { }
        }
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

data class DashboardUiState(
    val selectedRange: DashboardTimeRange = DashboardTimeRange.ONE_WEEK,
    val totalAssets: BigDecimal = BigDecimal.ZERO,
    val totalCash: BigDecimal = BigDecimal.ZERO,
    val totalBank: BigDecimal = BigDecimal.ZERO,
    val totalRevenue: BigDecimal = BigDecimal.ZERO,
    val netProfit: BigDecimal = BigDecimal.ZERO,
    val soldCount: Int = 0,
    val todaysExpenses: List<Expense> = emptyList(),
    val recentExpenses: List<Expense> = emptyList(),
    val totalExpensesInPeriod: BigDecimal = BigDecimal.ZERO,
    val categoryStats: List<CategoryStat> = emptyList(),
    val trendPoints: List<TrendPoint> = emptyList(),
    val periodChangePercent: Double? = null,
    val isLoading: Boolean = true,
    // Sync state fields
    val syncState: com.ezcar24.business.data.sync.SyncState = com.ezcar24.business.data.sync.SyncState.Idle,
    val lastSyncTime: Date? = null,
    val queueCount: Int = 0
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
