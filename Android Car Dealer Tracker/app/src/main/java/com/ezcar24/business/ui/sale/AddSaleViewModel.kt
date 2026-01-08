package com.ezcar24.business.ui.sale

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AddSaleUiState(
    val availableVehicles: List<Vehicle> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),
    val isLoading: Boolean = false
)

@HiltViewModel
class AddSaleViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val saleDao: SaleDao,
    private val clientDao: ClientDao,
    private val accountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(AddSaleUiState())
    val uiState: StateFlow<AddSaleUiState> = _uiState.asStateFlow()

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            kotlinx.coroutines.flow.combine(
                vehicleDao.getAllActive(),
                accountDao.getAll()
            ) { allVehicles, accounts ->
                val available = allVehicles.filter { it.status != "sold" }
                
                _uiState.update { 
                    it.copy(
                        availableVehicles = available, 
                        accounts = accounts, 
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
            // 1. Create Sale
            val newSale = Sale(
                id = UUID.randomUUID(),
                vehicleId = vehicle.id,
                amount = amount,
                date = date,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                paymentMethod = paymentMethod,
                accountId = account?.id,
                createdAt = Date(),
                updatedAt = Date()
            )
            saleDao.upsert(newSale)

            // 2. Update Vehicle Status
            val updatedVehicle = vehicle.copy(
                status = "sold",
                salePrice = amount,
                saleDate = date,
                buyerName = buyerName, // Denormalize for easy access
                buyerPhone = buyerPhone,
                updatedAt = Date()
            )
            vehicleDao.upsert(updatedVehicle)

            // 3. Create or Update Client (Simple logic: Create new for now)
            val newClient = Client(
                id = UUID.randomUUID(),
                name = buyerName,
                phone = buyerPhone,
                email = null,
                notes = null,
                requestDetails = null,
                preferredDate = null,
                status = "purchased", // Enum string
                createdAt = Date(),
                updatedAt = Date(),
                vehicleId = vehicle.id
            )
            clientDao.upsert(newClient)
            
            // 4. Update Account Balance
            account?.let { acc ->
                val currentBal = acc.balance
                val newBal = currentBal.add(amount)
                val updatedAcc = acc.copy(balance = newBal, updatedAt = Date())
                accountDao.upsert(updatedAcc)
                
                cloudSyncManager.upsertFinancialAccount(updatedAcc)
            }

            // Sync Everything
            cloudSyncManager.upsertSale(newSale)
            cloudSyncManager.upsertVehicle(updatedVehicle)
            cloudSyncManager.upsertClient(newClient)
        }
    }
}
