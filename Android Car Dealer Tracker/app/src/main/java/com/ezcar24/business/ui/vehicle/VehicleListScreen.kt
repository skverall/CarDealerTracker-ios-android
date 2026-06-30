package com.ezcar24.business.ui.vehicle

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Whatshot
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.SubscriptionAccess
import com.ezcar24.business.util.isVehicleOnSaleStatus
import com.ezcar24.business.util.isVehicleReservedGroupStatus
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import com.ezcar24.business.util.vehicleStatusLabelSource
import kotlinx.coroutines.launch
import coil.compose.AsyncImage
import coil.request.ImageRequest
import coil.request.CachePolicy
import java.math.BigDecimal
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
    onNavigateToPaywall: () -> Unit = {},
    onNavigateToDetail: (String) -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    var quickSaleVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var showVehicleLimitDialog by remember { mutableStateOf(false) }

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
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            if (showNavigation) {
                Surface(
                    color = MaterialTheme.colorScheme.background.copy(alpha = 0.98f),
                    shadowElevation = 8.dp
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 12.dp)
                            .statusBarsPadding(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Vehicles",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground
                        )
                        IconButton(
                            onClick = {
                                val shouldGate = SubscriptionAccess.shouldGateVehicleCreation(
                                    isProAccessActive = uiState.isProAccessActive,
                                    isCheckingStatus = uiState.isSubscriptionStatusLoading,
                                    vehicleCount = uiState.vehicles.size
                                )
                                if (shouldGate) {
                                    showVehicleLimitDialog = true
                                } else {
                                    onNavigateToAddVehicle()
                                }
                            },
                            colors = IconButtonDefaults.iconButtonColors(
                                containerColor = EzcarNavy,
                                contentColor = Color.White
                            ),
                            modifier = Modifier.size(42.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = localizedUiString("Add Vehicle"))
                        }
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
                val onSaleCount = allVehicles.count { isVehicleOnSaleStatus(it.vehicle.status) }
                val inGarageCount = allVehicles.count { isVehicleReservedGroupStatus(it.vehicle.status) }
                val inTransitCount = allVehicles.count { it.vehicle.status == "in_transit" }
                val soldCount = allVehicles.count { it.vehicle.status == "sold" }
                val currentFilter = uiState.filterStatus

                androidx.compose.foundation.lazy.LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    item {
                        StatusCard(
                            title = "Total",
                            count = totalCount,
                            icon = Icons.Default.DirectionsCar,
                            color = Color(0xFF007AFF), // Brand primary blue
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
                            title = "Reserved",
                            count = inGarageCount,
                            icon = Icons.Default.Home, // house.fill equivalent
                            color = EzcarOrange,
                            isActive = currentFilter == "reserved",
                            onClick = { viewModel.setStatusFilter("reserved") }
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

                // 3. Search Bar Row
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextField(
                        value = uiState.searchQuery,
                        onValueChange = { viewModel.onSearchQueryChanged(it) },
                        placeholder = {
                            Text(
                                text = localizedUiString("Search vehicles"),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 14.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(18.dp)
                            )
                        },
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.White,
                            unfocusedContainerColor = Color.White,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            focusedTextColor = MaterialTheme.colorScheme.onSurface,
                            unfocusedTextColor = MaterialTheme.colorScheme.onSurface
                        ),
                        singleLine = true,
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .border(BorderStroke(1.dp, Color.Gray.copy(alpha = 0.2f)), RoundedCornerShape(10.dp))
                    )

                    // Sort Button
                    Box {
                        var showSortMenu by remember { mutableStateOf(false) }
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White)
                                .border(BorderStroke(1.dp, Color.Gray.copy(alpha = 0.2f)), RoundedCornerShape(10.dp))
                                .clickable { showSortMenu = true },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.Sort,
                                contentDescription = localizedUiString("Sort"),
                                tint = EzcarNavy,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                        DropdownMenu(
                            expanded = showSortMenu,
                            onDismissRequest = { showSortMenu = false }
                        ) {
                            val currentSort = uiState.sortOrder
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Newest Added")) },
                                onClick = { viewModel.setSortOrder("newest"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "newest") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Oldest Added")) },
                                onClick = { viewModel.setSortOrder("oldest"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "oldest") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Price: Low to High")) },
                                onClick = { viewModel.setSortOrder("price_asc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "price_asc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Price: High to Low")) },
                                onClick = { viewModel.setSortOrder("price_desc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "price_desc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Year: Newest")) },
                                onClick = { viewModel.setSortOrder("year_desc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "year_desc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Days: Low to High")) },
                                onClick = { viewModel.setSortOrder("days_asc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "days_asc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("Days: High to Low")) },
                                onClick = { viewModel.setSortOrder("days_desc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "days_desc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("ROI: Low to High")) },
                                onClick = { viewModel.setSortOrder("roi_asc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "roi_asc") Icon(Icons.Default.Check, null) }
                            )
                            DropdownMenuItem(
                                text = { Text(localizedUiString("ROI: High to Low")) },
                                onClick = { viewModel.setSortOrder("roi_desc"); showSortMenu = false },
                                leadingIcon = { if(currentSort == "roi_desc") Icon(Icons.Default.Check, null) }
                            )
                        }
                    }

                    // Filter Menu Button
                    if (uiState.filterStatus != "sold") {
                        Box {
                            var showFilterMenu by remember { mutableStateOf(false) }
                            val isFilterActive = uiState.filterStatus != null && uiState.filterStatus != "all"
                            Box(
                                modifier = Modifier
                                    .size(48.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(Color.White)
                                    .border(
                                        BorderStroke(
                                            1.dp,
                                            if (isFilterActive) EzcarNavy.copy(alpha = 0.5f) else Color.Gray.copy(alpha = 0.2f)
                                        ),
                                        RoundedCornerShape(10.dp)
                                    )
                                    .clickable { showFilterMenu = true },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = Icons.Default.FilterList,
                                    contentDescription = localizedUiString("Filter"),
                                    tint = if (isFilterActive) EzcarNavy else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                            DropdownMenu(
                                expanded = showFilterMenu,
                                onDismissRequest = { showFilterMenu = false }
                            ) {
                                val currentFilter = uiState.filterStatus
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("All Inventory")) },
                                    onClick = { viewModel.setStatusFilter("all"); showFilterMenu = false },
                                    leadingIcon = { if(currentFilter == "all" || currentFilter == null) Icon(Icons.Default.Check, null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("Reserved")) },
                                    onClick = { viewModel.setStatusFilter("reserved"); showFilterMenu = false },
                                    leadingIcon = { if(currentFilter == "reserved") Icon(Icons.Default.Check, null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("On Sale")) },
                                    onClick = { viewModel.setStatusFilter("on_sale"); showFilterMenu = false },
                                    leadingIcon = { if(currentFilter == "on_sale") Icon(Icons.Default.Check, null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("In Transit")) },
                                    onClick = { viewModel.setStatusFilter("in_transit"); showFilterMenu = false },
                                    leadingIcon = { if(currentFilter == "in_transit") Icon(Icons.Default.Check, null) }
                                )
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("Under Service")) },
                                    onClick = { viewModel.setStatusFilter("under_service"); showFilterMenu = false },
                                    leadingIcon = { if(currentFilter == "under_service") Icon(Icons.Default.Check, null) }
                                )
                            }
                        }

                        // Burning Flame Quick Filter
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White)
                                .border(BorderStroke(1.dp, Color.Gray.copy(alpha = 0.2f)), RoundedCornerShape(10.dp))
                                .clickable {
                                    viewModel.setSortOrder("days_desc")
                                    viewModel.setStatusFilter("all")
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Whatshot,
                                contentDescription = localizedUiString("Burning Inventory"),
                                tint = EzcarOrange,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }

                // 4. Vehicle List
                if (uiState.filteredVehicles.isEmpty() && !uiState.isLoading) {
                    Box(modifier = Modifier.fillMaxSize().weight(1f), contentAlignment = Alignment.Center) {
                        Text(localizedUiString("No vehicles found"), color = Color.Gray)
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
                                            quickSaleVehicle = item.vehicle
                                            false
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
                                            Icon(Icons.Default.Delete, contentDescription = localizedUiString("Delete"), tint = Color.White)
                                        } else if (direction == SwipeToDismissBoxValue.StartToEnd) {
                                            if (item.vehicle.status != "sold") {
                                                Icon(Icons.Default.CheckCircle, contentDescription = localizedUiString("Mark Sold"), tint = Color.White)
                                            }
                                        }
                                    }
                                }
                            ) {
                                VehicleItem(
                                    item = item,
                                    inventoryStats = uiState.inventoryStats,
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

    quickSaleVehicle?.let { vehicle ->
        QuickSaleSheet(
            vehicle = vehicle,
            accounts = uiState.accounts,
            onDismiss = { quickSaleVehicle = null },
            onSave = { salePrice, saleDate, buyerName, buyerPhone, paymentMethod, accountId ->
                viewModel.completeQuickSale(
                    vehicleId = vehicle.id,
                    salePrice = salePrice,
                    saleDate = saleDate,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    accountId = accountId
                )
            }
        )
    }

    if (showVehicleLimitDialog) {
        AlertDialog(
            onDismissRequest = { showVehicleLimitDialog = false },
            icon = {
                Icon(
                    imageVector = Icons.Default.Lock,
                    contentDescription = null,
                    tint = EzcarNavy
                )
            },
            title = { Text(localizedUiString("2-car free limit")) },
            text = {
                Text(
                    localizedUiString("Free plan includes up to 2 vehicles. Upgrade to Pro to add unlimited inventory.")
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showVehicleLimitDialog = false
                        onNavigateToPaywall()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy)
                ) {
                    Text(localizedUiString("Upgrade to Pro"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showVehicleLimitDialog = false }) {
                    Text(localizedUiString("Not now"))
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuickSaleSheet(
    vehicle: Vehicle,
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onSave: suspend (
        salePrice: BigDecimal,
        saleDate: Date,
        buyerName: String,
        buyerPhone: String,
        paymentMethod: String,
        accountId: UUID
    ) -> Result<Unit>
) {
    val scope = rememberCoroutineScope()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val vehicleTitle = remember(vehicle.id) {
        listOfNotNull(vehicle.year?.toString(), vehicle.make, vehicle.model)
            .joinToString(" ")
            .ifBlank { vehicle.vin }
    }
    val currencyCode = regionState.selectedRegion.currencyCode
    val paymentMethods = remember { listOf("Cash", "Bank Transfer", "Cheque", "Finance", "Other") }
    var salePrice by remember(vehicle.id) {
        mutableStateOf(
            vehicle.askingPrice?.takeIf { it > BigDecimal.ZERO }?.toPlainString()
                ?: vehicle.purchasePrice.toPlainString()
        )
    }
    var saleDate by remember(vehicle.id) { mutableStateOf(Date()) }
    var buyerName by remember(vehicle.id) { mutableStateOf(vehicle.buyerName.orEmpty()) }
    var buyerPhone by remember(vehicle.id) { mutableStateOf(vehicle.buyerPhone.orEmpty()) }
    var paymentMethod by remember(vehicle.id) { mutableStateOf(vehicle.paymentMethod ?: "Cash") }
    var selectedAccount by remember(vehicle.id) { mutableStateOf<FinancialAccount?>(null) }
    var showSaleDatePicker by remember { mutableStateOf(false) }
    var showAccountPicker by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }

    LaunchedEffect(vehicle.id, accounts) {
        if (accounts.isEmpty()) {
            selectedAccount = null
        } else if (selectedAccount == null || accounts.none { it.id == selectedAccount?.id }) {
            selectedAccount = accounts.find { it.accountType.equals("cash", ignoreCase = true) } ?: accounts.first()
        }
    }

    val canSave = salePrice.toBigDecimalOrNull()?.let { it > BigDecimal.ZERO } == true &&
        buyerName.isNotBlank() &&
        selectedAccount != null &&
        !isSaving

    ModalBottomSheet(
        onDismissRequest = {
            if (!isSaving) {
                onDismiss()
            }
        },
        modifier = Modifier.fillMaxHeight(0.96f),
        containerColor = EzcarBackgroundLight,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surface,
                tonalElevation = 2.dp
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = localizedUiString("Mark as Sold"),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = vehicleTitle,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = localizedUiString("Purchase %s", regionSettingsManager.formatCurrency(vehicle.purchasePrice)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            FormSection(title = "Sale Details", icon = Icons.Default.CheckCircle) {
                CustomFormField(
                    label = localizedUiString("Sale Price (%s)", currencyCode),
                    value = salePrice,
                    onValueChange = {
                        salePrice = it.filter { char -> char.isDigit() || char == '.' }
                        errorMessage = null
                    },
                    icon = Icons.Default.AttachMoney,
                    keyboardType = KeyboardType.Decimal,
                    placeholder = "0.00"
                )
                PickerField(
                    label = "Sale Date",
                    value = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(saleDate),
                    onClick = { showSaleDatePicker = true }
                )
                PickerField(
                    label = "Deposit To",
                    value = selectedAccount?.accountType ?: localizedUiString("Select Account"),
                    onClick = { showAccountPicker = true }
                )
            }

            FormSection(title = "Buyer Details", icon = Icons.Default.Person) {
                CustomFormField(
                    label = "Buyer Name",
                    value = buyerName,
                    onValueChange = {
                        buyerName = it
                        errorMessage = null
                    },
                    icon = Icons.Default.Person,
                    placeholder = "John Doe"
                )
                CustomFormField(
                    label = "Buyer Phone",
                    value = buyerPhone,
                    onValueChange = { buyerPhone = it },
                    icon = Icons.Default.Phone,
                    keyboardType = KeyboardType.Phone,
                    placeholder = "+971..."
                )
                Text(
                    text = localizedUiString("Payment Method"),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    paymentMethods.forEach { method ->
                        FilterChip(
                            selected = paymentMethod == method,
                            onClick = { paymentMethod = method },
                            label = { Text(localizedUiString(method)) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = EzcarGreen,
                                selectedLabelColor = Color.White
                            )
                        )
                    }
                }
            }

            if (accounts.isEmpty()) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    color = EzcarDanger.copy(alpha = 0.08f),
                    border = BorderStroke(1.dp, EzcarDanger.copy(alpha = 0.2f))
                ) {
                    Text(
                        text = localizedUiString("No financial accounts available. Add at least one cash or bank account before completing this sale."),
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = EzcarDanger
                    )
                }
            }

            errorMessage?.let { message ->
                Text(
                    text = localizedUiString(message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = EzcarDanger
                )
            }

            Button(
                onClick = {
                    val normalizedPrice = salePrice.toBigDecimalOrNull()
                    val accountId = selectedAccount?.id
                    if (normalizedPrice == null || normalizedPrice <= BigDecimal.ZERO) {
                        errorMessage = "Enter a valid sale price."
                        return@Button
                    }
                    if (buyerName.isBlank()) {
                        errorMessage = "Buyer name is required."
                        return@Button
                    }
                    if (accountId == null) {
                        errorMessage = "Select the account where this payment should be deposited."
                        return@Button
                    }
                    isSaving = true
                    errorMessage = null
                    scope.launch {
                        val result = onSave(
                            normalizedPrice,
                            saleDate,
                            buyerName,
                            buyerPhone,
                            paymentMethod,
                            accountId
                        )
                        isSaving = false
                        result.onSuccess {
                            onDismiss()
                        }.onFailure { error ->
                            errorMessage = error.message ?: "Failed to complete sale."
                        }
                    }
                },
                enabled = canSave,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = EzcarNavy,
                    contentColor = Color.White
                )
            ) {
                if (isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = Color.White
                    )
                } else {
                    Text(
                        text = localizedUiString("Complete Sale"),
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }

    if (showSaleDatePicker) {
        DatePickerDialog(
            onDismiss = { showSaleDatePicker = false },
            onDateSelected = {
                saleDate = it
                showSaleDatePicker = false
            }
        )
    }

    if (showAccountPicker) {
        AlertDialog(
            onDismissRequest = { showAccountPicker = false },
            title = { Text(localizedUiString("Select Account")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    accounts.forEach { account ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    selectedAccount = account
                                    showAccountPicker = false
                                }
                                .padding(vertical = 6.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(
                                    text = account.accountType,
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = regionSettingsManager.formatCurrency(account.balance),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            if (selectedAccount?.id == account.id) {
                                Icon(
                                    imageVector = Icons.Default.Check,
                                    contentDescription = null,
                                    tint = EzcarGreen
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showAccountPicker = false }) {
                    Text(localizedUiString("Cancel"))
                }
            }
        )
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
    val backgroundColor = if (isActive) color else color.copy(alpha = 0.08f)
    val contentColor = if (isActive) Color.White else color
    val textColor = if (isActive) Color.White.copy(alpha = 0.9f) else color.copy(alpha = 0.9f)
    val valueColor = if (isActive) Color.White else MaterialTheme.colorScheme.onSurface
    val borderColor = if (isActive) Color.Transparent else color.copy(alpha = 0.22f)

    Row(
        modifier = Modifier
            .shadow(elevation = if (isActive) 3.dp else 0.dp, shape = CircleShape)
            .clip(CircleShape)
            .background(backgroundColor)
            .border(BorderStroke(1.dp, borderColor), shape = CircleShape)
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp, horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(24.dp)
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
                modifier = Modifier.size(12.dp)
            )
        }
        Column(
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = localizedUiString(title),
                style = MaterialTheme.typography.labelSmall,
                fontSize = 9.sp,
                color = textColor,
                maxLines = 1
            )
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = valueColor,
                maxLines = 1
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
            Text(text = localizedUiString(label), style = MaterialTheme.typography.labelSmall, color = Color.Gray, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun VehicleItem(
    item: VehicleWithFinancials,
    inventoryStats: Map<String, com.ezcar24.business.data.local.VehicleInventoryStats> = emptyMap(),
    onClick: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val vehicle = item.vehicle
    val totalCost = vehicle.purchasePrice.add(item.totalExpenseCost ?: java.math.BigDecimal.ZERO)

    val vehicleStats = inventoryStats[vehicle.id.toString()]
    val daysInStock = vehicleStats?.daysInInventory ?: try {
        val diff = Date().time - vehicle.purchaseDate.time
        TimeUnit.DAYS.convert(diff, TimeUnit.MILLISECONDS).toInt()
    } catch (e: Exception) { 0 }

    val roiPercent = vehicleStats?.roiPercent
    val isBurning = daysInStock >= 90

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(2.dp),
        border = BorderStroke(0.5.dp, Color.Gray.copy(alpha = 0.1f))
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                val context = androidx.compose.ui.platform.LocalContext.current
                val dealerId = com.ezcar24.business.data.sync.CloudSyncEnvironment.currentDealerId
                val storeKey = dealerId?.toString() ?: "guest"
                val localFile = remember(vehicle.id, storeKey) {
                    java.io.File(java.io.File(context.filesDir, "VehicleImages"), "$storeKey/${vehicle.id}.jpg")
                }
                val remotePhotoUrl = vehicle.photoUrl ?: com.ezcar24.business.data.sync.CloudSyncEnvironment.vehicleImageUrl(vehicle.id)
                val model = remember(localFile, remotePhotoUrl) {
                    if (localFile.exists()) {
                        localFile
                    } else {
                        remotePhotoUrl
                    }
                }

                Box(
                    modifier = Modifier
                        .size(70.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    contentAlignment = Alignment.Center
                ) {
                    if (model != null) {
                        coil.compose.SubcomposeAsyncImage(
                            model = ImageRequest.Builder(context)
                                .data(model)
                                .crossfade(true)
                                .diskCachePolicy(CachePolicy.ENABLED)
                                .memoryCachePolicy(CachePolicy.ENABLED)
                                .build(),
                            contentDescription = localizedUiString("Vehicle"),
                            modifier = Modifier.fillMaxSize(),
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                            error = {
                                Icon(
                                    imageVector = Icons.Default.DirectionsCar,
                                    contentDescription = localizedUiString("Car"),
                                    tint = Color.Gray.copy(alpha = 0.5f),
                                    modifier = Modifier.size(28.dp)
                                )
                            },
                            loading = {
                                Box(
                                    modifier = Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.05f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.DirectionsCar,
                                        contentDescription = null,
                                        tint = Color.Gray.copy(alpha = 0.5f),
                                        modifier = Modifier.size(28.dp)
                                    )
                                }
                            }
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.DirectionsCar,
                            contentDescription = localizedUiString("Car"),
                            tint = Color.Gray.copy(alpha = 0.5f),
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Top,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}".trim()
                                    .ifEmpty { localizedUiString("Vehicle") },
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )

                            vehicle.inventoryId?.takeIf { it.isNotBlank() }?.let { inventoryId ->
                                Text(
                                    text = localizedUiString("ID: %s", inventoryId),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Color.Gray,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.padding(vertical = 2.dp)
                            ) {
                                Text(
                                    text = "${vehicle.year ?: "-"}",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Medium,
                                    color = Color(0xFF4F6DE6)
                                )
                                if (vehicle.mileage > 0) {
                                    Text("•", color = Color.Gray.copy(alpha = 0.5f), fontSize = 10.sp)
                                    Text(
                                        text = regionSettingsManager.formatMileage(vehicle.mileage),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = Color.Gray
                                    )
                                }
                            }
                        }

                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (vehicle.status != "sold" && daysInStock > 0) {
                                val badgeColor = when {
                                    daysInStock <= 30 -> EzcarGreen
                                    daysInStock <= 60 -> EzcarOrange
                                    daysInStock <= 90 -> Color(0xFFFFA500)
                                    else -> EzcarDanger
                                }
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(badgeColor.copy(alpha = 0.1f))
                                        .border(BorderStroke(1.dp, badgeColor.copy(alpha = 0.3f)), CircleShape)
                                        .padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(6.dp)
                                            .background(badgeColor, CircleShape)
                                    )
                                    Text(
                                        text = "${daysInStock}d",
                                        style = MaterialTheme.typography.labelSmall,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = badgeColor
                                    )
                                }
                            }

                            val statusBg = vehicleStatusColor(vehicle.status).copy(alpha = 0.15f)
                            val statusColor = vehicleStatusColor(vehicle.status)
                            val statusText = vehicleStatusLabelSource(vehicle.status)
                            Text(
                                text = localizedUiString(statusText),
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(statusBg)
                                    .border(BorderStroke(1.dp, statusColor.copy(alpha = 0.3f)), RoundedCornerShape(8.dp))
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                style = MaterialTheme.typography.labelSmall,
                                fontSize = 10.sp,
                                color = statusColor,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }

                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(top = 4.dp)
                    ) {
                        Text(
                            text = "VIN: ${vehicle.vin}",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.Gray,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text("•", color = Color.Gray.copy(alpha = 0.5f), fontSize = 10.sp)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Build,
                                contentDescription = null,
                                tint = Color.Gray,
                                modifier = Modifier.size(10.dp)
                            )
                            Text(
                                text = localizedUiString("%d exp", item.expenseCount),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.Gray
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider(color = Color(0xFFE5E5EA), thickness = 0.5.dp)
            Spacer(modifier = Modifier.height(10.dp))

            // Footer: Purchase Price, Holding Cost, Total Cost / Profit
            val holdingCost = vehicleStats?.holdingCostAccumulated ?: java.math.BigDecimal.ZERO
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(horizontalAlignment = Alignment.Start) {
                    Text(
                        text = localizedUiString("PURCHASE PRICE"),
                        style = MaterialTheme.typography.labelSmall,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Gray,
                        letterSpacing = 0.5.sp
                    )
                    Text(
                        text = regionSettingsManager.formatCurrency(vehicle.purchasePrice),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }

                if (holdingCost > java.math.BigDecimal.ZERO || daysInStock > 0) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = localizedUiString("HOLDING COST"),
                            style = MaterialTheme.typography.labelSmall,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (holdingCost > java.math.BigDecimal.ZERO) EzcarOrange else Color.Gray,
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = regionSettingsManager.formatCurrency(holdingCost),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            color = if (holdingCost > java.math.BigDecimal.ZERO) EzcarOrange else Color.Gray
                        )
                    }
                }

                Column(horizontalAlignment = Alignment.End) {
                    val totalCostWithHolding = totalCost.add(holdingCost)
                    if (vehicle.status == "sold" && vehicle.salePrice != null) {
                        val profit = vehicle.salePrice.subtract(totalCostWithHolding)
                        val isProfit = profit >= java.math.BigDecimal.ZERO

                        Text(
                            text = localizedUiString("PROFIT"),
                            style = MaterialTheme.typography.labelSmall,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.Gray,
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = regionSettingsManager.formatCurrency(profit),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Black,
                            color = if (isProfit) EzcarGreen else Color.Red
                        )
                    } else {
                        Text(
                            text = localizedUiString("TOTAL COST"),
                            style = MaterialTheme.typography.labelSmall,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.Gray,
                            letterSpacing = 0.5.sp
                        )
                        Text(
                            text = regionSettingsManager.formatCurrency(totalCostWithHolding),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF007AFF) // Primary color matching iOS
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
        Text(text = localizedUiString(label), style = MaterialTheme.typography.bodySmall, color = Color.Gray, fontSize = 10.sp)
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isWarning) EzcarOrange else Color.Black,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium
        )
    }
}
