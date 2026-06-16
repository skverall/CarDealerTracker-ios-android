package com.ezcar24.business.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AppFeedbackRequest
import com.ezcar24.business.data.repository.FeedbackRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class FeedbackBoardUiState(
    val requests: List<AppFeedbackRequest> = emptyList(),
    val isLoading: Boolean = false,
    val isSubmitting: Boolean = false,
    val errorMessage: String? = null,
    val composerError: String? = null,
    val togglingVotes: Set<UUID> = emptySet(),
    val deletingRequests: Set<UUID> = emptySet(),
    val updatingStatuses: Set<UUID> = emptySet()
)

@HiltViewModel
class FeedbackBoardViewModel @Inject constructor(
    private val repository: FeedbackRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow(FeedbackBoardUiState())
    val uiState: StateFlow<FeedbackBoardUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            runCatching { repository.fetchRequests() }
                .onSuccess { requests ->
                    _uiState.update {
                        it.copy(
                            requests = requests,
                            isLoading = false,
                            errorMessage = null
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = error.message ?: "Unable to load ideas."
                        )
                    }
                }
        }
    }

    fun createRequest(title: String, details: String?, language: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSubmitting = true, composerError = null) }
            runCatching {
                repository.createRequest(
                    title = title,
                    details = details,
                    platform = "android",
                    language = language
                )
            }.onSuccess {
                _uiState.update { it.copy(isSubmitting = false, composerError = null) }
                onSuccess()
                load()
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        isSubmitting = false,
                        composerError = error.message ?: "Unable to send idea."
                    )
                }
            }
        }
    }

    fun toggleVote(requestId: UUID) {
        if (_uiState.value.togglingVotes.contains(requestId)) return
        viewModelScope.launch {
            _uiState.update { it.copy(togglingVotes = it.togglingVotes + requestId) }
            runCatching { repository.toggleVote(requestId) }
                .onSuccess { result ->
                    if (result != null) {
                        _uiState.update { state ->
                            val updated = state.requests.map { request ->
                                if (request.id == requestId) {
                                    request.copy(
                                        hasVoted = result.voted,
                                        voteCount = result.voteCount
                                    )
                                } else {
                                    request
                                }
                            }.sortedWith(feedbackRequestComparator)
                            state.copy(
                                requests = updated,
                                togglingVotes = state.togglingVotes - requestId
                            )
                        }
                    } else {
                        _uiState.update { it.copy(togglingVotes = it.togglingVotes - requestId) }
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            togglingVotes = it.togglingVotes - requestId,
                            errorMessage = error.message ?: "Unable to update vote."
                        )
                    }
                }
        }
    }

    fun deleteRequest(requestId: UUID) {
        if (_uiState.value.deletingRequests.contains(requestId)) return
        viewModelScope.launch {
            _uiState.update { it.copy(deletingRequests = it.deletingRequests + requestId) }
            runCatching { repository.deleteRequest(requestId) }
                .onSuccess {
                    _uiState.update { state ->
                        state.copy(
                            requests = state.requests.filterNot { it.id == requestId },
                            deletingRequests = state.deletingRequests - requestId
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            deletingRequests = it.deletingRequests - requestId,
                            errorMessage = error.message ?: "Unable to delete idea."
                        )
                    }
                }
        }
    }

    fun markDone(requestId: UUID) {
        if (_uiState.value.updatingStatuses.contains(requestId)) return
        viewModelScope.launch {
            _uiState.update { it.copy(updatingStatuses = it.updatingStatuses + requestId) }
            runCatching { repository.setStatus(requestId, "shipped") }
                .onSuccess { result ->
                    if (result != null) {
                        _uiState.update { state ->
                            val updated = state.requests.map { request ->
                                if (request.id == requestId) {
                                    request.copy(
                                        status = result.status,
                                        completedAt = result.completedAt
                                    )
                                } else {
                                    request
                                }
                            }.sortedWith(feedbackRequestComparator)
                            state.copy(
                                requests = updated,
                                updatingStatuses = state.updatingStatuses - requestId
                            )
                        }
                    } else {
                        _uiState.update { it.copy(updatingStatuses = it.updatingStatuses - requestId) }
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            updatingStatuses = it.updatingStatuses - requestId,
                            errorMessage = error.message ?: "Unable to mark idea done."
                        )
                    }
                }
        }
    }

    fun clearComposerError() {
        _uiState.update { it.copy(composerError = null) }
    }
}

private fun feedbackStatusRank(status: String): Int {
    return when (status) {
        "open" -> 1
        "planned" -> 2
        "in_progress" -> 3
        "closed" -> 4
        "shipped" -> 5
        else -> 6
    }
}

private val feedbackRequestComparator =
    compareBy<AppFeedbackRequest> { feedbackStatusRank(it.status) }
        .thenByDescending { it.voteCount }
        .thenByDescending { it.createdAt.time }
