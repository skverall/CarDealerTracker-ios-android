package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.User
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarNavy

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamMembersScreen(
    onBack: () -> Unit,
    viewModel: TeamMembersViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showInviteDialog by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = EzcarBackgroundLight,
        topBar = {
            TopAppBar(
                title = { Text("Team Members", fontWeight = FontWeight.Bold, color = EzcarNavy) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = EzcarNavy)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showInviteDialog = true },
                containerColor = EzcarNavy,
                contentColor = Color.White
            ) {
                Icon(Icons.Default.Add, contentDescription = "Invite Member")
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            if (uiState.isLoading) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(uiState.users) { user ->
                        TeamMemberItem(user)
                    }
                    if (uiState.users.isEmpty()) {
                        item {
                            Text(
                                "No team members found.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = Color.Gray,
                                modifier = Modifier.padding(16.dp)
                            )
                        }
                    }
                }
            }
            
            // Snackbar for Success/Error
            uiState.inviteSuccess?.let { msg ->
                LaunchedEffect(msg) {
                    // Show snackbar or toast? Just a simple Text overlay for now or rely on Scaffold snackbarHost
                }
                // Placeholder UI logic
            }
        }
    }

    if (showInviteDialog) {
        AddMemberDialog(
            onDismiss = { showInviteDialog = false },
            onAdd = { name ->
                viewModel.addTeamMember(name)
                showInviteDialog = false
            },
            isLoading = uiState.isInviting
        )
    }
}

@Composable
fun TeamMemberItem(user: User) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White, RoundedCornerShape(12.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(EzcarBlueBright.copy(alpha = 0.1f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = user.name.take(1).uppercase(),
                fontWeight = FontWeight.Bold,
                color = EzcarBlueBright
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Column {
            Text(user.name, fontWeight = FontWeight.Bold, color = EzcarNavy)
            Text("Team Member", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
    }
}

@Composable
fun AddMemberDialog(
    onDismiss: () -> Unit,
    onAdd: (String) -> Unit,
    isLoading: Boolean
) {
    var name by remember { mutableStateOf("") }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Add Team Member",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
                Spacer(modifier = Modifier.height(16.dp))
                
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(24.dp))
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = Color.Gray)
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = { onAdd(name) },
                        enabled = name.isNotBlank() && !isLoading,
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy)
                    ) {
                        if (isLoading) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White)
                        } else {
                            Text("Add")
                        }
                    }
                }
            }
        }
    }
}
