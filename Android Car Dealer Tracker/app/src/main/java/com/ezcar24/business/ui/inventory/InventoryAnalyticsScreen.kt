package com.ezcar24.business.ui.inventory

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.ezcar24.business.ui.components.inventory.*
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun InventoryAnalyticsScreen(
    viewModel: InventoryAnalyticsViewModel = hiltViewModel(),
    onNavigateToVehicle: (String) -> Unit = {},
    onNavigateToAlerts: () -> Unit = {},
    onBack: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )
    
    var showFilterSheet by remember { mutableStateOf(false) }
    
    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { 
                    Text(
                        text = "Inventory Analytics",
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
                    IconButton(onClick = { showFilterSheet = true }) {
                        Icon(Icons.Default.FilterList, contentDescription = "Filter")
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
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Alert Banner (if there are alerts)
                if (uiState.alerts.isNotEmpty()) {
                    item {
                        InventoryAlertBanner(
                            alerts = uiState.alerts,
                            onDismiss = { /* Mark all as read */ },
                            onViewAll = onNavigateToAlerts
                        )
                    }
                }
                
                // Key Metrics Row
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        CompactHealthScore(
                            score = uiState.healthScore,
                            modifier = Modifier.weight(1f)
                        )
                        
                        CompactTurnoverMetrics(
                            averageDaysInInventory = uiState.averageDaysInInventory,
                            turnoverRatio = uiState.inventoryTurnoverRatio,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                
                // Total Value Card
                item {
                    TotalValueCard(
                        totalValue = uiState.totalInventoryValue,
                        totalHoldingCost = uiState.totalHoldingCost,
                        vehiclesOver90Days = uiState.vehiclesOver90Days,
                        totalVehicles = uiState.vehicles.size
                    )
                }
                
                // Aging Distribution
                item {
                    AgingDistributionChart(
                        distribution = uiState.agingDistribution
                    )
                }
                
                // Burning Inventory
                item {
                    BurningInventoryList(
                        vehicles = uiState.vehicles,
                        stats = uiState.inventoryStats,
                        onVehicleClick = onNavigateToVehicle,
                        maxItems = 5
                    )
                }
                
                // Top Performers
                item {
                    TopPerformerCard(
                        vehicles = uiState.vehicles,
                        stats = uiState.inventoryStats,
                        onVehicleClick = onNavigateToVehicle,
                        isBest = true
                    )
                }
                
                // Needs Attention
                item {
                    TopPerformerCard(
                        vehicles = uiState.vehicles,
                        stats = uiState.inventoryStats,
                        onVehicleClick = onNavigateToVehicle,
                        isBest = false
                    )
                }
                
                // Full ROI Table
                item {
                    ROITable(
                        vehicles = uiState.vehicles,
                        stats = uiState.inventoryStats,
                        onVehicleClick = onNavigateToVehicle,
                        maxItems = 10
                    )
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
    
    // Filter Bottom Sheet
    if (showFilterSheet) {
        FilterBottomSheet(
            selectedAgingBucket = uiState.selectedAgingBucket,
            selectedStatus = uiState.selectedStatus,
            selectedSort = uiState.sortBy,
            onAgingBucketSelected = { viewModel.setAgingBucketFilter(it) },
            onStatusSelected = { viewModel.setStatusFilter(it) },
            onSortSelected = { viewModel.setSortOption(it) },
            onDismiss = { showFilterSheet = false }
        )
    }
}

@Composable
private fun TotalValueCard(
    totalValue: java.math.BigDecimal,
    totalHoldingCost: java.math.BigDecimal,
    vehiclesOver90Days: Int,
    totalVehicles: Int
) {
    val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
    
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .padding(20.dp)
    ) {
        Text(
            text = "Total Inventory Value",
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )
        
        Text(
            text = currencyFormat.format(totalValue).replace("$", "AED "),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = EzcarNavy
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            ValueMetric(
                label = "Holding Cost",
                value = currencyFormat.format(totalHoldingCost).replace("$", "AED "),
                color = EzcarOrange
            )
            
            ValueMetric(
                label = "90+ Days",
                value = "$vehiclesOver90Days vehicles",
                color = if (vehiclesOver90Days > 0) EzcarDanger else EzcarGreen
            )
            
            ValueMetric(
                label = "Total Units",
                value = "$totalVehicles",
                color = EzcarBlueBright
            )
        }
    }
}

@Composable
private fun ValueMetric(
    label: String,
    value: String,
    color: Color
) {
    Column {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = color
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = Color.Gray
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterBottomSheet(
    selectedAgingBucket: String?,
    selectedStatus: String?,
    selectedSort: InventorySortOption,
    onAgingBucketSelected: (String?) -> Unit,
    onStatusSelected: (String?) -> Unit,
    onSortSelected: (InventorySortOption) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState()
    
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Text(
                text = "Filter & Sort",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Aging Bucket Filter
            Text(
                text = "Aging Bucket",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = selectedAgingBucket == null,
                    onClick = { onAgingBucketSelected(null) },
                    label = { Text("All") }
                )
                FilterChip(
                    selected = selectedAgingBucket == "0-30",
                    onClick = { onAgingBucketSelected("0-30") },
                    label = { Text("0-30 days") }
                )
                FilterChip(
                    selected = selectedAgingBucket == "31-60",
                    onClick = { onAgingBucketSelected("31-60") },
                    label = { Text("31-60 days") }
                )
                FilterChip(
                    selected = selectedAgingBucket == "61-90",
                    onClick = { onAgingBucketSelected("61-90") },
                    label = { Text("61-90 days") }
                )
                FilterChip(
                    selected = selectedAgingBucket == "90+",
                    onClick = { onAgingBucketSelected("90+") },
                    label = { Text("90+ days") }
                )
            }
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Status Filter
            Text(
                text = "Status",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = selectedStatus == null,
                    onClick = { onStatusSelected(null) },
                    label = { Text("All") }
                )
                FilterChip(
                    selected = selectedStatus == "owned",
                    onClick = { onStatusSelected("owned") },
                    label = { Text("Owned") }
                )
                FilterChip(
                    selected = selectedStatus == "on_sale",
                    onClick = { onStatusSelected("on_sale") },
                    label = { Text("On Sale") }
                )
                FilterChip(
                    selected = selectedStatus == "in_transit",
                    onClick = { onStatusSelected("in_transit") },
                    label = { Text("In Transit") }
                )
            }
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Sort Options
            Text(
                text = "Sort By",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Column {
                SortOptionRow(
                    label = "Days in Inventory",
                    isSelected = selectedSort == InventorySortOption.DAYS_DESC || selectedSort == InventorySortOption.DAYS_ASC,
                    isAscending = selectedSort == InventorySortOption.DAYS_ASC,
                    onClick = {
                        onSortSelected(
                            if (selectedSort == InventorySortOption.DAYS_DESC) 
                                InventorySortOption.DAYS_ASC 
                            else 
                                InventorySortOption.DAYS_DESC
                        )
                    }
                )
                
                SortOptionRow(
                    label = "ROI",
                    isSelected = selectedSort == InventorySortOption.ROI_DESC || selectedSort == InventorySortOption.ROI_ASC,
                    isAscending = selectedSort == InventorySortOption.ROI_ASC,
                    onClick = {
                        onSortSelected(
                            if (selectedSort == InventorySortOption.ROI_DESC) 
                                InventorySortOption.ROI_ASC 
                            else 
                                InventorySortOption.ROI_DESC
                        )
                    }
                )
                
                SortOptionRow(
                    label = "Profit Estimate",
                    isSelected = selectedSort == InventorySortOption.PROFIT_DESC || selectedSort == InventorySortOption.PROFIT_ASC,
                    isAscending = selectedSort == InventorySortOption.PROFIT_ASC,
                    onClick = {
                        onSortSelected(
                            if (selectedSort == InventorySortOption.PROFIT_DESC) 
                                InventorySortOption.PROFIT_ASC 
                            else 
                                InventorySortOption.PROFIT_DESC
                        )
                    }
                )
            }
            
            Spacer(modifier = Modifier.height(20.dp))
            
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Done")
            }
            
            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SortOptionRow(
    label: String,
    isSelected: Boolean,
    isAscending: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = if (isSelected) EzcarNavy else Color.Black
        )
        
        if (isSelected) {
            Icon(
                imageVector = if (isAscending) Icons.Default.ArrowUpward else Icons.Default.ArrowDownward,
                contentDescription = null,
                tint = EzcarNavy
            )
        }
    }
}
