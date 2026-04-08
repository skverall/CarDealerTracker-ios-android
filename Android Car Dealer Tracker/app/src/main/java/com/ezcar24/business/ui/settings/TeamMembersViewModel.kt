package com.ezcar24.business.ui.settings

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.repository.TeamInviteResult
import com.ezcar24.business.data.repository.TeamMemberAccess
import com.ezcar24.business.util.TeamPermissionCatalog
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class TeamMembersUiState(
    val activeOrganization: OrganizationMembership? = null,
    val members: List<TeamMemberAccess> = emptyList(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val message: String? = null,
    val error: String? = null,
    val lastInviteResult: TeamInviteResult? = null
)

@HiltViewModel
class TeamMembersViewModel @Inject constructor(
    private val accountRepository: AccountRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TeamMembersUiState())
    val uiState: StateFlow<TeamMembersUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val organization = accountRepository.activeOrganization.value
                    ?: run {
                        accountRepository.refreshOrganizations()
                        accountRepository.activeOrganization.value
                    }

                if (organization == null) {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            activeOrganization = null,
                            members = emptyList(),
                            error = "No active business found."
                        )
                    }
                    return@launch
                }

                val members = accountRepository.fetchTeamMembers(organization.organizationId)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        activeOrganization = organization,
                        members = members
                    )
                }
            } catch (e: Exception) {
                Log.e(TEAM_MEMBERS_TAG, "refresh failed", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = UserFacingErrorMapper.map(e, UserFacingErrorContext.LOAD_TEAM)
                    )
                }
            }
        }
    }

    fun inviteMember(
        email: String,
        role: String,
        createAccount: Boolean,
        permissions: Map<String, Boolean>
    ) {
        val organization = _uiState.value.activeOrganization ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null, message = null, lastInviteResult = null) }
            try {
                val inviteResult = accountRepository.inviteMember(
                    email = email,
                    role = role,
                    organizationId = organization.organizationId,
                    createAccount = createAccount,
                    permissions = TeamPermissionCatalog.resolvedPermissions(permissions, role)
                )
                val members = accountRepository.fetchTeamMembers(organization.organizationId)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        members = members,
                        lastInviteResult = inviteResult,
                        message = inviteResult.message?.let {
                            UserFacingErrorMapper.map(it, UserFacingErrorContext.INVITE_TEAM_MEMBER)
                        } ?: "Invite sent successfully."
                    )
                }
            } catch (e: Exception) {
                Log.e(TEAM_MEMBERS_TAG, "inviteMember failed", e)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        error = UserFacingErrorMapper.map(e, UserFacingErrorContext.INVITE_TEAM_MEMBER)
                    )
                }
            }
        }
    }

    fun updateAccess(
        member: TeamMemberAccess,
        role: String,
        permissions: Map<String, Boolean>
    ) {
        val organization = _uiState.value.activeOrganization ?: return
        if (!member.canEditRole) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null, message = null) }
            try {
                if (member.isInvited) {
                    accountRepository.updateInviteRole(
                        organization.organizationId,
                        member.id,
                        role,
                        TeamPermissionCatalog.resolvedPermissions(permissions, role)
                    )
                } else {
                    accountRepository.updateMemberRole(
                        organization.organizationId,
                        member.id,
                        role,
                        TeamPermissionCatalog.resolvedPermissions(permissions, role)
                    )
                }
                val members = accountRepository.fetchTeamMembers(organization.organizationId)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        members = members,
                        message = "Access updated."
                    )
                }
            } catch (e: Exception) {
                Log.e(TEAM_MEMBERS_TAG, "updateAccess failed", e)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        error = UserFacingErrorMapper.map(e, UserFacingErrorContext.UPDATE_TEAM_ACCESS)
                    )
                }
            }
        }
    }

    fun removeMember(member: TeamMemberAccess) {
        val organization = _uiState.value.activeOrganization ?: return
        if (!member.canEditRole) return
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null, message = null) }
            try {
                if (member.isInvited) {
                    accountRepository.cancelInvite(organization.organizationId, member.id)
                } else {
                    accountRepository.removeMember(organization.organizationId, member.id)
                }
                val members = accountRepository.fetchTeamMembers(organization.organizationId)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        members = members,
                        message = if (member.isInvited) "Invite removed." else "Member removed."
                    )
                }
            } catch (e: Exception) {
                Log.e(TEAM_MEMBERS_TAG, "removeMember failed", e)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        error = UserFacingErrorMapper.map(e, UserFacingErrorContext.REMOVE_TEAM_MEMBER)
                    )
                }
            }
        }
    }

    fun clearMessages() {
        _uiState.update { it.copy(message = null, error = null) }
    }

    fun consumeInviteResult() {
        _uiState.update { it.copy(lastInviteResult = null) }
    }
}

private const val TEAM_MEMBERS_TAG = "TeamMembersViewModel"
