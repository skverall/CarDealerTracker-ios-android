package com.ezcar24.business.ui.analytics

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.billing.SubscriptionManager
import com.ezcar24.business.data.repository.AIInsightsHttpException
import com.ezcar24.business.data.repository.AIInsightsReport
import com.ezcar24.business.data.repository.AIInsightsRepository
import com.ezcar24.business.data.repository.AIInsightsResponse
import com.ezcar24.business.data.repository.AIInsightsUsage
import com.ezcar24.business.ui.dashboard.DashboardTimeRange
import dagger.hilt.android.lifecycle.HiltViewModel
import java.text.DateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AIInsightsUiState(
    val response: AIInsightsResponse? = null,
    val generatedAtMillis: Long? = null,
    val history: List<AIInsightsReport> = emptyList(),
    val selectedReportId: String? = null,
    val usage: AIInsightsUsage? = null,
    val isLoading: Boolean = false,
    val isHistoryLoading: Boolean = false,
    val errorMessage: String? = null,
    val isSignedIn: Boolean = false,
    val hasProAccess: Boolean = false,
    val isCheckingAccess: Boolean = true,
    val isConfirmingRegeneration: Boolean = false,
    val hasData: Boolean = true,
    val preparedFingerprint: String? = null
)

@HiltViewModel
class AIInsightsViewModel @Inject constructor(
    private val repository: AIInsightsRepository,
    subscriptionManager: SubscriptionManager
) : ViewModel() {
    private val _uiState = MutableStateFlow(AIInsightsUiState())
    val uiState: StateFlow<AIInsightsUiState> = _uiState.asStateFlow()

    private var currentRange: DashboardTimeRange? = null

    init {
        viewModelScope.launch {
            combine(
                subscriptionManager.isProAccessActive,
                subscriptionManager.isCheckingStatus
            ) { hasPro, isChecking -> hasPro to isChecking }
                .collect { (hasPro, isChecking) ->
                    _uiState.update {
                        it.copy(
                            hasProAccess = hasPro,
                            isCheckingAccess = isChecking,
                            isSignedIn = repository.isSignedIn()
                        )
                    }
                    val range = currentRange
                    if (range != null && hasPro && !isChecking) {
                        loadHistory(range)
                    }
                }
        }
    }

    fun prepare(range: DashboardTimeRange) {
        currentRange = range
        viewModelScope.launch {
            val isSignedIn = repository.isSignedIn()
            _uiState.update {
                it.copy(
                    isSignedIn = isSignedIn,
                    errorMessage = null,
                    isConfirmingRegeneration = false
                )
            }

            runCatching { repository.prepare(range) }
                .onSuccess { prepared ->
                    _uiState.update { current ->
                        if (current.preparedFingerprint == prepared.fingerprint && current.response != null) {
                            current.copy(hasData = prepared.hasData)
                        } else {
                            val cached = prepared.cachedEntry
                            current.copy(
                                response = cached?.response,
                                generatedAtMillis = cached?.generatedAtMillis,
                                selectedReportId = cached?.response?.reportId,
                                hasData = prepared.hasData,
                                preparedFingerprint = prepared.fingerprint,
                                errorMessage = null
                            )
                        }
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            response = null,
                            generatedAtMillis = null,
                            selectedReportId = null,
                            hasData = false,
                            errorMessage = userFacingError(error)
                        )
                    }
                }

            if (_uiState.value.hasProAccess && isSignedIn) {
                loadHistory(range)
            }
        }
    }

    fun onPrimaryAction(range: DashboardTimeRange) {
        val state = _uiState.value
        if (state.isLoading || state.isCheckingAccess) return
        if (!state.hasProAccess) return
        if (!state.isSignedIn) {
            _uiState.update { it.copy(errorMessage = "Please sign in to generate AI insights.") }
            return
        }
        if (state.usage?.remaining == 0) return

        if (state.response != null) {
            _uiState.update { it.copy(isConfirmingRegeneration = true) }
        } else {
            generate(range, forceRefresh = false)
        }
    }

    fun confirmRegeneration(range: DashboardTimeRange) {
        _uiState.update { it.copy(isConfirmingRegeneration = false) }
        generate(range, forceRefresh = true)
    }

    fun cancelRegeneration() {
        _uiState.update { it.copy(isConfirmingRegeneration = false) }
    }

    fun selectReport(report: AIInsightsReport) {
        _uiState.update {
            it.copy(
                response = report.response(),
                generatedAtMillis = parseInstantMillis(report.createdAt),
                selectedReportId = report.id,
                errorMessage = null,
                isConfirmingRegeneration = false
            )
        }
    }

    private fun generate(range: DashboardTimeRange, forceRefresh: Boolean) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null
                )
            }

            runCatching { repository.generate(range, forceRefresh) }
                .onSuccess { (response, cacheEntry) ->
                    val reports = response.history.orEmpty()
                    _uiState.update {
                        it.copy(
                            response = response,
                            generatedAtMillis = cacheEntry.generatedAtMillis,
                            selectedReportId = response.reportId,
                            usage = response.usage ?: it.usage,
                            history = if (reports.isNotEmpty()) reports else it.history,
                            isLoading = false,
                            errorMessage = null,
                            preparedFingerprint = cacheEntry.fingerprint
                        )
                    }
                }
                .onFailure { error ->
                    val usage = (error as? AIInsightsHttpException)?.response?.usage
                    _uiState.update {
                        it.copy(
                            usage = usage ?: it.usage,
                            isLoading = false,
                            errorMessage = userFacingError(error)
                        )
                    }
                }
        }
    }

    private fun loadHistory(range: DashboardTimeRange) {
        if (_uiState.value.isHistoryLoading) return
        viewModelScope.launch {
            _uiState.update { it.copy(isHistoryLoading = true) }
            runCatching { repository.loadHistory(range) }
                .onSuccess { (reports, usage) ->
                    _uiState.update {
                        it.copy(
                            history = reports,
                            usage = usage ?: it.usage,
                            isHistoryLoading = false
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isHistoryLoading = false,
                            errorMessage = if (it.response == null) userFacingError(error) else it.errorMessage
                        )
                    }
                }
        }
    }

    private fun userFacingError(error: Throwable): String {
        val response = (error as? AIInsightsHttpException)?.response
        return when (response?.code) {
            "AI_INSIGHTS_LIMIT_REACHED" -> "AI insights daily limit reached."
            "AI_INSIGHTS_LANGUAGE_MISMATCH" -> "Please try again."
            else -> response?.error?.trim()?.takeIf { it.isNotEmpty() }
                ?: error.message?.takeIf { it.isNotBlank() }
                ?: "Unable to generate AI insights right now."
        }
    }
}

fun AIInsightsUsage.resetDisplayText(): String? {
    val millis = resetsAt?.let(::parseInstantMillis) ?: return null
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
        .format(Date(millis))
}

fun AIInsightsReport.displayDateText(): String {
    val millis = parseInstantMillis(createdAt) ?: return createdAt
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
        .format(Date(millis))
}

fun Long.displayGeneratedAtText(): String {
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, Locale.getDefault())
        .format(Date(this))
}

private fun parseInstantMillis(value: String?): Long? {
    if (value.isNullOrBlank()) return null
    return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
}
