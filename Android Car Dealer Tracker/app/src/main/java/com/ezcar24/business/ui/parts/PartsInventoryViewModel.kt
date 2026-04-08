package com.ezcar24.business.ui.parts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import androidx.room.withTransaction
import com.ezcar24.business.data.local.ActiveDatabaseProvider
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.data.local.PartBatch
import com.ezcar24.business.data.local.PartBatchDao
import com.ezcar24.business.data.local.PartDao
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PartInventoryItem(
    val part: Part,
    val quantityOnHand: BigDecimal,
    val inventoryValue: BigDecimal
)

data class PartsInventoryUiState(
    val parts: List<PartInventoryItem> = emptyList(),
    val filteredParts: List<PartInventoryItem> = emptyList(),
    val searchQuery: String = "",
    val selectedCategory: String? = null,
    val showLowStockOnly: Boolean = false,
    val categories: List<String> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList()
)

@HiltViewModel
class PartsInventoryViewModel @Inject constructor(
    private val databaseProvider: ActiveDatabaseProvider,
    private val partDao: PartDao,
    private val partBatchDao: PartBatchDao,
    private val financialAccountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "PartsInventoryViewModel"
    private val _uiState = MutableStateFlow(PartsInventoryUiState())
    val uiState = _uiState.asStateFlow()

    init {
        observeInventory()
        observeAccounts()
    }

    private fun observeInventory() {
        viewModelScope.launch {
            combine(
                partDao.getAllActive(),
                partBatchDao.getAllActive()
            ) { parts, batches ->
                buildInventoryItems(parts, batches)
            }.collect { items ->
                val categories = items.mapNotNull { item ->
                    item.part.category?.trim()?.takeIf { it.isNotEmpty() }
                }.distinct().sortedBy { it.lowercase(Locale.US) }
                _uiState.update { it.copy(parts = items, categories = categories) }
                applyFilters()
            }
        }
    }

    private fun observeAccounts() {
        viewModelScope.launch {
            financialAccountDao.getAll().collect { accounts ->
                _uiState.update { it.copy(accounts = accounts) }
            }
        }
    }

    private fun buildInventoryItems(
        parts: List<Part>,
        batches: List<PartBatch>
    ): List<PartInventoryItem> {
        val batchesByPart = batches.groupBy { it.partId }
        return parts.map { part ->
            val partBatches = batchesByPart[part.id].orEmpty()
            val quantity = partBatches.fold(BigDecimal.ZERO) { total, batch ->
                total + batch.quantityRemaining
            }
            val value = partBatches.fold(BigDecimal.ZERO) { total, batch ->
                total + batch.quantityRemaining.multiply(batch.unitCost)
            }
            PartInventoryItem(
                part = part,
                quantityOnHand = quantity,
                inventoryValue = value
            )
        }.sortedBy { it.part.name.lowercase(Locale.US) }
    }

    fun onSearchQueryChanged(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFilters()
    }

    fun setCategory(category: String?) {
        _uiState.update { it.copy(selectedCategory = category) }
        applyFilters()
    }

    fun toggleLowStockOnly(enabled: Boolean) {
        _uiState.update { it.copy(showLowStockOnly = enabled) }
        applyFilters()
    }

    private fun applyFilters() {
        val state = _uiState.value
        val query = state.searchQuery.trim().lowercase(Locale.US)
        val category = state.selectedCategory?.trim()?.lowercase(Locale.US)

        val filtered = state.parts.filter { item ->
            val matchesSearch = if (query.isEmpty()) true else {
                val name = item.part.name.lowercase(Locale.US)
                val code = item.part.code?.lowercase(Locale.US)
                val cat = item.part.category?.lowercase(Locale.US)
                name.contains(query) || (code?.contains(query) == true) || (cat?.contains(query) == true)
            }
            val matchesCategory = category == null || item.part.category?.lowercase(Locale.US) == category
            val isLowStock = item.quantityOnHand <= BigDecimal("2")
            matchesSearch && matchesCategory && (!state.showLowStockOnly || isLowStock)
        }

        _uiState.update { it.copy(filteredParts = filtered) }
    }

    fun addPart(
        name: String,
        code: String?,
        category: String?,
        notes: String?,
        addInitialStock: Boolean,
        initialQuantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        selectedAccountId: UUID?
    ) {
        viewModelScope.launch {
            val trimmedName = name.trim()
            if (trimmedName.isEmpty()) return@launch
            val now = Date()

            var newBatch: PartBatch? = null
            var updatedAccount: FinancialAccount? = null
            val part = Part(
                id = UUID.randomUUID(),
                name = trimmedName,
                code = code?.trim()?.takeIf { it.isNotEmpty() },
                category = category?.trim()?.takeIf { it.isNotEmpty() },
                notes = notes?.trim()?.takeIf { it.isNotEmpty() },
                createdAt = now,
                updatedAt = now,
                deletedAt = null
            )

            val db = databaseProvider.currentDatabase()
            db.withTransaction {
                db.partDao().upsert(part)
                if (addInitialStock && initialQuantity > BigDecimal.ZERO) {
                    val accountId = selectedAccountId
                    newBatch = PartBatch(
                        id = UUID.randomUUID(),
                        partId = part.id,
                        batchLabel = batchLabel?.trim()?.takeIf { it.isNotEmpty() },
                        quantityReceived = initialQuantity,
                        quantityRemaining = initialQuantity,
                        unitCost = unitCost,
                        purchaseDate = now,
                        purchaseAccountId = accountId,
                        notes = null,
                        createdAt = now,
                        updatedAt = now,
                        deletedAt = null
                    )
                    db.partBatchDao().upsert(newBatch!!)
                    if (accountId != null) {
                        val account = db.financialAccountDao().getById(accountId)
                        if (account != null) {
                            val totalCost = initialQuantity.multiply(unitCost)
                            updatedAccount = account.copy(
                                balance = account.balance.subtract(totalCost),
                                updatedAt = now
                            )
                            db.financialAccountDao().upsert(updatedAccount!!)
                        }
                    }
                }
            }

            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.upsertPart(part)
                    if (newBatch != null) {
                        cloudSyncManager.upsertPartBatch(newBatch!!)
                    }
                    if (updatedAccount != null) {
                        cloudSyncManager.upsertFinancialAccount(updatedAccount!!)
                    }
                } catch (e: Exception) {
                    Log.e(tag, "addPart sync failed: ${e.message}", e)
                }
            }
        }
    }

    fun receiveStock(
        partId: UUID,
        quantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        notes: String?,
        purchaseDate: Date,
        selectedAccountId: UUID?
    ) {
        viewModelScope.launch {
            if (quantity <= BigDecimal.ZERO) return@launch
            val now = Date()
            val part = partDao.getById(partId) ?: return@launch
            val batch = PartBatch(
                id = UUID.randomUUID(),
                partId = partId,
                batchLabel = batchLabel?.trim()?.takeIf { it.isNotEmpty() },
                quantityReceived = quantity,
                quantityRemaining = quantity,
                unitCost = unitCost,
                purchaseDate = purchaseDate,
                purchaseAccountId = selectedAccountId,
                notes = notes?.trim()?.takeIf { it.isNotEmpty() },
                createdAt = now,
                updatedAt = now,
                deletedAt = null
            )

            var updatedAccount: FinancialAccount? = null
            val updatedPart = part.copy(updatedAt = now)

            val db = databaseProvider.currentDatabase()
            db.withTransaction {
                db.partBatchDao().upsert(batch)
                db.partDao().upsert(updatedPart)
                if (selectedAccountId != null) {
                    val account = db.financialAccountDao().getById(selectedAccountId)
                    if (account != null) {
                        val totalCost = quantity.multiply(unitCost)
                        updatedAccount = account.copy(
                            balance = account.balance.subtract(totalCost),
                            updatedAt = now
                        )
                        db.financialAccountDao().upsert(updatedAccount!!)
                    }
                }
            }

            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    cloudSyncManager.upsertPart(updatedPart)
                    cloudSyncManager.upsertPartBatch(batch)
                    if (updatedAccount != null) {
                        cloudSyncManager.upsertFinancialAccount(updatedAccount!!)
                    }
                } catch (e: Exception) {
                    Log.e(tag, "receiveStock sync failed: ${e.message}", e)
                }
            }
        }
    }
}
