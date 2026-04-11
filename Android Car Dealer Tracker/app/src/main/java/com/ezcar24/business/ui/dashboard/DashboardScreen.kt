package com.ezcar24.business.ui.dashboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.ui.theme.*
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.ezcar24.business.ui.expense.AddExpenseSheet
import com.ezcar24.business.ui.expense.ExpenseDetailBottomSheet
import com.ezcar24.business.ui.expense.ExpenseViewModel
import com.ezcar24.business.data.sync.SyncState
import com.ezcar24.business.util.expenseDisplayDateTime
import com.ezcar24.business.util.rememberRegionSettingsManager
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.text.style.TextOverflow

// Time range enum matching iOS DashboardTimeRange
@OptIn(ExperimentalMaterialApi::class)
@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel = hiltViewModel(),
    expenseViewModel: ExpenseViewModel = hiltViewModel(),
    onNavigateToAccounts: () -> Unit,
    onNavigateToDebts: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToSearch: () -> Unit,
    onNavigateToVehicles: () -> Unit = {},
    onNavigateToSoldVehicles: () -> Unit = {},
    onNavigateToSales: () -> Unit = {},
    onNavigateToExpenses: () -> Unit = {},
    onNavigateToLeadFunnel: () -> Unit = {},
    onNavigateToInventoryAnalytics: () -> Unit = {},
    onNavigateToDataHealth: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    val expenseUiState by expenseViewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val context = androidx.compose.ui.platform.LocalContext.current
    var showAddExpenseSheet by remember { mutableStateOf(false) }
    var selectedExpense by remember { mutableStateOf<Expense?>(null) }
    var showCreateBusinessDialog by remember { mutableStateOf(false) }
    var pendingCreateBusiness by remember { mutableStateOf(false) }
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    LaunchedEffect(
        pendingCreateBusiness,
        showCreateBusinessDialog,
        uiState.isSwitchingOrganization,
        uiState.errorMessage
    ) {
        if (pendingCreateBusiness && showCreateBusinessDialog && !uiState.isSwitchingOrganization) {
            if (uiState.errorMessage == null) {
                showCreateBusinessDialog = false
            }
            pendingCreateBusiness = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .pullRefresh(pullRefreshState)
    ) {
        LazyColumn(
            contentPadding = PaddingValues(bottom = 80.dp), // Space for BottomNav
            modifier = Modifier.fillMaxSize()
        ) {
            // --- Top Bar ---
            item {
                DashboardTopBar(
                    syncState = uiState.syncState,
                    activeOrganization = uiState.activeOrganization,
                    organizations = uiState.organizations,
                    isSwitchingOrganization = uiState.isSwitchingOrganization,
                    onSelectOrganization = viewModel::switchOrganization,
                    onCreateBusiness = { showCreateBusinessDialog = true },
                    onProfileClick = onNavigateToSettings,
                    onAddClick = { showAddExpenseSheet = true },
                    onSearchClick = onNavigateToSearch
                )
            }

            uiState.statusMessage?.let { statusMessage ->
                item {
                    DashboardMessageBanner(
                        message = statusMessage,
                        isError = false,
                        onDismiss = viewModel::clearStatusMessage
                    )
                }
            }

            uiState.errorMessage?.let { errorMessage ->
                item {
                    DashboardMessageBanner(
                        message = errorMessage,
                        isError = true,
                        onDismiss = viewModel::clearErrorMessage
                    )
                }
            }
            
            // --- Sync Status Card ---
            item {
                SyncStatusCard(
                    syncState = uiState.syncState,
                    lastSyncTime = uiState.lastSyncTime,
                    queueCount = uiState.queueCount,
                    onSyncClick = { viewModel.triggerSync() },
                    onDataHealthClick = onNavigateToDataHealth
                )
            }

            // --- Time Range Picker ---
            item {
                TimeRangePicker(
                    selectedRange = uiState.selectedRange,
                    onRangeSelected = { viewModel.onTimeRangeChange(it) }
                )
            }

            // --- Financial Overview ---
            item {
                FinancialOverviewSection(
                    uiState = uiState,
                    onNavigateToAccounts = onNavigateToAccounts,
                    onNavigateToAssets = onNavigateToVehicles,
                    onNavigateToSold = onNavigateToSoldVehicles,
                    onNavigateToSales = onNavigateToSales
                )
            }

            // --- Today's Expenses ---
            item {
                TodaysExpensesSection(
                    todaysExpenses = uiState.todaysExpenses,
                    onAddExpense = { showAddExpenseSheet = true },
                    onExpenseClick = { selectedExpense = it }
                )
            }

            // --- Summary Section (Total Spent & Breakdown) ---
            item {
                SummarySection(
                    totalSpent = uiState.totalExpensesInPeriod,
                    changePercent = uiState.periodChangePercent,
                    trendPoints = uiState.trendPoints,
                    categoryStats = uiState.categoryStats,
                    selectedRange = uiState.selectedRange
                )
            }

            // --- Recent Expenses ---
            item {
                RecentExpensesSection(
                    recentExpenses = uiState.recentExpenses,
                    vehicleTitlesById = uiState.vehicleTitlesById,
                    onSeeAll = onNavigateToExpenses,
                    onExpenseClick = { selectedExpense = it }
                )
            }

            // --- CRM Summary Card ---
            item {
                CRMSummaryCard(
                    newLeadsToday = uiState.newLeadsToday,
                    callsMadeToday = uiState.callsMadeToday,
                    pipelineValue = uiState.pipelineValue,
                    conversionRate = uiState.conversionRate,
                    onNavigateToLeadFunnel = onNavigateToLeadFunnel
                )
            }
            
            // --- Inventory Summary Card ---
            item {
                InventorySummaryCard(
                    totalVehicles = uiState.totalVehiclesInInventory,
                    averageDays = uiState.averageDaysInInventory,
                    vehiclesOver90Days = uiState.vehiclesOver90Days,
                    healthScore = uiState.inventoryHealthScore,
                    onNavigateToInventoryAnalytics = onNavigateToInventoryAnalytics
                )
            }
        }
        
        PullRefreshIndicator(
            refreshing = uiState.isLoading,
            state = pullRefreshState,
            modifier = Modifier.align(Alignment.TopCenter),
            backgroundColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.primary
        )
    }

    // Add Expense Sheet
    if (showAddExpenseSheet) {
        AddExpenseSheet(
            onDismiss = { showAddExpenseSheet = false },
            onSave = { amount, date, desc, cat, veh, usr, acc, expenseType, receipt ->
                expenseViewModel.saveExpense(amount, date, desc, cat, veh, usr, acc, expenseType, receipt)
                showAddExpenseSheet = false
                viewModel.refresh() // Refresh dashboard to show new expense
            },
            onSaveTemplate = expenseViewModel::saveTemplate,
            vehicles = expenseUiState.vehicles,
            users = expenseUiState.users,
            accounts = expenseUiState.accounts,
            templates = expenseUiState.templates,
            currencyCode = regionState.selectedRegion.currencyCode
        )
    }

    selectedExpense?.let { expense ->
        ExpenseDetailBottomSheet(
            expense = expense,
            vehicleTitle = expense.vehicleId?.let(uiState.vehicleTitlesById::get),
            onDismiss = { selectedExpense = null },
            onSaveComment = expenseViewModel::updateExpenseComment,
            onViewReceipt = { expenseViewModel.openExpenseReceipt(context, it) },
            onReplaceReceipt = { targetExpense, receipt, onUpdated ->
                expenseViewModel.replaceExpenseReceipt(targetExpense, receipt, onUpdated)
            },
            onRemoveReceipt = { targetExpense, onUpdated ->
                expenseViewModel.removeExpenseReceipt(targetExpense, onUpdated)
            }
        )
    }

    if (showCreateBusinessDialog) {
        DashboardCreateBusinessDialog(
            isSaving = uiState.isSwitchingOrganization,
            onDismiss = {
                if (!uiState.isSwitchingOrganization) {
                    showCreateBusinessDialog = false
                    pendingCreateBusiness = false
                }
            },
            onCreate = { businessName ->
                pendingCreateBusiness = true
                viewModel.createOrganization(businessName)
            }
        )
    }
}

@Composable
fun DashboardTopBar(
    syncState: SyncState,
    activeOrganization: OrganizationMembership?,
    organizations: List<OrganizationMembership>,
    isSwitchingOrganization: Boolean,
    onSelectOrganization: (UUID) -> Unit,
    onCreateBusiness: () -> Unit,
    onProfileClick: () -> Unit,
    onAddClick: () -> Unit,
    onSearchClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .padding(horizontal = 20.dp, vertical = 12.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = getGreeting(),
                    style = MaterialTheme.typography.titleSmall.copy(fontStyle = FontStyle.Italic),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "Dashboard",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Spacer(modifier = Modifier.height(10.dp))
                DashboardOrganizationSwitcher(
                    activeOrganization = activeOrganization,
                    organizations = organizations,
                    isSwitchingOrganization = isSwitchingOrganization,
                    onSelectOrganization = onSelectOrganization,
                    onCreateBusiness = onCreateBusiness
                )
            }
            
            Spacer(modifier = Modifier.width(12.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (syncState is SyncState.Syncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = EzcarBlueBright
                    )
                }

                IconButton(
                    onClick = onSearchClick,
                    modifier = Modifier
                        .size(44.dp)
                        .background(MaterialTheme.colorScheme.surface, CircleShape)
                ) {
                    Icon(Icons.Default.Search, contentDescription = "Search", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }

                IconButton(
                    onClick = onProfileClick,
                    modifier = Modifier
                        .size(44.dp)
                        .background(MaterialTheme.colorScheme.surface, CircleShape)
                ) {
                    Icon(Icons.Default.Person, contentDescription = "Profile", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                
                IconButton(
                    onClick = onAddClick,
                    modifier = Modifier
                        .size(44.dp)
                        .background(EzcarNavy, CircleShape)
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Add", tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun DashboardOrganizationSwitcher(
    activeOrganization: OrganizationMembership?,
    organizations: List<OrganizationMembership>,
    isSwitchingOrganization: Boolean,
    onSelectOrganization: (UUID) -> Unit,
    onCreateBusiness: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier.widthIn(max = 240.dp)
    ) {
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = 6.dp,
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = !isSwitchingOrganization) { showMenu = true }
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = activeOrganization?.organizationName ?: "Select Business",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = activeOrganization?.role?.replaceFirstChar { it.titlecase(Locale.getDefault()) }
                            ?: "Switch business or create one",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                if (isSwitchingOrganization) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = EzcarBlueBright
                    )
                } else {
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowDown,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false }
        ) {
            if (organizations.isEmpty()) {
                DropdownMenuItem(
                    text = { Text("No organizations yet") },
                    onClick = {},
                    enabled = false
                )
            } else {
                organizations.forEach { organization ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(organization.organizationName)
                                Text(
                                    text = organization.role.replaceFirstChar { it.titlecase(Locale.getDefault()) },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        },
                        onClick = {
                            showMenu = false
                            onSelectOrganization(organization.organizationId)
                        },
                        trailingIcon = {
                            if (organization.organizationId == activeOrganization?.organizationId) {
                                Icon(
                                    imageVector = Icons.Default.Verified,
                                    contentDescription = null,
                                    tint = EzcarGreen
                                )
                            }
                        }
                    )
                }
            }

            HorizontalDivider()

            DropdownMenuItem(
                text = { Text("Create Business") },
                onClick = {
                    showMenu = false
                    onCreateBusiness()
                },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = null
                    )
                }
            )
        }
    }
}

@Composable
private fun DashboardMessageBanner(
    message: String,
    isError: Boolean,
    onDismiss: () -> Unit
) {
    val containerColor = if (isError) {
        EzcarDanger.copy(alpha = 0.12f)
    } else {
        EzcarSuccess.copy(alpha = 0.12f)
    }
    val contentColor = if (isError) EzcarDanger else EzcarSuccess

    Surface(
        color = containerColor,
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (isError) Icons.Default.Error else Icons.Default.CheckCircle,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun DashboardCreateBusinessDialog(
    isSaving: Boolean,
    onDismiss: () -> Unit,
    onCreate: (String) -> Unit
) {
    var businessName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create Business") },
        text = {
            OutlinedTextField(
                value = businessName,
                onValueChange = { businessName = it },
                label = { Text("Business name") },
                enabled = !isSaving,
                singleLine = true
            )
        },
        confirmButton = {
            Button(
                onClick = { onCreate(businessName.trim()) },
                enabled = businessName.trim().isNotEmpty() && !isSaving
            ) {
                Text(if (isSaving) "Creating..." else "Create")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSaving) {
                Text("Cancel")
            }
        }
    )
}

private fun getGreeting(): String {
    val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
    return when (hour) {
        in 0..11 -> "Good Morning"
        in 12..16 -> "Good Afternoon"
        else -> "Good Evening"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeRangePicker(
    selectedRange: DashboardTimeRange,
    onRangeSelected: (DashboardTimeRange) -> Unit
) {
    val ranges = DashboardTimeRange.values()
    val scrollState = rememberScrollState()
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(scrollState)
            .padding(horizontal = 20.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ranges.forEach { range ->
            val isSelected = range == selectedRange
            
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(if (isSelected) EzcarNavy else MaterialTheme.colorScheme.surface)
                    .clickable { onRangeSelected(range) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = range.displayLabel,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}

@Composable
fun FinancialOverviewSection(
    uiState: DashboardUiState,
    onNavigateToAccounts: () -> Unit,
    onNavigateToAssets: () -> Unit,
    onNavigateToSold: () -> Unit,
    onNavigateToSales: () -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
        // Row 1: Assets, Cash, Bank
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            FinancialCard(
                title = "Total Assets",
                amount = uiState.totalAssets,
                icon = Icons.Default.AccountBalance,
                baseColor = EzcarBlueBright,
                gradient = Brush.linearGradient(
                    colors = listOf(Color(0xFF5AC8FA), EzcarBlueBright), // Light Blue -> Brand Blue
                    start = Offset(0f, 0f),
                    end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY) 
                ),
                isSolidBackground = true,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToAssets
            )
            FinancialCard(
                title = "Cash",
                amount = uiState.totalCash,
                icon = Icons.Default.AttachMoney,
                baseColor = EzcarGreen,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToAccounts
            )
            FinancialCard(
                title = "Bank",
                amount = uiState.totalBank,
                icon = Icons.Default.CreditCard,
                baseColor = EzcarPurple,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToAccounts
            )
        }
        
        Spacer(modifier = Modifier.height(12.dp))
        
        // Row 2: Revenue, Profit, Sold
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            FinancialCard(
                title = "Total Revenue",
                amount = uiState.totalRevenue,
                icon = Icons.AutoMirrored.Filled.TrendingUp,
                baseColor = EzcarOrange,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToSales
            )
            FinancialCard(
                title = "Net Profit",
                amount = uiState.netProfit,
                icon = Icons.Default.MonetizationOn,
                baseColor = EzcarSuccess,
                gradient = Brush.linearGradient(
                    colors = listOf(Color(0xFF63E689), EzcarSuccess), // Lighter Green -> Brand Green
                    start = Offset(0f, 0f),
                    end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY)
                ),
                isSolidBackground = true,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToSales
            )
             FinancialCard(
                title = "Sold",
                valueStr = uiState.soldCount.toString(),
                icon = Icons.Default.CheckCircle,
                baseColor = EzcarBlueLight,
                isCount = true,
                modifier = Modifier.weight(1f),
                onClick = onNavigateToSold
            )
        }
    }
}

@Composable
fun FinancialCard(
    title: String,
    amount: BigDecimal? = null,
    valueStr: String? = null,
    icon: ImageVector,
    baseColor: Color,
    gradient: Brush? = null,
    isSolidBackground: Boolean = false,
    isHero: Boolean = false, 
    isCount: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val displayValue = if (isCount && valueStr != null) valueStr else {
        regionSettingsManager.formatCurrency(amount ?: BigDecimal.ZERO)
    }
    
    // Solid background logic
    val backgroundColor = if (isSolidBackground) baseColor else Color.White
    val contentColor = if (isSolidBackground) Color.White else Color.Black
    val titleColor = if (isSolidBackground) Color.White.copy(alpha = 0.9f) else Color.Gray
    
    // Icon Logic for Solid Cards: Standard iOS icon style (white with transparency circle or just white)
    // For Non-Solid: Colored icon with light bg
    val iconTint = if (isSolidBackground) Color.White else baseColor
    val iconBg = if (isSolidBackground) Color.White.copy(alpha = 0.2f) else baseColor.copy(alpha = 0.1f)
    
    val cardModifier = if (gradient != null && isSolidBackground) {
        modifier
            .clip(RoundedCornerShape(16.dp))
            .background(gradient)
    } else {
        modifier
            .clip(RoundedCornerShape(16.dp))
            .background(backgroundColor)
    }

    Column(
        modifier = cardModifier
            .clickable(enabled = onClick != null, onClick = onClick ?: {})
            .padding(12.dp)
            .height(100.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        // Icon Header
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(iconBg),
                contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(16.dp)
            )
        }
        
        // Value & Title
        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.labelSmall,
                color = titleColor,
                maxLines = 1
            )
            Text(
                text = displayValue,
                style = if (isCount) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = contentColor,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun TodaysExpensesSection(
    todaysExpenses: List<Expense>,
    onAddExpense: () -> Unit,
    onExpenseClick: (Expense) -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Today's Expenses",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = todaysExpenses.size.toString(),
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        
        Spacer(modifier = Modifier.height(12.dp))

        if (todaysExpenses.isEmpty()) {
            EmptyTodayCard(onAddExpense)
        } else {
            // 2-Column Grid using Rows
            val chunked = todaysExpenses.chunked(2)
            chunked.forEach { rowItems ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    rowItems.forEach { expense ->
                        Box(modifier = Modifier.weight(1f)) {
                            TodayExpenseCard(
                                expense = expense,
                                onClick = { onExpenseClick(expense) }
                            )
                        }
                    }
                    // Fill empty space if odd number
                    if (rowItems.size == 1) {
                         Box(modifier = Modifier.weight(1f))
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@Composable
fun TodayExpenseCard(
    expense: Expense,
    onClick: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(130.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                // Icon
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(EzcarBlueBright.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Receipt,
                        contentDescription = null,
                        tint = EzcarBlueBright,
                        modifier = Modifier.size(18.dp)
                    )
                }
                
                // Time
                Text(
                    text = timeFormat.format(expenseDisplayDateTime(expense)),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray,
                    modifier = Modifier
                        .background(MaterialTheme.colorScheme.background, CircleShape)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
            
            Column {
                Text(
                    text = regionSettingsManager.formatCurrency(expense.amount),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = expense.expenseDescription ?: expense.category ?: "Expense",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun EmptyTodayCard(onAddExpense: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ListAlt,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = Color.Gray.copy(alpha = 0.5f)
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No expenses today",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium
            )
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onAddExpense,
                colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy)
            ) {
                Text("Add Expense")
            }
        }
    }
}

@Composable
fun SummarySection(
    totalSpent: BigDecimal,
    changePercent: Double?,
    trendPoints: List<TrendPoint>,
    categoryStats: List<CategoryStat>,
    selectedRange: DashboardTimeRange
) {
    Column(
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        SummaryOverviewCard(totalSpent, changePercent, trendPoints, selectedRange)
        CategoryBreakdownCard(categoryStats)
    }
}

@Composable
fun SummaryOverviewCard(
    totalSpent: BigDecimal,
    changePercent: Double?,
    trendPoints: List<TrendPoint>,
    selectedRange: DashboardTimeRange
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(24.dp)) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column {
                    Text(
                        text = "Total Spent (${selectedRange.displayLabel})",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = regionSettingsManager.formatCurrency(totalSpent),
                            style = MaterialTheme.typography.headlineLarge, // equivalent to 32pt
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        
                        if (changePercent != null) {
                            Spacer(modifier = Modifier.width(8.dp))
                            val isPositive = changePercent >= 0
                            val color = if (isPositive) EzcarDanger else EzcarSuccess // Use Danger for + spending? iOS logic
                            val bg = color.copy(alpha = 0.1f)
                            
                            Row(
                                modifier = Modifier
                                    .background(bg, CircleShape)
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = if (isPositive) Icons.Default.ArrowOutward else Icons.Default.ArrowDownward,
                                    contentDescription = null,
                                    tint = color,
                                    modifier = Modifier.size(12.dp)
                                )
                                Text(
                                    text = "${String.format("%.1f", abs(changePercent))}%",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = color
                                )
                            }
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Chart
            if (trendPoints.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                ) {
                    SpendingTrendChart(points = trendPoints)
                }
            } else {
                Text(
                    text = "No spending data for this period",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )
            }
        }
    }
}

@Composable
fun SpendingTrendChart(points: List<TrendPoint>) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val color = EzcarBlueBright
    val density = LocalDensity.current
    val textPaint = remember(density) {
        Paint().apply {
            this.color = android.graphics.Color.GRAY
            this.textSize = density.run { 10.sp.toPx() }
            this.typeface = Typeface.DEFAULT
            this.isAntiAlias = true
        }
    }
    
    var selectedX by remember { mutableStateOf<Float?>(null) }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull()
                        if (change != null) {
                            if (change.pressed) {
                                selectedX = change.position.x
                            } else {
                                selectedX = null
                            }
                        }
                    }
                }
            }
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            if (points.isEmpty()) return@Canvas
            
            val width = size.width
            val height = size.height
            // Reserve space for labels
            val bottomPadding = 20.dp.toPx()
            val availableHeight = height - bottomPadding
            
            val maxVal = points.maxOf { it.value }
            val minVal = 0f // Baseline 0
            
            val range = if (maxVal - minVal == 0f) 1f else maxVal - minVal
            val stepX = width / (points.size - 1).coerceAtLeast(1)
            
            // Draw Grid Lines (3 lines)
            val gridLines = 3
            for (i in 0..gridLines) {
                val y = availableHeight - (i.toFloat() / gridLines * availableHeight)
                drawLine(
                    color = Color.LightGray.copy(alpha = 0.5f),
                    start = Offset(0f, y),
                    end = Offset(width, y),
                    strokeWidth = 1.dp.toPx()
                )
            }
            
            val path = Path()
            
            // Calculate coordinates
            val mappedPoints = points.mapIndexed { index, point ->
                val x = index * stepX
                val y = availableHeight - ((point.value - minVal) / range * availableHeight)
                Offset(x, y)
            }
            
            path.moveTo(mappedPoints[0].x, mappedPoints[0].y)
            
            // Smooth Curve
            for (i in 0 until mappedPoints.size - 1) {
                val p0 = mappedPoints[i]
                val p1 = mappedPoints[i + 1]
                val controlPoint1 = Offset(p0.x + (p1.x - p0.x) / 2, p0.y)
                val controlPoint2 = Offset(p0.x + (p1.x - p0.x) / 2, p1.y)
                path.cubicTo(controlPoint1.x, controlPoint1.y, controlPoint2.x, controlPoint2.y, p1.x, p1.y)
            }
            
            // Fill Gradient
            val fillPath = Path()
            fillPath.addPath(path)
            fillPath.lineTo(mappedPoints.last().x, availableHeight)
            fillPath.lineTo(0f, availableHeight)
            fillPath.close()
            
            drawPath(
                path = fillPath,
                brush = Brush.verticalGradient(
                    colors = listOf(color.copy(alpha = 0.2f), color.copy(alpha = 0.0f)),
                    startY = 0f,
                    endY = availableHeight
                )
            )
            
            // Stroke
            drawPath(
                path = path,
                color = color,
                style = Stroke(
                    width = 3.dp.toPx(),
                    cap = StrokeCap.Round,
                    join = androidx.compose.ui.graphics.StrokeJoin.Round
                )
            )
            
            // Draw X-Axis Labels (First, Middle, Last)
            if (points.size > 1) {
                val dateFormat = SimpleDateFormat("MMM dd", Locale.getDefault())
                val indices = listOf(0, points.size / 2, points.size - 1)
                
                indices.forEach { index ->
                    if (index in points.indices) {
                        val point = points[index]
                        val x = index * stepX
                        val dateStr = dateFormat.format(point.date)
                        
                        // Align text: Left for first, Center for middle, Right for last
                        val measureText = textPaint.measureText(dateStr)
                        val textX = when (index) {
                            0 -> 0f
                            points.size - 1 -> width - measureText
                            else -> x - measureText / 2
                        }
                        
                        drawContext.canvas.nativeCanvas.drawText(
                            dateStr,
                            textX,
                            height - 5f, // Just above bottom
                            textPaint
                        )
                    }
                }
            }
            
            // Draw Touch Interaction
            selectedX?.let { touchX ->
                // Find closest point
                val index = (touchX / stepX).measureIndex(points.size)
                val closestPoint = mappedPoints[index]
                val originalPoint = points[index]
                
                // Draw vertical line
                drawLine(
                    color = Color.Gray,
                    start = Offset(closestPoint.x, 0f),
                    end = Offset(closestPoint.x, availableHeight),
                    strokeWidth = 1.dp.toPx(),
                    pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(10f, 10f))
                )
                
                // Draw Dot
                drawCircle(
                    color = Color.White,
                    radius = 6.dp.toPx(),
                    center = closestPoint
                )
                drawCircle(
                    color = color,
                    radius = 4.dp.toPx(),
                    center = closestPoint
                )
                
                // Draw Tooltip (Value)
                val valueStr = regionSettingsManager.formatCurrency(
                    BigDecimal.valueOf(originalPoint.value.toDouble())
                )
                val textWidth = textPaint.measureText(valueStr)
                val tooltipX = (closestPoint.x - textWidth / 2).coerceIn(0f, width - textWidth)
                val tooltipY = (closestPoint.y - 30.dp.toPx()).coerceAtLeast(20f)
                
                drawContext.canvas.nativeCanvas.drawText(
                    valueStr,
                    tooltipX,
                    tooltipY,
                    textPaint.apply { 
                        this.color = android.graphics.Color.BLACK 
                        this.isFakeBoldText = true   
                    }
                )
            }
        }
    }
}

private fun Float.measureIndex(count: Int): Int {
    return kotlin.math.round(this).toInt().coerceIn(0, count - 1)
}

@Composable
fun CategoryBreakdownCard(stats: List<CategoryStat>) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text(
                text = "Spending Breakdown",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            if (stats.isEmpty()) {
                Text(
                    text = "No expenses for this period",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            } else {
                stats.forEach { stat ->
                    CategoryBreakdownRow(stat)
                    Spacer(modifier = Modifier.height(16.dp))
                }
            }
        }
    }
}

@Composable
fun CategoryBreakdownRow(stat: CategoryStat) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val color = getCategoryColor(stat.key)
    
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .background(color, CircleShape)
                )
                Text(
                    text = stat.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
            }
            
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = regionSettingsManager.formatCurrency(stat.amount),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "${String.format("%.1f", stat.percent)}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
            }
        }
        
        // Progress Bar (Custom)
        val animatedProgress by animateFloatAsState(
            targetValue = stat.percent.toFloat() / 100f,
            animationSpec = tween(durationMillis = 1000)
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(animatedProgress)
                    .background(color, CircleShape)
            )
        }
    }
}

@Composable
fun RecentExpensesSection(
    recentExpenses: List<Expense>,
    vehicleTitlesById: Map<UUID, String>,
    onSeeAll: () -> Unit,
    onExpenseClick: (Expense) -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Recent Expenses",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onBackground
            )
            TextButton(
                onClick = onSeeAll,
                colors = ButtonDefaults.textButtonColors(contentColor = EzcarBlueBright)
            ) {
                Text("See All")
            }
        }
        
        if (recentExpenses.isEmpty()) {
            Text(
                text = "No recent expenses",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray,
                modifier = Modifier.padding(vertical = 12.dp)
            )
        } else {
            recentExpenses.forEach { expense ->
                RecentExpenseItem(
                    expense = expense,
                    vehicleTitle = expense.vehicleId?.let(vehicleTitlesById::get),
                    onClick = { onExpenseClick(expense) }
                )
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
    }
}

@Composable
fun RecentExpenseItem(
    expense: Expense,
    vehicleTitle: String?,
    onClick: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val dateFormat = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault())

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(EzcarBlueBright.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Receipt, // Generic
                    contentDescription = null,
                    tint = EzcarBlueBright
                )
            }
            
            Spacer(modifier = Modifier.width(16.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = expense.expenseDescription ?: expense.category ?: "Expense",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "${vehicleTitle ?: "General"} • ${dateFormat.format(expenseDisplayDateTime(expense))}",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray
                )
            }
            
            Text(
                text = regionSettingsManager.formatCurrency(expense.amount),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
fun SyncStatusCard(
    syncState: SyncState,
    lastSyncTime: java.util.Date?,
    queueCount: Int,
    onSyncClick: () -> Unit,
    onDataHealthClick: () -> Unit
) {
    val dateFormat = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
    val isSyncing = syncState is SyncState.Syncing

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 0.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val (icon, color, text) = when (syncState) {
            is SyncState.Syncing -> Triple(null, Color.Gray, "Syncing...")
            is SyncState.Success -> Triple(Icons.Default.CheckCircle, EzcarGreen, "Synced just now")
            is SyncState.Failure -> Triple(Icons.Default.Error, EzcarDanger, "Sync failed")
            else -> Triple(null, Color.Gray, "Sync Status")
        }
        
        if (isSyncing) {
             CircularProgressIndicator(
                modifier = Modifier.size(12.dp),
                strokeWidth = 2.dp,
                color = Color.Gray
            )
        } else if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(8.dp))
        
        val displayMessage = when {
            syncState is SyncState.Failure ->
                syncState.message
                    ?.lineSequence()
                    ?.firstOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?: "Sync failed"
            lastSyncTime != null && !isSyncing -> "Synced at ${dateFormat.format(lastSyncTime)}"
            else -> text
        }

        Text(
            text = displayMessage,
            style = MaterialTheme.typography.labelMedium,
            color = Color.Black.copy(alpha = 0.7f),
            maxLines = if (syncState is SyncState.Failure) 2 else 1,
            overflow = TextOverflow.Ellipsis
        )

        if (queueCount > 0) {
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "• $queueCount queued",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        
        Spacer(modifier = Modifier.weight(1f))

        Row(
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.MonitorHeart,
                contentDescription = "Data Health",
                tint = if (queueCount > 0) EzcarOrange else EzcarBlueBright,
                modifier = Modifier
                    .size(16.dp)
                    .clickable { onDataHealthClick() }
            )

            Icon(
                imageVector = Icons.Default.Refresh,
                contentDescription = "Sync",
                tint = EzcarBlueBright,
                modifier = Modifier
                    .size(16.dp)
                    .alpha(if (isSyncing) 0.35f else 1f)
                    .clickable(enabled = !isSyncing) { onSyncClick() }
            )
        }
    }
}

@Composable
fun CRMSummaryCard(
    newLeadsToday: Int,
    callsMadeToday: Int,
    pipelineValue: BigDecimal,
    conversionRate: Double,
    onNavigateToLeadFunnel: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    
    Card(
        colors = CardDefaults.cardColors(containerColor = EzcarNavy),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp)
            .clickable(onClick = onNavigateToLeadFunnel),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "CRM Summary",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.TrendingUp,
                    contentDescription = "View Funnel",
                    tint = EzcarGreen,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                CRMStatItem(
                    value = newLeadsToday.toString(),
                    label = "New Leads",
                    color = EzcarGreen
                )
                CRMStatItem(
                    value = callsMadeToday.toString(),
                    label = "Calls Today",
                    color = EzcarBlueBright
                )
                CRMStatItem(
                    value = regionSettingsManager.formatCurrency(pipelineValue),
                    label = "Pipeline",
                    color = EzcarOrange
                )
                CRMStatItem(
                    value = "${String.format("%.1f", conversionRate)}%",
                    label = "Conversion",
                    color = EzcarSuccess
                )
            }
        }
    }
}

@Composable
private fun CRMStatItem(
    value: String,
    label: String,
    color: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Text(
            text = label,
            fontSize = 11.sp,
            color = Color.White.copy(alpha = 0.7f)
        )
    }
}

@Composable
fun InventorySummaryCard(
    totalVehicles: Int,
    averageDays: Int,
    vehiclesOver90Days: Int,
    healthScore: Int,
    onNavigateToInventoryAnalytics: () -> Unit
) {
    val healthColor = when {
        healthScore >= 80 -> EzcarGreen
        healthScore >= 60 -> EzcarWarning
        healthScore >= 40 -> EzcarOrange
        else -> EzcarDanger
    }
    
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp)
            .clickable(onClick = onNavigateToInventoryAnalytics),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Inventory,
                        contentDescription = null,
                        tint = EzcarNavy,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Inventory Summary",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                }
                
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = "View Analytics",
                    tint = Color.Gray
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                InventoryStatItem(
                    value = totalVehicles.toString(),
                    label = "Vehicles",
                    color = EzcarBlueBright
                )
                
                InventoryStatItem(
                    value = "$averageDays",
                    label = "Avg Days",
                    color = if (averageDays <= 60) EzcarGreen else EzcarOrange
                )
                
                InventoryStatItem(
                    value = vehiclesOver90Days.toString(),
                    label = "90+ Days",
                    color = if (vehiclesOver90Days == 0) EzcarGreen else EzcarDanger
                )
                
                InventoryStatItem(
                    value = "$healthScore",
                    label = "Health",
                    color = healthColor
                )
            }
        }
    }
}

@Composable
private fun InventoryStatItem(
    value: String,
    label: String,
    color: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = value,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Text(
            text = label,
            fontSize = 12.sp,
            color = Color.Gray
        )
    }
}
