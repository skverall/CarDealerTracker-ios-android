package com.ezcar24.business.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.User
import com.ezcar24.business.data.local.UserDao
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import java.util.Date

data class TeamMembersUiState(
    val users: List<User> = emptyList(),
    val isLoading: Boolean = false,
    val isInviting: Boolean = false,
    val inviteError: String? = null,
    val inviteSuccess: String? = null
)

@HiltViewModel
class TeamMembersViewModel @Inject constructor(
    private val userDao: UserDao,
    private val cloudSyncManager: com.ezcar24.business.data.sync.CloudSyncManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(TeamMembersUiState())
    val uiState: StateFlow<TeamMembersUiState> = _uiState.asStateFlow()

    init {
        loadUsers()
    }

    fun loadUsers() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            userDao.getAllActive().collect { users ->
                 _uiState.update { it.copy(users = users, isLoading = false) }
            }
        }
    }

    fun addTeamMember(name: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isInviting = true, inviteError = null, inviteSuccess = null) }
            try {
                val newUser = User(
                    id = UUID.randomUUID(),
                    name = name,
                    createdAt = Date(),
                    updatedAt = Date(),
                    deletedAt = null
                )
                cloudSyncManager.upsertUser(newUser)
                
                _uiState.update { 
                    it.copy(
                        isInviting = false, 
                        inviteSuccess = "Added $name to team"
                    ) 
                }
            } catch (e: Exception) {
                _uiState.update { 
                    it.copy(
                        isInviting = false, 
                        inviteError = "Failed to add member: ${e.message}" 
                    ) 
                }
            }
        }
    }
    
    fun clearMessages() {
        _uiState.update { it.copy(inviteError = null, inviteSuccess = null) }
    }
}
