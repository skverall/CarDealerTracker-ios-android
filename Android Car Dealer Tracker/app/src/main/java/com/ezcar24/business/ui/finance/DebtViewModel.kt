package com.ezcar24.business.ui.finance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject

data class DebtUiState(
    val debts: List<Debt> = emptyList(),
    val filteredDebts: List<Debt> = emptyList(), // Based on tab (owed to me / by me)
    val accounts: List<FinancialAccount> = emptyList(), // For payment selection
    val selectedDebt: Debt? = null,
    val isLoading: Boolean = false,
    val selectedTab: String = "owed_to_me", // or "owed_by_me"
    val searchText: String = "",
    val debtPayments: List<com.ezcar24.business.data.local.DebtPayment> = emptyList() // Payments for selected debt
)

@HiltViewModel
class DebtViewModel @Inject constructor(
    private val debtDao: DebtDao,
    private val debtPaymentDao: DebtPaymentDao,
    private val accountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(DebtUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            kotlinx.coroutines.flow.combine(
                debtDao.getAllFlow(),
                accountDao.getAll()
            ) { allDebts, accounts ->
                val activeDebts = allDebts.filter { it.deletedAt == null }
                
                // If a debt is selected, ensure we have the latest version of it
                val currentSelection = _uiState.value.selectedDebt
                val updatedSelection = if (currentSelection != null) {
                    activeDebts.find { it.id == currentSelection.id } ?: currentSelection
                } else null

                _uiState.update { 
                    it.copy(
                        debts = activeDebts,
                        accounts = accounts,
                        selectedDebt = updatedSelection,
                        isLoading = false
                    ) 
                }
                applyFilter()
            }.collect { }
        }
    }
    
    fun selectDebt(debt: Debt) {
        viewModelScope.launch {
            _uiState.update { it.copy(selectedDebt = debt) }
            val allPayments = debtPaymentDao.getAllIncludingDeleted()
            val filtered = allPayments.filter { it.debtId == debt.id && it.deletedAt == null }.sortedByDescending { it.date }
            _uiState.update { it.copy(debtPayments = filtered) }
        }
    }

    fun clearSelection() {
        _uiState.update { it.copy(selectedDebt = null, debtPayments = emptyList()) }
    }

    fun setTab(tab: String) {
        _uiState.update { it.copy(selectedTab = tab) }
        applyFilter()
    }

    private fun applyFilter() {
        val current = _uiState.value
        var filtered = current.debts.filter { it.direction == current.selectedTab }
        
        if (current.searchText.isNotBlank()) {
            val query = current.searchText.lowercase()
            filtered = filtered.filter { 
                it.counterpartyName.lowercase().contains(query) ||
                (it.notes?.lowercase()?.contains(query) == true)
            }
        }
        
        _uiState.update { it.copy(filteredDebts = filtered) }
    }

    fun onSearchTextChange(text: String) {
        _uiState.update { it.copy(searchText = text) }
        applyFilter()
    }

    fun saveDebt(
        id: String?,
        name: String,
        phone: String,
        amount: BigDecimal,
        direction: String,
        notes: String
    ) {
        viewModelScope.launch {
            val now = Date()
            val debt = if (id != null) {
                val existing = debtDao.getById(UUID.fromString(id)) ?: return@launch
                existing.copy(
                    counterpartyName = name,
                    counterpartyPhone = phone,
                    amount = amount,
                    direction = direction,
                    notes = notes,
                    updatedAt = now
                )
            } else {
                Debt(
                    id = UUID.randomUUID(),
                    counterpartyName = name,
                    counterpartyPhone = phone,
                    amount = amount,
                    direction = direction,
                    notes = notes,
                    dueDate = null, // Can add date picker later
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null
                )
            }
            debtDao.upsert(debt)
            // loadData() removed - Flow updates automatically
        }
    }
    
    fun deleteDebt(id: UUID) {
        viewModelScope.launch {
             val existing = debtDao.getById(id) ?: return@launch
             debtDao.upsert(existing.copy(deletedAt = Date()))
             // loadData() removed - Flow updates automatically
        }
    }

    fun recordPayment(debtId: UUID, amount: BigDecimal, accountId: UUID) {
        viewModelScope.launch {
            // 1. Create Payment Record
            val payment = DebtPayment(
                id = UUID.randomUUID(),
                debtId = debtId,
                accountId = accountId,
                amount = amount,
                date = Date(),
                note = "Payment",
                paymentMethod = "transfer",
                createdAt = Date(),
                updatedAt = Date(),
                deletedAt = null
            )
            debtPaymentDao.upsert(payment)
            
            // 2. Reduce Debt Amount
            val debt = debtDao.getById(debtId) ?: return@launch
            val newAmount = debt.amount.subtract(amount)
            // If new amount is <= 0, maybe mark as paid/archived? For now just reduce.
            debtDao.upsert(debt.copy(amount = newAmount, updatedAt = Date()))
            
            // 3. Update Account Balance
            val account = accountDao.getById(accountId) ?: return@launch
            // Logic:
            // "owed_to_me" (I receive money) -> Account Balance Increases
            // "owed_by_me" (I pay money) -> Account Balance Decreases
            val balanceChange = if (debt.direction == "owed_to_me") amount else amount.negate()
            val newBalance = account.balance.add(balanceChange)
            
            accountDao.upsert(account.copy(balance = newBalance, updatedAt = Date()))
            
            // Reload Payment History for the Detail View
            val allPayments = debtPaymentDao.getAllIncludingDeleted()
            val filtered = allPayments.filter { it.debtId == debtId && it.deletedAt == null }.sortedByDescending { it.date }
            _uiState.update { it.copy(debtPayments = filtered) }
        }
    }
}
