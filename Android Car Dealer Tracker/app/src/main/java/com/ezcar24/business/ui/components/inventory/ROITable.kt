package com.ezcar24.business.ui.components.inventory

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.ui.theme.EzcarWarning
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

enum class ROISortColumn {
    VEHICLE, ROI, PROFIT, DAYS, TOTAL_COST
}

enum class ROISortDirection {
    ASC, DESC
}

@Composable
fun ROITable(
    vehicles: List<Vehicle>,
    stats: Map<String, VehicleInventoryStats>,
    onVehicleClick: (String) -> Unit,
    modifier: Modifier = Modifier,
    maxItems: Int = 10
) {
    var sortColumn by remember { mutableStateOf(ROISortColumn.ROI) }
    var sortDirection by remember { mutableStateOf(ROISortDirection.DESC) }
    
    val sortedVehicles = remember(vehicles, stats, sortColumn, sortDirection) {
        val sorted = when (sortColumn) {
            ROISortColumn.VEHICLE -> vehicles.sortedBy { "${it.make} ${it.model}" }
            ROISortColumn.ROI -> vehicles.sortedBy { 
                stats[it.id.toString()]?.roiPercent ?: BigDecimal.ZERO 
            }
            ROISortColumn.PROFIT -> vehicles.sortedBy { 
                stats[it.id.toString()]?.profitEstimate ?: BigDecimal.ZERO 
            }
            ROISortColumn.DAYS -> vehicles.sortedBy { 
                stats[it.id.toString()]?.daysInInventory ?: 0 
            }
            ROISortColumn.TOTAL_COST -> vehicles.sortedBy { 
                stats[it.id.toString()]?.totalCost ?: BigDecimal.ZERO 
            }
        }
        
        if (sortDirection == ROISortDirection.DESC) sorted.reversed() else sorted
    }.take(maxItems)
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Text(
            text = "ROI Leaderboard",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = Color.Black
        )
        
        Spacer(modifier = Modifier.height(12.dp))
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            SortableHeader(
                text = "Vehicle",
                isSorted = sortColumn == ROISortColumn.VEHICLE,
                direction = sortDirection,
                modifier = Modifier.weight(2f),
                onClick = {
                    if (sortColumn == ROISortColumn.VEHICLE) {
                        sortDirection = if (sortDirection == ROISortDirection.ASC) 
                            ROISortDirection.DESC else ROISortDirection.ASC
                    } else {
                        sortColumn = ROISortColumn.VEHICLE
                        sortDirection = ROISortDirection.ASC
                    }
                }
            )
            
            SortableHeader(
                text = "ROI",
                isSorted = sortColumn == ROISortColumn.ROI,
                direction = sortDirection,
                modifier = Modifier.weight(1f),
                onClick = {
                    if (sortColumn == ROISortColumn.ROI) {
                        sortDirection = if (sortDirection == ROISortDirection.ASC) 
                            ROISortDirection.DESC else ROISortDirection.ASC
                    } else {
                        sortColumn = ROISortColumn.ROI
                        sortDirection = ROISortDirection.DESC
                    }
                }
            )
            
            SortableHeader(
                text = "Days",
                isSorted = sortColumn == ROISortColumn.DAYS,
                direction = sortDirection,
                modifier = Modifier.weight(0.8f),
                onClick = {
                    if (sortColumn == ROISortColumn.DAYS) {
                        sortDirection = if (sortDirection == ROISortDirection.ASC) 
                            ROISortDirection.DESC else ROISortDirection.ASC
                    } else {
                        sortColumn = ROISortColumn.DAYS
                        sortDirection = ROISortDirection.ASC
                    }
                }
            )
        }
        
        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
        
        sortedVehicles.forEach { vehicle ->
            val vehicleStats = stats[vehicle.id.toString()]
            ROITableRow(
                vehicle = vehicle,
                stats = vehicleStats,
                onClick = { onVehicleClick(vehicle.id.toString()) }
            )
            
            if (vehicle != sortedVehicles.last()) {
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 8.dp),
                    color = Color(0xFFF2F2F7)
                )
            }
        }
    }
}

@Composable
private fun SortableHeader(
    text: String,
    isSorted: Boolean,
    direction: ROISortDirection,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = if (isSorted) FontWeight.Bold else FontWeight.Normal,
            color = if (isSorted) Color.Black else Color.Gray
        )
        
        if (isSorted) {
            Icon(
                imageVector = if (direction == ROISortDirection.ASC) 
                    Icons.Default.ArrowUpward else Icons.Default.ArrowDownward,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = Color.Black
            )
        }
    }
}

@Composable
private fun ROITableRow(
    vehicle: Vehicle,
    stats: VehicleInventoryStats?,
    onClick: () -> Unit
) {
    val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier.weight(2f)
        ) {
            Text(
                text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = Color.Black,
                maxLines = 1
            )
            Text(
                text = vehicle.vin.takeLast(6),
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        
        Box(modifier = Modifier.weight(1f)) {
            ROIBadge(roiPercent = stats?.roiPercent)
        }
        
        val daysColor = when {
            (stats?.daysInInventory ?: 0) <= 30 -> EzcarGreen
            (stats?.daysInInventory ?: 0) <= 60 -> EzcarWarning
            (stats?.daysInInventory ?: 0) <= 90 -> EzcarOrange
            else -> EzcarDanger
        }
        
        Text(
            text = "${stats?.daysInInventory ?: 0}d",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = daysColor,
            modifier = Modifier.weight(0.8f)
        )
    }
}

@Composable
fun TopPerformerCard(
    vehicles: List<Vehicle>,
    stats: Map<String, VehicleInventoryStats>,
    onVehicleClick: (String) -> Unit,
    modifier: Modifier = Modifier,
    isBest: Boolean = true
) {
    val sortedByROI = remember(vehicles, stats) {
        vehicles.sortedBy { stats[it.id.toString()]?.roiPercent ?: BigDecimal.ZERO }
            .let { if (isBest) it.reversed() else it }
            .take(3)
    }
    
    val title = if (isBest) "Top Performers" else "Needs Attention"
    val icon = if (isBest) Icons.Default.TrendingUp else Icons.Default.TrendingDown
    val color = if (isBest) EzcarSuccess else EzcarDanger
    
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.Black
            )
        }
        
        Spacer(modifier = Modifier.height(12.dp))
        
        sortedByROI.forEachIndexed { index, vehicle ->
            val vehicleStats = stats[vehicle.id.toString()]
            
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onVehicleClick(vehicle.id.toString()) }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(color.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "${index + 1}",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.Bold,
                        color = color
                    )
                }
                
                Spacer(modifier = Modifier.width(12.dp))
                
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        color = Color.Black,
                        maxLines = 1
                    )
                    Text(
                        text = vehicle.vin.takeLast(6),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
                
                ROIBadge(roiPercent = vehicleStats?.roiPercent)
            }
            
            if (index < sortedByROI.size - 1) {
                HorizontalDivider(color = Color(0xFFF2F2F7))
            }
        }
    }
}
