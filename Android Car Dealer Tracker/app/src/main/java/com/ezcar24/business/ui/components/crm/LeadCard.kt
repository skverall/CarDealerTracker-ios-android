package com.ezcar24.business.ui.components.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal

@Composable
fun LeadCard(
    client: Client,
    onClick: () -> Unit,
    onCall: (() -> Unit)? = null,
    onMessage: (() -> Unit)? = null,
    onEmail: (() -> Unit)? = null,
    onChangeStage: ((LeadStage) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    var showMenu by remember { mutableStateOf(false) }
    
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Top Row: Name, Priority, Menu
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f)
                ) {
                    // Avatar placeholder
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .background(EzcarBlueBright.copy(alpha = 0.1f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Person,
                            contentDescription = null,
                            tint = EzcarBlueBright,
                            modifier = Modifier.size(24.dp)
                        )
                    }
                    
                    Spacer(modifier = Modifier.width(12.dp))
                    
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = client.name,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        
                        if (client.phone != null) {
                            Text(
                                text = client.phone,
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.Gray
                            )
                        }
                    }
                }
                
                // Priority indicator
                if (client.priority > 0) {
                    LeadPriorityIndicator(
                        priority = client.priority,
                        showLabel = false
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                
                // Menu
                Box {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "More options")
                    }
                    
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        LeadStage.values().forEach { stage ->
                            if (stage != client.leadStage) {
                                DropdownMenuItem(
                                    text = { Text("Move to ${getStageDisplayName(stage)}") },
                                    onClick = {
                                        onChangeStage?.invoke(stage)
                                        showMenu = false
                                    }
                                )
                            }
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // Stage and Source row
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                LeadStageBadge(stage = client.leadStage)
                LeadSourceBadge(source = client.leadSource)
            }
            
            // Estimated value
            if (client.estimatedValue != null && client.estimatedValue > BigDecimal.ZERO) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Est. Value: ${formatCurrency(client.estimatedValue)}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = EzcarBlueBright
                )
            }
            
            // Notes preview
            if (!client.notes.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = client.notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            
            // Action buttons
            if (onCall != null || onMessage != null || onEmail != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (onEmail != null && client.email != null) {
                        IconButton(
                            onClick = onEmail,
                            modifier = Modifier
                                .size(36.dp)
                                .background(Color.LightGray.copy(alpha = 0.2f), CircleShape)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Email,
                                contentDescription = "Email",
                                tint = EzcarBlueBright,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    
                    if (onMessage != null && client.phone != null) {
                        IconButton(
                            onClick = onMessage,
                            modifier = Modifier
                                .size(36.dp)
                                .background(Color.LightGray.copy(alpha = 0.2f), CircleShape)
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.Message,
                                contentDescription = "Message",
                                tint = Color(0xFF4CAF50),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    
                    if (onCall != null && client.phone != null) {
                        IconButton(
                            onClick = onCall,
                            modifier = Modifier
                                .size(36.dp)
                                .background(EzcarBlueBright.copy(alpha = 0.1f), CircleShape)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Call,
                                contentDescription = "Call",
                                tint = EzcarBlueBright,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
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

private fun getStageDisplayName(stage: LeadStage): String {
    return when (stage) {
        LeadStage.new -> "New"
        LeadStage.contacted -> "Contacted"
        LeadStage.qualified -> "Qualified"
        LeadStage.negotiation -> "Negotiation"
        LeadStage.offer -> "Offer"
        LeadStage.test_drive -> "Test Drive"
        LeadStage.closed_won -> "Won"
        LeadStage.closed_lost -> "Lost"
    }
}

@Composable
private fun formatCurrency(amount: BigDecimal): String {
    val regionSettingsManager = rememberRegionSettingsManager()
    return regionSettingsManager.formatCurrency(amount)
}

@Composable
fun LeadCardCompact(
    client: Client,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(EzcarBlueBright.copy(alpha = 0.1f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    tint = EzcarBlueBright,
                    modifier = Modifier.size(20.dp)
                )
            }
            
            Spacer(modifier = Modifier.width(12.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = client.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    LeadStageBadge(stage = client.leadStage)
                    if (client.estimatedValue != null && client.estimatedValue > BigDecimal.ZERO) {
                        Text(
                            text = formatCurrency(client.estimatedValue),
                            fontSize = 12.sp,
                            color = EzcarBlueBright,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
            
            if (client.priority > 0) {
                LeadPriorityIndicator(
                    priority = client.priority,
                    showLabel = false
                )
            }
        }
    }
}
