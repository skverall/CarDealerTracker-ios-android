package com.ezcar24.business.ui.vehicle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import java.util.UUID
import java.util.Date
import java.math.BigDecimal

data class VehicleUiState(
    val vehicles: List<VehicleWithFinancials> = emptyList(),
    val filteredVehicles: List<VehicleWithFinancials> = emptyList(),
    val isLoading: Boolean = false,
    val filterStatus: String? = null, // null = inventory (all active except sold), "sold" = sold vehicles only
    val searchQuery: String = "",
    val selectedVehicle: Vehicle? = null,
    val accounts: List<FinancialAccount> = emptyList(),
    val sortOrder: String = "newest"
)

@HiltViewModel
class VehicleViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val financialAccountDao: FinancialAccountDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "VehicleViewModel"
    private val _uiState = MutableStateFlow(VehicleUiState())
    val uiState = _uiState.asStateFlow()

    init {
        loadVehicles()
        loadAccounts()
    }

    private fun loadAccounts() {
        viewModelScope.launch {
            financialAccountDao.getAll().collect { accounts ->
                _uiState.update { it.copy(accounts = accounts) }
            }
        }
    }

    fun setStatusFilter(status: String?) {
        _uiState.update { it.copy(filterStatus = status) }
        applyFilters()
    }

    fun onSearchQueryChanged(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFilters()
    }

    fun setSortOrder(order: String) {
        _uiState.update { it.copy(sortOrder = order) }
        applyFilters()
    }

    fun updateVehicleStatus(id: UUID, status: String) {
        viewModelScope.launch {
            val vehicle = vehicleDao.getById(id)
            if (vehicle != null) {
                val updated = vehicle.copy(
                    status = status,
                    updatedAt = Date(),
                    // If marking as sold, maybe set defaults? simplified for now
                    saleDate = if (status == "sold") Date() else vehicle.saleDate
                )
                vehicleDao.upsert(updated)
                // loadVehicles() removed - updates are automatic via Flow
            }
        }
    }

    private fun applyFilters() {
        val currentState = _uiState.value
        val allVehicles = currentState.vehicles
        val status = currentState.filterStatus
        val query = currentState.searchQuery.trim().lowercase()
        val sort = currentState.sortOrder

        var filtered = allVehicles.filter { item ->
            // Status Filter - matches iOS VehicleStatusDashboard logic
            val matchesStatus = when (status) {
                "sold" -> item.vehicle.status == "sold"
                "on_sale" -> item.vehicle.status == "on_sale"
                "owned" -> item.vehicle.status == "owned" || item.vehicle.status == "under_service"
                "in_transit" -> item.vehicle.status == "in_transit"
                "all" -> item.vehicle.status != "sold" // All inventory (non-sold)
                null -> item.vehicle.status != "sold" // Default: show inventory
                else -> item.vehicle.status != "sold"
            }

            // Search Filter
            val matchesSearch = if (query.isEmpty()) true else {
                val v = item.vehicle
                (v.make?.lowercase()?.contains(query) == true) ||
                (v.model?.lowercase()?.contains(query) == true) ||
                (v.vin.lowercase().contains(query)) ||
                (v.year?.toString()?.contains(query) == true)
            }

            matchesStatus && matchesSearch
        }
        
        // Apply Sorting
        filtered = when (sort) {
            "price_asc" -> filtered.sortedBy { it.vehicle.purchasePrice }
            "price_desc" -> filtered.sortedByDescending { it.vehicle.purchasePrice }
            "year_desc" -> filtered.sortedByDescending { it.vehicle.year ?: 0 }
            "year_asc" -> filtered.sortedBy { it.vehicle.year ?: 0 }
            "oldest" -> filtered.sortedBy { it.vehicle.createdAt }
            else -> filtered.sortedByDescending { it.vehicle.createdAt } // Default: Newest first
        }
        
        _uiState.update { it.copy(filteredVehicles = filtered) }
    }

    fun loadVehicles() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            // Observe active vehicles with financials flow
            vehicleDao.getAllActiveWithFinancialsFlow().collect { vehicles ->
                _uiState.update { it.copy(vehicles = vehicles, isLoading = false) }
                applyFilters()
            }
        }
    }

    // loadAccounts() removed - duplicate, exists in init block helper if needed but already collected there.
    // Actually, looking at the code, init calls loadAccounts() which is defined at line 50.
    // This duplicate at line 143 was error prone. Removing it.

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
            // loadVehicles() removed - Flow remains active
        }
    }

    fun selectVehicle(id: String) {
        viewModelScope.launch {
            try {
                val uuid = UUID.fromString(id)
                val vehicle = vehicleDao.getById(uuid)
                _uiState.update { it.copy(selectedVehicle = vehicle) }
            } catch (e: Exception) {
                Log.e(tag, "Failed to select vehicle", e)
                _uiState.update { it.copy(selectedVehicle = null) }
            }
        }
    }

    fun clearSelection() {
        _uiState.update { it.copy(selectedVehicle = null) }
    }

    fun deleteVehicle(id: UUID) {
        viewModelScope.launch {
            val vehicle = vehicleDao.getById(id)
            if (vehicle != null) {
                // Soft delete by setting deletedAt
                val deleted = vehicle.copy(deletedAt = Date(), updatedAt = Date())
                vehicleDao.upsert(deleted)
                // For now, reload list.
                // loadVehicles() removed - updates are automatic
                _uiState.update { it.copy(selectedVehicle = null) }
            }
        }
    }

    fun saveVehicle(
        id: String?,
        vin: String,
        make: String,
        model: String,
        year: Int?,
        purchasePrice: BigDecimal,
        purchaseDate: Date,
        askingPrice: BigDecimal?,
        status: String,
        notes: String,
        salePrice: BigDecimal? = null,
        saleDate: Date? = null,
        buyerName: String? = null,
        buyerPhone: String? = null,
        paymentMethod: String? = null,
        reportURL: String? = null
    ) {
        viewModelScope.launch {
            val now = Date()
            val vehicle = if (id != null) {
                // Update
                val existing = vehicleDao.getById(UUID.fromString(id)) ?: return@launch
                existing.copy(
                    vin = vin,
                    make = make,
                    model = model,
                    year = year,
                    purchasePrice = purchasePrice,
                    purchaseDate = purchaseDate,
                    askingPrice = askingPrice,
                    status = status,
                    notes = notes,
                    salePrice = if (status == "sold") salePrice else null,
                    saleDate = if (status == "sold") saleDate else null,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    reportURL = reportURL,
                    updatedAt = now
                )
            } else {
                // Create
                Vehicle(
                    id = UUID.randomUUID(),
                    vin = vin,
                    make = make,
                    model = model,
                    year = year,
                    purchasePrice = purchasePrice,
                    purchaseDate = purchaseDate,
                    status = status,
                    notes = notes,
                    askingPrice = askingPrice,
                    createdAt = now,
                    updatedAt = now,
                    deletedAt = null,
                    saleDate = if (status == "sold") saleDate else null,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    salePrice = if (status == "sold") salePrice else null,
                    reportURL = reportURL
                )
            }
            vehicleDao.upsert(vehicle)
            // loadVehicles() removed - updates are automatic
            
            // Return the vehicle ID so caller can upload image if needed
            vehicle.id
        }
    }
    
    fun uploadVehicleImage(vehicleId: UUID, imageData: ByteArray) {
        val dealerId = CloudSyncEnvironment.currentDealerId ?: return
        viewModelScope.launch {
            try {
                cloudSyncManager.uploadVehicleImage(vehicleId, dealerId, imageData)
                Log.i(tag, "Uploaded vehicle image for vehicleId=$vehicleId")
            } catch (e: Exception) {
                Log.e(tag, "Failed to upload vehicle image: ${e.message}", e)
            }
        }
    }
}

