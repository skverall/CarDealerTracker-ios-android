package com.ezcar24.business.ui.expense

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class DateFilter(val label: String) {
    ALL("All"),
    TODAY("Today"),
    WEEK("Week"),
    MONTH("Month")
}

data class ExpenseUiState(
    val expenses: List<Expense> = emptyList(),
    val filteredExpenses: List<Expense> = emptyList(),
    val vehicles: List<Vehicle> = emptyList(),
    val users: List<User> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),
    
    // Filters
    val dateFilter: DateFilter = DateFilter.ALL,
    val selectedCategory: String = "All",
    val selectedVehicle: Vehicle? = null,
    val selectedUser: User? = null,
    val searchQuery: String = "",
    val totalAmount: BigDecimal = BigDecimal.ZERO,
    
    val isLoading: Boolean = false
)

@HiltViewModel
class ExpenseViewModel @Inject constructor(
    private val expenseDao: ExpenseDao,
    private val vehicleDao: VehicleDao,
    private val userDao: UserDao,
    private val financialAccountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "ExpenseViewModel"
    private val _uiState = MutableStateFlow(ExpenseUiState())
    val uiState: StateFlow<ExpenseUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            loadDataInternal()
        }
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
            loadDataInternal()
        }
    }
    
    fun setDateFilter(filter: DateFilter) {
        _uiState.update { it.copy(dateFilter = filter) }
        applyFilters()
    }

    fun setCategoryFilter(category: String) {
        _uiState.update { it.copy(selectedCategory = category) }
        applyFilters()
    }
    
    fun setVehicleFilter(vehicle: Vehicle?) {
        _uiState.update { it.copy(selectedVehicle = vehicle) }
        applyFilters()
    }

    fun setSearchQuery(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFilters()
    }

    private fun applyFilters() {
        val currentState = _uiState.value
        val now = System.currentTimeMillis()
        val dayMillis = 86400000L
        val query = currentState.searchQuery.trim().lowercase()
        
        var result = currentState.expenses
        
        // Date Filter
        result = when (currentState.dateFilter) {
            DateFilter.TODAY -> result.filter { it.date.time > (now - dayMillis) }
            DateFilter.WEEK -> result.filter { it.date.time > (now - (7 * dayMillis)) }
            DateFilter.MONTH -> result.filter { it.date.time > (now - (30 * dayMillis)) }
            DateFilter.ALL -> result
        }
        
        // Category Filter
        if (currentState.selectedCategory != "All") {
            val filterCategory = if (currentState.selectedCategory == "Bills") "office" else currentState.selectedCategory
            result = result.filter { it.category.equals(filterCategory, ignoreCase = true) }
        }
        
        // Vehicle Filter
        currentState.selectedVehicle?.let { vehicle ->
            result = result.filter { it.vehicleId == vehicle.id }
        }

        // Search Filter
        if (query.isNotEmpty()) {
            result = result.filter { expense ->
                (expense.expenseDescription?.lowercase()?.contains(query) == true) ||
                (expense.category.lowercase().contains(query))
            }
        }


        val totalAmount = result.sumOf { it.amount }
        _uiState.update { it.copy(filteredExpenses = result, totalAmount = totalAmount) }
    }

    private fun loadDataInternal() {
        // Collect using combine to wait for all data sources
        viewModelScope.launch {
            kotlinx.coroutines.flow.combine(
                expenseDao.getAll(),
                vehicleDao.getAllActive(),
                userDao.getAllActive(),
                financialAccountDao.getAll()
            ) { expenses, vehicles, users, accounts ->
                _uiState.update { currentState ->
                    currentState.copy(
                        expenses = expenses,
                        vehicles = vehicles,
                        accounts = accounts,
                        users = users,
                        isLoading = false
                    )
                }
                applyFilters()
            }.collect { }
        }
    }

    fun deleteExpense(expense: Expense) {
        viewModelScope.launch {
            cloudSyncManager.deleteExpense(expense)
            // loadData() // Flow updates automatically
        }
    }
    
    fun saveExpense(
        amount: BigDecimal,
        date: Date,
        description: String,
        category: String,
        vehicle: Vehicle?,
        user: User?,
        account: FinancialAccount?
    ) {
        viewModelScope.launch {
            val newExpense = Expense(
                id = UUID.randomUUID(),
                amount = amount,
                date = date,
                expenseDescription = description,
                category = category,
                vehicleId = vehicle?.id,
                userId = user?.id,
                accountId = account?.id,
                createdAt = Date(),
                updatedAt = Date()
            )
            cloudSyncManager.upsertExpense(newExpense)
            // loadData() // Flow updates automatically
        }
    }
}
