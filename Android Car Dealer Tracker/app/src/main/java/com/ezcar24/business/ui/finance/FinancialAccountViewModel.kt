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
import java.util.Locale
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
                    accountType = name,
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
            _uiState.update { state ->
                if (state.selectedAccount?.id == account.id) {
                    state.copy(selectedAccount = account)
                } else {
                    state
                }
            }
        }
    }

    fun createDefaultAccounts() {
        viewModelScope.launch {
            val activeTypes = accountDao.getAllIncludingDeleted()
                .filter { it.deletedAt == null }
                .map { it.accountType.trim().lowercase(Locale.US) }
                .toSet()
            val now = Date()
            val defaults = buildList {
                if ("cash" !in activeTypes) {
                    add(
                        FinancialAccount(
                            id = UUID.randomUUID(),
                            accountType = "Cash",
                            balance = BigDecimal.ZERO,
                            updatedAt = now,
                            deletedAt = null
                        )
                    )
                }
                if ("bank" !in activeTypes) {
                    add(
                        FinancialAccount(
                            id = UUID.randomUUID(),
                            accountType = "Bank",
                            balance = BigDecimal.ZERO,
                            updatedAt = now,
                            deletedAt = null
                        )
                    )
                }
            }

            defaults.forEach { account ->
                upsertAccountSafely(account)
            }
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
    
    fun addTransaction(accountId: UUID, amount: BigDecimal, type: String, date: Date, note: String) {
        viewModelScope.launch {
            if (amount <= BigDecimal.ZERO) return@launch

            val now = Date()
            val transaction = AccountTransaction(
                id = UUID.randomUUID(),
                accountId = accountId,
                amount = amount,
                date = date,
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
                val updatedAccount = account.copy(balance = newBalance, updatedAt = now)
                upsertAccountSafely(updatedAccount)
                _uiState.update { it.copy(selectedAccount = updatedAccount) }
            }
            
            loadTransactions(accountId)
        }
    }

    fun deleteTransaction(transaction: AccountTransaction) {
        viewModelScope.launch {
            val accountId = transaction.accountId ?: return@launch
            val account = accountDao.getById(accountId) ?: return@launch
            val now = Date()
            val reversedBalance = if (transaction.transactionType == "deposit") {
                account.balance.subtract(transaction.amount)
            } else {
                account.balance.add(transaction.amount)
            }
            val updatedAccount = account.copy(balance = reversedBalance, updatedAt = now)

            upsertAccountSafely(updatedAccount)
            deleteTransactionSafely(transaction)
            _uiState.update { it.copy(selectedAccount = updatedAccount) }
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

    private suspend fun deleteTransactionSafely(transaction: AccountTransaction) {
        val deleted = transaction.copy(deletedAt = Date(), updatedAt = Date())
        if (CloudSyncEnvironment.currentDealerId == null) {
            transactionDao.upsert(deleted)
            return
        }

        try {
            cloudSyncManager.deleteAccountTransaction(transaction)
        } catch (e: Exception) {
            Log.e(tag, "deleteAccountTransaction failed: ${e.message}", e)
            transactionDao.upsert(deleted)
        }
    }
}
