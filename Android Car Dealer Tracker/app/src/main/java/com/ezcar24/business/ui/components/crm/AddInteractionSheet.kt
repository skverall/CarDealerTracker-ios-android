package com.ezcar24.business.ui.components.crm

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.automirrored.filled.Note
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AddInteractionSheet(
    onDismiss: () -> Unit,
    onSave: (
        type: String,
        title: String,
        detail: String,
        outcome: String?,
        durationMinutes: Int?,
        isFollowUpRequired: Boolean,
        value: BigDecimal?,
        occurredAt: Date
    ) -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState()
) {
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var selectedType by remember { mutableStateOf("call") }
    var title by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf("") }
    var outcome by remember { mutableStateOf<String?>(null) }
    var durationMinutes by remember { mutableStateOf("") }
    var value by remember { mutableStateOf("") }
    var isFollowUpRequired by remember { mutableStateOf(false) }
    var occurredAt by remember { mutableStateOf(Date()) }

    val interactionTypes = listOf(
        InteractionType("call", "Call", Icons.Default.Call, EzcarGreen),
        InteractionType("meeting", "Meeting", Icons.Default.Event, EzcarPurple),
        InteractionType("email", "Email", Icons.Default.Email, EzcarBlueBright),
        InteractionType("message", "Message", Icons.AutoMirrored.Filled.Message, Color(0xFF2196F3)),
        InteractionType("test_drive", "Test Drive", Icons.Default.Visibility, EzcarOrange),
        InteractionType("note", "Note", Icons.AutoMirrored.Filled.Note, Color.Gray)
    )

    val outcomes = listOf(
        "Positive",
        "Neutral",
        "Negative",
        "No Answer",
        "Callback Requested",
        "Not Interested"
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Add Interaction",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Interaction Type Selector
            Text(
                text = "Interaction Type",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = Color.Gray
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                interactionTypes.forEach { type ->
                    val isSelected = selectedType == type.id
                    FilterChip(
                        selected = isSelected,
                        onClick = { selectedType = type.id },
                        label = { Text(type.label) },
                        leadingIcon = {
                            Icon(
                                imageVector = type.icon,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                        },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = type.color,
                            selectedLabelColor = Color.White,
                            selectedLeadingIconColor = Color.White
                        )
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Title
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Title") },
                placeholder = { Text("Brief summary of the interaction") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Detail
            OutlinedTextField(
                value = detail,
                onValueChange = { detail = it },
                label = { Text("Notes") },
                placeholder = { Text("Detailed notes about the interaction...") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(100.dp),
                maxLines = 4
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White, RoundedCornerShape(12.dp))
                    .clickable {
                        val calendar = Calendar.getInstance().apply { time = occurredAt }
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
                                        occurredAt = calendar.time
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
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 14.dp)
                        .background(Color.Transparent, RoundedCornerShape(12.dp)),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.CalendarToday, contentDescription = null, tint = Color.Gray)
                    Spacer(modifier = Modifier.size(16.dp))
                    Text(
                        text = "Date",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(occurredAt),
                        style = MaterialTheme.typography.bodyMedium,
                        color = EzcarBlueBright,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.size(8.dp))
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, tint = Color.Gray)
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White, RoundedCornerShape(12.dp))
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = value,
                    onValueChange = {
                        if (it.isEmpty() || it.toBigDecimalOrNull() != null) {
                            value = it
                        }
                    },
                    label = { Text("Deal Value (${regionState.selectedRegion.currencyCode})") },
                    leadingIcon = { Text(regionState.selectedRegion.currencySymbol) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "Outcome (Optional)",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = Color.Gray
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                outcomes.forEach { outcomeOption ->
                    val isSelected = outcome == outcomeOption
                    FilterChip(
                        selected = isSelected,
                        onClick = { outcome = if (isSelected) null else outcomeOption },
                        label = { Text(outcomeOption) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Duration
            OutlinedTextField(
                value = durationMinutes,
                onValueChange = { 
                    if (it.isEmpty() || it.toIntOrNull() != null) {
                        durationMinutes = it
                    }
                },
                label = { Text("Duration (minutes)") },
                leadingIcon = { Icon(Icons.Default.Schedule, contentDescription = null) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Follow-up Required
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Checkbox(
                    checked = isFollowUpRequired,
                    onCheckedChange = { isFollowUpRequired = it }
                )
                Text(
                    text = "Follow-up required",
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Cancel")
                }
                
                Button(
                    onClick = {
                        onSave(
                            selectedType,
                            title.ifBlank { selectedType.replaceFirstChar { it.uppercase() } },
                            detail,
                            outcome,
                            durationMinutes.toIntOrNull(),
                            isFollowUpRequired,
                            value.toBigDecimalOrNull(),
                            occurredAt
                        )
                        onDismiss()
                    },
                    enabled = title.isNotBlank() || detail.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Save Interaction")
                }
            }
        }
    }
}

private data class InteractionType(
    val id: String,
    val label: String,
    val icon: ImageVector,
    val color: Color
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickInteractionButton(
    type: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val (icon, color, label) = when (type.lowercase()) {
        "call" -> Triple(Icons.Default.Call, EzcarGreen, "Call")
        "message" -> Triple(Icons.AutoMirrored.Filled.Message, Color(0xFF2196F3), "Message")
        "email" -> Triple(Icons.Default.Email, EzcarBlueBright, "Email")
        else -> Triple(Icons.AutoMirrored.Filled.Note, Color.Gray, "Note")
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        IconButton(
            onClick = onClick,
            modifier = Modifier
                .size(48.dp)
                .background(color.copy(alpha = 0.1f), CircleShape)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = color,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            color = Color.Gray
        )
    }
}
