package com.ezcar24.business.ui.client

import android.app.DatePickerDialog
import android.content.Intent
import android.net.Uri
import android.app.TimePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.ClientReminder
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.components.crm.AddInteractionSheet
import com.ezcar24.business.ui.components.crm.InteractionItem
import com.ezcar24.business.ui.components.crm.LeadPriorityIndicator
import com.ezcar24.business.ui.components.crm.LeadPrioritySelector
import com.ezcar24.business.ui.components.crm.LeadSourceBadge
import com.ezcar24.business.ui.components.crm.LeadSourceSelector
import com.ezcar24.business.ui.components.crm.LeadStageBadge
import com.ezcar24.business.ui.components.crm.LeadStageSelector
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID



@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClientDetailScreen(
    clientId: String?,
    onBack: () -> Unit,
    viewModel: ClientDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val context = LocalContext.current
    val leadScore = remember(uiState.client, uiState.interactions) { viewModel.calculateLeadScore() }
    val isNewClient = clientId.isNullOrBlank() || clientId == "new"
    
    // Form State
    var name by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var requestDetails by remember { mutableStateOf("") }
    var preferredDate by remember { mutableStateOf(Date()) }
    var selectedVehicleId by remember { mutableStateOf<UUID?>(null) }
    var status by remember { mutableStateOf("new") }
    
    // CRM Form State
    var leadStage by remember { mutableStateOf(LeadStage.new) }
    var leadSource by remember { mutableStateOf<LeadSource?>(null) }
    var estimatedValue by remember { mutableStateOf("") }
    var priority by remember { mutableIntStateOf(0) }
    
    // Sheet/Dialog States
    var showInteractionSheet by remember { mutableStateOf(false) }
    var showReminderDialog by remember { mutableStateOf(false) }
    var showVehicleMenu by remember { mutableStateOf(false) }
    var interactionPendingDelete by remember { mutableStateOf<ClientInteraction?>(null) }
    var reminderPendingDelete by remember { mutableStateOf<ClientReminder?>(null) }
    var isEditing by remember { mutableStateOf(isNewClient) }
    val canManageFollowUps = uiState.client != null
    val selectedVehicle = uiState.vehicles.firstOrNull { it.id == selectedVehicleId }
    
    // Initialize form when data loads
    LaunchedEffect(uiState.client) {
        uiState.client?.let {
            name = it.name ?: ""
            phone = it.phone ?: ""
            email = it.email ?: ""
            notes = it.notes ?: ""
            requestDetails = it.requestDetails ?: ""
            preferredDate = it.preferredDate ?: Date()
            selectedVehicleId = it.vehicleId
            status = it.status ?: "new"
            leadStage = it.leadStage
            leadSource = it.leadSource
            estimatedValue = it.estimatedValue?.toString() ?: ""
            priority = it.priority
        }
    }

    LaunchedEffect(uiState.saveCompleted) {
        if (uiState.saveCompleted) {
            viewModel.consumeSaveCompleted()
            if (isNewClient) {
                onBack()
            } else {
                isEditing = false
            }
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            isNewClient -> "New Client"
                            isEditing -> "Edit Client"
                            else -> "Client Details"
                        }
                    )
                },
                navigationIcon = {
                    IconButton(
                        onClick = {
                            if (isEditing && !isNewClient) {
                                uiState.client?.let {
                                    name = it.name ?: ""
                                    phone = it.phone ?: ""
                                    email = it.email ?: ""
                                    notes = it.notes ?: ""
                                    requestDetails = it.requestDetails ?: ""
                                    preferredDate = it.preferredDate ?: Date()
                                    selectedVehicleId = it.vehicleId
                                    status = it.status ?: "new"
                                    leadStage = it.leadStage
                                    leadSource = it.leadSource
                                    estimatedValue = it.estimatedValue?.toString() ?: ""
                                    priority = it.priority
                                }
                                isEditing = false
                            } else {
                                onBack()
                            }
                        }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (uiState.isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    } else if (!isEditing && !isNewClient) {
                        TextButton(onClick = { isEditing = true }) {
                            Text("Edit")
                        }
                    } else {
                        Button(
                            onClick = {
                                viewModel.saveClient(
                                    name = name,
                                    phone = phone,
                                    email = email,
                                    notes = notes,
                                    requestDetails = requestDetails,
                                    preferredDate = preferredDate,
                                    vehicleId = selectedVehicleId,
                                    status = status,
                                    leadStage = leadStage,
                                    leadSource = leadSource,
                                    estimatedValue = estimatedValue.toBigDecimalOrNull(),
                                    priority = priority
                                )
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
            uiState.errorMessage?.let { errorMessage ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF1F0)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = errorMessage,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color(0xFFB42318),
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = viewModel::clearErrorMessage) {
                            Text("Dismiss")
                        }
                    }
                }
            }

            if (!isEditing && !isNewClient) {
                uiState.client?.let { client ->
                    ClientReadOnlyContent(
                        client = client,
                        selectedVehicle = selectedVehicle,
                        interactions = uiState.interactions,
                        reminders = uiState.reminders,
                        leadScore = leadScore,
                        onCall = { openDialer(context, it) },
                        onWhatsApp = { openWhatsApp(context, it) },
                        onSms = { openSms(context, it) },
                        onEmail = { openEmail(context, it) }
                    )
                } ?: Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
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

            // CRM Section - Lead Stage, Source, Priority, Estimated Value
            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text("LEAD INFORMATION", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    
                    // Lead Stage Selector
                    Text("Lead Stage", style = MaterialTheme.typography.bodyMedium, color = Color.DarkGray)
                    LeadStageSelector(
                        selectedStage = leadStage,
                        onStageSelected = { leadStage = it },
                        excludeClosed = false
                    )
                    
                    // Lead Source Selector
                    Text("Lead Source", style = MaterialTheme.typography.bodyMedium, color = Color.DarkGray)
                    LeadSourceSelector(
                        selectedSource = leadSource,
                        onSourceSelected = { leadSource = it },
                        includeUnknown = true
                    )
                    
                    // Priority Selector
                    LeadPrioritySelector(
                        priority = priority,
                        onPriorityChange = { priority = it }
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = EzcarBlueBright.copy(alpha = 0.08f)),
                            modifier = Modifier.weight(1f)
                        ) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text("Lead Score", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = "$leadScore/100",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = EzcarBlueBright
                                )
                            }
                        }

                        Card(
                            colors = CardDefaults.cardColors(containerColor = EzcarGreen.copy(alpha = 0.08f)),
                            modifier = Modifier.weight(1f)
                        ) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text("Interactions", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    text = uiState.interactions.size.toString(),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = EzcarGreen
                                )
                            }
                        }
                    }
                    
                    // Estimated Value
                    OutlinedTextField(
                        value = estimatedValue,
                        onValueChange = { 
                            if (it.isEmpty() || it.toBigDecimalOrNull() != null) {
                                estimatedValue = it
                            }
                        },
                        label = { Text("Estimated Value (${regionState.selectedRegion.currencyCode})") },
                        leadingIcon = { 
                            Text(
                                regionState.selectedRegion.currencySymbol,
                                modifier = Modifier.padding(start = 12.dp),
                                color = EzcarBlueBright,
                                fontWeight = FontWeight.Bold
                            )
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                }
            }

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

                    if (phone.isNotBlank() || email.isNotBlank()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (phone.isNotBlank()) {
                                FilledTonalButton(
                                    onClick = { openDialer(context, phone) },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("Call")
                                }
                                FilledTonalButton(
                                    onClick = { openWhatsApp(context, phone) },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.AutoMirrored.Filled.Message, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("WhatsApp")
                                }
                            }

                            if (email.isNotBlank()) {
                                FilledTonalButton(
                                    onClick = { openEmail(context, email) },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Icon(Icons.Default.Email, contentDescription = null, modifier = Modifier.size(18.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("Email")
                                }
                            }
                        }
                    }
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text("VEHICLE INTEREST", style = MaterialTheme.typography.labelSmall, color = Color.Gray)

                    Box(modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { showVehicleMenu = true },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.DirectionsCar, contentDescription = null)
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = selectedVehicle?.let(::formatVehicleInterestLabel) ?: "Select vehicle",
                                    modifier = Modifier.weight(1f),
                                    color = if (selectedVehicle == null) Color.Gray else Color.Black
                                )
                                Icon(Icons.Default.KeyboardArrowDown, contentDescription = null)
                            }
                        }

                        DropdownMenu(
                            expanded = showVehicleMenu,
                            onDismissRequest = { showVehicleMenu = false },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            DropdownMenuItem(
                                text = { Text("No vehicle selected") },
                                onClick = {
                                    selectedVehicleId = null
                                    showVehicleMenu = false
                                }
                            )
                            uiState.vehicles.forEach { vehicle ->
                                DropdownMenuItem(
                                    text = { Text(formatVehicleInterestLabel(vehicle)) },
                                    onClick = {
                                        selectedVehicleId = vehicle.id
                                        showVehicleMenu = false
                                    }
                                )
                            }
                        }
                    }

                    if (uiState.vehicles.isEmpty()) {
                        Text(
                            "No inventory available yet",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray
                        )
                    }

                    OutlinedButton(
                        onClick = {
                            val calendar = Calendar.getInstance().apply { time = preferredDate }
                            DatePickerDialog(
                                context,
                                { _, year, month, dayOfMonth ->
                                    calendar.set(year, month, dayOfMonth)
                                    TimePickerDialog(
                                        context,
                                        { _, hour, minute ->
                                            calendar.set(Calendar.HOUR_OF_DAY, hour)
                                            calendar.set(Calendar.MINUTE, minute)
                                            calendar.set(Calendar.SECOND, 0)
                                            calendar.set(Calendar.MILLISECOND, 0)
                                            preferredDate = calendar.time
                                        },
                                        calendar.get(Calendar.HOUR_OF_DAY),
                                        calendar.get(Calendar.MINUTE),
                                        true
                                    ).show()
                                },
                                calendar.get(Calendar.YEAR),
                                calendar.get(Calendar.MONTH),
                                calendar.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.CalendarToday, contentDescription = null)
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(preferredDate),
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    OutlinedTextField(
                        value = requestDetails,
                        onValueChange = { requestDetails = it },
                        label = { Text("Request Details") },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(120.dp),
                        placeholder = { Text("What is this client looking for?") }
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
                    TextButton(onClick = { showReminderDialog = true }, enabled = canManageFollowUps) {
                        Text("Add", color = EzcarBlueBright)
                    }
                }

                if (!canManageFollowUps) {
                    Text(
                        "Save client to add reminders",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray,
                        modifier = Modifier.padding(start = 4.dp)
                    )
                } else if (uiState.reminders.isEmpty()) {
                    Text("No reminders set", style = MaterialTheme.typography.bodySmall, color = Color.Gray, modifier = Modifier.padding(start = 4.dp))
                } else {
                    uiState.reminders.forEach { reminder ->
                        ReminderItem(
                            reminder = reminder,
                            onToggle = { viewModel.toggleReminder(reminder) },
                            onDelete = { reminderPendingDelete = reminder }
                        )
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
                    Text("INTERACTIONS", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    TextButton(onClick = { showInteractionSheet = true }, enabled = canManageFollowUps) {
                        Text("Add Interaction", color = EzcarBlueBright)
                    }
                }

                if (!canManageFollowUps) {
                    Text(
                        "Save client to log interactions",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray,
                        modifier = Modifier.padding(start = 4.dp)
                    )
                } else if (uiState.interactions.isEmpty()) {
                    Text("No interactions recorded", style = MaterialTheme.typography.bodySmall, color = Color.Gray, modifier = Modifier.padding(start = 4.dp))
                } else {
                    uiState.interactions.forEach { interaction ->
                        InteractionItem(
                            interaction = interaction,
                            onDelete = { interactionPendingDelete = interaction }
                        )
                    }
                }
            }
            }
        }
        
        if (showInteractionSheet) {
            AddInteractionSheet(
                onDismiss = { showInteractionSheet = false },
                onSave = { type, title, detail, outcome, duration, followUp, value, occurredAt ->
                    viewModel.addInteraction(
                        type = type,
                        title = title,
                        detail = detail,
                        outcome = outcome,
                        durationMinutes = duration,
                        isFollowUpRequired = followUp,
                        value = value,
                        date = occurredAt
                    )
                }
            )
        }
        
        if (showReminderDialog) {
            AddReminderDialog(
                onDismiss = { showReminderDialog = false },
                onSave = { title, notes, date ->
                    viewModel.addReminder(title, date, notes)
                    showReminderDialog = false
                }
            )
        }

        interactionPendingDelete?.let { interaction ->
            AlertDialog(
                onDismissRequest = { interactionPendingDelete = null },
                title = { Text("Delete interaction") },
                text = { Text("This interaction will be removed from the client timeline.") },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.deleteInteraction(interaction.id)
                            interactionPendingDelete = null
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text("Delete")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { interactionPendingDelete = null }) {
                        Text("Cancel")
                    }
                }
            )
        }

        reminderPendingDelete?.let { reminder ->
            AlertDialog(
                onDismissRequest = { reminderPendingDelete = null },
                title = { Text("Delete reminder") },
                text = { Text("This reminder and its notification will be removed.") },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.deleteReminder(reminder)
                            reminderPendingDelete = null
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text("Delete")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { reminderPendingDelete = null }) {
                        Text("Cancel")
                    }
                }
            )
        }
    }
}

private fun formatVehicleInterestLabel(vehicle: Vehicle): String {
    val title = listOfNotNull(
        vehicle.year?.toString(),
        vehicle.make?.takeIf { it.isNotBlank() },
        vehicle.model?.takeIf { it.isNotBlank() }
    ).joinToString(" ")

    return title.ifBlank { vehicle.vin }
}

private fun openDialer(context: android.content.Context, phone: String) {
    context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
}

private fun openWhatsApp(context: android.content.Context, phone: String) {
    val normalizedPhone = phone.replace(Regex("[^0-9+]"), "")
    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$normalizedPhone")))
}

private fun openEmail(context: android.content.Context, email: String) {
    context.startActivity(
        Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$email"))
    )
}

private fun openSms(context: android.content.Context, phone: String) {
    context.startActivity(
        Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
    )
}

@Composable
private fun ClientReadOnlyContent(
    client: com.ezcar24.business.data.local.Client,
    selectedVehicle: Vehicle?,
    interactions: List<ClientInteraction>,
    reminders: List<ClientReminder>,
    leadScore: Int,
    onCall: (String) -> Unit,
    onWhatsApp: (String) -> Unit,
    onSms: (String) -> Unit,
    onEmail: (String) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val nextReminder = reminders
        .filterNot { it.isCompleted }
        .minByOrNull { it.dueDate }
    val lastInteraction = interactions.maxByOrNull { it.occurredAt }

    ClientReadOnlyCard(title = "CRM Summary") {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            LeadStageBadge(stage = client.leadStage)
            LeadSourceBadge(source = client.leadSource)
        }

        Spacer(modifier = Modifier.height(12.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Card(
                colors = CardDefaults.cardColors(containerColor = EzcarBlueBright.copy(alpha = 0.08f)),
                modifier = Modifier.weight(1f)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Lead Score", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "$leadScore/100",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = EzcarBlueBright
                    )
                }
            }

            Card(
                colors = CardDefaults.cardColors(containerColor = EzcarGreen.copy(alpha = 0.08f)),
                modifier = Modifier.weight(1f)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Estimated Value", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = regionSettingsManager.formatCurrency(client.estimatedValue),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = EzcarGreen
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))
        LeadPriorityIndicator(priority = client.priority)

        lastInteraction?.let { interaction ->
            Spacer(modifier = Modifier.height(12.dp))
            ClientReadOnlyRow(
                label = "Last Interaction",
                value = listOfNotNull(
                    interaction.title?.takeIf { it.isNotBlank() },
                    formatDateTime(interaction.occurredAt)
                ).joinToString(" • ")
            )
            interaction.detail?.takeIf { it.isNotBlank() }?.let { detail ->
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.DarkGray
                )
            }
        }

        nextReminder?.let { reminder ->
            Spacer(modifier = Modifier.height(12.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = EzcarOrange.copy(alpha = 0.08f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Next Reminder", style = MaterialTheme.typography.labelSmall, color = EzcarOrange)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = reminder.title,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = formatDateTime(reminder.dueDate),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
            }
        }
    }

    ClientReadOnlyCard(title = "Contact Info") {
        ClientReadOnlyRow(label = "Name", value = displayValue(client.name))
        ClientReadOnlyRow(label = "Phone", value = displayValue(client.phone))
        ClientReadOnlyRow(label = "Email", value = displayValue(client.email))

        ClientContactActions(
            phone = client.phone,
            email = client.email,
            onCall = onCall,
            onWhatsApp = onWhatsApp,
            onSms = onSms,
            onEmail = onEmail
        )
    }

    ClientReadOnlyCard(title = "Vehicle Interest") {
        ClientReadOnlyRow(
            label = "Vehicle",
            value = selectedVehicle?.let(::formatVehicleInterestLabel) ?: "Not selected"
        )
        ClientReadOnlyRow(
            label = "Preferred Date",
            value = formatDateTime(client.preferredDate)
        )
        client.requestDetails?.takeIf { it.isNotBlank() }?.let { details ->
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = details,
                style = MaterialTheme.typography.bodyMedium,
                color = Color.DarkGray
            )
        }
    }

    ClientReadOnlyCard(title = "Notes") {
        Text(
            text = displayValue(client.notes),
            style = MaterialTheme.typography.bodyMedium,
            color = if (client.notes.isNullOrBlank()) Color.Gray else Color.DarkGray
        )
    }

    ClientReadOnlyCard(title = "Deal History") {
        if (interactions.isEmpty()) {
            Text("No interactions recorded", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                interactions.forEach { interaction ->
                    InteractionItem(interaction = interaction)
                }
            }
        }
    }

    ClientReadOnlyCard(title = "Reminders") {
        if (reminders.isEmpty()) {
            Text("No reminders set", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                reminders.forEach { reminder ->
                    ReadOnlyReminderItem(reminder = reminder)
                }
            }
        }
    }
}

@Composable
private fun ClientReadOnlyCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content
        )
    }
}

@Composable
private fun ClientReadOnlyRow(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.Gray
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = Color.DarkGray
        )
    }
}

@Composable
private fun ClientContactActions(
    phone: String?,
    email: String?,
    onCall: (String) -> Unit,
    onWhatsApp: (String) -> Unit,
    onSms: (String) -> Unit,
    onEmail: (String) -> Unit
) {
    val cleanPhone = phone?.takeIf { it.isNotBlank() }
    val cleanEmail = email?.takeIf { it.isNotBlank() }

    if (cleanPhone != null) {
        Spacer(modifier = Modifier.height(8.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilledTonalButton(
                onClick = { onCall(cleanPhone) },
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Call")
            }
            FilledTonalButton(
                onClick = { onWhatsApp(cleanPhone) },
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.AutoMirrored.Filled.Message, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("WhatsApp")
            }
            FilledTonalButton(
                onClick = { onSms(cleanPhone) },
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.Sms, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("SMS")
            }
        }
    }

    if (cleanEmail != null) {
        Spacer(modifier = Modifier.height(8.dp))
        FilledTonalButton(
            onClick = { onEmail(cleanEmail) },
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Email, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("Email")
        }
    }
}

@Composable
private fun ReadOnlyReminderItem(reminder: ClientReminder) {
    val statusColor = when {
        reminder.isCompleted -> EzcarGreen
        reminder.dueDate.before(Date()) -> MaterialTheme.colorScheme.error
        else -> EzcarOrange
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = statusColor.copy(alpha = 0.08f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = reminder.title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            reminder.notes?.takeIf { it.isNotBlank() }?.let { notes ->
                Text(
                    text = notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.DarkGray
                )
            }
            Text(
                text = formatDateTime(reminder.dueDate),
                style = MaterialTheme.typography.labelSmall,
                color = statusColor
            )
        }
    }
}

private fun displayValue(value: String?): String = value?.takeIf { it.isNotBlank() } ?: "Not provided"

private fun formatDateTime(date: Date?): String {
    if (date == null) return "Not set"
    return SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(date)
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
fun ReminderItem(reminder: ClientReminder, onToggle: () -> Unit, onDelete: () -> Unit) {
    val dueColor = when {
        reminder.isCompleted -> EzcarGreen
        reminder.dueDate.before(Date()) -> MaterialTheme.colorScheme.error
        else -> Color.Gray
    }

    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(
                checked = reminder.isCompleted,
                onCheckedChange = { onToggle() },
                colors = CheckboxDefaults.colors(checkedColor = EzcarGreen)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = reminder.title,
                    style = MaterialTheme.typography.bodyMedium,
                    textDecoration = if (reminder.isCompleted) androidx.compose.ui.text.style.TextDecoration.LineThrough else null
                )
                reminder.notes?.takeIf { it.isNotBlank() }?.let { notes ->
                    Text(
                        text = notes,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.DarkGray
                    )
                }
                Text(
                    text = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(reminder.dueDate),
                    style = MaterialTheme.typography.labelSmall,
                    color = dueColor
                )
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete reminder", tint = Color.Gray)
            }
        }
    }
}

@Composable
fun LegacyInteractionItem(interaction: com.ezcar24.business.data.local.ClientInteraction) {
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
fun LegacyAddInteractionDialog(onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
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
fun AddReminderDialog(onDismiss: () -> Unit, onSave: (String, String, Date) -> Unit) {
    val context = LocalContext.current
    var title by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var dueDate by remember {
        mutableStateOf(
            Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 9)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.time
        )
    }

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
                
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(100.dp)
                )

                OutlinedButton(
                    onClick = {
                        val calendar = Calendar.getInstance().apply { time = dueDate }
                        DatePickerDialog(
                            context,
                            { _, year, month, dayOfMonth ->
                                calendar.set(year, month, dayOfMonth)
                                TimePickerDialog(
                                    context,
                                    { _, hour, minute ->
                                        calendar.set(Calendar.HOUR_OF_DAY, hour)
                                        calendar.set(Calendar.MINUTE, minute)
                                        calendar.set(Calendar.SECOND, 0)
                                        calendar.set(Calendar.MILLISECOND, 0)
                                        dueDate = calendar.time
                                    },
                                    calendar.get(Calendar.HOUR_OF_DAY),
                                    calendar.get(Calendar.MINUTE),
                                    true
                                ).show()
                            },
                            calendar.get(Calendar.YEAR),
                            calendar.get(Calendar.MONTH),
                            calendar.get(Calendar.DAY_OF_MONTH)
                        ).show()
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Due: ${SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(dueDate)}")
                }
                
                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(
                        onClick = {
                            onSave(title, notes, dueDate)
                        },
                        enabled = title.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) { Text("Save") }
                }
            }
        }
    }
}
