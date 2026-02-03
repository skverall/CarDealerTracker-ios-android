package com.ezcar24.business.ui.crm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.data.repository.ClientRepository
import com.ezcar24.business.util.calculator.DailyActivitySummary
import com.ezcar24.business.util.calculator.FunnelMetrics
import com.ezcar24.business.util.calculator.SourcePerformance
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

data class LeadFunnelUiState(
    val funnelMetrics: FunnelMetrics = FunnelMetrics(
        countsPerStage = emptyMap(),
        conversionRates = emptyMap(),
        averageTimePerStage = emptyMap(),
        totalLeads = 0,
        wonLeads = 0,
        lostLeads = 0,
        activeLeads = 0,
        overallConversionRate = 0.0
    ),
    val dailyActivity: DailyActivitySummary = DailyActivitySummary(
        callsCount = 0,
        meetingsCount = 0,
        messagesCount = 0,
        newLeadsCount = 0,
        followUpsCount = 0,
        totalInteractions = 0,
        date = Date()
    ),
    val sourcePerformance: Map<LeadSource, SourcePerformance> = emptyMap(),
    val pipelineValue: BigDecimal = BigDecimal.ZERO,
    val weightedPipelineValue: BigDecimal = BigDecimal.ZERO,
    val selectedStage: LeadStage? = null,
    val leadsInSelectedStage: List<Client> = emptyList(),
    val selectedSource: LeadSource? = null,
    val startDate: Date? = null,
    val endDate: Date? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class LeadFunnelViewModel @Inject constructor(
    private val clientRepository: ClientRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LeadFunnelUiState())
    val uiState: StateFlow<LeadFunnelUiState> = _uiState.asStateFlow()

    init {
        loadFunnelData()
    }

    fun loadFunnelData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                combine(
                    clientRepository.getFunnelMetricsFlow(),
                    clientRepository.getDailyActivitySummaryFlow(),
                    clientRepository.getLeadSourcePerformanceFlow(),
                    clientRepository.getPipelineValueFlow(),
                    clientRepository.getWeightedPipelineValueFlow()
                ) { metrics, activity, sources, pipeline, weightedPipeline ->
                    LeadFunnelUiState(
                        funnelMetrics = metrics,
                        dailyActivity = activity,
                        sourcePerformance = sources,
                        pipelineValue = pipeline,
                        weightedPipelineValue = weightedPipeline,
                        isLoading = false
                    )
                }.collect { state ->
                    _uiState.update { current ->
                        state.copy(
                            selectedStage = current.selectedStage,
                            leadsInSelectedStage = current.leadsInSelectedStage,
                            selectedSource = current.selectedSource,
                            startDate = current.startDate,
                            endDate = current.endDate
                        )
                    }
                }
            } catch (e: Exception) {
                _uiState.update { 
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load funnel data"
                    )
                }
            }
        }
    }

    fun onStageSelected(stage: LeadStage?) {
        _uiState.update { it.copy(selectedStage = stage) }
        
        if (stage != null) {
            loadLeadsForStage(stage)
        } else {
            _uiState.update { it.copy(leadsInSelectedStage = emptyList()) }
        }
    }

    private fun loadLeadsForStage(stage: LeadStage) {
        viewModelScope.launch {
            clientRepository.getClientsByLeadStage(stage).collect { leads ->
                _uiState.update { 
                    it.copy(leadsInSelectedStage = leads)
                }
            }
        }
    }

    fun onSourceFilterSelected(source: LeadSource?) {
        _uiState.update { it.copy(selectedSource = source) }
        applyFilters()
    }

    fun onDateRangeSelected(start: Date?, end: Date?) {
        _uiState.update { 
            it.copy(startDate = start, endDate = end)
        }
        applyFilters()
    }

    private fun applyFilters() {
        val current = _uiState.value
        val stage = current.selectedStage ?: return

        viewModelScope.launch {
            clientRepository.getClientsByLeadStage(stage).collect { leads ->
                var filtered = leads

                // Apply source filter
                current.selectedSource?.let { source ->
                    filtered = filtered.filter { it.leadSource == source }
                }

                // Apply date range filter
                current.startDate?.let { start ->
                    filtered = filtered.filter { 
                        (it.leadCreatedAt ?: it.createdAt) >= start 
                    }
                }
                current.endDate?.let { end ->
                    filtered = filtered.filter { 
                        (it.leadCreatedAt ?: it.createdAt) <= end 
                    }
                }

                _uiState.update { it.copy(leadsInSelectedStage = filtered) }
            }
        }
    }

    fun refresh() {
        loadFunnelData()
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun getConversionRate(fromStage: LeadStage, toStage: LeadStage): Double {
        return _uiState.value.funnelMetrics.conversionRates[fromStage to toStage] ?: 0.0
    }

    fun getLeadsCountForStage(stage: LeadStage): Int {
        return _uiState.value.funnelMetrics.countsPerStage[stage] ?: 0
    }

    fun getAverageTimeInStage(stage: LeadStage): Int {
        return _uiState.value.funnelMetrics.averageTimePerStage[stage] ?: 0
    }
}
