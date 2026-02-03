package com.ezcar24.business.ui.inventory

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.InventoryAlertType
import com.ezcar24.business.ui.components.inventory.AlertSeverityBadge
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarWarning
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun InventoryAlertsScreen(
    viewModel: InventoryAlertsViewModel = hiltViewModel(),
    onNavigateToVehicle: (String) -> Unit = {},
    onBack: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )
    
    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { 
                    Text(
                        text = "Inventory Alerts",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (uiState.unreadCount > 0) {
                        TextButton(onClick = { viewModel.markAllAsRead() }) {
                            Text("Mark All Read")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.White
                )
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pullRefresh(pullRefreshState)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Filter Chips
                item {
                    AlertFilterChips(
                        selectedSeverity = uiState.selectedSeverity,
                        selectedType = uiState.selectedType,
                        onSeveritySelected = { viewModel.setSeverityFilter(it) },
                        onTypeSelected = { viewModel.setTypeFilter(it) },
                        criticalCount = viewModel.getSeverityCount("high"),
                        warningCount = viewModel.getSeverityCount("medium"),
                        infoCount = viewModel.getSeverityCount("low")
                    )
                }
                
                // Alert Stats
                item {
                    AlertStatsRow(
                        totalAlerts = uiState.alerts.size,
                        unreadCount = uiState.unreadCount,
                        criticalCount = viewModel.getSeverityCount("high")
                    )
                }
                
                // Alerts List
                items(
                    items = uiState.alerts,
                    key = { it.alert.id.toString() }
                ) { alertWithVehicle ->
                    AlertListItem(
                        alertWithVehicle = alertWithVehicle,
                        onClick = { 
                            alertWithVehicle.vehicle?.let {
                                onNavigateToVehicle(it.id.toString())
                            }
                            viewModel.markAsRead(alertWithVehicle.alert.id)
                        },
                        onDismiss = { viewModel.dismissAlert(alertWithVehicle.alert.id) }
                    )
                }
                
                // Empty State
                if (uiState.alerts.isEmpty() && !uiState.isLoading) {
                    item {
                        EmptyAlertsState()
                    }
                }
                
                // Bottom spacing
                item {
                    Spacer(modifier = Modifier.height(32.dp))
                }
            }
            
            PullRefreshIndicator(
                refreshing = uiState.isLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter),
                backgroundColor = Color.White,
                contentColor = EzcarGreen
            )
        }
    }
}

@Composable
private fun AlertFilterChips(
    selectedSeverity: String?,
    selectedType: InventoryAlertType?,
    onSeveritySelected: (String?) -> Unit,
    onTypeSelected: (InventoryAlertType?) -> Unit,
    criticalCount: Int,
    warningCount: Int,
    infoCount: Int
) {
    Column {
        // Severity Filters
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = selectedSeverity == null && selectedType == null,
                onClick = { 
                    onSeveritySelected(null)
                    onTypeSelected(null)
                },
                label = { Text("All") }
            )
            
            FilterChip(
                selected = selectedSeverity == "high",
                onClick = { onSeveritySelected("high") },
                label = { 
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Critical")
                        if (criticalCount > 0) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Badge(
                                containerColor = EzcarDanger,
                                contentColor = Color.White
                            ) {
                                Text(criticalCount.toString())
                            }
                        }
                    }
                },
                leadingIcon = if (selectedSeverity == "high") {
                    { Icon(Icons.Default.Error, null, modifier = Modifier.size(18.dp)) }
                } else null
            )
            
            FilterChip(
                selected = selectedSeverity == "medium",
                onClick = { onSeveritySelected("medium") },
                label = { 
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Warning")
                        if (warningCount > 0) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Badge(
                                containerColor = EzcarOrange,
                                contentColor = Color.White
                            ) {
                                Text(warningCount.toString())
                            }
                        }
                    }
                },
                leadingIcon = if (selectedSeverity == "medium") {
                    { Icon(Icons.Default.Warning, null, modifier = Modifier.size(18.dp)) }
                } else null
            )
            
            FilterChip(
                selected = selectedSeverity == "low",
                onClick = { onSeveritySelected("low") },
                label = { 
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Info")
                        if (infoCount > 0) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Badge(
                                containerColor = EzcarWarning,
                                contentColor = Color.Black
                            ) {
                                Text(infoCount.toString())
                            }
                        }
                    }
                },
                leadingIcon = if (selectedSeverity == "low") {
                    { Icon(Icons.Default.Info, null, modifier = Modifier.size(18.dp)) }
                } else null
            )
        }
        
        Spacer(modifier = Modifier.height(8.dp))
        
        // Type Filters
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            InventoryAlertType.values().forEach { type ->
                val isSelected = selectedType == type
                FilterChip(
                    selected = isSelected,
                    onClick = { 
                        onTypeSelected(if (isSelected) null else type)
                    },
                    label = { Text(getAlertTypeLabel(type)) }
                )
            }
        }
    }
}

@Composable
private fun AlertStatsRow(
    totalAlerts: Int,
    unreadCount: Int,
    criticalCount: Int
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        AlertStatCard(
            label = "Total",
            value = totalAlerts.toString(),
            icon = Icons.Default.Notifications,
            color = EzcarGreen,
            modifier = Modifier.weight(1f)
        )
        
        AlertStatCard(
            label = "Unread",
            value = unreadCount.toString(),
            icon = Icons.Default.MarkEmailUnread,
            color = EzcarWarning,
            modifier = Modifier.weight(1f)
        )
        
        AlertStatCard(
            label = "Critical",
            value = criticalCount.toString(),
            icon = Icons.Default.Error,
            color = EzcarDanger,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun AlertStatCard(
    label: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(24.dp)
        )
        
        Spacer(modifier = Modifier.height(8.dp))
        
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

@Composable
private fun AlertListItem(
    alertWithVehicle: AlertWithVehicle,
    onClick: () -> Unit,
    onDismiss: () -> Unit
) {
    val alert = alertWithVehicle.alert
    val vehicle = alertWithVehicle.vehicle
    val dateFormat = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault())
    
    val (icon, iconColor, bgColor) = when (alert.severity) {
        "high" -> Triple(Icons.Default.Error, EzcarDanger, EzcarDanger.copy(alpha = 0.1f))
        "medium" -> Triple(Icons.Default.Warning, EzcarOrange, EzcarOrange.copy(alpha = 0.1f))
        else -> Triple(Icons.Default.Info, EzcarWarning, EzcarWarning.copy(alpha = 0.1f))
    }
    
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (alert.isRead) Color.White else bgColor
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = if (alert.isRead) 0.dp else 2.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
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
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            Spacer(modifier = Modifier.width(16.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = getAlertTypeLabel(alert.alertType),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                    
                    if (!alert.isRead) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .background(iconColor)
                        )
                    }
                }
                
                vehicle?.let {
                    Text(
                        text = "${it.make ?: ""} ${it.model ?: ""} (${it.vin.takeLast(6)})",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
                
                Text(
                    text = alert.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.DarkGray,
                    maxLines = 2
                )
                
                Text(
                    text = dateFormat.format(alert.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
            }
            
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss",
                    tint = Color.Gray,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}

@Composable
private fun EmptyAlertsState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = EzcarGreen,
            modifier = Modifier.size(64.dp)
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Text(
            text = "No Alerts",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = EzcarGreen
        )
        
        Text(
            text = "Your inventory is in good shape",
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )
    }
}

private fun getAlertTypeLabel(type: InventoryAlertType): String {
    return when (type) {
        InventoryAlertType.aging_90_days -> "90+ Days"
        InventoryAlertType.aging_60_days -> "60+ Days"
        InventoryAlertType.low_roi -> "Low ROI"
        InventoryAlertType.high_holding_cost -> "High Cost"
        InventoryAlertType.price_reduction_needed -> "Price Drop"
    }
}
