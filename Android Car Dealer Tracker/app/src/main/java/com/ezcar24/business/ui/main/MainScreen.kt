package com.ezcar24.business.ui.main

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.ezcar24.business.ui.client.ClientListScreen
import com.ezcar24.business.ui.dashboard.DashboardScreen
import com.ezcar24.business.ui.expense.ExpenseScreen
import com.ezcar24.business.ui.sale.SalesScreen
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.vehicle.VehicleListScreen

sealed class BottomNavItem(val route: String, val title: String, val icon: ImageVector) {
    object Dashboard : BottomNavItem("dashboard", "Home", Icons.Filled.Home)
    object Vehicles : BottomNavItem("vehicles", "Vehicles", Icons.Filled.DirectionsCar)
    object Expenses : BottomNavItem("expenses", "Expenses", Icons.Filled.CreditCard)
    object Sales : BottomNavItem("sales", "Sales", Icons.Filled.AttachMoney)
    object Clients : BottomNavItem("clients", "Clients", Icons.Filled.People)
}

@Composable
fun MainScreen(
    onNavigateToClientDetail: (String?) -> Unit,
    onNavigateToVehicleDetail: (String) -> Unit,
    onNavigateToAddVehicle: () -> Unit,
    onNavigateToAccounts: () -> Unit,
    onNavigateToDebts: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    val navController = rememberNavController()
    val items = listOf(
        BottomNavItem.Dashboard,
        BottomNavItem.Vehicles,
        BottomNavItem.Expenses,
        BottomNavItem.Sales,
        BottomNavItem.Clients
    )

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = Color.White.copy(alpha = 0.95f), // Translucent-ish white
                tonalElevation = 0.dp
            ) {
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination
                items.forEach { screen ->
                    val isSelected = currentDestination?.hierarchy?.any { it.route?.substringBefore("?") == screen.route } == true
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = screen.title) },
                        label = { Text(screen.title, style = MaterialTheme.typography.labelSmall) },
                        selected = isSelected,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = EzcarGreen,
                            selectedTextColor = EzcarGreen,
                            indicatorColor = EzcarGreen.copy(alpha = 0.1f),
                            unselectedIconColor = Color.Gray,
                            unselectedTextColor = Color.Gray
                        ),
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController,
            startDestination = BottomNavItem.Dashboard.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(BottomNavItem.Dashboard.route) { 
                DashboardScreen(
                    onNavigateToAccounts = onNavigateToAccounts,
                    onNavigateToDebts = onNavigateToDebts,
                    onNavigateToSettings = onNavigateToSettings,
                    onNavigateToVehicles = {
                        navController.navigate(BottomNavItem.Vehicles.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onNavigateToSoldVehicles = {
                        // Navigate to vehicles tab - VehicleListScreen will show sold filter
                        navController.navigate("vehicles?status=sold") {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                        }
                    },
                    onNavigateToExpenses = {
                        navController.navigate(BottomNavItem.Expenses.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                ) 
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
            // Also handle plain vehicles route without parameter
            composable(BottomNavItem.Vehicles.route) { 
                VehicleListScreen(
                    onNavigateToAddVehicle = onNavigateToAddVehicle,
                    onNavigateToDetail = onNavigateToVehicleDetail
                ) 
            }
            composable(BottomNavItem.Expenses.route) { ExpenseScreen() }
            composable(BottomNavItem.Sales.route) { SalesScreen() }
            composable(BottomNavItem.Clients.route) { 
                ClientListScreen(onNavigateToDetail = onNavigateToClientDetail) 
            }
        }
    }
}
