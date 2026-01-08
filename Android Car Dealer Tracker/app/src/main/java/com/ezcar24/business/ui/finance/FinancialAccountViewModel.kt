package com.ezcar24.business.ui.finance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.FinancialAccountDao
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

data class FinancialAccountUiState(
    val accounts: List<FinancialAccount> = emptyList(),
    val isLoading: Boolean = false,
    val totalBalance: BigDecimal = BigDecimal.ZERO,
    val transactions: List<com.ezcar24.business.data.local.AccountTransaction> = emptyList(),
    val selectedAccount: FinancialAccount? = null
)

@HiltViewModel
class FinancialAccountViewModel @Inject constructor(
    private val accountDao: FinancialAccountDao,
    private val transactionDao: com.ezcar24.business.data.local.AccountTransactionDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(FinancialAccountUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadAccounts()
    }

    fun loadAccounts() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            // Collect the Flow
            accountDao.getAll().collect { list ->
                val total = list.fold(BigDecimal.ZERO) { acc, item -> acc.add(item.balance) }
                _uiState.update { it.copy(accounts = list, totalBalance = total, isLoading = false) }
            }
        }
    }
    
    fun selectAccount(account: FinancialAccount) {
        _uiState.update { it.copy(selectedAccount = account) }
        loadTransactions(account.id)
    }
    
    fun clearSelection() {
        _uiState.update { it.copy(selectedAccount = null, transactions = emptyList()) }
    }

    private fun loadTransactions(accountId: UUID) {
        viewModelScope.launch {
             // Basic fetch, ideally should be Flow or paginated
             // Since Entity logic is complex (Transactions could be Expenses, Sales, or pure AccountTransactions),
             // For now we only fetch AccountTransactions table. 
             // Ideally we should Union all types for a full history, but parity request implies "Financial Accounts" parity.
             // If iOS shows "All Transactions" (expenses/sales too), we need a massive query.
             // Assuming "Transactions" means manual transfers/deposits for now + linked items if DAO supports it.
             // Given DAOs are separate, let's start with AccountTransactions table.
             val all = transactionDao.getAllIncludingDeleted()
             val forAccount = all.filter { it.accountId == accountId && it.deletedAt == null }.sortedByDescending { it.date }
             _uiState.update { it.copy(transactions = forAccount) }
        }
    }

    fun saveAccount(id: String?, name: String, initialBalance: BigDecimal) {
        viewModelScope.launch {
            val now = Date()
            val account = if (id != null) {
                val existing = accountDao.getById(UUID.fromString(id)) ?: return@launch
                existing.copy(
                    accountType = name, // Using accountType as Name per schema
                    balance = initialBalance,
                    updatedAt = now
                )
            } else {
                FinancialAccount(
                    id = UUID.randomUUID(),
                    accountType = name,
                    balance = initialBalance,
                    updatedAt = now,
                    deletedAt = null
                )
            }
            accountDao.upsert(account)
            // Trigger sync if needed (omitted for brevity, usually handled by worker or manual sync)
        }
    }

    fun deleteAccount(id: UUID) {
        viewModelScope.launch {
            val account = accountDao.getById(id)
            if (account != null) {
                val deleted = account.copy(deletedAt = Date(), updatedAt = Date())
                accountDao.upsert(deleted)
                // loadAccounts() updates via Flow
            }
        }
    }
    
    fun addTransaction(accountId: UUID, amount: BigDecimal, type: String, note: String) {
        viewModelScope.launch {
            val now = Date()
            val transaction = com.ezcar24.business.data.local.AccountTransaction(
                id = UUID.randomUUID(),
                accountId = accountId,
                amount = amount,
                date = now,
                transactionType = type, // "deposit" or "withdrawal"
                note = note,
                createdAt = now,
                updatedAt = now,
                deletedAt = null
            )
            transactionDao.upsert(transaction)
            
            // Update Account Balance
            val account = accountDao.getById(accountId)
            if (account != null) {
                val newBalance = if (type == "deposit") {
                    account.balance.add(amount)
                } else {
                    account.balance.subtract(amount)
                }
                accountDao.upsert(account.copy(balance = newBalance, updatedAt = now))
            }
            
            loadTransactions(accountId)
        }
    }
}
