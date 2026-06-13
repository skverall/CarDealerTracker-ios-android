package com.ezcar24.business.ui.sale

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.util.Locale
import com.ezcar24.business.ui.finance.DebtsContent
import com.ezcar24.business.ui.parts.PartSaleItemSummary
import com.ezcar24.business.ui.parts.PartSalesViewModel
import com.ezcar24.business.util.PermissionAccessState
import com.ezcar24.business.util.PermissionKey
import com.ezcar24.business.util.localizedUiString

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun SalesScreen(
    permissionState: PermissionAccessState,
    salesViewModel: SalesViewModel = hiltViewModel(),
    partSalesViewModel: PartSalesViewModel = hiltViewModel(),
    debtViewModel: com.ezcar24.business.ui.finance.DebtViewModel = hiltViewModel()
) {
    val salesUiState by salesViewModel.uiState.collectAsState()
    val partSalesUiState by partSalesViewModel.uiState.collectAsState()
    val debtUiState by debtViewModel.uiState.collectAsState()
    
    var selectedTab by remember { mutableStateOf(0) }
    var selectedSaleTypeFilter by remember { mutableStateOf(SaleTypeFilter.ALL) }
    var showAddSheet by remember { mutableStateOf(false) }
    var showAddDebtDialog by remember { mutableStateOf(false) }
    var isSearching by remember { mutableStateOf(false) }

    val canCreateSale = permissionState.can(PermissionKey.CREATE_SALE)
    val canDeleteRecords = permissionState.can(PermissionKey.DELETE_RECORDS)
    val canViewVehicleCost = permissionState.canViewVehicleCost()
    val canViewVehicleProfit = permissionState.canViewVehicleProfit()
    val canViewPartCost = permissionState.canViewPartCost()
    val canViewPartProfit = permissionState.canViewPartProfit()
    val visiblePartSales = if (partSalesUiState.searchQuery.isBlank()) {
        partSalesUiState.sales
    } else {
        partSalesUiState.filteredSales
    }
    val unifiedSales = remember(
        salesUiState.filteredSales,
        visiblePartSales,
        selectedSaleTypeFilter
    ) {
        val vehicleRows = salesUiState.filteredSales.map { it.toUnifiedSaleItem() }
        val partRows = visiblePartSales.map { it.toUnifiedSaleItem() }
        when (selectedSaleTypeFilter) {
            SaleTypeFilter.ALL -> vehicleRows + partRows
            SaleTypeFilter.VEHICLES -> vehicleRows
            SaleTypeFilter.PARTS -> partRows
        }.sortedByDescending { it.saleDate }
    }
    val totalRevenue = unifiedSales.fold(BigDecimal.ZERO) { total, item -> total.add(item.salePrice) }
    val totalProfit = unifiedSales
        .filter { it.canViewProfit(canViewVehicleProfit, canViewPartProfit) }
        .fold(BigDecimal.ZERO) { total, item -> total.add(item.netProfit) }
    val showProfitSummary = selectedSaleTypeFilter.canShowProfitSummary(
        canViewVehicleProfit = canViewVehicleProfit,
        canViewPartProfit = canViewPartProfit
    )
    
    val pullRefreshState = rememberPullRefreshState(
        refreshing = salesUiState.isLoading || debtUiState.isLoading,
        onRefresh = { 
            salesViewModel.refresh()
            debtViewModel.loadData()
        }
    )

    LaunchedEffect(Unit) {
        salesViewModel.loadData()
        debtViewModel.loadData()
    }
    
    val searchText = if (selectedTab == 0) salesUiState.searchText else debtUiState.searchText
    val onSearchTextChange: (String) -> Unit = if (selectedTab == 0) {
        { text ->
            salesViewModel.onSearchTextChange(text)
            partSalesViewModel.onSearchQueryChanged(text)
        }
    } else {
        debtViewModel::onSearchTextChange
    }
    val onCloseSearch = {
        if (selectedTab == 0) {
            salesViewModel.onSearchTextChange("")
            partSalesViewModel.onSearchQueryChanged("")
        } else {
            debtViewModel.onSearchTextChange("")
        }
        isSearching = false
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                SalesTopBar(
                    title = if (selectedTab == 0) "Sales History" else "Debts",
                    searchText = searchText,
                    isSearching = isSearching,
                    onSearchTextChange = onSearchTextChange,
                    onSearchClick = { isSearching = true },
                    onCloseSearch = onCloseSearch,
                    showAddAction = selectedTab == 1 || canCreateSale,
                    onAddClick = { 
                        if (selectedTab == 0) showAddSheet = true 
                        else showAddDebtDialog = true
                    }
                )
                SalesTabs(
                    selectedTab = selectedTab,
                    onTabSelected = { 
                        selectedTab = it 
                        isSearching = false
                    }
                )
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (selectedTab == 0) {
                Box(modifier = Modifier.pullRefresh(pullRefreshState)) {
                    if (unifiedSales.isEmpty()) {
                        Column(modifier = Modifier.fillMaxSize()) {
                            SalesTypeFilterRow(
                                selectedFilter = selectedSaleTypeFilter,
                                onFilterSelected = { selectedSaleTypeFilter = it },
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                            )
                            SalesInsightsStrip(
                                salesCount = unifiedSales.size,
                                totalRevenue = totalRevenue,
                                netProfit = totalProfit,
                                showProfit = showProfitSummary,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                            )
                            EmptySalesState(
                                padding = PaddingValues(),
                                modifier = Modifier.weight(1f)
                            )
                        }
                    } else {
                        SalesList(
                            sales = unifiedSales,
                            padding = PaddingValues(top = 0.dp),
                            selectedFilter = selectedSaleTypeFilter,
                            onFilterSelected = { selectedSaleTypeFilter = it },
                            salesCount = unifiedSales.size,
                            totalRevenue = totalRevenue,
                            netProfit = totalProfit,
                            showProfitSummary = showProfitSummary,
                            canDeleteRecords = canDeleteRecords,
                            canViewVehicleCost = canViewVehicleCost,
                            canViewVehicleProfit = canViewVehicleProfit,
                            canViewPartCost = canViewPartCost,
                            canViewPartProfit = canViewPartProfit,
                            onDeleteVehicle = salesViewModel::deleteSale,
                            onDeletePart = partSalesViewModel::deleteSale
                        )
                    }
                    PullRefreshIndicator(
                        refreshing = salesUiState.isLoading,
                        state = pullRefreshState,
                        modifier = Modifier.align(Alignment.TopCenter),
                        backgroundColor = MaterialTheme.colorScheme.surface,
                        contentColor = MaterialTheme.colorScheme.primary
                    )
                }
            } else {
                DebtsContent(
                    viewModel = debtViewModel,
                    showAddDialog = showAddDebtDialog,
                    onAddDialogDismiss = { showAddDebtDialog = false },
                    canDeleteRecords = canDeleteRecords
                )
            }
        }
    }

    if (showAddSheet) {
        AddSaleScreen(
            onDismiss = { showAddSheet = false },
            onSave = { 
                salesViewModel.loadData()
                showAddSheet = false
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SalesTopBar(
    title: String,
    searchText: String,
    isSearching: Boolean,
    onSearchTextChange: (String) -> Unit,
    onSearchClick: () -> Unit,
    onCloseSearch: () -> Unit,
    showAddAction: Boolean,
    onAddClick: () -> Unit
) {
    if (isSearching) {
        TopAppBar(
            title = {
                 TextField(
                     value = searchText,
                     onValueChange = onSearchTextChange,
                     placeholder = { Text(localizedUiString("Search...")) },
                     colors = TextFieldDefaults.colors(
                         focusedContainerColor = Color.Transparent,
                         unfocusedContainerColor = Color.Transparent,
                         focusedIndicatorColor = Color.Transparent,
                         unfocusedIndicatorColor = Color.Transparent
                     ),
                     singleLine = true,
                     modifier = Modifier.fillMaxWidth()
                 )
            },
            actions = {
                 IconButton(onClick = onCloseSearch) {
                     Icon(
                         Icons.Default.Close,
                         contentDescription = localizedUiString("Close"),
                         tint = MaterialTheme.colorScheme.primary
                     )
                 }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
        )
    } else {
        TopAppBar(
            title = {
                Text(localizedUiString(title),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            },
            actions = {
                IconButton(onClick = onSearchClick) {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = localizedUiString("Search"),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                if (showAddAction) {
                    IconButton(onClick = onAddClick) {
                        Icon(
                            Icons.Default.AddCircle,
                            contentDescription = localizedUiString("Add"),
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
        )
    }
}

@Composable
fun SalesTabs(selectedTab: Int, onTabSelected: (Int) -> Unit) {
    TabRow(
        selectedTabIndex = selectedTab,
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.primary,
        indicator = { tabPositions ->
            TabRowDefaults.SecondaryIndicator(
                modifier = Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                color = MaterialTheme.colorScheme.primary
            )
        }
    ) {
        Tab(
            selected = selectedTab == 0,
            onClick = { onTabSelected(0) },
            text = { Text(localizedUiString("Sales")) }
        )
        Tab(
            selected = selectedTab == 1,
            onClick = { onTabSelected(1) },
            text = { Text(localizedUiString("Debts")) }
        )
    }
}

@Composable
fun SalesList(
    sales: List<UnifiedSaleItem>,
    padding: PaddingValues,
    selectedFilter: SaleTypeFilter,
    onFilterSelected: (SaleTypeFilter) -> Unit,
    salesCount: Int,
    totalRevenue: BigDecimal,
    netProfit: BigDecimal,
    showProfitSummary: Boolean,
    canDeleteRecords: Boolean,
    canViewVehicleCost: Boolean,
    canViewVehicleProfit: Boolean,
    canViewPartCost: Boolean,
    canViewPartProfit: Boolean,
    onDeleteVehicle: (Sale) -> Unit,
    onDeletePart: (com.ezcar24.business.data.local.PartSale) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding() + 8.dp,
            bottom = 80.dp,
            start = 16.dp, 
            end = 16.dp
        ),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SalesTypeFilterRow(
                selectedFilter = selectedFilter,
                onFilterSelected = onFilterSelected
            )
        }
        item {
            SalesInsightsStrip(
                salesCount = salesCount,
                totalRevenue = totalRevenue,
                netProfit = netProfit,
                showProfit = showProfitSummary
            )
        }
        items(sales, key = { "${it.type.name}-${it.id}" }) { item ->
            SaleCard(
                item = item,
                canDelete = canDeleteRecords && item.vehicleSale?.isDealDeskSale != true,
                canViewCost = item.canViewCost(canViewVehicleCost, canViewPartCost),
                canViewProfit = item.canViewProfit(canViewVehicleProfit, canViewPartProfit),
                onDelete = {
                    when (item.type) {
                        UnifiedSaleType.VEHICLE -> item.vehicleSale?.let(onDeleteVehicle)
                        UnifiedSaleType.PART -> item.partSale?.sale?.let(onDeletePart)
                    }
                }
            )
        }
    }
}

@Composable
fun SalesTypeFilterRow(
    selectedFilter: SaleTypeFilter,
    onFilterSelected: (SaleTypeFilter) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(SaleTypeFilter.values()) { filter ->
            val isSelected = filter == selectedFilter
            FilterChip(
                selected = isSelected,
                onClick = { onFilterSelected(filter) },
                label = { Text(localizedUiString(filter.labelSource)) },
                leadingIcon = if (isSelected) {
                    {
                        Icon(
                            Icons.Default.Check,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                } else {
                    null
                },
                modifier = Modifier.heightIn(min = 48.dp),
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
                    selectedLeadingIconColor = MaterialTheme.colorScheme.onPrimary,
                    containerColor = MaterialTheme.colorScheme.surface,
                    labelColor = MaterialTheme.colorScheme.primary
                ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = isSelected,
                    borderColor = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                )
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaleCard(
    item: UnifiedSaleItem,
    canDelete: Boolean,
    canViewCost: Boolean,
    canViewProfit: Boolean,
    onDelete: () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = {
            if (canDelete && it == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val color = if (canDelete && dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart) EzcarDanger else Color.Transparent
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(16.dp))
                    .background(color)
                    .padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                if (canDelete) {
                    Icon(Icons.Default.Delete, contentDescription = localizedUiString("Delete"), tint = Color.White)
                }
            }
        },
        content = {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                shape = RoundedCornerShape(16.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Row(
                            modifier = Modifier.weight(1f),
                            verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = if (item.type == UnifiedSaleType.VEHICLE) Icons.Default.DirectionsCar else Icons.Default.Build,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = saleDisplayTitle(item),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                item.subtitle?.takeIf { it.isNotBlank() }?.let { subtitle ->
                                    Text(
                                        text = subtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = java.text.SimpleDateFormat("d MMM", Locale.getDefault()).format(item.saleDate),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Person,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = saleDisplayBuyerName(item.buyerName),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 12.dp).alpha(0.5f),
                        color = MaterialTheme.colorScheme.outline
                    )

                    val metrics = buildSaleMetrics(
                        item = item,
                        canViewCost = canViewCost,
                        canViewProfit = canViewProfit,
                        primaryColor = MaterialTheme.colorScheme.primary,
                        secondaryColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(modifier = Modifier.fillMaxWidth()) {
                        metrics.forEachIndexed { index, metric ->
                            if (index > 0) {
                                Box(
                                    modifier = Modifier
                                        .width(1.dp)
                                        .height(30.dp)
                                        .background(MaterialTheme.colorScheme.outline)
                                )
                            }
                            FinancialColumn(
                                title = metric.title,
                                amount = metric.amount,
                                color = metric.color,
                                isBold = metric.isBold,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
        }
    )
}

@Composable
fun FinancialColumn(
    title: String, 
    amount: BigDecimal, 
    color: Color, 
    isBold: Boolean = false,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = localizedUiString(title).uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = regionSettingsManager.formatCurrency(amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal,
            color = color
        )
    }
}

@Composable
fun SalesInsightsStrip(
    salesCount: Int,
    totalRevenue: BigDecimal,
    netProfit: BigDecimal,
    showProfit: Boolean,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CompactSaleInsightCard(
                title = localizedUiString("Sold").uppercase(Locale.getDefault()),
                value = salesCount.toString(),
                icon = Icons.Default.DirectionsCar,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            CompactSaleInsightCard(
                title = localizedUiString("Revenue").uppercase(Locale.getDefault()),
                value = regionSettingsManager.formatCurrency(totalRevenue),
                icon = Icons.Default.AttachMoney,
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.weight(1f)
            )
        }

        if (showProfit) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                shape = RoundedCornerShape(18.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .background(EzcarSuccess.copy(alpha = 0.14f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.MonetizationOn,
                            contentDescription = null,
                            tint = EzcarSuccess
                        )
                    }

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            localizedUiString("Net Profit").uppercase(Locale.getDefault()),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            regionSettingsManager.formatCurrency(netProfit),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = if (netProfit >= BigDecimal.ZERO) EzcarSuccess else EzcarDanger,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CompactSaleInsightCard(
    title: String,
    value: String,
    icon: ImageVector,
    color: Color,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(18.dp),
        modifier = modifier.heightIn(min = 72.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(color.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(imageVector = icon, contentDescription = null, tint = color)
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    value,
                    style = MaterialTheme.typography.titleMedium,
                    color = color,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun saleDisplayTitle(item: UnifiedSaleItem): String {
    return when (item.title) {
        "Vehicle Removed" -> localizedUiString("Vehicle Removed")
        "Parts Sale" -> localizedUiString("Parts Sale")
        else -> item.title
    }
}

@Composable
private fun saleDisplayBuyerName(buyerName: String): String {
    return when (buyerName) {
        "Unknown Buyer" -> localizedUiString("Unknown Buyer")
        "Walk-in" -> localizedUiString("Walk-in")
        else -> buyerName
    }
}

@Composable
fun EmptySalesState(
    padding: PaddingValues,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(padding),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.MonetizationOn,
                    contentDescription = null,
                    modifier = Modifier.size(42.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.72f)
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = localizedUiString("No Sales Yet"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = localizedUiString("Record your first sale to see profit analytics."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

enum class SaleTypeFilter(val labelSource: String) {
    ALL("All"),
    VEHICLES("Vehicles"),
    PARTS("Parts")
}

enum class UnifiedSaleType {
    VEHICLE,
    PART
}

private data class SaleMetric(
    val title: String,
    val amount: BigDecimal,
    val color: Color,
    val isBold: Boolean = false
)

data class UnifiedSaleItem(
    val id: String,
    val type: UnifiedSaleType,
    val title: String,
    val subtitle: String?,
    val buyerName: String,
    val saleDate: java.util.Date,
    val salePrice: BigDecimal,
    val costPrice: BigDecimal,
    val netProfit: BigDecimal,
    val vehicleSale: Sale? = null,
    val partSale: PartSaleItemSummary? = null
)

private fun SaleItem.toUnifiedSaleItem() = UnifiedSaleItem(
    id = sale.id.toString(),
    type = UnifiedSaleType.VEHICLE,
    title = vehicleName,
    subtitle = null,
    buyerName = buyerName,
    saleDate = saleDate,
    salePrice = salePrice,
    costPrice = costPrice,
    netProfit = netProfit,
    vehicleSale = sale
)

private fun PartSaleItemSummary.toUnifiedSaleItem() = UnifiedSaleItem(
    id = sale.id.toString(),
    type = UnifiedSaleType.PART,
    title = "Parts Sale",
    subtitle = itemsSummary.takeIf { it.isNotBlank() },
    buyerName = buyerName,
    saleDate = saleDate,
    salePrice = totalAmount,
    costPrice = totalCost,
    netProfit = profit,
    partSale = this
)

private fun UnifiedSaleItem.canViewCost(
    canViewVehicleCost: Boolean,
    canViewPartCost: Boolean
): Boolean {
    return when (type) {
        UnifiedSaleType.VEHICLE -> canViewVehicleCost
        UnifiedSaleType.PART -> canViewPartCost
    }
}

private fun UnifiedSaleItem.canViewProfit(
    canViewVehicleProfit: Boolean,
    canViewPartProfit: Boolean
): Boolean {
    return when (type) {
        UnifiedSaleType.VEHICLE -> canViewVehicleProfit
        UnifiedSaleType.PART -> canViewPartProfit
    }
}

private fun SaleTypeFilter.canShowProfitSummary(
    canViewVehicleProfit: Boolean,
    canViewPartProfit: Boolean
): Boolean {
    return when (this) {
        SaleTypeFilter.ALL -> canViewVehicleProfit || canViewPartProfit
        SaleTypeFilter.VEHICLES -> canViewVehicleProfit
        SaleTypeFilter.PARTS -> canViewPartProfit
    }
}

private fun buildSaleMetrics(
    item: UnifiedSaleItem,
    canViewCost: Boolean,
    canViewProfit: Boolean,
    primaryColor: Color,
    secondaryColor: Color
): List<SaleMetric> {
    return buildList {
        add(SaleMetric(title = "Revenue", amount = item.salePrice, color = primaryColor))
        if (canViewCost) {
            add(SaleMetric(title = "Cost", amount = item.costPrice, color = secondaryColor))
        }
        if (canViewProfit) {
            add(
                SaleMetric(
                    title = "Net Profit",
                    amount = item.netProfit,
                    color = if (item.netProfit >= BigDecimal.ZERO) EzcarSuccess else EzcarDanger,
                    isBold = true
                )
            )
        }
    }
}
