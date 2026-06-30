package com.ezcar24.business.ui.client

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatAlignLeft
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.ClientReminder
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.components.crm.AddInteractionSheet
import com.ezcar24.business.ui.components.crm.InteractionItem
import com.ezcar24.business.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import com.ezcar24.business.util.localizedUiString



@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClientDetailScreen(
    clientId: String?,
    onBack: () -> Unit,
    viewModel: ClientDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
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
    var showVehicleSheet by remember { mutableStateOf(false) }
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
            status = normalizeClientStatusForIos(it.status)
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

    fun resetFormFromClient() {
        uiState.client?.let {
            name = it.name ?: ""
            phone = it.phone ?: ""
            email = it.email ?: ""
            notes = it.notes ?: ""
            requestDetails = it.requestDetails ?: ""
            preferredDate = it.preferredDate ?: Date()
            selectedVehicleId = it.vehicleId
            status = normalizeClientStatusForIos(it.status)
            leadStage = it.leadStage
            leadSource = it.leadSource
            estimatedValue = it.estimatedValue?.toString() ?: ""
            priority = it.priority
        }
    }

    fun saveClient() {
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
    }

    fun closeScreen() {
        if (isEditing && !isNewClient) {
            resetFormFromClient()
            isEditing = false
        } else {
            onBack()
        }
    }

    fun showPreferredDatePicker() {
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
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EzcarBackgroundLight)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            ClientDetailHeader(
                title = localizedUiString(
                    when {
                        isNewClient -> "New Client"
                        isEditing -> "Edit Client"
                        else -> "Client Details"
                    }
                ),
                isViewing = !isEditing && !isNewClient,
                onClose = { closeScreen() },
                onEdit = { isEditing = true }
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = if (isEditing) 116.dp else 0.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = if (isEditing) 24.dp else 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                uiState.errorMessage?.let { errorMessage ->
                    ClientErrorCard(
                        message = errorMessage,
                        onDismiss = viewModel::clearErrorMessage,
                        modifier = Modifier.padding(horizontal = 20.dp)
                    )
                }

                if (!isEditing && !isNewClient) {
                    uiState.client?.let { client ->
                        Column(
                            modifier = Modifier.padding(horizontal = 20.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            ClientReadOnlyContent(
                                client = client,
                                selectedVehicle = selectedVehicle,
                                interactions = uiState.interactions,
                                reminders = uiState.reminders,
                                onCall = { openDialer(context, it) },
                                onWhatsApp = { openWhatsApp(context, it) },
                                onSms = { openSms(context, it) },
                                onEmail = { openEmail(context, it) }
                            )
                        }
                    } ?: Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 48.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                } else {
                    ClientEditContent(
                        name = name,
                        onNameChange = { name = it },
                        status = status,
                        onStatusSelected = { status = it },
                        phone = phone,
                        onPhoneChange = { phone = it },
                        email = email,
                        onEmailChange = { email = it },
                        selectedVehicle = selectedVehicle,
                        onVehicleClick = { showVehicleSheet = true },
                        preferredDate = preferredDate,
                        onPreferredDateClick = { showPreferredDatePicker() },
                        requestDetails = requestDetails,
                        onRequestDetailsChange = { requestDetails = it },
                        notes = notes,
                        onNotesChange = { notes = it },
                        canManageFollowUps = canManageFollowUps,
                        reminders = uiState.reminders,
                        interactions = uiState.interactions,
                        onAddReminder = { showReminderDialog = true },
                        onToggleReminder = { viewModel.toggleReminder(it) },
                        onDeleteReminder = { reminderPendingDelete = it },
                        onAddInteraction = { showInteractionSheet = true },
                        onDeleteInteraction = { interactionPendingDelete = it }
                    )
                }
            }
        }

        if (isEditing) {
            ClientFloatingSaveButton(
                isSaving = uiState.isSaving,
                enabled = name.isNotBlank(),
                onClick = { saveClient() },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 16.dp)
            )
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

        if (showVehicleSheet) {
            VehicleSelectionBottomSheet(
                vehicles = uiState.vehicles,
                selectedVehicleId = selectedVehicleId,
                onDismiss = { showVehicleSheet = false },
                onSelect = {
                    selectedVehicleId = it
                    showVehicleSheet = false
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
                title = { Text(localizedUiString("Delete interaction")) },
                text = { Text(localizedUiString("This interaction will be removed from the client timeline.")) },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.deleteInteraction(interaction.id)
                            interactionPendingDelete = null
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text(localizedUiString("Delete"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { interactionPendingDelete = null }) {
                        Text(localizedUiString("Cancel"))
                    }
                }
            )
        }

        reminderPendingDelete?.let { reminder ->
            AlertDialog(
                onDismissRequest = { reminderPendingDelete = null },
                title = { Text(localizedUiString("Delete reminder")) },
                text = { Text(localizedUiString("This reminder and its notification will be removed.")) },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.deleteReminder(reminder)
                            reminderPendingDelete = null
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text(localizedUiString("Delete"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { reminderPendingDelete = null }) {
                        Text(localizedUiString("Cancel"))
                    }
                }
            )
        }
    }
}

@Composable
private fun ClientDetailHeader(
    title: String,
    isViewing: Boolean,
    onClose: () -> Unit,
    onEdit: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .background(EzcarBackgroundLight)
            .padding(horizontal = 20.dp)
            .padding(top = 10.dp, bottom = 10.dp)
    ) {
        IconButton(
            onClick = onClose,
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(36.dp)
                .background(EzcarSurfaceMutedLight, CircleShape)
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = localizedUiString("Back"),
                tint = EzcarTextSecondaryLight,
                modifier = Modifier.size(18.dp)
            )
        }

        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = EzcarTextPrimaryLight,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = 104.dp)
        )

        if (isViewing) {
            TextButton(
                onClick = onEdit,
                colors = ButtonDefaults.textButtonColors(contentColor = EzcarNavy),
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .height(36.dp)
                    .background(EzcarNavy.copy(alpha = 0.10f), RoundedCornerShape(18.dp))
            ) {
                Text(
                    text = localizedUiString("Edit"),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun ClientErrorCard(
    message: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF1F0)),
        shape = RoundedCornerShape(14.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFFB42318),
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onDismiss) {
                Text(localizedUiString("Dismiss"))
            }
        }
    }
}

@Composable
private fun ClientEditContent(
    name: String,
    onNameChange: (String) -> Unit,
    status: String,
    onStatusSelected: (String) -> Unit,
    phone: String,
    onPhoneChange: (String) -> Unit,
    email: String,
    onEmailChange: (String) -> Unit,
    selectedVehicle: Vehicle?,
    onVehicleClick: () -> Unit,
    preferredDate: Date,
    onPreferredDateClick: () -> Unit,
    requestDetails: String,
    onRequestDetailsChange: (String) -> Unit,
    notes: String,
    onNotesChange: (String) -> Unit,
    canManageFollowUps: Boolean,
    reminders: List<ClientReminder>,
    interactions: List<ClientInteraction>,
    onAddReminder: () -> Unit,
    onToggleReminder: (ClientReminder) -> Unit,
    onDeleteReminder: (ClientReminder) -> Unit,
    onAddInteraction: () -> Unit,
    onDeleteInteraction: (ClientInteraction) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
        ClientNameInput(name = name, onNameChange = onNameChange)

        StatusSelector(selectedStatus = status, onStatusSelected = onStatusSelected)

        ClientEditSection(title = "Contact Info") {
            ClientPlainTextFieldRow(
                icon = Icons.Default.Phone,
                value = phone,
                onValueChange = onPhoneChange,
                placeholder = "Phone Number",
                keyboardType = KeyboardType.Phone
            )
            ClientDivider()
            ClientPlainTextFieldRow(
                icon = Icons.Default.Email,
                value = email,
                onValueChange = onEmailChange,
                placeholder = "Email Address",
                keyboardType = KeyboardType.Email
            )
        }

        ClientEditSection(title = "Vehicle Interest") {
            ClientPickerRow(
                icon = Icons.Default.DirectionsCar,
                text = selectedVehicle?.let(::formatVehicleInterestLabel) ?: localizedUiString("Select vehicle"),
                isPlaceholder = selectedVehicle == null,
                trailingIcon = Icons.Default.ChevronRight,
                onClick = onVehicleClick
            )
            ClientDivider()
            ClientPickerRow(
                icon = Icons.Default.CalendarToday,
                text = formatDateTime(preferredDate),
                isPlaceholder = false,
                onClick = onPreferredDateClick
            )
            ClientDivider()
            ClientPlainTextFieldRow(
                icon = Icons.AutoMirrored.Filled.FormatAlignLeft,
                value = requestDetails,
                onValueChange = onRequestDetailsChange,
                placeholder = "Request Details",
                singleLine = false,
                minHeight = 82.dp
            )
        }

        ClientEditSection(title = "Notes") {
            ClientPlainTextFieldRow(
                icon = Icons.AutoMirrored.Filled.Notes,
                value = notes,
                onValueChange = onNotesChange,
                placeholder = "Add notes here...",
                singleLine = false,
                minHeight = 104.dp
            )
        }

        if (canManageFollowUps) {
            ClientFollowUpSection(
                title = "Reminders",
                addLabel = "Add Reminder",
                emptyText = "No reminders set",
                isEmpty = reminders.isEmpty(),
                onAdd = onAddReminder
            ) {
                reminders.forEach { reminder ->
                    ReminderItem(
                        reminder = reminder,
                        onToggle = { onToggleReminder(reminder) },
                        onDelete = { onDeleteReminder(reminder) }
                    )
                }
            }

            ClientFollowUpSection(
                title = "Interactions",
                addLabel = "Add Interaction",
                emptyText = "No interactions recorded",
                isEmpty = interactions.isEmpty(),
                onAdd = onAddInteraction
            ) {
                interactions.forEach { interaction ->
                    InteractionItem(
                        interaction = interaction,
                        onDelete = { onDeleteInteraction(interaction) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ClientNameInput(
    name: String,
    onNameChange: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = localizedUiString("Client Name").uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = EzcarTextSecondaryLight,
            letterSpacing = 1.sp
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 58.dp)
                .padding(horizontal = 20.dp),
            contentAlignment = Alignment.Center
        ) {
            if (name.isBlank()) {
                Text(
                    text = localizedUiString("Client Name"),
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarTextSecondaryLight.copy(alpha = 0.55f),
                    textAlign = TextAlign.Center
                )
            }
            BasicTextField(
                value = name,
                onValueChange = onNameChange,
                singleLine = true,
                textStyle = MaterialTheme.typography.headlineLarge.merge(
                    TextStyle(
                        color = EzcarTextPrimaryLight,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                ),
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun ClientEditSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier.padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = localizedUiString(title),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = EzcarTextSecondaryLight,
            modifier = Modifier.padding(start = 4.dp)
        )
        Card(
            colors = CardDefaults.cardColors(containerColor = EzcarSurfaceLight),
            shape = RoundedCornerShape(16.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(content = content)
        }
    }
}

@Composable
private fun ClientPlainTextFieldRow(
    icon: ImageVector,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
    minHeight: Dp = 56.dp
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .padding(16.dp),
        verticalAlignment = if (singleLine) Alignment.CenterVertically else Alignment.Top
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = EzcarTextSecondaryLight,
            modifier = Modifier
                .padding(top = if (singleLine) 0.dp else 3.dp)
                .width(24.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Box(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = if (singleLine) 28.dp else minHeight - 32.dp),
            contentAlignment = if (singleLine) Alignment.CenterStart else Alignment.TopStart
        ) {
            if (value.isBlank()) {
                Text(
                    text = localizedUiString(placeholder),
                    style = MaterialTheme.typography.bodyLarge,
                    color = EzcarTextSecondaryLight.copy(alpha = 0.75f)
                )
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = singleLine,
                maxLines = if (singleLine) 1 else 5,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                textStyle = MaterialTheme.typography.bodyLarge.merge(
                    TextStyle(color = EzcarTextPrimaryLight)
                ),
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

@Composable
private fun ClientPickerRow(
    icon: ImageVector,
    text: String,
    isPlaceholder: Boolean,
    trailingIcon: ImageVector? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = EzcarTextSecondaryLight,
            modifier = Modifier.width(24.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = if (isPlaceholder) EzcarTextSecondaryLight else EzcarTextPrimaryLight,
            modifier = Modifier.weight(1f)
        )
        trailingIcon?.let {
            Icon(
                imageVector = it,
                contentDescription = null,
                tint = EzcarTextSecondaryLight,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun ClientDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 52.dp),
        color = EzcarBorderLight
    )
}

@Composable
private fun ClientFollowUpSection(
    title: String,
    addLabel: String,
    emptyText: String,
    isEmpty: Boolean,
    onAdd: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier.padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = localizedUiString(title),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = EzcarTextSecondaryLight,
            modifier = Modifier.padding(start = 4.dp)
        )
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (isEmpty) {
                Text(
                    text = localizedUiString(emptyText),
                    style = MaterialTheme.typography.bodySmall,
                    color = EzcarTextSecondaryLight,
                    modifier = Modifier.padding(start = 4.dp)
                )
            } else {
                content()
            }
            TextButton(
                onClick = onAdd,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(EzcarSurfaceLight, RoundedCornerShape(12.dp))
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null, tint = EzcarNavy)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = localizedUiString(addLabel),
                    color = EzcarNavy,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun ClientFloatingSaveButton(
    isSaving: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(
        onClick = onClick,
        enabled = enabled && !isSaving,
        shape = RoundedCornerShape(20.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = EzcarNavy,
            disabledContainerColor = EzcarTextSecondaryLight.copy(alpha = 0.30f),
            contentColor = Color.White,
            disabledContentColor = Color.White
        ),
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
    ) {
        if (isSaving) {
            CircularProgressIndicator(
                color = Color.White,
                strokeWidth = 2.dp,
                modifier = Modifier
                    .size(20.dp)
                    .padding(end = 8.dp)
            )
        }
        Text(
            text = if (isSaving) localizedUiString("Saving...") else localizedUiString("Save"),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VehicleSelectionBottomSheet(
    vehicles: List<Vehicle>,
    selectedVehicleId: UUID?,
    onDismiss: () -> Unit,
    onSelect: (UUID?) -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = EzcarBackgroundLight
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = localizedUiString("Select Vehicle"),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = EzcarTextPrimaryLight
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 480.dp)
                    .verticalScroll(rememberScrollState())
                    .background(EzcarSurfaceLight, RoundedCornerShape(16.dp))
            ) {
                VehicleSheetRow(
                    title = localizedUiString("No vehicle selected"),
                    selected = selectedVehicleId == null,
                    onClick = { onSelect(null) }
                )
                vehicles.forEach { vehicle ->
                    ClientDivider()
                    VehicleSheetRow(
                        title = formatVehicleInterestLabel(vehicle),
                        selected = selectedVehicleId == vehicle.id,
                        onClick = { onSelect(vehicle.id) }
                    )
                }
            }

            if (vehicles.isEmpty()) {
                Text(
                    text = localizedUiString("No inventory available yet"),
                    style = MaterialTheme.typography.bodySmall,
                    color = EzcarTextSecondaryLight,
                    modifier = Modifier.padding(horizontal = 4.dp)
                )
            }
        }
    }
}

@Composable
private fun VehicleSheetRow(
    title: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            color = EzcarTextPrimaryLight,
            modifier = Modifier.weight(1f)
        )
        if (selected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = EzcarNavy,
                modifier = Modifier.size(20.dp)
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
    onCall: (String) -> Unit,
    onWhatsApp: (String) -> Unit,
    onSms: (String) -> Unit,
    onEmail: (String) -> Unit
) {
    val nextReminder = reminders
        .filterNot { it.isCompleted }
        .minByOrNull { it.dueDate }
    val lastInteraction = interactions.maxByOrNull { it.occurredAt }

    ClientReadOnlyCard(title = "CRM Summary") {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            ClientStatusBadge(status = client.status)
            client.preferredDate?.let { preferredDate ->
                Text(
                    text = formatDateTime(preferredDate),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))

        if (lastInteraction != null) {
            ClientReadOnlyRow(
                label = "Last Interaction",
                value = listOfNotNull(
                    lastInteraction.title?.takeIf { it.isNotBlank() },
                    formatDateTime(lastInteraction.occurredAt)
                ).joinToString(" • ")
            )
            lastInteraction.detail?.takeIf { it.isNotBlank() }?.let { detail ->
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.DarkGray
                )
            }
        } else {
            Text(localizedUiString("No interactions recorded"), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }

        nextReminder?.let { reminder ->
            Spacer(modifier = Modifier.height(12.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = EzcarOrange.copy(alpha = 0.08f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(localizedUiString("Next Reminder"), style = MaterialTheme.typography.labelSmall, color = EzcarOrange)
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
            value = selectedVehicle?.let(::formatVehicleInterestLabel) ?: localizedUiString("Not selected")
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
            Text(localizedUiString("No interactions recorded"), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
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
            Text(localizedUiString("No reminders set"), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
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
private fun ClientStatusBadge(status: String?) {
    val normalizedStatus = normalizeClientStatusForIos(status)
    val statusColor = clientStatusColor(normalizedStatus)
    val labelSource = when (normalizedStatus) {
        "contacted" -> "Contacted"
        "viewing" -> "Viewing"
        "negotiation" -> "Negotiation"
        "sold" -> "Sold"
        else -> "New"
    }

    Text(
        text = localizedUiString(labelSource),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = statusColor,
        modifier = Modifier
            .background(
                color = statusColor.copy(alpha = 0.1f),
                shape = RoundedCornerShape(50)
            )
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}

@Composable
private fun ClientReadOnlyCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = localizedUiString(title),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            content()
        }
    }
}

@Composable
private fun ClientReadOnlyRow(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = localizedUiString(label),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
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
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            ClientContactActionButton(
                icon = Icons.Default.Phone,
                contentDescription = "Call",
                background = EzcarNavy,
                onClick = { onCall(cleanPhone) },
            )
            ClientContactActionButton(
                icon = Icons.AutoMirrored.Filled.Message,
                contentDescription = "WhatsApp",
                background = Color(0xFF1DB954),
                onClick = { onWhatsApp(cleanPhone) },
            )
            ClientContactActionButton(
                icon = Icons.Default.Sms,
                contentDescription = "SMS",
                background = EzcarBlueBright,
                onClick = { onSms(cleanPhone) },
            )
            if (cleanEmail != null) {
                ClientContactActionButton(
                    icon = Icons.Default.Email,
                    contentDescription = "Email",
                    background = EzcarTextSecondaryLight,
                    onClick = { onEmail(cleanEmail) },
                )
            }
        }
    }
}

@Composable
private fun ClientContactActionButton(
    icon: ImageVector,
    contentDescription: String,
    background: Color,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(44.dp)
            .background(background, CircleShape)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = localizedUiString(contentDescription),
            tint = Color.White,
            modifier = Modifier.size(20.dp)
        )
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

@Composable
private fun displayValue(value: String?): String = value?.takeIf { it.isNotBlank() } ?: localizedUiString("Not provided")

@Composable
private fun formatDateTime(date: Date?): String {
    if (date == null) return localizedUiString("Not set")
    return SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(date)
}

@Composable
fun StatusSelector(selectedStatus: String, onStatusSelected: (String) -> Unit) {
    val statuses = listOf(
        "new" to "New",
        "contacted" to "Contacted",
        "viewing" to "Viewing",
        "negotiation" to "Negotiation",
        "sold" to "Sold"
    )
    val normalizedSelectedStatus = normalizeClientStatusForIos(selectedStatus)
    
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 4.dp)
    ) {
        items(statuses) { (key, label) ->
            val selected = normalizedSelectedStatus == key
            val statusColor = clientStatusColor(key)
            Surface(
                onClick = { onStatusSelected(key) },
                shape = RoundedCornerShape(20.dp),
                color = if (selected) statusColor else EzcarSurfaceLight,
                contentColor = if (selected) Color.White else EzcarTextSecondaryLight,
                border = if (selected) null else BorderStroke(1.dp, EzcarTextSecondaryLight.copy(alpha = 0.20f)),
                shadowElevation = if (selected) 4.dp else 0.dp
            ) {
                Text(
                    text = localizedUiString(label),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                )
            }
        }
    }
}

private fun clientStatusColor(status: String?): Color {
    return when (normalizeClientStatusForIos(status)) {
        "contacted" -> EzcarOrange
        "viewing" -> Color(0xFFFF9800)
        "negotiation" -> EzcarBlueBright
        "sold" -> EzcarGreen
        else -> EzcarNavy
    }
}

private fun normalizeClientStatusForIos(status: String?): String {
    return when (status) {
        "contacted", "engaged", "in_progress" -> "contacted"
        "viewing" -> "viewing"
        "negotiation", "completed" -> "negotiation"
        "sold", "purchased" -> "sold"
        else -> "new"
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
                Icon(Icons.Default.Delete, contentDescription = localizedUiString("Delete reminder"), tint = Color.Gray)
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
                    text = (interaction.title ?: localizedUiString("Interaction")).replaceFirstChar { it.uppercase() },
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
                Text(localizedUiString("Add Interaction"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                
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
                    label = { Text(localizedUiString("Notes")) },
                    modifier = Modifier.fillMaxWidth().height(100.dp)
                )
                
                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) }
                    Button(onClick = { onSave(type, notes) }, colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)) { Text(localizedUiString("Save")) }
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
                Text(localizedUiString("Add Reminder"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text(localizedUiString("Reminder Title")) },
                    modifier = Modifier.fillMaxWidth()
                )
                
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text(localizedUiString("Notes")) },
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
                    Text(localizedUiString("Due: %s", SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(dueDate)))
                }
                
                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) }
                    Button(
                        onClick = {
                            onSave(title, notes, dueDate)
                        },
                        enabled = title.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) { Text(localizedUiString("Save")) }
                }
            }
        }
    }
}
