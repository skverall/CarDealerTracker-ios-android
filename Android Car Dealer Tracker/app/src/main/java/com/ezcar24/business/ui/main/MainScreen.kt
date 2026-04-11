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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
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
    onNavigateToClientDetail: (String?) -> Unit,
    onNavigateToVehicleDetail: (String) -> Unit,
    onNavigateToAddVehicle: () -> Unit,
    onNavigateToAccounts: () -> Unit,
    onNavigateToDebts: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToDataHealth: () -> Unit
) {
    val navController = rememberNavController()
    val items = listOf(
        MainTab.Dashboard,
        MainTab.Expenses,
        MainTab.Vehicles,
        MainTab.Parts,
        MainTab.Sales,
        MainTab.Clients
    )
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
                    onNavigateToInventoryAnalytics = { navController.navigate("inventory_analytics") },
                    onNavigateToDataHealth = onNavigateToDataHealth
                )
            }
            composable(MainTab.Expenses.route) {
                ExpenseScreen()
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
                VehicleListScreen(
                    onNavigateToAddVehicle = onNavigateToAddVehicle,
                    onNavigateToDetail = onNavigateToVehicleDetail,
                    presetStatus = statusFilter?.takeIf { it.isNotEmpty() }
                )
            }
            composable(MainTab.Vehicles.route) {
                VehicleListScreen(
                    onNavigateToAddVehicle = onNavigateToAddVehicle,
                    onNavigateToDetail = onNavigateToVehicleDetail
                )
            }
            composable(MainTab.Parts.route) {
                PartsDashboardScreen()
            }
            composable(MainTab.Sales.route) {
                SalesScreen()
            }
            composable(MainTab.Clients.route) {
                ClientListScreen(onNavigateToDetail = onNavigateToClientDetail)
            }
            composable("search") {
                GlobalSearchScreen(
                    onBack = { navController.popBackStack() },
                    onOpenVehicle = onNavigateToVehicleDetail,
                    onOpenClient = onNavigateToClientDetail
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
private fun MainTabBar(
    items: List<MainTab>,
    currentDestinationRoute: String?,
    onTabSelected: (MainTab) -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        shadowElevation = 22.dp,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(EzcarBackgroundLight.copy(alpha = 0.35f))
                .navigationBarsPadding()
                .padding(horizontal = 8.dp, vertical = 10.dp),
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

@Composable
private fun MainTabBarItem(
    item: MainTab,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val iconTint by animateColorAsState(
        targetValue = if (isSelected) item.tint else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "tabIconTint"
    )
    val textColor by animateColorAsState(
        targetValue = if (isSelected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
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
        Surface(
            color = if (isSelected) item.tint.copy(alpha = 0.14f) else Color.Transparent,
            shape = CircleShape,
            modifier = Modifier.size(42.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = item.icon,
                    contentDescription = item.title,
                    tint = iconTint,
                    modifier = Modifier.size(22.dp)
                )
            }
        }
        Text(
            text = item.title,
            style = MaterialTheme.typography.labelSmall,
            fontSize = 10.sp,
            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
            color = textColor,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
        )
    }
}
