package com.ezcar24.business.ui.components.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.automirrored.filled.Note
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Locale

@Composable
fun InteractionItem(
    interaction: ClientInteraction,
    modifier: Modifier = Modifier,
    onDelete: (() -> Unit)? = null
) {
    val interactionType = interaction.interactionType ?: "note"
    val (icon, color) = getInteractionTypeInfo(interactionType)
    val regionSettingsManager = rememberRegionSettingsManager()
    
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .background(color.copy(alpha = 0.1f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(20.dp)
                )
            }
            
            Spacer(modifier = Modifier.width(12.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = interaction.title ?: interactionType.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )

                    Column(horizontalAlignment = Alignment.End) {
                        interaction.value?.let { value ->
                            Surface(
                                color = EzcarGreen.copy(alpha = 0.12f),
                                shape = RoundedCornerShape(999.dp)
                            ) {
                                Text(
                                    text = regionSettingsManager.formatCurrency(value),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = EzcarGreen,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                        }

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = formatInteractionDate(interaction.occurredAt),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.Gray
                            )
                            onDelete?.let {
                                IconButton(
                                    onClick = it,
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(
                                        Icons.Default.DeleteOutline,
                                        contentDescription = "Delete interaction",
                                        tint = Color.Gray,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                
                Spacer(modifier = Modifier.height(4.dp))
                
                if (!interaction.detail.isNullOrBlank()) {
                    Text(
                        text = interaction.detail,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.DarkGray,
                        maxLines = 3
                    )
                }
                
                if (interaction.outcome != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Outcome: ${interaction.outcome}",
                        style = MaterialTheme.typography.labelSmall,
                        color = EzcarGreen,
                        fontWeight = FontWeight.Medium
                    )
                }
                
                if (interaction.isFollowUpRequired) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Follow-up required",
                        style = MaterialTheme.typography.labelSmall,
                        color = EzcarOrange,
                        fontWeight = FontWeight.Medium
                    )
                }
                
                if (interaction.durationMinutes != null && interaction.durationMinutes > 0) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Duration: ${interaction.durationMinutes} min",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.Gray
                    )
                }
            }
        }
    }
}

@Composable
private fun Box(
    modifier: Modifier = Modifier,
    contentAlignment: Alignment = Alignment.TopStart,
    content: @Composable () -> Unit
) {
    androidx.compose.foundation.layout.Box(
        modifier = modifier,
        contentAlignment = contentAlignment,
        content = { content() }
    )
}

private fun getInteractionTypeInfo(type: String?): Pair<ImageVector, Color> {
    return when (type?.lowercase()) {
        "call" -> Icons.Default.Call to EzcarGreen
        "meeting" -> Icons.Default.Event to EzcarPurple
        "email" -> Icons.Default.Email to EzcarBlueBright
        "message", "sms", "text" -> Icons.AutoMirrored.Filled.Message to Color(0xFF2196F3)
        "test_drive" -> Icons.Default.Visibility to EzcarOrange
        "note" -> Icons.AutoMirrored.Filled.Note to Color.Gray
        else -> Icons.AutoMirrored.Filled.Note to Color.Gray
    }
}

private fun formatInteractionDate(date: java.util.Date): String {
    val now = java.util.Date()
    val diffMillis = now.time - date.time
    val diffDays = diffMillis / (1000 * 60 * 60 * 24)
    
    return when {
        diffDays < 1 -> {
            val diffHours = diffMillis / (1000 * 60 * 60)
            when {
                diffHours < 1 -> "Just now"
                diffHours < 24 -> "$diffHours h ago"
                else -> "Today"
            }
        }
        diffDays < 2 -> "Yesterday"
        diffDays < 7 -> "$diffDays days ago"
        else -> SimpleDateFormat("MMM dd", Locale.getDefault()).format(date)
    }
}

@Composable
fun InteractionTypeIcon(
    interactionType: String?,
    modifier: Modifier = Modifier,
    size: Int = 24
) {
    val (icon, color) = getInteractionTypeInfo(interactionType)
    
    Icon(
        imageVector = icon,
        contentDescription = interactionType,
        tint = color,
        modifier = modifier.size(size.dp)
    )
}

@Composable
fun InteractionSummaryRow(
    callsCount: Int,
    meetingsCount: Int,
    messagesCount: Int,
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = modifier
    ) {
        InteractionCountItem(
            icon = Icons.Default.Call,
            count = callsCount,
            label = "Calls",
            color = EzcarGreen
        )
        
        InteractionCountItem(
            icon = Icons.Default.Event,
            count = meetingsCount,
            label = "Meetings",
            color = EzcarPurple
        )
        
        InteractionCountItem(
            icon = Icons.AutoMirrored.Filled.Message,
            count = messagesCount,
            label = "Messages",
            color = Color(0xFF2196F3)
        )
    }
}

@Composable
private fun InteractionCountItem(
    icon: ImageVector,
    count: Int,
    label: String,
    color: Color
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = "$count $label",
            fontSize = 12.sp,
            color = Color.Gray
        )
    }
}
