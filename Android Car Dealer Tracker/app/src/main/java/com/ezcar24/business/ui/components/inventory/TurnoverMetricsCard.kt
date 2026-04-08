package com.ezcar24.business.ui.components.inventory

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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal

@Composable
fun TurnoverMetricsCard(
    totalInventoryValue: BigDecimal,
    averageDaysInInventory: Int,
    turnoverRatio: Double,
    totalVehicles: Int,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Text(
            text = "Turnover Metrics",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = Color.Black
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            MetricItem(
                icon = Icons.Default.Inventory,
                label = "Total Value",
                value = regionSettingsManager.formatCurrency(totalInventoryValue),
                color = EzcarNavy,
                modifier = Modifier.weight(1f)
            )
            
            MetricItem(
                icon = Icons.Default.Schedule,
                label = "Avg Days",
                value = "$averageDaysInInventory",
                color = EzcarOrange,
                modifier = Modifier.weight(1f)
            )
        }
        
        Spacer(modifier = Modifier.height(12.dp))
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            MetricItem(
                icon = Icons.Default.TrendingUp,
                label = "Turnover",
                value = String.format("%.1fx", turnoverRatio),
                color = EzcarGreen,
                modifier = Modifier.weight(1f)
            )
            
            MetricItem(
                icon = Icons.Default.DirectionsCar,
                label = "Vehicles",
                value = totalVehicles.toString(),
                color = EzcarBlueBright,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun MetricItem(
    icon: ImageVector,
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.1f)),
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
        
        Column {
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }
    }
}

@Composable
fun CompactTurnoverMetrics(
    averageDaysInInventory: Int,
    turnoverRatio: Double,
    modifier: Modifier = Modifier
) {
    val daysColor = when {
        averageDaysInInventory <= 45 -> EzcarGreen
        averageDaysInInventory <= 75 -> EzcarWarning
        else -> EzcarOrange
    }
    
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White)
            .padding(16.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        CompactMetric(
            label = "Avg Days",
            value = "$averageDaysInInventory",
            color = daysColor
        )
        
        Box(
            modifier = Modifier
                .width(1.dp)
                .height(40.dp)
                .background(Color(0xFFE5E5EA))
        )
        
        CompactMetric(
            label = "Turnover",
            value = String.format("%.1fx", turnoverRatio),
            color = EzcarGreen
        )
    }
}

@Composable
private fun CompactMetric(
    label: String,
    value: String,
    color: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
    }
}
