package com.ezcar24.business.ui.parts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import androidx.room.withTransaction
import com.ezcar24.business.data.local.AppDatabase
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientDao
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.data.local.PartBatch
import com.ezcar24.business.data.local.PartBatchDao
import com.ezcar24.business.data.local.PartDao
import com.ezcar24.business.data.local.PartSale
import com.ezcar24.business.data.local.PartSaleDao
import com.ezcar24.business.data.local.PartSaleLineItem
import com.ezcar24.business.data.local.PartSaleLineItemDao
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

data class PartSaleItemSummary(
    val sale: PartSale,
    val saleDate: Date,
    val buyerName: String,
    val totalAmount: BigDecimal,
    val totalCost: BigDecimal,
    val profit: BigDecimal,
    val itemsSummary: String
)

data class PartSalesUiState(
    val sales: List<PartSaleItemSummary> = emptyList(),
    val filteredSales: List<PartSaleItemSummary> = emptyList(),
    val searchQuery: String = "",
    val accounts: List<FinancialAccount> = emptyList(),
    val clients: List<Client> = emptyList(),
    val parts: List<Part> = emptyList(),
    val batches: List<PartBatch> = emptyList()
)

data class PartSaleLineDraft(
    val partId: UUID,
    val quantity: BigDecimal,
    val unitPrice: BigDecimal
)

@HiltViewModel
class PartSalesViewModel @Inject constructor(
    private val db: AppDatabase,
    private val partSaleDao: PartSaleDao,
    private val partSaleLineItemDao: PartSaleLineItemDao,
    private val partDao: PartDao,
    private val partBatchDao: PartBatchDao,
    private val financialAccountDao: FinancialAccountDao,
    private val clientDao: ClientDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "PartSalesViewModel"
    private val _uiState = MutableStateFlow(PartSalesUiState())
    val uiState = _uiState.asStateFlow()

    init {
        observeData()
    }

    private fun observeData() {
        viewModelScope.launch {
            combine(
                partSaleDao.getAllActive(),
                partSaleLineItemDao.getAllActive(),
                partDao.getAllActive()
            ) { sales, items, parts ->
                buildSaleSummaries(sales, items, parts)
            }.collect { summaries ->
                _uiState.update { it.copy(sales = summaries) }
                applyFilters()
            }
        }

        viewModelScope.launch {
            financialAccountDao.getAll().collect { accounts ->
                _uiState.update { it.copy(accounts = accounts) }
            }
        }

        viewModelScope.launch {
            clientDao.getAllActive().collect { clients ->
                _uiState.update { it.copy(clients = clients) }
            }
        }

        viewModelScope.launch {
            partDao.getAllActive().collect { parts ->
                _uiState.update { it.copy(parts = parts) }
            }
        }

        viewModelScope.launch {
            partBatchDao.getAllActive().collect { batches ->
                _uiState.update { it.copy(batches = batches) }
            }
        }
    }

    fun onSearchQueryChanged(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFilters()
    }

    private fun applyFilters() {
        val state = _uiState.value
        val query = state.searchQuery.trim().lowercase(Locale.US)
        val filtered = if (query.isEmpty()) {
            state.sales
        } else {
            state.sales.filter { sale ->
                sale.buyerName.lowercase(Locale.US).contains(query) ||
                    sale.itemsSummary.lowercase(Locale.US).contains(query)
            }
        }
        _uiState.update { it.copy(filteredSales = filtered) }
    }

    private fun buildSaleSummaries(
        sales: List<PartSale>,
        items: List<PartSaleLineItem>,
        parts: List<Part>
    ): List<PartSaleItemSummary> {
        val itemsBySale = items.groupBy { it.saleId }
        val partsById = parts.associateBy { it.id }

        return sales.sortedByDescending { it.date }.map { sale ->
            val saleItems = itemsBySale[sale.id].orEmpty()
            if (saleItems.isEmpty()) {
                val amount = sale.amount
                PartSaleItemSummary(
                    sale = sale,
                    saleDate = sale.date,
                    buyerName = sale.buyerName?.takeIf { it.isNotBlank() } ?: "Walk-in",
                    totalAmount = amount,
                    totalCost = BigDecimal.ZERO,
                    profit = amount,
                    itemsSummary = ""
                )
            } else {
                var totalAmount = BigDecimal.ZERO
                var totalCost = BigDecimal.ZERO
                val grouped = linkedMapOf<String, BigDecimal>()

                saleItems.forEach { item ->
                    val qty = item.quantity
                    val price = item.unitPrice
                    val cost = item.unitCost
                    totalAmount += qty.multiply(price)
                    totalCost += qty.multiply(cost)
                    val partName = partsById[item.partId]?.name ?: "Part"
                    grouped[partName] = (grouped[partName] ?: BigDecimal.ZERO) + qty
                }

                val summary = grouped.entries.joinToString(", ") { entry ->
                    "${formatQuantity(entry.value)} x ${entry.key}"
                }
                PartSaleItemSummary(
                    sale = sale,
                    saleDate = sale.date,
                    buyerName = sale.buyerName?.takeIf { it.isNotBlank() } ?: "Walk-in",
                    totalAmount = totalAmount,
                    totalCost = totalCost,
                    profit = totalAmount - totalCost,
                    itemsSummary = summary
                )
            }
        }
    }

    private fun formatQuantity(value: BigDecimal): String {
        return value.stripTrailingZeros().toPlainString()
    }

    fun createSale(
        saleDate: Date,
        selectedAccountId: UUID,
        lineItems: List<PartSaleLineDraft>,
        buyerName: String?,
        buyerPhone: String?,
        paymentMethod: String?,
        notes: String?,
        selectedClientId: UUID?
    ): Boolean {
        if (lineItems.isEmpty()) return false
        val now = Date()
        var createdSale: PartSale? = null
        var createdLineItems: List<PartSaleLineItem> = emptyList()
        val updatedBatches = mutableListOf<PartBatch>()
        val updatedParts = mutableMapOf<UUID, Part>()
        var updatedAccount: FinancialAccount? = null
        var updatedClient: Client? = null

        return try {
            db.withTransaction {
                val account = financialAccountDao.getById(selectedAccountId)
                    ?: throw IllegalStateException("Account not found")
                val partsById = partDao.getAllActiveList().associateBy { it.id }
                val batchesByPart = partBatchDao.getAllActiveList().groupBy { it.partId }

                val sale = PartSale(
                    id = UUID.randomUUID(),
                    amount = BigDecimal.ZERO,
                    date = saleDate,
                    buyerName = buyerName?.trim()?.takeIf { it.isNotEmpty() },
                    buyerPhone = buyerPhone?.trim()?.takeIf { it.isNotEmpty() },
                    paymentMethod = paymentMethod?.trim()?.takeIf { it.isNotEmpty() },
                    accountId = account.id,
                    notes = notes?.trim()?.takeIf { it.isNotEmpty() },
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null
                )

                val lineItemRecords = mutableListOf<PartSaleLineItem>()
                var total = BigDecimal.ZERO

                lineItems.forEach { line ->
                    val part = partsById[line.partId]
                        ?: throw IllegalStateException("Part not found")
                    var remaining = line.quantity
                    val availableBatches = batchesByPart[line.partId]
                        .orEmpty()
                        .filter { it.quantityRemaining > BigDecimal.ZERO }
                        .sortedBy { it.purchaseDate }

                    for (batch in availableBatches) {
                        if (remaining <= BigDecimal.ZERO) break
                        val available = batch.quantityRemaining
                        if (available <= BigDecimal.ZERO) continue
                        val allocate = if (available < remaining) available else remaining

                        val item = PartSaleLineItem(
                            id = UUID.randomUUID(),
                            saleId = sale.id,
                            partId = part.id,
                            batchId = batch.id,
                            quantity = allocate,
                            unitPrice = line.unitPrice,
                            unitCost = batch.unitCost,
                            createdAt = now,
                            updatedAt = now,
                            deletedAt = null
                        )
                        lineItemRecords.add(item)

                        total += allocate.multiply(line.unitPrice)
                        remaining -= allocate

                        val updatedBatch = batch.copy(
                            quantityRemaining = batch.quantityRemaining - allocate,
                            updatedAt = now
                        )
                        updatedBatches.add(updatedBatch)
                    }

                    if (remaining > BigDecimal.ZERO) {
                        throw IllegalStateException("Insufficient stock")
                    }

                    updatedParts[part.id] = part.copy(updatedAt = now)
                }

                val updatedSale = sale.copy(amount = total)
                createdSale = updatedSale
                createdLineItems = lineItemRecords

                partSaleDao.upsert(updatedSale)
                partSaleLineItemDao.upsertAll(lineItemRecords)
                updatedBatches.forEach { partBatchDao.upsert(it) }
                updatedParts.values.forEach { partDao.upsert(it) }

                val updatedBalance = account.balance + total
                updatedAccount = account.copy(balance = updatedBalance, updatedAt = now)
                financialAccountDao.upsert(updatedAccount!!)

                if (selectedClientId != null) {
                    val client = clientDao.getById(selectedClientId)
                    if (client != null) {
                        updatedClient = client.copy(updatedAt = now)
                        clientDao.upsert(updatedClient!!)
                    }
                }
            }

            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    if (createdSale != null) {
                        cloudSyncManager.upsertPartSale(createdSale!!)
                    }
                    createdLineItems.forEach { cloudSyncManager.upsertPartSaleLineItem(it) }
                    updatedBatches.forEach { cloudSyncManager.upsertPartBatch(it) }
                    updatedParts.values.forEach { cloudSyncManager.upsertPart(it) }
                    if (updatedAccount != null) {
                        cloudSyncManager.upsertFinancialAccount(updatedAccount!!)
                    }
                    if (updatedClient != null) {
                        cloudSyncManager.upsertClient(updatedClient!!)
                    }
                } catch (e: Exception) {
                    Log.e(tag, "createSale sync failed: ${e.message}", e)
                }
            }
            true
        } catch (e: Exception) {
            Log.e(tag, "createSale failed: ${e.message}", e)
            false
        }
    }

    fun deleteSale(sale: PartSale) {
        viewModelScope.launch {
            val now = Date()
            val lineItems = partSaleLineItemDao.getBySaleId(sale.id)
            val updatedBatches = mutableListOf<PartBatch>()
            val updatedParts = mutableMapOf<UUID, Part>()
            var updatedAccount: FinancialAccount? = null

            db.withTransaction {
                lineItems.forEach { item ->
                    val deletedItem = item.copy(deletedAt = now, updatedAt = now)
                    partSaleLineItemDao.upsert(deletedItem)
                    val batch = partBatchDao.getById(item.batchId)
                    if (batch != null) {
                        val updatedBatch = batch.copy(
                            quantityRemaining = batch.quantityRemaining + item.quantity,
                            updatedAt = now
                        )
                        partBatchDao.upsert(updatedBatch)
                        updatedBatches.add(updatedBatch)
                    }
                    val part = partDao.getById(item.partId)
                    if (part != null) {
                        val updatedPart = part.copy(updatedAt = now)
                        partDao.upsert(updatedPart)
                        updatedParts[updatedPart.id] = updatedPart
                    }
                }

                val accountId = sale.accountId
                if (accountId != null) {
                    val account = financialAccountDao.getById(accountId)
                    if (account != null) {
                        val updatedBalance = account.balance - sale.amount
                        updatedAccount = account.copy(balance = updatedBalance, updatedAt = now)
                        financialAccountDao.upsert(updatedAccount!!)
                    }
                }

                val deletedSale = sale.copy(deletedAt = now, updatedAt = now)
                partSaleDao.upsert(deletedSale)
            }

            val dealerId = CloudSyncEnvironment.currentDealerId
            if (dealerId != null) {
                try {
                    lineItems.forEach { cloudSyncManager.deletePartSaleLineItem(it) }
                    updatedBatches.forEach { cloudSyncManager.upsertPartBatch(it) }
                    updatedParts.values.forEach { cloudSyncManager.upsertPart(it) }
                    if (updatedAccount != null) {
                        cloudSyncManager.upsertFinancialAccount(updatedAccount!!)
                    }
                    cloudSyncManager.deletePartSale(sale)
                } catch (e: Exception) {
                    Log.e(tag, "deleteSale sync failed: ${e.message}", e)
                }
            }
        }
    }
}
