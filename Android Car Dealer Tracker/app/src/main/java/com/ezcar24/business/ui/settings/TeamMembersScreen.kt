package com.ezcar24.business.ui.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Leaderboard
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PointOfSale
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.repository.TeamInviteResult
import com.ezcar24.business.data.repository.TeamMemberAccess
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.util.PermissionOption
import com.ezcar24.business.util.TeamPermissionCatalog
import java.util.Locale

private val TeamRoles = TeamPermissionCatalog.roles

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamMembersScreen(
    onBack: () -> Unit,
    viewModel: TeamMembersViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var showInviteDialog by remember { mutableStateOf(false) }
    var memberToEdit by remember { mutableStateOf<TeamMemberAccess?>(null) }
    var memberToDelete by remember { mutableStateOf<TeamMemberAccess?>(null) }

    Scaffold(
        containerColor = EzcarBackgroundLight,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = "Team Management",
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        uiState.activeOrganization?.let {
                            Text(
                                text = it.organizationName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = EzcarNavy)
                    }
                },
                actions = {
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = !uiState.isLoading && !uiState.isSaving
                    ) {
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = EzcarNavy
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.People,
                                contentDescription = "Refresh",
                                tint = EzcarNavy
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        },
        floatingActionButton = {
            Button(
                onClick = { showInviteDialog = true },
                enabled = uiState.activeOrganization != null && !uiState.isSaving,
                colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy)
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Invite")
            }
        }
    ) { padding ->
        when {
            uiState.isLoading && uiState.members.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = EzcarNavy)
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    uiState.error?.let { error ->
                        item {
                            TeamStatusCard(
                                text = error,
                                color = EzcarDanger,
                                onDismiss = viewModel::clearMessages
                            )
                        }
                    }

                    uiState.message?.let { message ->
                        item {
                            TeamStatusCard(
                                text = message,
                                color = EzcarGreen,
                                onDismiss = viewModel::clearMessages
                            )
                        }
                    }

                    item {
                        TeamSummaryCard(
                            organizationName = uiState.activeOrganization?.organizationName,
                            role = uiState.activeOrganization?.role,
                            memberCount = uiState.members.count { !it.isInvited },
                            inviteCount = uiState.members.count { it.isInvited }
                        )
                    }

                    if (uiState.members.isEmpty()) {
                        item {
                            EmptyTeamState()
                        }
                    } else {
                        items(uiState.members, key = { it.id }) { member ->
                            TeamMemberCard(
                                member = member,
                                isSaving = uiState.isSaving,
                                onChangeRole = {
                                    if (member.canEditRole) {
                                        memberToEdit = member
                                    }
                                },
                                onRemove = {
                                    if (member.canEditRole) {
                                        memberToDelete = member
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showInviteDialog) {
        InviteMemberDialog(
            isLoading = uiState.isSaving,
            onDismiss = { showInviteDialog = false },
            onInvite = { email, role, createAccount, permissions ->
                showInviteDialog = false
                viewModel.inviteMember(email, role, createAccount, permissions)
            }
        )
    }

    memberToEdit?.let { member ->
        MemberRoleDialog(
            member = member,
            isLoading = uiState.isSaving,
            onDismiss = { memberToEdit = null },
            onSave = { role, permissions ->
                memberToEdit = null
                viewModel.updateAccess(member, role, permissions)
            }
        )
    }

    memberToDelete?.let { member ->
        DeleteMemberDialog(
            member = member,
            isLoading = uiState.isSaving,
            onDismiss = { memberToDelete = null },
            onConfirm = {
                memberToDelete = null
                viewModel.removeMember(member)
            }
        )
    }

    uiState.lastInviteResult?.let { inviteResult ->
        InviteResultDialog(
            inviteResult = inviteResult,
            onDismiss = viewModel::consumeInviteResult,
            onCopy = { value ->
                copyTeamValue(context, value)
            }
        )
    }
}

@Composable
private fun TeamStatusCard(
    text: String,
    color: androidx.compose.ui.graphics.Color,
    onDismiss: () -> Unit
) {
    Surface(
        color = color.copy(alpha = 0.12f),
        shape = RoundedCornerShape(18.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = text,
                color = color,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onDismiss) {
                Text("Dismiss", color = color)
            }
        }
    }
}

@Composable
private fun TeamSummaryCard(
    organizationName: String?,
    role: String?,
    memberCount: Int,
    inviteCount: Int
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 6.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = organizationName ?: "No active business",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
            Text(
                text = role?.replaceFirstChar { it.titlecase(Locale.getDefault()) }
                    ?: "Switch to a business in Account first",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TeamMetricPill(
                    label = "Active",
                    value = memberCount.toString(),
                    color = EzcarBlueBright
                )
                TeamMetricPill(
                    label = "Invited",
                    value = inviteCount.toString(),
                    color = EzcarOrange
                )
            }
        }
    }
}

@Composable
private fun TeamMetricPill(
    label: String,
    value: String,
    color: androidx.compose.ui.graphics.Color
) {
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = value,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = color
        )
    }
}

@Composable
private fun EmptyTeamState() {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .background(EzcarBlueBright.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.People,
                    contentDescription = null,
                    tint = EzcarBlueBright,
                    modifier = Modifier.size(30.dp)
                )
            }
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = "No team members yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Invite teammates by email and assign the correct role.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun TeamMemberCard(
    member: TeamMemberAccess,
    isSaving: Boolean,
    onChangeRole: () -> Unit,
    onRemove: () -> Unit
) {
    val accentColor = if (member.isInvited) EzcarOrange else EzcarBlueBright

    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(18.dp),
        shadowElevation = 4.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .background(accentColor.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = member.email?.take(1)?.uppercase(Locale.getDefault()).orEmpty().ifBlank { "?" },
                        fontWeight = FontWeight.Bold,
                        color = accentColor
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = member.email ?: "Unknown user",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = EzcarNavy
                    )
                    Text(
                        text = if (member.isInvited) "Pending invite" else "Active member",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TeamRoleBadge(role = member.role, isInvited = member.isInvited)
            }

            Text(
                text = TeamPermissionCatalog.permissionSummary(member.permissions, member.role),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (member.canEditRole) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    TextButton(
                        onClick = onChangeRole,
                        enabled = !isSaving
                    ) {
                        Text("Change Role")
                    }
                    TextButton(
                        onClick = onRemove,
                        enabled = !isSaving
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = null,
                            tint = EzcarDanger
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Remove", color = EzcarDanger)
                    }
                }
            }
        }
    }
}

@Composable
private fun TeamRoleBadge(role: String, isInvited: Boolean) {
    val color = when (role) {
        "admin" -> EzcarBlueBright
        "sales" -> EzcarGreen
        "viewer" -> EzcarOrange
        else -> EzcarNavy
    }
    Text(
        text = buildString {
            append(role.replaceFirstChar { it.titlecase(Locale.getDefault()) })
            if (isInvited) append(" • Invite")
        },
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        style = MaterialTheme.typography.labelMedium,
        color = color,
        fontWeight = FontWeight.Bold
    )
}

@Composable
private fun InviteMemberDialog(
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onInvite: (String, String, Boolean, Map<String, Boolean>) -> Unit
) {
    var email by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("sales") }
    var createAccount by remember { mutableStateOf(false) }
    var permissions by remember { mutableStateOf(TeamPermissionCatalog.defaultPermissions(role)) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Invite Team Member") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Email") },
                    singleLine = true,
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.MailOutline,
                            contentDescription = null
                        )
                    }
                )
                Text(
                    text = "Role",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TeamRoles.forEach { option ->
                        val selected = option == role
                        Button(
                            onClick = {
                                role = option
                                permissions = TeamPermissionCatalog.defaultPermissions(option)
                            },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (selected) EzcarNavy else MaterialTheme.colorScheme.surfaceVariant,
                                contentColor = if (selected) androidx.compose.ui.graphics.Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(option.replaceFirstChar { it.titlecase(Locale.getDefault()) })
                        }
                    }
                }
                Text(
                    text = TeamPermissionCatalog.roleSummary(role),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Create account now",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "Create a login immediately instead of sending only an invite code.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Switch(
                        checked = createAccount,
                        onCheckedChange = { createAccount = it }
                    )
                }
                PermissionMatrix(
                    role = role,
                    permissions = permissions,
                    onPermissionChange = { key, enabled ->
                        permissions = permissions.toMutableMap().apply { put(key, enabled) }
                    },
                    onReset = {
                        permissions = TeamPermissionCatalog.defaultPermissions(role)
                    }
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onInvite(
                        email,
                        role,
                        createAccount,
                        TeamPermissionCatalog.resolvedPermissions(permissions, role)
                    )
                },
                enabled = email.trim().isNotEmpty() && !isLoading
            ) {
                Text(if (isLoading) "Inviting..." else "Invite")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun MemberRoleDialog(
    member: TeamMemberAccess,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onSave: (String, Map<String, Boolean>) -> Unit
) {
    var role by remember(member.id) { mutableStateOf(member.role) }
    var permissions by remember(member.id) {
        mutableStateOf(TeamPermissionCatalog.resolvedPermissions(member.permissions, member.role))
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Update Access") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = member.email ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TeamRoles.forEach { option ->
                        val selected = option == role
                        Button(
                            onClick = {
                                role = option
                                permissions = TeamPermissionCatalog.defaultPermissions(option)
                            },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (selected) EzcarNavy else MaterialTheme.colorScheme.surfaceVariant,
                                contentColor = if (selected) androidx.compose.ui.graphics.Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                            ),
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(option.replaceFirstChar { it.titlecase(Locale.getDefault()) })
                        }
                    }
                }
                Text(
                    text = TeamPermissionCatalog.roleSummary(role),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                PermissionMatrix(
                    role = role,
                    permissions = permissions,
                    onPermissionChange = { key, enabled ->
                        permissions = permissions.toMutableMap().apply { put(key, enabled) }
                    },
                    onReset = {
                        permissions = TeamPermissionCatalog.defaultPermissions(role)
                    }
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onSave(
                        role,
                        TeamPermissionCatalog.resolvedPermissions(permissions, role)
                    )
                },
                enabled = !isLoading && (
                    role != member.role ||
                        TeamPermissionCatalog.resolvedPermissions(permissions, role) != TeamPermissionCatalog.resolvedPermissions(member.permissions, member.role)
                    )
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun DeleteMemberDialog(
    member: TeamMemberAccess,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (member.isInvited) "Remove Invite" else "Remove Member") },
        text = {
            Text(
                if (member.isInvited) {
                    "This will cancel the pending invite for ${member.email}."
                } else {
                    "This will remove ${member.email} from the team."
                }
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                enabled = !isLoading,
                colors = ButtonDefaults.buttonColors(containerColor = EzcarDanger)
            ) {
                Text("Remove")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun PermissionMatrix(
    role: String,
    permissions: Map<String, Boolean>,
    onPermissionChange: (String, Boolean) -> Unit,
    onReset: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Access",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onReset) {
                Text("Reset")
            }
        }
        TeamPermissionCatalog.permissions.forEach { option ->
            PermissionToggleCard(
                option = option,
                checked = permissions[option.key] == true,
                onCheckedChange = { enabled ->
                    onPermissionChange(option.key, enabled)
                }
            )
        }
    }
}

@Composable
private fun PermissionToggleCard(
    option: PermissionOption,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
        shape = RoundedCornerShape(14.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(EzcarBlueBright.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = permissionIcon(option.key),
                    contentDescription = null,
                    tint = EzcarBlueBright
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = option.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = option.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange
            )
        }
    }
}

@Composable
private fun InviteResultDialog(
    inviteResult: TeamInviteResult,
    onDismiss: () -> Unit,
    onCopy: (String) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Invite Ready") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                inviteResult.message?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium)
                }
                inviteResult.inviteCode?.let { code ->
                    ResultValueRow(
                        label = "Invite code",
                        value = code,
                        onCopy = { onCopy(code) }
                    )
                }
                inviteResult.generatedPassword?.let { password ->
                    ResultValueRow(
                        label = "Generated password",
                        value = password,
                        onCopy = { onCopy(password) }
                    )
                }
                inviteResult.inviteUrl?.let { url ->
                    ResultValueRow(
                        label = "Fallback link",
                        value = url,
                        onCopy = { onCopy(url) }
                    )
                }
            }
        },
        confirmButton = {
            Button(onClick = onDismiss) {
                Text("Done")
            }
        },
        dismissButton = {}
    )
}

@Composable
private fun ResultValueRow(
    label: String,
    value: String,
    onCopy: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp))
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f)
            )
            Icon(
                imageVector = Icons.Default.ContentCopy,
                contentDescription = null,
                tint = EzcarNavy,
                modifier = Modifier.clickable(onClick = onCopy)
            )
        }
    }
}

private fun permissionIcon(key: String) = when (key) {
    "view_inventory" -> Icons.Default.Inventory2
    "create_sale" -> Icons.Default.PointOfSale
    "view_expenses" -> Icons.Default.CreditCard
    "manage_team" -> Icons.Default.PersonAdd
    "view_leads" -> Icons.Default.People
    "delete_records" -> Icons.Default.Delete
    "view_vehicle_cost" -> Icons.Default.Visibility
    "view_vehicle_profit" -> Icons.Default.Leaderboard
    else -> Icons.Default.BarChart
}

private fun copyTeamValue(context: Context, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("team_value", value))
    Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
}
