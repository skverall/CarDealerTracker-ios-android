package com.ezcar24.business.ui.client

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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

data class ClientDetailUiState(
    val client: Client? = null,
    val interactions: List<ClientInteraction> = emptyList(),
    val reminders: List<ClientReminder> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false
)

@HiltViewModel
class ClientDetailViewModel @Inject constructor(
    private val clientDao: ClientDao,
    private val interactionDao: ClientInteractionDao,
    private val reminderDao: ClientReminderDao,
    private val cloudSyncManager: CloudSyncManager,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(ClientDetailUiState())
    val uiState: StateFlow<ClientDetailUiState> = _uiState.asStateFlow()

    private val clientIdString: String? = savedStateHandle.get<String>("clientId")

    init {
        if (clientIdString != null && clientIdString != "new") {
            loadClient(UUID.fromString(clientIdString))
        }
    }

    private fun loadClient(id: UUID) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val client = clientDao.getById(id)
            val interactions = interactionDao.getByClient(id)
            val reminders = reminderDao.getByClient(id)
            _uiState.update { 
                it.copy(
                    client = client, 
                    interactions = interactions,
                    reminders = reminders,
                    isLoading = false
                )
            }
        }
    }

    fun saveClient(
        name: String,
        phone: String,
        email: String,
        notes: String,
        status: String?
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true) }
            val now = Date()
            val id = if (clientIdString != null && clientIdString != "new") UUID.fromString(clientIdString) else UUID.randomUUID()
            
            val currentClient = if (clientIdString != null && clientIdString != "new") clientDao.getById(id) else null

            val client = currentClient?.copy(
                name = name,
                phone = phone,
                email = email,
                notes = notes,
                status = status,
                updatedAt = now
            ) ?: Client(
                id = id,
                name = name,
                phone = phone,
                email = email,
                notes = notes,
                status = status ?: "new",
                createdAt = now,
                updatedAt = now,
                deletedAt = null,
                vehicleId = null,
                requestDetails = null,
                preferredDate = null
            )

            clientDao.upsert(client)
            _uiState.update { it.copy(isSaving = false) }
            // Trigger sync if needed
        }
    }

    fun addInteraction(type: String, notes: String, date: Date = Date()) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val interaction = ClientInteraction(
                id = UUID.randomUUID(),
                clientId = client.id,
                title = type, // Mapping type to title
                detail = notes, // Mapping notes to detail
                occurredAt = date,
                stage = "update",
                value = null
            )
            interactionDao.upsert(interaction)
            loadClient(client.id)
        }
    }

    fun deleteInteraction(id: UUID) {
        // Not implemented (missing DELETE in DAO for single item)
    }

    fun addReminder(title: String, dueDate: Date) {
        val client = _uiState.value.client ?: return
        viewModelScope.launch {
            val reminder = ClientReminder(
                id = UUID.randomUUID(),
                clientId = client.id,
                title = title,
                dueDate = dueDate,
                isCompleted = false,
                createdAt = Date(),
                notes = null
            )
            reminderDao.upsert(reminder)
            loadClient(client.id)
        }
    }

    fun toggleReminder(reminder: ClientReminder) {
         viewModelScope.launch {
             // ClientReminder is immutable and missing updatedAt/deletedAt in schema.
             // Just upsert a copy.
             reminderDao.upsert(reminder.copy(isCompleted = !reminder.isCompleted))
             _uiState.value.client?.let { loadClient(it.id) }
         }
    }
}
