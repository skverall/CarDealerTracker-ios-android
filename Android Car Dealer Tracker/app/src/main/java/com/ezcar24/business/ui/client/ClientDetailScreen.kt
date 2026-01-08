package com.ezcar24.business.ui.client

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClientDetailScreen(
    clientId: String?,
    onBack: () -> Unit,
    viewModel: ClientDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    
    // Form State
    var name by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("new") }
    
    // Dialog States
    var showInteractionDialog by remember { mutableStateOf(false) }
    var showReminderDialog by remember { mutableStateOf(false) }
    
    // Initialize form when data loads
    LaunchedEffect(uiState.client) {
        uiState.client?.let {
            name = it.name ?: ""
            phone = it.phone ?: ""
            email = it.email ?: ""
            notes = it.notes ?: ""
            status = it.status ?: "new"
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(if (clientId == null) "New Client" else "Details") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (uiState.isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    } else {
                        Button(
                            onClick = {
                                viewModel.saveClient(name, phone, email, notes, status)
                                onBack()
                            },
                            enabled = name.isNotBlank()
                        ) {
                            Text("Save")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Name Section
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Client Name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            // Status Selector
            StatusSelector(selectedStatus = status, onStatusSelected = { status = it })

            // Contact Section
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("CONTACT INFO", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    
                    OutlinedTextField(
                        value = phone,
                        onValueChange = { phone = it },
                        label = { Text("Phone Number") },
                        leadingIcon = { Icon(Icons.Default.Phone, contentDescription = null) },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone)
                    )
                    
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        label = { Text("Email Address") },
                        leadingIcon = { Icon(Icons.Default.Email, contentDescription = null) },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                    )
                }
            }

            // Notes Section
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("NOTES", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        modifier = Modifier.fillMaxWidth().height(120.dp),
                        placeholder = { Text("Add notes here...") }
                    )
                }
            }

            // Reminders Section
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("REMINDERS", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    TextButton(onClick = { showReminderDialog = true }) {
                        Text("Add", color = EzcarBlueBright)
                    }
                }
                
                if (uiState.reminders.isEmpty()) {
                    Text("No reminders set", style = MaterialTheme.typography.bodySmall, color = Color.Gray, modifier = Modifier.padding(start = 4.dp))
                } else {
                    uiState.reminders.forEach { reminder ->
                        ReminderItem(reminder = reminder, onToggle = { viewModel.toggleReminder(reminder) })
                    }
                }
            }

            // Interactions Section
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("HISTORY", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    TextButton(onClick = { showInteractionDialog = true }) {
                        Text("Add", color = EzcarBlueBright)
                    }
                }
                
                if (uiState.interactions.isEmpty()) {
                    Text("No interactions recorded", style = MaterialTheme.typography.bodySmall, color = Color.Gray, modifier = Modifier.padding(start = 4.dp))
                } else {
                    uiState.interactions.forEach { interaction ->
                        InteractionItem(interaction = interaction)
                    }
                }
            }
        }
        
        if (showInteractionDialog) {
            AddInteractionDialog(
                onDismiss = { showInteractionDialog = false },
                onSave = { type, notes ->
                    viewModel.addInteraction(type, notes)
                    showInteractionDialog = false
                }
            )
        }
        
        if (showReminderDialog) {
            AddReminderDialog(
                onDismiss = { showReminderDialog = false },
                onSave = { title, date ->
                    viewModel.addReminder(title, date)
                    showReminderDialog = false
                }
            )
        }
    }
}

@Composable
fun StatusSelector(selectedStatus: String, onStatusSelected: (String) -> Unit) {
    val statuses = listOf(
        "new" to "New",
        "engaged" to "Engaged",
        "negotiation" to "Negot.",
        "purchased" to "Bought",
        "lost" to "Lost"
    )
    
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(statuses) { (key, label) ->
            FilterChip(
                selected = selectedStatus == key,
                onClick = { onStatusSelected(key) },
                label = { Text(label) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary,
                    selectedLabelColor = Color.White
                )
            )
        }
    }
}

@Composable
fun ReminderItem(reminder: com.ezcar24.business.data.local.ClientReminder, onToggle: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(
                checked = reminder.isCompleted,
                onCheckedChange = { onToggle() },
                colors = CheckboxDefaults.colors(checkedColor = EzcarGreen)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column {
                Text(
                    text = reminder.title,
                    style = MaterialTheme.typography.bodyMedium,
                    textDecoration = if (reminder.isCompleted) androidx.compose.ui.text.style.TextDecoration.LineThrough else null
                )
                Text(
                    text = java.text.SimpleDateFormat("MMM dd, HH:mm", java.util.Locale.getDefault()).format(reminder.dueDate),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
            }
        }
    }
}

@Composable
fun InteractionItem(interaction: com.ezcar24.business.data.local.ClientInteraction) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                 modifier = Modifier.fillMaxWidth(),
                 horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = (interaction.title ?: "Interaction").replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelSmall,
                    color = EzcarBlueBright,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = java.text.SimpleDateFormat("MMM dd", java.util.Locale.getDefault()).format(interaction.occurredAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = interaction.detail ?: "", style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun AddInteractionDialog(onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
    var type by remember { mutableStateOf("note") }
    var notes by remember { mutableStateOf("") }
    
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Card(shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Add Interaction", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                
                // Type Selector
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("call", "meeting", "email", "note").forEach { t ->
                        FilterChip(
                            selected = type == t,
                            onClick = { type = t },
                            label = { Text(t.uppercase()) }
                        )
                    }
                }
                
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes") },
                    modifier = Modifier.fillMaxWidth().height(100.dp)
                )
                
                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(onClick = { onSave(type, notes) }, colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)) { Text("Save") }
                }
            }
        }
    }
}

@Composable
fun AddReminderDialog(onDismiss: () -> Unit, onSave: (String, java.util.Date) -> Unit) {
    var title by remember { mutableStateOf("") }
    
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Card(shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
            Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Add Reminder", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Reminder Title") },
                    modifier = Modifier.fillMaxWidth()
                )
                
                Text("Due: Tomorrow (Placeholder)", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
                
                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(onClick = { 
                        // Default to tomorrow
                        val cal = java.util.Calendar.getInstance()
                        cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                        onSave(title, cal.time) 
                    }, enabled = title.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)) { Text("Save") }
                }
            }
        }
    }
}
