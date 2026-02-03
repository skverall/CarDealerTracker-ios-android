package com.ezcar24.business.ui.components.inventory

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.data.local.InventoryAlert
import com.ezcar24.business.data.local.InventoryAlertType
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning

@Composable
fun InventoryAlertBanner(
    alerts: List<InventoryAlert>,
    onDismiss: () -> Unit,
    onViewAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    val criticalCount = alerts.count { it.severity == "high" }
    val warningCount = alerts.count { it.severity == "medium" }
    
    val backgroundColor = when {
        criticalCount > 0 -> EzcarDanger.copy(alpha = 0.1f)
        warningCount > 0 -> EzcarOrange.copy(alpha = 0.1f)
        else -> EzcarWarning.copy(alpha = 0.1f)
    }
    
    val iconColor = when {
        criticalCount > 0 -> EzcarDanger
        warningCount > 0 -> EzcarOrange
        else -> EzcarWarning
    }
    
    val icon = when {
        criticalCount > 0 -> Icons.Default.Error
        warningCount > 0 -> Icons.Default.Warning
        else -> Icons.Default.Info
    }
    
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(backgroundColor)
            .clickable(onClick = onViewAll)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(iconColor.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center
        ) {
            BadgedBox(
                badge = {
                    if (alerts.isNotEmpty()) {
                        Badge(
                            containerColor = iconColor,
                            contentColor = Color.White
                        ) {
                            Text(alerts.size.toString())
                        }
                    }
                }
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(24.dp)
                )
            }
        }
        
        Spacer(modifier = Modifier.width(16.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = when {
                    criticalCount > 0 -> "$criticalCount Critical Alerts"
                    warningCount > 0 -> "$warningCount Warnings"
                    else -> "${alerts.size} Notifications"
                },
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color.Black
            )
            Text(
                text = "Tap to view inventory alerts",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        
        IconButton(onClick = onDismiss) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "Dismiss",
                tint = Color.Gray
            )
        }
    }
}

@Composable
fun InventoryAlertItem(
    alert: InventoryAlert,
    onDismiss: () -> Unit,
    onViewVehicle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val (icon, iconColor, bgColor) = when (alert.severity) {
        "high" -> Triple(Icons.Default.Error, EzcarDanger, EzcarDanger.copy(alpha = 0.1f))
        "medium" -> Triple(Icons.Default.Warning, EzcarOrange, EzcarOrange.copy(alpha = 0.1f))
        else -> Triple(Icons.Default.Info, EzcarWarning, EzcarWarning.copy(alpha = 0.1f))
    }
    
    val alertTypeLabel = when (alert.alertType) {
        InventoryAlertType.aging_90_days -> "Aging Alert"
        InventoryAlertType.aging_60_days -> "Aging Warning"
        InventoryAlertType.low_roi -> "Low ROI"
        InventoryAlertType.high_holding_cost -> "High Holding Cost"
        InventoryAlertType.price_reduction_needed -> "Price Reduction"
    }
    
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(bgColor)
            .clickable(onClick = onViewVehicle)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(iconColor.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier.size(20.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(12.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = alertTypeLabel,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Black
                )
                
                Spacer(modifier = Modifier.width(8.dp))
                
                Surface(
                    color = iconColor.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Text(
                        text = alert.severity.uppercase(),
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = iconColor
                    )
                }
            }
            
            Text(
                text = alert.message,
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray,
                maxLines = 2
            )
        }
        
        IconButton(onClick = onDismiss) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "Dismiss",
                tint = Color.Gray,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
fun AlertSeverityBadge(
    severity: String,
    modifier: Modifier = Modifier
) {
    val (color, label) = when (severity) {
        "high" -> EzcarDanger to "Critical"
        "medium" -> EzcarOrange to "Warning"
        else -> EzcarWarning to "Info"
    }
    
    Surface(
        color = color.copy(alpha = 0.1f),
        shape = RoundedCornerShape(6.dp),
        modifier = modifier
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = color
        )
    }
}
