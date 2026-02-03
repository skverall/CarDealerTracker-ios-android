package com.ezcar24.business.ui.crm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.data.repository.ClientRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class LeadSortOption {
    NEWEST,
    OLDEST,
    PRIORITY_HIGH,
    PRIORITY_LOW,
    VALUE_HIGH,
    VALUE_LOW,
    NAME_ASC,
    NAME_DESC
}

data class LeadManagementUiState(
    val allLeads: List<Client> = emptyList(),
    val filteredLeads: List<Client> = emptyList(),
    val searchQuery: String = "",
    val selectedStage: LeadStage? = null,
    val selectedSource: LeadSource? = null,
    val sortOption: LeadSortOption = LeadSortOption.NEWEST,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class LeadManagementViewModel @Inject constructor(
    private val clientRepository: ClientRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LeadManagementUiState())
    val uiState: StateFlow<LeadManagementUiState> = _uiState.asStateFlow()

    init {
        loadLeads()
    }

    fun loadLeads() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                clientRepository.getAllActiveClients().collect { clients ->
                    _uiState.update { 
                        it.copy(
                            allLeads = clients,
                            isLoading = false
                        )
                    }
                    applyFiltersAndSort()
                }
            } catch (e: Exception) {
                _uiState.update { 
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load leads"
                    )
                }
            }
        }
    }

    fun onSearchQueryChange(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        applyFiltersAndSort()
    }

    fun onStageFilterSelected(stage: LeadStage?) {
        _uiState.update { it.copy(selectedStage = stage) }
        applyFiltersAndSort()
    }

    fun onSourceFilterSelected(source: LeadSource?) {
        _uiState.update { it.copy(selectedSource = source) }
        applyFiltersAndSort()
    }

    fun onSortOptionSelected(option: LeadSortOption) {
        _uiState.update { it.copy(sortOption = option) }
        applyFiltersAndSort()
    }

    fun clearFilters() {
        _uiState.update {
            it.copy(
                searchQuery = "",
                selectedStage = null,
                selectedSource = null,
                sortOption = LeadSortOption.NEWEST
            )
        }
        applyFiltersAndSort()
    }

    private fun applyFiltersAndSort() {
        val current = _uiState.value
        var filtered = current.allLeads

        // Apply search filter
        if (current.searchQuery.isNotBlank()) {
            val query = current.searchQuery.lowercase()
            filtered = filtered.filter { client ->
                client.name.lowercase().contains(query) ||
                client.phone?.lowercase()?.contains(query) == true ||
                client.email?.lowercase()?.contains(query) == true ||
                client.notes?.lowercase()?.contains(query) == true
            }
        }

        // Apply stage filter
        current.selectedStage?.let { stage ->
            filtered = filtered.filter { it.leadStage == stage }
        }

        // Apply source filter
        current.selectedSource?.let { source ->
            filtered = filtered.filter { it.leadSource == source }
        }

        // Apply sorting
        filtered = when (current.sortOption) {
            LeadSortOption.NEWEST -> filtered.sortedByDescending { it.createdAt }
            LeadSortOption.OLDEST -> filtered.sortedBy { it.createdAt }
            LeadSortOption.PRIORITY_HIGH -> filtered.sortedByDescending { it.priority }
            LeadSortOption.PRIORITY_LOW -> filtered.sortedBy { it.priority }
            LeadSortOption.VALUE_HIGH -> filtered.sortedByDescending { it.estimatedValue ?: java.math.BigDecimal.ZERO }
            LeadSortOption.VALUE_LOW -> filtered.sortedBy { it.estimatedValue ?: java.math.BigDecimal.ZERO }
            LeadSortOption.NAME_ASC -> filtered.sortedBy { it.name.lowercase() }
            LeadSortOption.NAME_DESC -> filtered.sortedByDescending { it.name.lowercase() }
        }

        _uiState.update { it.copy(filteredLeads = filtered) }
    }

    fun refresh() {
        loadLeads()
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun getLeadsByStage(stage: LeadStage): List<Client> {
        return _uiState.value.allLeads.filter { it.leadStage == stage }
    }

    fun getLeadsBySource(source: LeadSource): List<Client> {
        return _uiState.value.allLeads.filter { it.leadSource == source }
    }

    fun getSourceBreakdown(): Map<LeadSource?, Int> {
        return _uiState.value.allLeads
            .filter { it.leadSource != null }
            .groupingBy { it.leadSource }
            .eachCount()
    }

    fun getStageBreakdown(): Map<LeadStage, Int> {
        return _uiState.value.allLeads
            .groupingBy { it.leadStage }
            .eachCount()
    }

    fun getTotalPipelineValue(): java.math.BigDecimal {
        return _uiState.value.allLeads
            .filter { it.leadStage != LeadStage.closed_won && it.leadStage != LeadStage.closed_lost }
            .map { it.estimatedValue ?: java.math.BigDecimal.ZERO }
            .fold(java.math.BigDecimal.ZERO) { acc, value -> acc.add(value) }
    }

    fun getActiveLeadsCount(): Int {
        return _uiState.value.allLeads.count { 
            it.leadStage != LeadStage.closed_won && it.leadStage != LeadStage.closed_lost 
        }
    }

    fun getNewLeadsTodayCount(): Int {
        val today = Date()
        val calendar = java.util.Calendar.getInstance()
        calendar.time = today
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        val startOfDay = calendar.time

        return _uiState.value.allLeads.count { 
            (it.leadCreatedAt ?: it.createdAt) >= startOfDay 
        }
    }
}
