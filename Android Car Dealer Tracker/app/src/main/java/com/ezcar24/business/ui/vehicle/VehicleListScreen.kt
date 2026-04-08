package com.ezcar24.business.ui.vehicle

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Speed
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleWithFinancials
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.rememberRegionSettingsManager
import kotlinx.coroutines.launch
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
    onNavigateToDetail: (String) -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    var quickSaleVehicle by remember { mutableStateOf<Vehicle?>(null) }
    
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
                            onClick = onNavigateToAddVehicle,
                            colors = IconButtonDefaults.iconButtonColors(
                                containerColor = EzcarNavy,
                                contentColor = Color.White
                            ),
                            modifier = Modifier.size(42.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = "Add Vehicle")
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
                        placeholder = { Text("Search Make, Model, VIN...", color = MaterialTheme.colorScheme.onSurfaceVariant) },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
                        trailingIcon = {
                            Box {
                                var showSortMenu by remember { mutableStateOf(false) }
                                IconButton(onClick = { showSortMenu = true }) {
                                    Icon(Icons.Default.Sort, contentDescription = "Sort", tint = MaterialTheme.colorScheme.onSurfaceVariant)
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
                                    DropdownMenuItem(
                                        text = { Text("Days: Low to High") },
                                        onClick = { viewModel.setSortOrder("days_asc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "days_asc") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Days: High to Low") },
                                        onClick = { viewModel.setSortOrder("days_desc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "days_desc") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("ROI: Low to High") },
                                        onClick = { viewModel.setSortOrder("roi_asc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "roi_asc") Icon(Icons.Default.Check, null) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("ROI: High to Low") },
                                        onClick = { viewModel.setSortOrder("roi_desc"); showSortMenu = false },
                                        leadingIcon = { if(currentSort == "roi_desc") Icon(Icons.Default.Check, null) }
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(18.dp)),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surface,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            focusedTextColor = MaterialTheme.colorScheme.onSurface,
                            unfocusedTextColor = MaterialTheme.colorScheme.onSurface
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
                        text = "Mark as Sold",
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
                        text = "Purchase ${regionSettingsManager.formatCurrency(vehicle.purchasePrice)}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            FormSection(title = "Sale Details", icon = Icons.Default.CheckCircle) {
                CustomFormField(
                    label = "Sale Price ($currencyCode)",
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
                    value = selectedAccount?.accountType ?: "Select Account",
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
                    text = "Payment Method",
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
                            label = { Text(method) },
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
                        text = "No financial accounts available. Add at least one cash or bank account before completing this sale.",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = EzcarDanger
                    )
                }
            }

            errorMessage?.let { message ->
                Text(
                    text = message,
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
                        text = "Complete Sale",
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
            title = { Text("Select Account") },
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
                    Text("Cancel")
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
    val backgroundColor = if (isActive) color.copy(alpha = 0.14f) else MaterialTheme.colorScheme.surface
    val contentColor = color
    val textColor = if (isActive) color else MaterialTheme.colorScheme.onSurface
    
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
                color = if (isActive) color else MaterialTheme.colorScheme.onSurfaceVariant
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
    inventoryStats: Map<String, com.ezcar24.business.data.local.VehicleInventoryStats> = emptyMap(),
    onClick: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val vehicle = item.vehicle
    val totalCost = vehicle.purchasePrice.add(item.totalExpenseCost ?: java.math.BigDecimal.ZERO)
    
    // Get stats from inventory stats map
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
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(8.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                val imageUrl = vehicle.photoUrl ?: com.ezcar24.business.data.sync.CloudSyncEnvironment.vehicleImageUrl(vehicle.id)
                
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
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
                                color = MaterialTheme.colorScheme.onSurface,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = "VIN: ${vehicle.vin}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Icon(Icons.Default.CalendarToday, null, modifier = Modifier.size(10.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("${vehicle.year ?: "-"}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                if (vehicle.mileage > 0) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Icon(Icons.Default.Speed, null, modifier = Modifier.size(10.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Text(
                                            regionSettingsManager.formatMileage(vehicle.mileage),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Icon(Icons.Default.Build, null, modifier = Modifier.size(10.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("${item.expenseCount} exp", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                        
                        // Status Badge + Burning Badge
                        Column(horizontalAlignment = Alignment.End) {
                            if (isBurning && vehicle.status != "sold") {
                                Surface(
                                    color = EzcarDanger.copy(alpha = 0.15f),
                                    shape = RoundedCornerShape(6.dp)
                                ) {
                                    Text(
                                        text = "BURNING",
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = EzcarDanger,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                                Spacer(modifier = Modifier.height(4.dp))
                            }
                            
                            Surface(
                                color = vehicleStatusBackground(vehicle.status),
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
                                    color = vehicleStatusColor(vehicle.status),
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(12.dp))
                    
                    // Price
                    Text(
                        text = regionSettingsManager.formatCurrency(vehicle.purchasePrice),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
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
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                 MetricData(
                     label = "Stock",
                     value = "$daysInStock days",
                     isWarning = daysInStock >= 90
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
                 
                 // ROI Badge
                 if (roiPercent != null && vehicle.status != "sold") {
                     com.ezcar24.business.ui.components.ROIBadge(roiPercent = roiPercent)
                 } else {
                     MetricData(
                         label = "Total Cost",
                         value = regionSettingsManager.formatCurrencyCompact(totalCost),
                         isBold = true
                     )
                 }
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
                        text = "Sale: ${regionSettingsManager.formatCurrency(vehicle.salePrice)}",
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
                            text = regionSettingsManager.formatCurrency(profit),
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
