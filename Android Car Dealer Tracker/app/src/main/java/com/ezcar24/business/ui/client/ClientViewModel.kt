package com.ezcar24.business.ui.client

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class DateFilterType {
    ALL, TODAY, WEEK, MONTH
}

data class ClientUiState(
    val clients: List<Client> = emptyList(),
    val filteredClients: List<Client> = emptyList(),
    val searchText: String = "",
    val dateFilter: DateFilterType = DateFilterType.ALL,
    val isLoading: Boolean = false
)

@HiltViewModel
class ClientViewModel @Inject constructor(
    private val clientDao: ClientDao,
    private val vehicleDao: VehicleDao,
    private val interactionDao: ClientInteractionDao,
    private val reminderDao: ClientReminderDao,
    private val cloudSyncManager: CloudSyncManager
) : ViewModel() {

    private val tag = "ClientViewModel"
    private val _uiState = MutableStateFlow(ClientUiState())
    val uiState: StateFlow<ClientUiState> = _uiState.asStateFlow()

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
        applyFilters()
    }

    fun onDateFilterChange(filter: DateFilterType) {
        _uiState.update { it.copy(dateFilter = filter) }
        applyFilters()
    }

    private fun applyFilters() {
        val current = _uiState.value
        val query = current.searchText.lowercase()
        
        var list = current.clients

        // 1. Search Filter
        if (query.isNotBlank()) {
            list = list.filter { client ->
                (client.name?.lowercase()?.contains(query) == true) ||
                (client.phone?.lowercase()?.contains(query) == true) ||
                (client.email?.lowercase()?.contains(query) == true)
            }
        }

        // 2. Date Filter
        if (current.dateFilter != DateFilterType.ALL) {
            val now = System.currentTimeMillis()
            val dayMillis = 86400000L
            val cutoff = when (current.dateFilter) {
                DateFilterType.TODAY -> now - dayMillis // Rough approx
                DateFilterType.WEEK -> now - (7 * dayMillis)
                DateFilterType.MONTH -> now - (30 * dayMillis)
                else -> 0L
            }
            
            list = list.filter { client ->
                (client.createdAt?.time ?: 0L) >= cutoff
            }
        }

        _uiState.update { it.copy(filteredClients = list) }
    }

    private suspend fun loadDataInternal() {
        // Collect Flow from DAO
        clientDao.getAllActive().collect { allClients ->
            _uiState.update { it.copy(clients = allClients, isLoading = false) }
            applyFilters()
        }
    }

    fun deleteClient(client: Client) {
        viewModelScope.launch {
            // Manually delete interactions/reminders (hard delete as per DAO)
            interactionDao.deleteByClient(client.id)
            reminderDao.deleteByClient(client.id)
            
            // Soft delete Client via Manager (handles local update + sync queue)
            cloudSyncManager.deleteClient(client)

            // loadData() removed - Flow updates automatically
        }
    }
}
