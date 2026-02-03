<parameter name="path">Android Car Dealer Tracker/app/src/main/java/com/ezcar24/business/ui/components/inventory/BurningInventoryList.kt</parameter>
<parameter name="content">package com.ezcar24.business.ui.components.inventory

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleInventoryStats
import com.ezcar24.business.ui.components.ROIBadge
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

@Composable
fun BurningInventoryList(
    vehicles: List<Vehicle>,
    stats: Map<String, VehicleInventoryStats>,
    onVehicleClick: (String) -> Unit,
    modifier: Modifier = Modifier,
    maxItems: Int = 5
) {
    val burningVehicles = remember(vehicles, stats) {
        vehicles.filter { vehicle ->
            val vehicleStats = stats[vehicle.id.toString()]
            (vehicleStats?.daysInInventory ?: 0) >= 90 ||
            (vehicleStats?.roiPercent?.compareTo(BigDecimal("15")) ?: 1) < 0
        }.sortedBy { stats[it.id.toString()]?.daysInInventory ?: 0 }
            .reversed()
            .take(maxItems)
    }
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = EzcarDanger,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Burning Inventory",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Black
                )
            }
            
            Badge(
                containerColor = EzcarDanger.copy(alpha = 0.1f),
                contentColor = EzcarDanger
            ) {
                Text(
                    text = burningVehicles.size.toString(),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
        }
        
        if (burningVehicles.isEmpty()) {
            Spacer(modifier = Modifier.height(16.dp))
            EmptyBurningState()
        } else {
            Spacer(modifier = Modifier.height(12.dp))
            
            burningVehicles.forEachIndexed { index, vehicle ->
                val vehicleStats = stats[vehicle.id.toString()]
                BurningVehicleItem(
                    vehicle = vehicle,
                    stats = vehicleStats,
                    onClick = { onVehicleClick(vehicle.id.toString()) }
                )
                
                if (index < burningVehicles.size - 1) {
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 8.dp),
                        color = Color(0xFFF2F2F7)
                    )
                }
            }
        }
    }
}

@Composable
private fun BurningVehicleItem(
    vehicle: Vehicle,
    stats: VehicleInventoryStats?,
    onClick: () -> Unit
) {
    val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
    
    val isCritical = (stats?.daysInInventory ?: 0) >= 120
    val backgroundColor = if (isCritical) EzcarDanger.copy(alpha = 0.05f) else Color.Transparent
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(backgroundColor)
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Black,
                    maxLines = 1
                )
                
                if (isCritical) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Surface(
                        color = EzcarDanger,
                        shape = RoundedCornerShape(4.dp)
                    ) {
                        Text(
                            text = "CRITICAL",
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }
            }
            
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                val days = stats?.daysInInventory ?: 0
                val daysColor = when {
                    days >= 120 -> EzcarDanger
                    days >= 90 -> EzcarOrange
                    days >= 60 -> EzcarWarning
                    else -> EzcarGreen
                }
                
                Text(
                    text = "$days days in inventory",
                    style = MaterialTheme.typography.bodySmall,
                    color = daysColor
                )
                
                Text(
                    text = "•",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
                
                Text(
                    text = currencyFormat.format(stats?.totalCost ?: BigDecimal.ZERO).replace("$", "AED "),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
        }
        
        ROIBadge(roiPercent = stats?.roiPercent)
    }
}

@Composable
private fun EmptyBurningState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = EzcarGreen,
            modifier = Modifier.size(48.dp)
        )
        
        Spacer(modifier = Modifier.height(12.dp))
        
        Text(
            text = "No Burning Inventory",
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = EzcarGreen
        )
        
        Text(
            text = "All vehicles are within healthy aging thresholds",
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
    }
}

@Composable
fun BurningInventoryMiniCard(
    count: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val backgroundColor = when {
        count == 0 -> EzcarGreen.copy(alpha = 0.1f)
        count <= 3 -> EzcarWarning.copy(alpha = 0.1f)
        else -> EzcarDanger.copy(alpha = 0.1f)
    }
    
    val iconColor = when {
        count == 0 -> EzcarGreen
        count <= 3 -> EzcarWarning
        else -> EzcarDanger
    }
    
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(backgroundColor)
            .clickable(onClick = onClick)
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
            Icon(
                imageVector = if (count == 0) Icons.Default.CheckCircle else Icons.Default.Warning,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier.size(24.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(16.dp))
        
        Column {
            Text(
                text = if (count == 0) "All Good" else "$count Vehicles",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = iconColor
            )
            Text(
                text = if (count == 0) "No burning inventory" else "Need attention (90+ days)",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        
        Spacer(modifier = Modifier.weight(1f))
        
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = Color.Gray
        )
    }
}
</parameter>