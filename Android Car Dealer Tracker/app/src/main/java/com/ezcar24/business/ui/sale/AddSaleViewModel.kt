package com.ezcar24.business.ui.sale

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.repository.PermissionRepository
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.PermissionKey
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AddSaleUiState(
    val availableVehicles: List<Vehicle> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),
    val vehicleCosts: Map<UUID, BigDecimal> = emptyMap(),
    val canViewFinancials: Boolean = false,
    val isLoading: Boolean = false
)

internal fun saleTotalCost(
    purchasePrice: BigDecimal?,
    expenseAmounts: Iterable<BigDecimal>
): BigDecimal {
    return expenseAmounts.fold(purchasePrice ?: BigDecimal.ZERO) { total, amount ->
        total.add(amount)
    }
}

internal fun saleEstimatedProfit(salePrice: BigDecimal?, totalCost: BigDecimal): BigDecimal {
    return (salePrice ?: BigDecimal.ZERO).subtract(totalCost)
}

@HiltViewModel
class AddSaleViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val expenseDao: ExpenseDao,
    private val saleDao: SaleDao,
    private val clientDao: ClientDao,
    private val accountDao: FinancialAccountDao,
    private val permissionRepository: PermissionRepository,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "AddSaleViewModel"
    private val _uiState = MutableStateFlow(AddSaleUiState())
    val uiState: StateFlow<AddSaleUiState> = _uiState.asStateFlow()

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            combine(
                vehicleDao.getAllActive(),
                accountDao.getAll(),
                permissionRepository.state
            ) { allVehicles, accounts, permissionState ->
                val available = allVehicles.filter { it.status != "sold" }
                val canViewFinancials = permissionState.can(PermissionKey.VIEW_FINANCIALS)
                val vehicleCosts = if (canViewFinancials) {
                    available.associate { vehicle ->
                        val expenses = expenseDao.getExpensesForVehicleSync(vehicle.id)
                        vehicle.id to saleTotalCost(
                            purchasePrice = vehicle.purchasePrice,
                            expenseAmounts = expenses.map { it.amount }
                        )
                    }
                } else {
                    emptyMap()
                }
                
                _uiState.update { 
                    it.copy(
                        availableVehicles = available,
                        accounts = accounts,
                        vehicleCosts = vehicleCosts,
                        canViewFinancials = canViewFinancials,
                        isLoading = false
                    ) 
                }
            }.collect { }
        }
    }

    fun saveSale(
        vehicle: Vehicle,
        amount: BigDecimal,
        date: Date,
        buyerName: String,
        buyerPhone: String,
        paymentMethod: String,
        account: FinancialAccount?
    ) {
        viewModelScope.launch {
            val now = Date()
            val newSale = Sale(
                id = UUID.randomUUID(),
                vehicleId = vehicle.id,
                amount = amount,
                date = date,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                paymentMethod = paymentMethod,
                accountId = account?.id,
                createdAt = now,
                updatedAt = now
            )

            val updatedVehicle = vehicle.copy(
                status = "sold",
                salePrice = amount,
                saleDate = date,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                paymentMethod = paymentMethod,
                updatedAt = now
            )

            val newClient = Client(
                id = UUID.randomUUID(),
                name = buyerName,
                phone = buyerPhone,
                email = null,
                notes = null,
                requestDetails = null,
                preferredDate = null,
                status = "purchased",
                createdAt = now,
                updatedAt = now,
                vehicleId = vehicle.id
            )

            upsertSaleSafely(newSale)
            upsertVehicleSafely(updatedVehicle)
            upsertClientSafely(newClient)

            account?.let { acc ->
                val updatedAcc = acc.copy(
                    balance = acc.balance.add(saleAccountBalanceChange(amount)),
                    updatedAt = now
                )
                upsertAccountSafely(updatedAcc)
            }
        }
    }

    private suspend fun upsertSaleSafely(sale: Sale) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            saleDao.upsert(sale)
            return
        }

        try {
            cloudSyncManager.upsertSale(sale)
        } catch (e: Exception) {
            Log.e(tag, "upsertSale failed: ${e.message}", e)
            saleDao.upsert(sale)
        }
    }

    private suspend fun upsertVehicleSafely(vehicle: Vehicle) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            vehicleDao.upsert(vehicle)
            return
        }

        try {
            cloudSyncManager.upsertVehicle(vehicle)
        } catch (e: Exception) {
            Log.e(tag, "upsertVehicle failed: ${e.message}", e)
            vehicleDao.upsert(vehicle)
        }
    }

    private suspend fun upsertClientSafely(client: Client) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            clientDao.upsert(client)
            return
        }

        try {
            cloudSyncManager.upsertClient(client)
        } catch (e: Exception) {
            Log.e(tag, "upsertClient failed: ${e.message}", e)
            clientDao.upsert(client)
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
