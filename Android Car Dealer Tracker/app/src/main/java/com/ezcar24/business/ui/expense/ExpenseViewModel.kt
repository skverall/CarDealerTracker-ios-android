package com.ezcar24.business.ui.expense

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import android.widget.Toast
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.openExpenseReceipt as openExpenseReceiptFile
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Job
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
    val templates: List<ExpenseTemplate> = emptyList(),
    val vehicles: List<Vehicle> = emptyList(),
    val users: List<User> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),

    // Filters
    val dateFilter: DateFilter = DateFilter.ALL,
    val selectedCategory: String = "All",
    val selectedExpenseType: ExpenseCategoryType? = null,
    val selectedVehicle: Vehicle? = null,
    val selectedUser: User? = null,
    val searchQuery: String = "",
    val totalAmount: BigDecimal = BigDecimal.ZERO,

    // Summary
    val expenseTypeBreakdown: Map<ExpenseCategoryType, BigDecimal> = emptyMap(),

    val isLoading: Boolean = false
)

@HiltViewModel
class ExpenseViewModel @Inject constructor(
    private val expenseDao: ExpenseDao,
    private val expenseTemplateDao: ExpenseTemplateDao,
    private val vehicleDao: VehicleDao,
    private val userDao: UserDao,
    private val financialAccountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "ExpenseViewModel"
    private val _uiState = MutableStateFlow(ExpenseUiState())
    val uiState: StateFlow<ExpenseUiState> = _uiState.asStateFlow()
    private var dataJob: Job? = null

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

    fun setExpenseTypeFilter(expenseType: ExpenseCategoryType?) {
        _uiState.update { it.copy(selectedExpenseType = expenseType) }
        applyFilters()
    }
    
    fun setVehicleFilter(vehicle: Vehicle?) {
        _uiState.update { it.copy(selectedVehicle = vehicle) }
        applyFilters()
    }

    fun setUserFilter(user: User?) {
        _uiState.update { it.copy(selectedUser = user) }
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

        // Expense Type Filter
        currentState.selectedExpenseType?.let { expenseType ->
            result = result.filter { it.expenseType == expenseType }
        }

        // Vehicle Filter
        currentState.selectedVehicle?.let { vehicle ->
            result = result.filter { it.vehicleId == vehicle.id }
        }

        currentState.selectedUser?.let { user ->
            result = result.filter { it.userId == user.id }
        }

        // Search Filter
        if (query.isNotEmpty()) {
            result = result.filter { expense ->
                (expense.expenseDescription?.lowercase()?.contains(query) == true) ||
                (expense.category.lowercase().contains(query))
            }
        }

        // Calculate breakdown by expense type
        val expenseTypeBreakdown = result
            .groupBy { it.expenseType }
            .mapValues { (_, expenses) ->
                expenses.sumOf { it.amount }
            }

        val totalAmount = result.sumOf { it.amount }
        _uiState.update {
            it.copy(
                filteredExpenses = result,
                totalAmount = totalAmount,
                expenseTypeBreakdown = expenseTypeBreakdown
            )
        }
    }

    private fun loadDataInternal() {
        dataJob?.cancel()
        dataJob = viewModelScope.launch {
            kotlinx.coroutines.flow.combine(
                expenseDao.getAll(),
                expenseTemplateDao.getAllActive(),
                vehicleDao.getAllActive(),
                userDao.getAllActive(),
                financialAccountDao.getAll()
            ) { expenses, templates, vehicles, users, accounts ->
                _uiState.update { currentState ->
                    currentState.copy(
                        expenses = expenses,
                        templates = templates,
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

    fun updateExpenseComment(expense: Expense, comment: String) {
        viewModelScope.launch {
            val normalizedComment = comment.trim().takeIf { it.isNotEmpty() }
            val currentComment = expense.expenseDescription?.trim()?.takeIf { it.isNotEmpty() }
            if (normalizedComment == currentComment) return@launch

            cloudSyncManager.upsertExpense(
                expense.copy(
                    expenseDescription = normalizedComment,
                    updatedAt = Date()
                )
            )
        }
    }

    fun saveTemplate(
        name: String,
        category: String,
        defaultAmount: BigDecimal?,
        defaultDescription: String?,
        vehicle: Vehicle?,
        user: User?,
        account: FinancialAccount?
    ) {
        viewModelScope.launch {
            val templateName = name.trim().takeIf { it.isNotEmpty() } ?: "Template"
            val now = Date()
            val template = ExpenseTemplate(
                id = UUID.randomUUID(),
                name = templateName,
                category = category.trim().takeIf { it.isNotEmpty() },
                defaultDescription = defaultDescription?.trim()?.takeIf { it.isNotEmpty() },
                defaultAmount = defaultAmount,
                updatedAt = now,
                vehicleId = vehicle?.id,
                userId = user?.id,
                accountId = account?.id
            )
            cloudSyncManager.upsertTemplate(template)
        }
    }
    
    fun saveExpense(
        amount: BigDecimal,
        date: Date,
        description: String,
        category: String,
        vehicle: Vehicle?,
        user: User?,
        account: FinancialAccount?,
        expenseType: ExpenseCategoryType = ExpenseCategoryType.OPERATIONAL,
        receipt: ExpenseReceiptDraft? = null
    ) {
        viewModelScope.launch {
            val now = Date()
            val newExpense = Expense(
                id = UUID.randomUUID(),
                amount = amount,
                date = date,
                expenseDescription = description,
                category = category,
                vehicleId = vehicle?.id,
                userId = user?.id,
                accountId = account?.id,
                expenseType = expenseType,
                createdAt = now,
                updatedAt = now
            )
            cloudSyncManager.upsertExpense(newExpense)

            if (receipt != null) {
                val dealerId = CloudSyncEnvironment.currentDealerId
                if (dealerId != null) {
                    val path = cloudSyncManager.uploadExpenseReceipt(
                        expenseId = newExpense.id,
                        dealerId = dealerId,
                        data = receipt.bytes,
                        contentType = receipt.contentType,
                        fileExtension = receipt.fileExtension
                    )
                    if (path != null) {
                        cloudSyncManager.upsertExpense(
                            newExpense.copy(
                                receiptPath = path,
                                updatedAt = Date()
                            )
                        )
                    }
                }
            }
        }
    }

    fun openExpenseReceipt(context: Context, expense: Expense) {
        val path = expense.receiptPath ?: return
        viewModelScope.launch {
            val data = cloudSyncManager.downloadExpenseReceipt(path)
            if (data == null) {
                Toast.makeText(context, "Could not open receipt", Toast.LENGTH_SHORT).show()
                return@launch
            }

            val opened = openExpenseReceiptFile(
                context = context,
                fileName = path.substringAfterLast('/'),
                bytes = data
            )
            if (!opened) {
                Toast.makeText(context, "Could not open receipt", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun replaceExpenseReceipt(
        expense: Expense,
        receipt: ExpenseReceiptDraft,
        onComplete: (Expense) -> Unit = {}
    ) {
        viewModelScope.launch {
            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId == null) {
                Log.w(tag, "replaceExpenseReceipt skipped: dealerId is null")
                return@launch
            }

            val newPath = cloudSyncManager.uploadExpenseReceipt(
                expenseId = expense.id,
                dealerId = dealerId,
                data = receipt.bytes,
                contentType = receipt.contentType,
                fileExtension = receipt.fileExtension
            ) ?: run {
                Log.e(tag, "replaceExpenseReceipt failed: upload returned null for expenseId=${expense.id}")
                return@launch
            }

            val updatedExpense = expense.copy(
                receiptPath = newPath,
                updatedAt = Date()
            )
            cloudSyncManager.upsertExpense(updatedExpense)

            val previousPath = expense.receiptPath
            if (!previousPath.isNullOrBlank() && previousPath != newPath) {
                cloudSyncManager.deleteExpenseReceipt(previousPath)
            }

            onComplete(updatedExpense)
        }
    }

    fun removeExpenseReceipt(
        expense: Expense,
        onComplete: (Expense) -> Unit = {}
    ) {
        viewModelScope.launch {
            val previousPath = expense.receiptPath
            if (previousPath.isNullOrBlank()) return@launch

            val updatedExpense = expense.copy(
                receiptPath = null,
                updatedAt = Date()
            )
            cloudSyncManager.upsertExpense(updatedExpense)
            cloudSyncManager.deleteExpenseReceipt(previousPath)
            onComplete(updatedExpense)
        }
    }
}
