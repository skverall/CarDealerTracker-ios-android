package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.data.local.InventoryAlert
import com.ezcar24.business.data.local.InventoryAlertType

@Composable
fun InventoryAlertCard(
    alert: InventoryAlert,
    modifier: Modifier = Modifier
) {
    val (icon, iconColor, bgColor) = when (alert.alertType) {
        InventoryAlertType.aging_90_days -> 
            Triple(Icons.Default.Warning, EzcarDanger, EzcarDanger.copy(alpha = 0.1f))
        InventoryAlertType.aging_60_days -> 
            Triple(Icons.Default.Schedule, EzcarOrange, EzcarOrange.copy(alpha = 0.1f))
        InventoryAlertType.low_roi -> 
            Triple(Icons.Default.TrendingDown, EzcarDanger, EzcarDanger.copy(alpha = 0.1f))
        InventoryAlertType.high_holding_cost -> 
            Triple(Icons.Default.AttachMoney, EzcarWarning, EzcarWarning.copy(alpha = 0.1f))
        InventoryAlertType.price_reduction_needed -> 
            Triple(Icons.Default.PriceChange, EzcarOrange, EzcarOrange.copy(alpha = 0.1f))
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(bgColor, RoundedCornerShape(12.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(iconColor.copy(alpha = 0.2f), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier.size(24.dp)
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = getAlertTitle(alert.alertType),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.Black
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = alert.message,
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
    }
}

@Composable
fun InventoryAlertList(
    alerts: List<InventoryAlert>,
    modifier: Modifier = Modifier
) {
    if (alerts.isEmpty()) return

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = "Alerts (${alerts.size})",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = Color.Black
        )

        alerts.forEach { alert ->
            InventoryAlertCard(alert = alert)
        }
    }
}

@Composable
fun CompactAlertBadge(
    count: Int,
    modifier: Modifier = Modifier
) {
    if (count <= 0) return

    val color = when {
        count >= 3 -> EzcarDanger
        count >= 2 -> EzcarOrange
        else -> EzcarWarning
    }

    Box(
        modifier = modifier
            .background(color, RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(
            text = count.toString(),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
    }
}

private fun getAlertTitle(type: InventoryAlertType): String {
    return when (type) {
        InventoryAlertType.aging_90_days -> "90+ Days in Inventory"
        InventoryAlertType.aging_60_days -> "60+ Days in Inventory"
        InventoryAlertType.low_roi -> "Low ROI Warning"
        InventoryAlertType.high_holding_cost -> "High Holding Cost"
        InventoryAlertType.price_reduction_needed -> "Price Reduction Recommended"
    }
}
