package com.ezcar24.business.ui.main

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.ezcar24.business.ui.analytics.AnalyticsHubScreen
import com.ezcar24.business.ui.client.ClientListScreen
import com.ezcar24.business.ui.crm.LeadFunnelScreen
import com.ezcar24.business.ui.crm.LeadManagementScreen
import com.ezcar24.business.ui.dashboard.DashboardScreen
import com.ezcar24.business.ui.expense.ExpenseScreen
import com.ezcar24.business.ui.inventory.InventoryAlertsScreen
import com.ezcar24.business.ui.inventory.InventoryAnalyticsScreen
import com.ezcar24.business.ui.parts.PartsDashboardScreen
import com.ezcar24.business.ui.sale.SalesScreen
import com.ezcar24.business.ui.search.GlobalSearchScreen
import com.ezcar24.business.ui.settings.HoldingCostSettingsScreen
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.vehicle.VehicleListScreen
import com.ezcar24.business.util.PermissionAccessState
import com.ezcar24.business.util.PermissionKey
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager

import androidx.compose.foundation.BorderStroke

private sealed class MainTab(
    val route: String,
    val title: String,
    val icon: ImageVector,
    val tint: Color
) {
    data object Dashboard : MainTab("dashboard", "Dashboard", Icons.Filled.Home, EzcarNavy)
    data object Expenses : MainTab("expenses", "Expenses", Icons.Filled.CreditCard, Color(0xFFE04F5F))
    data object Vehicles : MainTab("vehicles", "Vehicles", Icons.Filled.DirectionsCar, EzcarPurple)
    data object Parts : MainTab("parts", "Parts", Icons.Filled.Inventory2, EzcarOrange)
    data object Sales : MainTab("sales", "Sales", Icons.Filled.AttachMoney, EzcarGreen)
    data object Clients : MainTab("clients", "Clients", Icons.Filled.People, Color(0xFF4F6DE6))
}

@Composable
fun MainScreen(
    isGuestMode: Boolean,
    permissionState: PermissionAccessState,
    onNavigateToClientDetail: (String?) -> Unit,
    onNavigateToVehicleDetail: (String) -> Unit,
    onNavigateToAddVehicle: () -> Unit,
    onNavigateToPaywall: () -> Unit,
    onNavigateToAccounts: () -> Unit,
    onNavigateToDebts: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToDataHealth: () -> Unit,
    onRefreshPermissions: () -> Unit,
    onGuestAccountRequested: () -> Unit
) {
    val navController = rememberNavController()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()

    val items = buildList {
        add(MainTab.Dashboard)
        add(MainTab.Expenses)
        add(MainTab.Vehicles)
        if (regionState.isPartsEnabled) {
            add(MainTab.Parts)
        }
        add(MainTab.Sales)
        add(MainTab.Clients)
    }
    
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            MainTabBar(
                items = items,
                currentDestinationRoute = currentDestination?.route,
                onTabSelected = { tab ->
                    navController.navigate(tab.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                }
            )
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = MainTab.Dashboard.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(MainTab.Dashboard.route) {
                if (isGuestMode) {
                    GuestFeaturePreview(
                        title = localizedUiString(MainTab.Dashboard.title),
                        tint = MainTab.Dashboard.tint,
                        onGuestAccountRequested = onGuestAccountRequested
                    )
                } else {
                    DashboardScreen(
                        onNavigateToAccounts = onNavigateToAccounts,
                        onNavigateToDebts = onNavigateToDebts,
                        onNavigateToSettings = onNavigateToSettings,
                        onNavigateToSearch = { navController.navigate("search") },
                        onNavigateToVehicles = {
                            navController.navigate(MainTab.Vehicles.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        onNavigateToSoldVehicles = {
                            navController.navigate("vehicles?status=sold") {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                            }
                        },
                        onNavigateToSales = {
                            navController.navigate(MainTab.Sales.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        onNavigateToExpenses = {
                            navController.navigate(MainTab.Expenses.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        onNavigateToLeadFunnel = { navController.navigate("lead_funnel") },
                        onNavigateToLeadManagement = { navController.navigate("lead_management") },
                        onNavigateToAnalyticsHub = { navController.navigate("analytics_hub") },
                        onNavigateToInventoryAnalytics = { navController.navigate("inventory_analytics") },
                        onNavigateToDataHealth = onNavigateToDataHealth
                    )
                }
            }
            composable(MainTab.Expenses.route) {
                PermissionGate(
                    title = localizedUiString(MainTab.Expenses.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.VIEW_EXPENSES),
                    tint = MainTab.Expenses.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    ExpenseScreen()
                }
            }
            composable(
                route = "vehicles?status={status}",
                arguments = listOf(
                    androidx.navigation.navArgument("status") {
                        type = androidx.navigation.NavType.StringType
                        defaultValue = ""
                        nullable = true
                    }
                )
            ) { backStackEntry ->
                val statusFilter = backStackEntry.arguments?.getString("status")
                PermissionGate(
                    title = localizedUiString(MainTab.Vehicles.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.VIEW_INVENTORY),
                    tint = MainTab.Vehicles.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    VehicleListScreen(
                        onNavigateToAddVehicle = onNavigateToAddVehicle,
                        onNavigateToPaywall = onNavigateToPaywall,
                        onNavigateToDetail = onNavigateToVehicleDetail,
                        presetStatus = statusFilter?.takeIf { it.isNotEmpty() }
                    )
                }
            }
            composable(MainTab.Vehicles.route) {
                PermissionGate(
                    title = localizedUiString(MainTab.Vehicles.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.VIEW_INVENTORY),
                    tint = MainTab.Vehicles.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    VehicleListScreen(
                        onNavigateToAddVehicle = onNavigateToAddVehicle,
                        onNavigateToPaywall = onNavigateToPaywall,
                        onNavigateToDetail = onNavigateToVehicleDetail
                    )
                }
            }
            composable(MainTab.Parts.route) {
                PermissionGate(
                    title = localizedUiString(MainTab.Parts.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.VIEW_PARTS_INVENTORY),
                    tint = MainTab.Parts.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    PartsDashboardScreen()
                }
            }
            composable(MainTab.Sales.route) {
                PermissionGate(
                    title = localizedUiString(MainTab.Sales.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.CREATE_SALE, PermissionKey.VIEW_FINANCIALS),
                    tint = MainTab.Sales.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    SalesScreen(permissionState = permissionState)
                }
            }
            composable(MainTab.Clients.route) {
                PermissionGate(
                    title = localizedUiString(MainTab.Clients.title),
                    isGuestMode = isGuestMode,
                    permissionState = permissionState,
                    requiredPermissions = listOf(PermissionKey.VIEW_LEADS),
                    tint = MainTab.Clients.tint,
                    onRefreshPermissions = onRefreshPermissions,
                    onGuestAccountRequested = onGuestAccountRequested
                ) {
                    ClientListScreen(
                        onNavigateToDetail = onNavigateToClientDetail,
                        onNavigateToLeadManagement = { navController.navigate("lead_management") }
                    )
                }
            }
            composable("search") {
                GlobalSearchScreen(
                    onBack = { navController.popBackStack() },
                    onOpenVehicle = onNavigateToVehicleDetail,
                    onOpenClient = onNavigateToClientDetail
                )
            }
            composable("analytics_hub") {
                AnalyticsHubScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToInventoryAnalytics = { navController.navigate("inventory_analytics") },
                    onNavigateToLeadFunnel = { navController.navigate("lead_funnel") },
                    onNavigateToLeadManagement = { navController.navigate("lead_management") },
                    onNavigateToDataHealth = onNavigateToDataHealth,
                    onNavigateToSales = {
                        navController.navigate(MainTab.Sales.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onNavigateToExpenses = {
                        navController.navigate(MainTab.Expenses.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
            }
            composable("lead_funnel") {
                LeadFunnelScreen(
                    onBack = { navController.popBackStack() },
                    onLeadClick = { clientId ->
                        navController.popBackStack()
                        onNavigateToClientDetail(clientId)
                    }
                )
            }
            composable("lead_management") {
                LeadManagementScreen(
                    onBack = { navController.popBackStack() },
                    onLeadClick = onNavigateToClientDetail,
                    onAddLead = { onNavigateToClientDetail(null) }
                )
            }
            composable("inventory_analytics") {
                InventoryAnalyticsScreen(
                    onNavigateToVehicle = onNavigateToVehicleDetail,
                    onNavigateToAlerts = { navController.navigate("inventory_alerts") },
                    onBack = { navController.popBackStack() }
                )
            }
            composable("inventory_alerts") {
                InventoryAlertsScreen(
                    onNavigateToVehicle = onNavigateToVehicleDetail,
                    onBack = { navController.popBackStack() }
                )
            }
            composable("holding_cost_settings") {
                HoldingCostSettingsScreen(
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}

@Composable
private fun PermissionGate(
    title: String,
    isGuestMode: Boolean,
    permissionState: PermissionAccessState,
    requiredPermissions: List<PermissionKey>,
    tint: Color,
    onRefreshPermissions: () -> Unit,
    onGuestAccountRequested: () -> Unit,
    content: @Composable () -> Unit
) {
    when {
        isGuestMode -> GuestFeaturePreview(
            title = title,
            tint = tint,
            onGuestAccountRequested = onGuestAccountRequested
        )

        !permissionState.didLoad && permissionState.isLoading -> PermissionLoadingScreen(title = title)

        permissionState.canAny(requiredPermissions) -> content()

        else -> RestrictedAccessScreen(
            title = title,
            onRefreshPermissions = onRefreshPermissions
        )
    }
}

@Composable
private fun GuestFeaturePreview(
    title: String,
    tint: Color,
    onGuestAccountRequested: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surface,
            shape = RoundedCornerShape(24.dp),
            shadowElevation = 8.dp,
            modifier = Modifier.widthIn(max = 460.dp)
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Surface(
                    color = tint.copy(alpha = 0.12f),
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.LockOpen,
                        contentDescription = null,
                        tint = tint,
                        modifier = Modifier
                            .padding(16.dp)
                            .size(30.dp)
                    )
                }
                Text(
                    text = localizedUiString("Preview mode"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = localizedUiString(
                        "Create an account to use %s with sync, team access and cloud backup.",
                        title
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(2.dp))
                Button(
                    onClick = onGuestAccountRequested,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                ) {
                    Text(localizedUiString("Create your account"))
                }
            }
        }
    }
}

@Composable
private fun RestrictedAccessScreen(
    title: String,
    onRefreshPermissions: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.widthIn(max = 460.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Lock,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(46.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = localizedUiString("You do not have permission to open %s.", title),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Button(
                onClick = onRefreshPermissions,
                modifier = Modifier.height(48.dp)
            ) {
                Text(localizedUiString("Refresh access"))
            }
        }
    }
}

@Composable
private fun PermissionLoadingScreen(title: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            CircularProgressIndicator()
            Text(
                text = localizedUiString("Checking access for %s...", title),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun MainTabBar(
    items: List<MainTab>,
    currentDestinationRoute: String?,
    onTabSelected: (MainTab) -> Unit
) {
    Surface(
        color = Color.Transparent,
        modifier = Modifier.fillMaxWidth()
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                contentColor = MaterialTheme.colorScheme.onSurface,
                shadowElevation = 12.dp,
                shape = CircleShape,
                border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    items.forEach { item ->
                        val selectedRoute = currentDestinationRoute?.substringBefore("?")
                        val isSelected = selectedRoute == item.route ||
                            (selectedRoute == null && item == MainTab.Dashboard)

                        MainTabBarItem(
                            item = item,
                            isSelected = isSelected,
                            onClick = { onTabSelected(item) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MainTabBarItem(
    item: MainTab,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val title = localizedUiString(item.title)
    val iconTint by animateColorAsState(
        targetValue = if (isSelected) item.tint else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "tabIconTint"
    )
    val textColor by animateColorAsState(
        targetValue = if (isSelected) item.tint else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "tabTextTint"
    )

    Column(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .clickable(
                interactionSource = androidx.compose.runtime.remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                indication = null,
                onClick = onClick
            )
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Box(
            modifier = Modifier.size(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = item.icon,
                contentDescription = title,
                tint = iconTint,
                modifier = Modifier.size(22.dp)
            )
        }
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            fontSize = 9.sp,
            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
            color = textColor,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
        )
    }
}
