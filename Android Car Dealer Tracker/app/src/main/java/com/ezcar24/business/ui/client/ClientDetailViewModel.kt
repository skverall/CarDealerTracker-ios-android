package com.ezcar24.business.ui.client

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.*
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.notification.NotificationScheduler
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ClientDetailUiState(
    val client: Client? = null,
    val vehicles: List<Vehicle> = emptyList(),
    val interactions: List<ClientInteraction> = emptyList(),
    val reminders: List<ClientReminder> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val saveCompleted: Boolean = false,
    val errorMessage: String? = null
)

@HiltViewModel
class ClientDetailViewModel @Inject constructor(
    private val clientDao: ClientDao,
    private val vehicleDao: VehicleDao,
    private val interactionDao: ClientInteractionDao,
    private val reminderDao: ClientReminderDao,
    private val cloudSyncManager: CloudSyncManager,
    private val notificationScheduler: NotificationScheduler,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(ClientDetailUiState())
    val uiState: StateFlow<ClientDetailUiState> = _uiState.asStateFlow()

    private val clientIdString: String? = savedStateHandle.get<String>("clientId")

    init {
        viewModelScope.launch {
            vehicleDao.getAllActive().collect { vehicles ->
                _uiState.update { it.copy(vehicles = vehicles) }
            }
        }
        if (clientIdString != null && clientIdString != "new") {
            loadClient(UUID.fromString(clientIdString))
        }
    }

    private fun loadClient(id: UUID) {
        viewModelScope.launch {
            reloadClient(id)
        }
    }

    fun saveClient(
        name: String,
        phone: String,
        email: String,
        notes: String,
        requestDetails: String,
        preferredDate: Date,
        vehicleId: UUID?,
        status: String?,
        leadStage: LeadStage = LeadStage.new,
        leadSource: LeadSource? = null,
        estimatedValue: java.math.BigDecimal? = null,
        priority: Int = 0
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, errorMessage = null, saveCompleted = false) }
            val now = Date()
            val id = if (clientIdString != null && clientIdString != "new") UUID.fromString(clientIdString) else UUID.randomUUID()
            
            val currentClient = if (clientIdString != null && clientIdString != "new") clientDao.getById(id) else null

            val client = currentClient?.copy(
                name = name,
                phone = phone,
                email = email,
                notes = notes,
                requestDetails = requestDetails.ifBlank { null },
                preferredDate = preferredDate,
                vehicleId = vehicleId,
                status = status,
                leadStage = leadStage,
                leadSource = leadSource,
                estimatedValue = estimatedValue,
                priority = priority,
                updatedAt = now
            ) ?: Client(
                id = id,
                name = name,
                phone = phone,
                email = email,
                notes = notes,
                requestDetails = requestDetails.ifBlank { null },
                preferredDate = preferredDate,
                status = status ?: "new",
                leadStage = leadStage,
                leadSource = leadSource,
                estimatedValue = estimatedValue,
                priority = priority,
                leadCreatedAt = now,
                createdAt = now,
                updatedAt = now,
                deletedAt = null,
                vehicleId = vehicleId
            )

            try {
                cloudSyncManager.upsertClient(client)
                _uiState.update {
                    it.copy(
                        client = client,
                        isSaving = false,
                        saveCompleted = true,
                        errorMessage = null
                    )
                }
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "saveClient failed", e)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.SAVE_CLIENT)
                    )
                }
            }
        }
    }

    fun addInteraction(
        type: String,
        title: String,
        detail: String,
        outcome: String? = null,
        durationMinutes: Int? = null,
        isFollowUpRequired: Boolean = false,
        value: BigDecimal? = null,
        date: Date = Date()
    ) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val interaction = ClientInteraction(
                id = UUID.randomUUID(),
                clientId = client.id,
                title = title,
                detail = detail,
                occurredAt = date,
                stage = client.leadStage.name,
                value = value,
                interactionType = type,
                outcome = outcome,
                durationMinutes = durationMinutes,
                isFollowUpRequired = isFollowUpRequired
            )
            try {
                cloudSyncManager.upsertClientInteraction(interaction)
                val updatedClient = client.copy(lastContactAt = date, updatedAt = date)
                cloudSyncManager.upsertClient(updatedClient)
                reloadClient(client.id)
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "addInteraction failed", e)
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            e,
                            UserFacingErrorContext.SAVE_CLIENT_INTERACTION
                        )
                    )
                }
            }
        }
    }

    fun deleteInteraction(id: UUID) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val interaction = interactionDao.getById(id) ?: return@launch
            try {
                cloudSyncManager.deleteClientInteraction(interaction)
                reloadClient(client.id)
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "deleteInteraction failed", e)
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            e,
                            UserFacingErrorContext.DELETE_CLIENT_INTERACTION
                        )
                    )
                }
            }
        }
    }

    fun addReminder(title: String, dueDate: Date, notes: String?) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val reminder = ClientReminder(
                id = UUID.randomUUID(),
                clientId = client.id,
                title = title,
                dueDate = dueDate,
                isCompleted = false,
                createdAt = Date(),
                notes = notes?.takeIf { it.isNotBlank() }
            )
            try {
                reminderDao.upsert(reminder)
                syncReminderState(client.id)
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "addReminder failed", e)
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            e,
                            UserFacingErrorContext.SAVE_CLIENT_REMINDER
                        )
                    )
                }
            }
        }
    }

    fun toggleReminder(reminder: ClientReminder) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            try {
                reminderDao.upsert(reminder.copy(isCompleted = !reminder.isCompleted))
                syncReminderState(client.id)
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "toggleReminder failed", e)
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            e,
                            UserFacingErrorContext.UPDATE_CLIENT_REMINDER
                        )
                    )
                }
            }
        }
    }

    fun deleteReminder(reminder: ClientReminder) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            try {
                reminderDao.delete(reminder)
                syncReminderState(client.id)
            } catch (e: Exception) {
                Log.e(CLIENT_DETAIL_TAG, "deleteReminder failed", e)
                _uiState.update {
                    it.copy(
                        errorMessage = UserFacingErrorMapper.map(
                            e,
                            UserFacingErrorContext.DELETE_CLIENT_REMINDER
                        )
                    )
                }
            }
        }
    }

    fun updateLeadStage(stage: LeadStage) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val updatedClient = client.copy(
                leadStage = stage,
                updatedAt = Date()
            )
            persistClientUpdate(updatedClient)
        }
    }

    fun updateLeadSource(source: LeadSource?) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val updatedClient = client.copy(
                leadSource = source,
                updatedAt = Date()
            )
            persistClientUpdate(updatedClient)
        }
    }

    fun updatePriority(priority: Int) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val updatedClient = client.copy(
                priority = priority,
                updatedAt = Date()
            )
            persistClientUpdate(updatedClient)
        }
    }

    fun updateEstimatedValue(value: java.math.BigDecimal?) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val updatedClient = client.copy(
                estimatedValue = value,
                updatedAt = Date()
            )
            persistClientUpdate(updatedClient)
        }
    }

    fun consumeSaveCompleted() {
        _uiState.update { it.copy(saveCompleted = false) }
    }

    fun clearErrorMessage() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    fun calculateLeadScore(): Int {
        val client = _uiState.value.client ?: return 0
        val interactions = _uiState.value.interactions
        return com.ezcar24.business.util.calculator.LeadFunnelCalculator.calculateLeadScore(client, interactions)
    }

    private suspend fun reloadClient(id: UUID) {
        _uiState.update { it.copy(isLoading = true) }
        val client = clientDao.getById(id)
        val interactions = interactionDao.getByClient(id)
        val reminders = reminderDao.getByClient(id)
        _uiState.update {
            it.copy(
                client = client,
                interactions = interactions,
                reminders = reminders,
                isLoading = false,
                errorMessage = null
            )
        }
    }

    private suspend fun syncReminderState(clientId: UUID) {
        val client = clientDao.getById(clientId)
        val reminders = reminderDao.getByClient(clientId)
        notificationScheduler.refreshAll()

        try {
            if (client != null) {
                val nextFollowUpAt = reminders
                    .filterNot { it.isCompleted }
                    .map { it.dueDate }
                    .minOrNull()

                if (client.nextFollowUpAt != nextFollowUpAt) {
                    cloudSyncManager.upsertClient(
                        client.copy(
                            nextFollowUpAt = nextFollowUpAt,
                            updatedAt = Date()
                        )
                    )
                }
            }
        } finally {
            reloadClient(clientId)
        }
    }

    private suspend fun persistClientUpdate(client: Client) {
        try {
            cloudSyncManager.upsertClient(client)
            reloadClient(client.id)
        } catch (e: Exception) {
            Log.e(CLIENT_DETAIL_TAG, "persistClientUpdate failed", e)
            _uiState.update {
                it.copy(errorMessage = UserFacingErrorMapper.map(e, UserFacingErrorContext.UPDATE_CLIENT))
            }
        }
    }
}

private const val CLIENT_DETAIL_TAG = "ClientDetailViewModel"
