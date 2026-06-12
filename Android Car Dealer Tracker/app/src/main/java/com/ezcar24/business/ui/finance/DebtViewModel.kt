package com.ezcar24.business.ui.finance

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
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
    val filteredDebts: List<Debt> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),
    val selectedDebt: Debt? = null,
    val isLoading: Boolean = false,
    val selectedTab: String = "owed_to_me",
    val searchText: String = "",
    val debtPayments: List<DebtPayment> = emptyList()
)

internal fun debtPaymentBalanceChange(amount: BigDecimal, direction: String): BigDecimal {
    return if (direction == "owed_to_me") amount else amount.negate()
}

internal fun debtPaymentDeletionBalanceChange(amount: BigDecimal, direction: String): BigDecimal {
    return debtPaymentBalanceChange(amount, direction).negate()
}

@HiltViewModel
class DebtViewModel @Inject constructor(
    private val debtDao: DebtDao,
    private val debtPaymentDao: DebtPaymentDao,
    private val accountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "DebtViewModel"
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
                    dueDate = null,
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null
                )
            }
            upsertDebtSafely(debt)
        }
    }
    
    fun deleteDebt(id: UUID) {
        viewModelScope.launch {
            val existing = debtDao.getById(id) ?: return@launch
            val activePayments = debtPaymentDao.getAllIncludingDeleted()
                .filter { it.debtId == id && it.deletedAt == null }
            val affectedAccounts = mutableMapOf<UUID, FinancialAccount>()
            val now = Date()

            activePayments.forEach { payment ->
                val accountId = payment.accountId
                if (accountId != null) {
                    val account = affectedAccounts[accountId] ?: accountDao.getById(accountId)
                    if (account != null) {
                        affectedAccounts[accountId] = account.copy(
                            balance = account.balance.add(
                                debtPaymentDeletionBalanceChange(payment.amount, existing.direction)
                            ),
                            updatedAt = now
                        )
                    }
                }
            }

            affectedAccounts.values.forEach { upsertAccountSafely(it) }
            activePayments.forEach { deleteDebtPaymentSafely(it) }
            deleteDebtSafely(existing)
            _uiState.update { it.copy(selectedDebt = null, debtPayments = emptyList()) }
        }
    }

    fun recordPayment(debtId: UUID, amount: BigDecimal, accountId: UUID) {
        viewModelScope.launch {
            val now = Date()
            val payment = DebtPayment(
                id = UUID.randomUUID(),
                debtId = debtId,
                accountId = accountId,
                amount = amount,
                date = now,
                note = "Payment",
                paymentMethod = "transfer",
                createdAt = now,
                updatedAt = now,
                deletedAt = null
            )
            upsertDebtPaymentSafely(payment)
            
            val debt = debtDao.getById(debtId) ?: return@launch
            val newAmount = debt.amount.subtract(amount)
            upsertDebtSafely(debt.copy(amount = newAmount, updatedAt = Date()))
            
            val account = accountDao.getById(accountId) ?: return@launch
            val balanceChange = debtPaymentBalanceChange(amount, debt.direction)
            val newBalance = account.balance.add(balanceChange)
            
            upsertAccountSafely(account.copy(balance = newBalance, updatedAt = Date()))
            
            val allPayments = debtPaymentDao.getAllIncludingDeleted()
            val filtered = allPayments.filter { it.debtId == debtId && it.deletedAt == null }.sortedByDescending { it.date }
            _uiState.update { it.copy(debtPayments = filtered) }
        }
    }

    private suspend fun upsertDebtSafely(debt: Debt) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            debtDao.upsert(debt)
            return
        }

        try {
            cloudSyncManager.upsertDebt(debt)
        } catch (e: Exception) {
            Log.e(tag, "upsertDebt failed: ${e.message}", e)
            debtDao.upsert(debt)
        }
    }

    private suspend fun deleteDebtSafely(debt: Debt) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            debtDao.upsert(debt.copy(deletedAt = Date(), updatedAt = Date()))
            return
        }

        try {
            cloudSyncManager.deleteDebt(debt)
        } catch (e: Exception) {
            Log.e(tag, "deleteDebt failed: ${e.message}", e)
            debtDao.upsert(debt.copy(deletedAt = Date(), updatedAt = Date()))
        }
    }

    private suspend fun upsertDebtPaymentSafely(payment: DebtPayment) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            debtPaymentDao.upsert(payment)
            return
        }

        try {
            cloudSyncManager.upsertDebtPayment(payment)
        } catch (e: Exception) {
            Log.e(tag, "upsertDebtPayment failed: ${e.message}", e)
            debtPaymentDao.upsert(payment)
        }
    }

    private suspend fun deleteDebtPaymentSafely(payment: DebtPayment) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            debtPaymentDao.upsert(payment.copy(deletedAt = Date(), updatedAt = Date()))
            return
        }

        try {
            cloudSyncManager.deleteDebtPayment(payment)
        } catch (e: Exception) {
            Log.e(tag, "deleteDebtPayment failed: ${e.message}", e)
            debtPaymentDao.upsert(payment.copy(deletedAt = Date(), updatedAt = Date()))
        }
    }

    private suspend fun upsertAccountSafely(account: FinancialAccount) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            accountDao.upsert(account)
            return
        }

        try {
            cloudSyncManager.upsertFinancialAccount(account)
        } catch (e: Exception) {
            Log.e(tag, "upsertFinancialAccount failed: ${e.message}", e)
            accountDao.upsert(account)
        }
    }
}
