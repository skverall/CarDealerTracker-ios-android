package com.ezcar24.business.ui.finance

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.AccountTransaction
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.AccountTransactionDao
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
    val transactions: List<AccountTransaction> = emptyList(),
    val selectedAccount: FinancialAccount? = null
)

@HiltViewModel
class FinancialAccountViewModel @Inject constructor(
    private val accountDao: FinancialAccountDao,
    private val transactionDao: AccountTransactionDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "FinancialAccountViewModel"
    private val _uiState = MutableStateFlow(FinancialAccountUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadAccounts()
    }

    fun loadAccounts() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
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
            upsertAccountSafely(account)
        }
    }

    fun deleteAccount(id: UUID) {
        viewModelScope.launch {
            val account = accountDao.getById(id)
            if (account != null) {
                deleteAccountSafely(account)
            }
        }
    }
    
    fun addTransaction(accountId: UUID, amount: BigDecimal, type: String, note: String) {
        viewModelScope.launch {
            val now = Date()
            val transaction = AccountTransaction(
                id = UUID.randomUUID(),
                accountId = accountId,
                amount = amount,
                date = now,
                transactionType = type,
                note = note,
                createdAt = now,
                updatedAt = now,
                deletedAt = null
            )
            upsertTransactionSafely(transaction)
            
            val account = accountDao.getById(accountId)
            if (account != null) {
                val newBalance = if (type == "deposit") {
                    account.balance.add(amount)
                } else {
                    account.balance.subtract(amount)
                }
                upsertAccountSafely(account.copy(balance = newBalance, updatedAt = now))
            }
            
            loadTransactions(accountId)
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

    private suspend fun deleteAccountSafely(account: FinancialAccount) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            accountDao.upsert(account.copy(deletedAt = Date(), updatedAt = Date()))
            return
        }

        try {
            cloudSyncManager.deleteFinancialAccount(account)
        } catch (e: Exception) {
            Log.e(tag, "deleteFinancialAccount failed: ${e.message}", e)
            accountDao.upsert(account.copy(deletedAt = Date(), updatedAt = Date()))
        }
    }

    private suspend fun upsertTransactionSafely(transaction: AccountTransaction) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            transactionDao.upsert(transaction)
            return
        }

        try {
            cloudSyncManager.upsertAccountTransaction(transaction)
        } catch (e: Exception) {
            Log.e(tag, "upsertAccountTransaction failed: ${e.message}", e)
            transactionDao.upsert(transaction)
        }
    }
}
