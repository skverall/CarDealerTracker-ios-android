package com.ezcar24.business.ui.vehicle

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.outlined.Garage
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.LocalShipping
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.ui.theme.*
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun VehicleListScreen(
    viewModel: VehicleViewModel = hiltViewModel(),
    presetStatus: String? = null,
    showNavigation: Boolean = true,
    onNavigateToAddVehicle: () -> Unit = {},
    onNavigateToDetail: (String) -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    
    LaunchedEffect(presetStatus) {
        if (presetStatus != null) {
            viewModel.setStatusFilter(presetStatus)
        }
    }
    
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )
    
    val allVehicles = uiState.vehicles

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            if (showNavigation) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.9f)) // Translucent header
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .statusBarsPadding(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Vehicles",
                        style = MaterialTheme.typography.headlineLarge.copy(
                            fontWeight = FontWeight.Bold,
                            color = Color.Black
                        )
                    )
                    IconButton(
                        onClick = onNavigateToAddVehicle,
                        colors = IconButtonDefaults.iconButtonColors(
                            containerColor = EzcarGreen,
                            contentColor = Color.White
                        )
                    ) {
                        Icon(Icons.Default.Add, contentDescription = "Add Vehicle")
                    }
                }
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pullRefresh(pullRefreshState)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Spacer(modifier = Modifier.height(8.dp))
                
                // 1. Segmented Control
                val isInventory = uiState.filterStatus != "sold"
                Box(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SegmentedControl(
                        items = listOf("Inventory", "Sold"),
                        defaultSelectedItemIndex = if (isInventory) 0 else 1,
                        onItemSelection = { index ->
                            if (index == 0) viewModel.setStatusFilter(null)
                            else viewModel.setStatusFilter("sold")
                        }
                    )
                }

                // 2. Vehicle Status Dashboard (iOS-style horizontal scroll)
                val totalCount = allVehicles.count { it.vehicle.status != "sold" }
                val onSaleCount = allVehicles.count { it.vehicle.status == "on_sale" }
                val inGarageCount = allVehicles.count { it.vehicle.status == "owned" || it.vehicle.status == "under_service" }
                val inTransitCount = allVehicles.count { it.vehicle.status == "in_transit" }
                val soldCount = allVehicles.count { it.vehicle.status == "sold" }
                val currentFilter = uiState.filterStatus

                androidx.compose.foundation.lazy.LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    item {
                        StatusCard(
                            title = "Total",
                            count = totalCount,
                            icon = Icons.Default.DirectionsCar,
                            color = Color.Black,
                            isActive = currentFilter == "all" || currentFilter == null,
                            onClick = { viewModel.setStatusFilter("all") }
                        )
                    }
                    item {
                        StatusCard(
                            title = "On Sale",
                            count = onSaleCount,
                            icon = Icons.Outlined.LocalOffer,
                            color = EzcarGreen,
                            isActive = currentFilter == "on_sale",
                            onClick = { viewModel.setStatusFilter("on_sale") }
                        )
                    }
                    item {
                        StatusCard(
                            title = "In Garage",
                            count = inGarageCount,
                            icon = Icons.Outlined.Garage,
                            color = EzcarOrange,
                            isActive = currentFilter == "owned",
                            onClick = { viewModel.setStatusFilter("owned") }
                        )
                    }
                    item {
                        StatusCard(
                            title = "In Transit",
                            count = inTransitCount,
                            icon = Icons.Outlined.LocalShipping,
                            color = EzcarPurple,
                            isActive = currentFilter == "in_transit",
                            onClick = { viewModel.setStatusFilter("in_transit") }
                        )
                    }
                    item {
                        StatusCard(
                            title = "Sold",
                            count = soldCount,
                            icon = Icons.Default.CheckCircle,
                            color = EzcarBlueBright,
                            isActive = currentFilter == "sold",
                            onClick = { viewModel.setStatusFilter("sold") }
                        )
                    }
                }



                // 3. Search Bar
                Box(modifier = Modifier.padding(horizontal = 16.dp)) {
                    TextField(
                        value = uiState.searchQuery,
                        onValueChange = { viewModel.onSearchQueryChanged(it) },
                        placeholder = { Text("Search Make, Model, VIN...", color = Color.Gray) },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = Color.Gray) },
                        trailingIcon = {
                            Box {
                                var showSortMenu by remember { mutableStateOf(false) }
                                IconButton(onClick = { showSortMenu = true }) {
                                    Icon(Icons.Default.Sort, contentDescription = "Sort", tint = Color.Gray)
                                }
                                DropdownMenu(
                                    expanded = showSortMenu,
                                    onDismissRequest = { showSortMenu = false }
                                ) {
                                    val currentSort = uiState.sortOrder
                                    DropdownMenuItem(
                                        text = { Text("Newest Added") },
                                        onClick = { viewModel.setSortOrder("newest"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "newest") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Oldest Added") },
                                        onClick = { viewModel.setSortOrder("oldest"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "oldest") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Price: Low to High") },
                                        onClick = { viewModel.setSortOrder("price_asc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "price_asc") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Price: High to Low") },
                                        onClick = { viewModel.setSortOrder("price_desc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "price_desc") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Year: Newest") },
                                        onClick = { viewModel.setSortOrder("year_desc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "year_desc") Icon(Icons.Default.Check, null) }
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp)),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.White,
                            unfocusedContainerColor = Color.White,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            focusedTextColor = Color.Black,
                            unfocusedTextColor = Color.Black
                        ),
                        singleLine = true
                    )
                }

                // 4. Vehicle List
                if (uiState.filteredVehicles.isEmpty() && !uiState.isLoading) {
                    Box(modifier = Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) {
                        Text("No vehicles found", color = Color.Gray)
                    }
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        items(uiState.filteredVehicles, key = { it.vehicle.id }) { item ->
                            val dismissState = rememberSwipeToDismissBoxState(
                                confirmValueChange = {
                                    if (it == SwipeToDismissBoxValue.EndToStart) {
                                        viewModel.deleteVehicle(item.vehicle.id) // Swipe Left to Delete
                                        true
                                    } else if (it == SwipeToDismissBoxValue.StartToEnd) {
                                        if (item.vehicle.status != "sold") {
                                            viewModel.updateVehicleStatus(item.vehicle.id, "sold") // Swipe Right to Mark Sold
                                            true
                                        } else false
                                    } else false
                                }
                            )

                            SwipeToDismissBox(
                                state = dismissState,
                                backgroundContent = {
                                    val direction = dismissState.dismissDirection
                                    val color = animateColorAsState(
                                        when (dismissState.targetValue) {
                                            SwipeToDismissBoxValue.EndToStart -> EzcarDanger // Red for Delete
                                            SwipeToDismissBoxValue.StartToEnd -> EzcarGreen // Green for Sold
                                            else -> Color.Transparent
                                        }, label = "SwipeColor"
                                    )
                                    
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .background(color.value, shape = RoundedCornerShape(12.dp))
                                            .padding(horizontal = 20.dp),
                                        contentAlignment = if (direction == SwipeToDismissBoxValue.EndToStart) Alignment.CenterEnd else Alignment.CenterStart
                                    ) {
                                        if (direction == SwipeToDismissBoxValue.EndToStart) {
                                            Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.White)
                                        } else if (direction == SwipeToDismissBoxValue.StartToEnd) {
                                            if (item.vehicle.status != "sold") {
                                                Icon(Icons.Default.CheckCircle, contentDescription = "Mark Sold", tint = Color.White)
                                            }
                                        }
                                    }
                                }
                            ) {
                                VehicleItem(
                                    item = item,
                                    onClick = { onNavigateToDetail(item.vehicle.id.toString()) }
                                )
                            }
                        }
                    }
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
fun SegmentedControl(
    items: List<String>,
    defaultSelectedItemIndex: Int = 0,
    onItemSelection: (selectedItemIndex: Int) -> Unit
) {
    val selectedIndex = remember { mutableStateOf(defaultSelectedItemIndex) }
    
    // Update state if external prop changes
    LaunchedEffect(defaultSelectedItemIndex) {
        selectedIndex.value = defaultSelectedItemIndex
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(36.dp)
            .background(Color(0xFFE5E5EA), RoundedCornerShape(8.dp)) // iOS System Gray 5
            .padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        items.forEachIndexed { index, item ->
            val isSelected = index == selectedIndex.value
            val backgroundColor by animateColorAsState(if (isSelected) Color.White else Color.Transparent)
            val textColor by animateColorAsState(if (isSelected) Color.Black else Color.Gray)
            val shadowElevation by androidx.compose.animation.core.animateDpAsState(targetValue = if (isSelected) 2.dp else 0.dp)

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .shadow(shadowElevation, RoundedCornerShape(6.dp))
                    .clip(RoundedCornerShape(6.dp))
                    .background(backgroundColor)
                    .clickable {
                        selectedIndex.value = index
                        onItemSelection(index)
                    },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = item,
                    color = textColor,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold)
                )
            }
        }
    }
}

@Composable
fun StatusCard(
    title: String,
    count: Int,
    icon: ImageVector,
    color: Color,
    isActive: Boolean,
    onClick: () -> Unit
) {
    val backgroundColor = if (isActive) color else Color.White
    val contentColor = if (isActive) Color.White else color
    val textColor = if (isActive) Color.White else Color.Black
    
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(backgroundColor)
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp, horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(
                    color = if (isActive) Color.White.copy(alpha = 0.2f) else color.copy(alpha = 0.1f),
                    shape = CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(16.dp)
            )
        }
        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.labelSmall,
                color = if (isActive) Color.White.copy(alpha = 0.9f) else Color.Gray
            )
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = textColor
            )
        }
    }
}

@Composable
fun StatusChip(
    icon: ImageVector,
    label: String,
    count: Int,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit = {}
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
             Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = count.toString(), style = MaterialTheme.typography.titleMedium, color = Color.Black, fontWeight = FontWeight.Bold)
            Text(text = label, style = MaterialTheme.typography.labelSmall, color = Color.Gray, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun VehicleItem(
    item: VehicleWithFinancials,
    onClick: () -> Unit
) {
    val vehicle = item.vehicle
    val totalCost = vehicle.purchasePrice.add(item.totalExpenseCost ?: java.math.BigDecimal.ZERO)
    
    // Metrics calculations
    val daysInStock = try {
        val diff = Date().time - vehicle.purchaseDate.time
        TimeUnit.DAYS.convert(diff, TimeUnit.MILLISECONDS)
    } catch (e: Exception) { 0 }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        elevation = CardDefaults.cardElevation(0.dp) // Flat list style
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                // Vehicle Photo Thumbnail
                val imageUrl = vehicle.photoUrl ?: com.ezcar24.business.data.sync.CloudSyncEnvironment.vehicleImageUrl(vehicle.id)
                
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFFF2F2F7)),
                    contentAlignment = Alignment.Center
                ) {
                    if (imageUrl != null) {
                        coil.compose.SubcomposeAsyncImage(
                            model = imageUrl,
                            contentDescription = "Vehicle",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                            error = {
                                Icon(
                                    imageVector = Icons.Default.DirectionsCar,
                                    contentDescription = "Car",
                                    tint = Color.Gray,
                                    modifier = Modifier.size(32.dp)
                                )
                            },
                            loading = {
                                androidx.compose.material3.CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    strokeWidth = 2.dp
                                )
                            }
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.DirectionsCar,
                            contentDescription = "Car",
                            tint = Color.Gray,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                }
                
                Spacer(modifier = Modifier.width(12.dp))
                
                Column(modifier = Modifier.weight(1f)) {
                    // Title and Badges
                    Row(
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Top,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = Color.Black,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = "VIN: ${vehicle.vin}",
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.Gray,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            // Year + Expense count row (iOS style)
                            Spacer(modifier = Modifier.height(4.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Icon(Icons.Default.CalendarToday, null, modifier = Modifier.size(10.dp), tint = Color.Gray)
                                    Text("${vehicle.year ?: "-"}", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                }
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Icon(Icons.Default.Build, null, modifier = Modifier.size(10.dp), tint = Color.Gray)
                                    Text("${item.expenseCount} exp", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                }
                            }
                        }
                        
                        // Status Badge
                        val badgeColor = when(vehicle.status) {
                            "sold" -> EzcarBlueBright.copy(alpha = 0.15f)
                            "owned" -> Color.Gray.copy(alpha = 0.15f)
                            "on_sale" -> EzcarGreen.copy(alpha = 0.15f)
                            "in_transit" -> EzcarPurple.copy(alpha = 0.15f)
                            "under_service" -> EzcarOrange.copy(alpha = 0.15f)
                            else -> EzcarGreen.copy(alpha = 0.15f) 
                        }
                        val textColor = when(vehicle.status) {
                            "sold" -> EzcarBlueBright
                            "owned" -> Color.Gray
                            "on_sale" -> EzcarGreen
                            "in_transit" -> EzcarPurple
                            "under_service" -> EzcarOrange
                            else -> EzcarGreen
                        }
                        
                        Surface(
                            color = badgeColor,
                            shape = RoundedCornerShape(6.dp)
                        ) {
                            Text(
                                text = when(vehicle.status) {
                                     "sold" -> "Sold"
                                     "owned" -> "Owned"
                                     "on_sale" -> "On Sale"
                                     "in_transit" -> "In Transit"
                                     "under_service" -> "Service"
                                     else -> "On Sale"
                                },
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = textColor,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(12.dp))
                    
                    // Price
                    Text(
                        text = NumberFormat.getCurrencyInstance(Locale.US).format(vehicle.purchasePrice).replace("$", "AED "),
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.Black,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(color = Color(0xFFE5E5EA), thickness = 0.5.dp)
            Spacer(modifier = Modifier.height(12.dp))
            
            // Metrics Row
            Row(
                modifier = Modifier.fillMaxWidth(), 
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                 MetricData(
                     label = "Stock",
                     value = "$daysInStock days"
                 )
                 MetricData(
                     label = "Added",
                     value = SimpleDateFormat("dd MMM", Locale.getDefault()).format(vehicle.purchaseDate)
                 )
                 MetricData(
                     label = "Expenses",
                     value = "${item.expenseCount}",
                     isWarning = item.expenseCount > 0
                 )
                 MetricData(
                     label = "Total Cost",
                     value = NumberFormat.getCurrencyInstance(Locale.US).format(totalCost).replace("$", "").substringBefore("."), 
                     isBold = true
                 )
            }
            
            // Profit Row (for sold vehicles)
            if (vehicle.status == "sold" && vehicle.salePrice != null) {
                val profit = vehicle.salePrice.subtract(totalCost)
                val isProfit = profit >= java.math.BigDecimal.ZERO
                
                Spacer(modifier = Modifier.height(12.dp))
                HorizontalDivider(color = Color(0xFFE5E5EA), thickness = 0.5.dp)
                Spacer(modifier = Modifier.height(12.dp))
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Sale: ${NumberFormat.getCurrencyInstance(Locale.US).format(vehicle.salePrice).replace("$", "AED ")}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Black
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Profit:",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray
                        )
                        Text(
                            text = NumberFormat.getCurrencyInstance(Locale.US).format(profit).replace("$", "AED "),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = if (isProfit) EzcarGreen else Color.Red
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun MetricData(
    label: String,
    value: String,
    isBold: Boolean = false,
    isWarning: Boolean = false
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = label, style = MaterialTheme.typography.bodySmall, color = Color.Gray, fontSize = 10.sp)
        Text(
            text = value, 
            style = MaterialTheme.typography.bodyMedium, 
            color = if (isWarning) EzcarOrange else Color.Black,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium
        )
    }
}

