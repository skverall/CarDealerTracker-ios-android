package com.ezcar24.business.ui.sale

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.local.SaleDao
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.math.MathContext
import java.util.Date
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SaleItem(
    val sale: Sale,
    val vehicleName: String,
    val buyerName: String,
    val saleDate: Date,
    val salePrice: BigDecimal,
    val costPrice: BigDecimal,
    val netProfit: BigDecimal,
    val profitMargin: Double
)

data class SalesUiState(
    val sales: List<SaleItem> = emptyList(),
    val filteredSales: List<SaleItem> = emptyList(),
    val searchText: String = "",
    val isLoading: Boolean = false
)

@HiltViewModel
class SalesViewModel @Inject constructor(
    private val saleDao: SaleDao,
    private val vehicleDao: VehicleDao,
    private val expenseDao: ExpenseDao,
    private val accountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "SalesViewModel"
    private val _uiState = MutableStateFlow(SalesUiState())
    val uiState: StateFlow<SalesUiState> = _uiState.asStateFlow()

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

    fun onSearchTextChange(text: String) {
        _uiState.update { it.copy(searchText = text) }
        applyFilter()
    }

    private fun applyFilter() {
        val current = _uiState.value
        if (current.searchText.isBlank()) {
            _uiState.update { it.copy(filteredSales = current.sales) }
        } else {
            val query = current.searchText.lowercase()
            val filtered = current.sales.filter { item ->
                item.vehicleName.lowercase().contains(query) ||
                item.buyerName.lowercase().contains(query)
            }
            _uiState.update { it.copy(filteredSales = filtered) }
        }
    }

    private suspend fun loadDataInternal() {
        saleDao.getAll().collect { salesList ->
            // Map to SaleItem with calculations
            val items = salesList.map { sale ->
                val vehicle = sale.vehicleId?.let { vehicleDao.getById(it) }
                
                // Fetch expenses for vehicle to calculate profit
                val expensesList = sale.vehicleId?.let { expenseDao.getExpensesForVehicleSync(it) } ?: emptyList()
                val totalExpenses = expensesList.sumOf { it.amount }

                val vehiclePurchasePrice = vehicle?.purchasePrice ?: BigDecimal.ZERO
                val costPrice = vehiclePurchasePrice.add(totalExpenses)
                val salePrice = sale.amount ?: BigDecimal.ZERO
                val netProfit = salePrice.subtract(costPrice)

                val profitMargin = if (salePrice > BigDecimal.ZERO) {
                    netProfit.toDouble() / salePrice.toDouble() * 100
                } else {
                    0.0
                }

                val make = vehicle?.make ?: ""
                val model = vehicle?.model ?: ""
                val vehicleName = if (make.isEmpty() && model.isEmpty()) "Vehicle Removed" else "$make $model"

                SaleItem(
                    sale = sale,
                    vehicleName = vehicleName,
                    buyerName = sale.buyerName ?: "Unknown Buyer",
                    saleDate = sale.date ?: Date(),
                    salePrice = salePrice,
                    costPrice = costPrice,
                    netProfit = netProfit,
                    profitMargin = profitMargin
                )
            }

            _uiState.update { it.copy(sales = items, isLoading = false) }
            applyFilter()
        }
    }

    fun deleteSale(sale: Sale) {
        viewModelScope.launch {
            // Revert Vehicle Status
            sale.vehicleId?.let { vid ->
                vehicleDao.getById(vid)?.let { vehicle ->
                    val updatedVehicle = vehicle.copy(
                        status = "available",
                        salePrice = null,
                        saleDate = null,
                        buyerName = null,
                        buyerPhone = null,
                        paymentMethod = null,
                        updatedAt = Date()
                    )
                    // Sync Manager handles local + remote
                    cloudSyncManager.upsertVehicle(updatedVehicle)
                }
            }

            // Revert Account Balance
            sale.accountId?.let { accId ->
                accountDao.getById(accId)?.let { account ->
                    val amountToSubtract = sale.amount ?: BigDecimal.ZERO
                    val currentBal = account.balance ?: BigDecimal.ZERO
                    val newBal = currentBal.subtract(amountToSubtract)
                    val updatedAccount = account.copy(balance = newBal, updatedAt = Date())

                    cloudSyncManager.upsertFinancialAccount(updatedAccount)
                }
            }

            // Soft Delete Sale via Manager
            cloudSyncManager.deleteSale(sale)

            // loadData() removed - Flow updates automatically
        }
    }
}
