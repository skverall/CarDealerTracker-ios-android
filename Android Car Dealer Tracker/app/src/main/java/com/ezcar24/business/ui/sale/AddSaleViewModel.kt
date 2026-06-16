package com.ezcar24.business.ui.sale

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.DealDeskRepository
import com.ezcar24.business.data.repository.DealDeskSettings
import com.ezcar24.business.data.repository.DealDeskSnapshot
import com.ezcar24.business.data.repository.toJsonString
import com.ezcar24.business.data.repository.PermissionRepository
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.PermissionKey
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AddSaleUiState(
    val availableVehicles: List<Vehicle> = emptyList(),
    val accounts: List<FinancialAccount> = emptyList(),
    val clients: List<Client> = emptyList(),
    val vehicleCosts: Map<UUID, BigDecimal> = emptyMap(),
    val canViewFinancials: Boolean = false,
    val dealDeskSettings: DealDeskSettings? = null,
    val isDealDeskSettingsLoading: Boolean = false,
    val dealDeskSettingsError: String? = null,
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
    private val clientInteractionDao: ClientInteractionDao,
    private val accountDao: FinancialAccountDao,
    private val accountRepository: AccountRepository,
    private val dealDeskRepository: DealDeskRepository,
    private val permissionRepository: PermissionRepository,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "AddSaleViewModel"
    private val _uiState = MutableStateFlow(AddSaleUiState())
    val uiState: StateFlow<AddSaleUiState> = _uiState.asStateFlow()
    private var hasStartedLoading = false

    fun loadData() {
        if (hasStartedLoading) return
        hasStartedLoading = true

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            
            combine(
                vehicleDao.getAllActive(),
                accountDao.getAll(),
                clientDao.getAllActive(),
                permissionRepository.state
            ) { allVehicles, accounts, clients, permissionState ->
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
                        clients = clients,
                        vehicleCosts = vehicleCosts,
                        canViewFinancials = canViewFinancials,
                        isLoading = false
                    ) 
                }
            }.collect { }
        }

        viewModelScope.launch {
            accountRepository.activeOrganization.collectLatest { organization ->
                val organizationId = organization?.organizationId
                if (organizationId == null) {
                    _uiState.update {
                        it.copy(
                            dealDeskSettings = null,
                            isDealDeskSettingsLoading = false,
                            dealDeskSettingsError = null
                        )
                    }
                    return@collectLatest
                }

                _uiState.update {
                    it.copy(
                        isDealDeskSettingsLoading = true,
                        dealDeskSettingsError = null
                    )
                }

                try {
                    val settings = dealDeskRepository.loadSettings(organizationId)
                    _uiState.update {
                        it.copy(
                            dealDeskSettings = settings,
                            isDealDeskSettingsLoading = false,
                            dealDeskSettingsError = null
                        )
                    }
                } catch (error: Exception) {
                    _uiState.update {
                        it.copy(
                            dealDeskSettings = null,
                            isDealDeskSettingsLoading = false,
                            dealDeskSettingsError = UserFacingErrorMapper.map(
                                error,
                                UserFacingErrorContext.LOAD_DEAL_DESK_SETTINGS
                            )
                        )
                    }
                }
            }
        }
    }

    fun saveSale(
        vehicle: Vehicle,
        amount: BigDecimal,
        date: Date,
        buyerName: String,
        buyerPhone: String,
        paymentMethod: String,
        account: FinancialAccount?,
        accountDepositAmount: BigDecimal = amount,
        notes: String? = null,
        selectedClient: Client? = null,
        vatRefundPercent: BigDecimal? = null,
        dealDeskSnapshot: DealDeskSnapshot? = null
    ) {
        viewModelScope.launch {
            val now = Date()
            val trimmedNotes = notes?.trim().orEmpty()
            val normalizedVatPercent = vatRefundPercent?.takeIf { it > BigDecimal.ZERO }
            val vatRefundAmount = normalizedVatPercent?.let { percent ->
                amount.multiply(percent).divide(BigDecimal("100"), 2, RoundingMode.HALF_UP)
            }
            val newSale = Sale(
                id = UUID.randomUUID(),
                vehicleId = vehicle.id,
                amount = amount,
                date = date,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                paymentMethod = paymentMethod,
                accountId = account?.id,
                vatRefundPercent = normalizedVatPercent,
                vatRefundAmount = vatRefundAmount,
                createdAt = now,
                updatedAt = now,
                dealDeskPayload = dealDeskSnapshot?.toJsonString(),
                dealDeskTemplateCode = dealDeskSnapshot?.templateCode,
                dealDeskTemplateVersion = dealDeskSnapshot?.templateVersion
            )

            val updatedVehicle = vehicle.copy(
                status = "sold",
                salePrice = amount,
                saleDate = date,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                paymentMethod = paymentMethod,
                notes = if (trimmedNotes.isBlank()) {
                    vehicle.notes
                } else {
                    "${vehicle.notes.orEmpty()}\n[Sale Note]: $trimmedNotes"
                },
                updatedAt = now
            )

            val clientForSale = saleClientForVehicleSale(
                selectedClient = selectedClient,
                buyerName = buyerName,
                buyerPhone = buyerPhone,
                vehicle = vehicle,
                now = now,
                saleDate = date
            )

            val closedWonInteraction = ClientInteraction(
                id = UUID.randomUUID(),
                title = "Vehicle Purchased",
                detail = saleClientInteractionDetail(vehicle, amount),
                occurredAt = date,
                stage = LeadStage.closed_won.name,
                value = amount,
                clientId = clientForSale.id,
                interactionType = "sale",
                outcome = "closed_won",
                createdAt = now,
                updatedAt = now
            )

            upsertSaleSafely(newSale)
            upsertVehicleSafely(updatedVehicle)
            upsertClientSafely(clientForSale)
            upsertClientInteractionSafely(closedWonInteraction)

            account?.let { acc ->
                val updatedAcc = acc.copy(
                    balance = acc.balance.add(saleAccountBalanceChange(accountDepositAmount)),
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

    private suspend fun upsertClientInteractionSafely(interaction: ClientInteraction) {
        if (CloudSyncEnvironment.currentDealerId == null) {
            clientInteractionDao.upsert(interaction)
            return
        }

        try {
            cloudSyncManager.upsertClientInteraction(interaction)
        } catch (e: Exception) {
            Log.e(tag, "upsertClientInteraction failed: ${e.message}", e)
            clientInteractionDao.upsert(interaction)
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

internal fun saleClientForVehicleSale(
    selectedClient: Client?,
    buyerName: String,
    buyerPhone: String,
    vehicle: Vehicle,
    now: Date,
    saleDate: Date
): Client {
    return selectedClient?.copy(
        status = "sold",
        updatedAt = now,
        vehicleId = vehicle.id,
        leadStage = LeadStage.closed_won,
        leadCreatedAt = selectedClient.leadCreatedAt ?: selectedClient.createdAt,
        lastContactAt = saleDate
    ) ?: Client(
        id = UUID.randomUUID(),
        name = buyerName,
        phone = buyerPhone,
        email = null,
        notes = null,
        requestDetails = null,
        preferredDate = null,
        status = "sold",
        createdAt = now,
        updatedAt = now,
        vehicleId = vehicle.id,
        leadStage = LeadStage.closed_won,
        leadCreatedAt = now,
        lastContactAt = saleDate
    )
}

internal fun saleClientPurchaseNote(vehicle: Vehicle): String {
    return "Purchased ${saleVehicleDisplayName(vehicle)}"
}

internal fun saleClientInteractionDetail(vehicle: Vehicle, saleAmount: BigDecimal): String {
    return "Purchased ${saleVehicleDisplayName(vehicle)} for ${saleAmount.stripTrailingZeros().toPlainString()}"
}

private fun saleVehicleDisplayName(vehicle: Vehicle): String {
    return listOfNotNull(
        vehicle.year?.toString(),
        vehicle.make?.takeIf { it.isNotBlank() },
        vehicle.model?.takeIf { it.isNotBlank() }
    ).joinToString(" ").ifBlank { vehicle.vin }
}
