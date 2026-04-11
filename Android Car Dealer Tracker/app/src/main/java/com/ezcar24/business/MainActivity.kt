package com.ezcar24.business

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.lifecycle.lifecycleScope
import com.ezcar24.business.data.repository.AuthRepository
import com.ezcar24.business.data.repository.AuthDeepLinkResult
import com.ezcar24.business.data.version.PlayStoreVersionChecker
import com.ezcar24.business.ui.auth.LoginScreen
import com.ezcar24.business.ui.auth.PasswordResetScreen
import com.ezcar24.business.ui.theme.CarDealerTrackerAndroidTheme
import com.ezcar24.business.ui.main.MainScreen
import com.ezcar24.business.ui.main.MainViewModel
import com.ezcar24.business.ui.update.ForceUpdateScreen
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var versionChecker: PlayStoreVersionChecker

    // Track if we received a password recovery deep-link
    private val showPasswordReset = MutableStateFlow(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Check for deep-link on cold start
        handleIntent(intent)

        setContent {
            CarDealerTrackerAndroidTheme {
                val isUpdateRequired by versionChecker.isUpdateRequired.collectAsState()

                // Check for updates on launch (matching iOS)
                LaunchedEffect(Unit) {
                    versionChecker.checkForUpdate()
                }

                // Show force update screen if update is required
                if (isUpdateRequired) {
                    ForceUpdateScreen(versionChecker = versionChecker)
                } else {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background
                    ) {
                        val viewModel = androidx.hilt.navigation.compose.hiltViewModel<MainViewModel>()
                        val navController = rememberNavController()
                        val lifecycleOwner = LocalLifecycleOwner.current

                        // Register ViewModel as lifecycle observer for foreground sync
                        LaunchedEffect(viewModel) {
                            lifecycleOwner.lifecycle.addObserver(viewModel)
                        }

                        val startDestination by viewModel.startDestination.collectAsState()
                        val isLoading by viewModel.isLoading.collectAsState()
                        val passwordResetMode by showPasswordReset.collectAsState()

                        // Navigate to password reset if deep-link detected
                        LaunchedEffect(passwordResetMode, startDestination) {
                            if (passwordResetMode && startDestination != null) {
                                navController.navigate("password_reset") {
                                    popUpTo(0) { inclusive = true }
                                }
                            }
                        }

                        if (isLoading || startDestination == null) {
                            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                                CircularProgressIndicator()
                            }
                        } else {
                            NavHost(
                                navController = navController,
                                startDestination = if (passwordResetMode) "password_reset" else startDestination!!
                            ) {
                                composable("login") {
                                    LoginScreen(
                                        onLoginSuccess = {
                                            viewModel.onLoginSuccess()
                                            navController.navigate("home") {
                                                popUpTo("login") { inclusive = true }
                                            }
                                        },
                                        onGuestMode = {
                                            viewModel.onGuestMode()
                                            navController.navigate("home") {
                                                popUpTo("login") { inclusive = true }
                                            }
                                        }
                                    )
                                }
                                composable("password_reset") {
                                    PasswordResetScreen(
                                        onComplete = {
                                            showPasswordReset.value = false
                                            navController.navigate("login") {
                                                popUpTo(0) { inclusive = true }
                                            }
                                        }
                                    )
                                }
                                composable("home") {
                                    MainScreen(
                                        onNavigateToClientDetail = { clientId ->
                                            val route = if (clientId != null) "client_detail/$clientId" else "client_detail/new"
                                            navController.navigate(route)
                                        },
                                        onNavigateToVehicleDetail = { vehicleId ->
                                            navController.navigate("vehicle_detail/$vehicleId")
                                        },
                                        onNavigateToAddVehicle = {
                                            navController.navigate("vehicle_form/new")
                                        },
                                        onNavigateToAccounts = {
                                            navController.navigate("financial_accounts")
                                        },
                                        onNavigateToDebts = {
                                            navController.navigate("debts")
                                        },
                                        onNavigateToDataHealth = {
                                            navController.navigate("data_health")
                                        },
                                        onNavigateToSettings = {
                                            navController.navigate("settings")
                                        }
                                    )
                                }
                                composable(
                                    route = "client_detail/{clientId}",
                                    arguments = listOf(androidx.navigation.navArgument("clientId") { type = androidx.navigation.NavType.StringType })
                                ) { backStackEntry ->
                                    val clientId = backStackEntry.arguments?.getString("clientId")
                                    com.ezcar24.business.ui.client.ClientDetailScreen(
                                        clientId = if (clientId == "new") null else clientId,
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable(
                                    route = "vehicle_detail/{vehicleId}",
                                    arguments = listOf(androidx.navigation.navArgument("vehicleId") { type = androidx.navigation.NavType.StringType })
                                ) { backStackEntry ->
                                    val vehicleId = backStackEntry.arguments?.getString("vehicleId") ?: return@composable
                                    com.ezcar24.business.ui.vehicle.VehicleDetailScreen(
                                        vehicleId = vehicleId,
                                        onBack = { navController.popBackStack() },
                                        onEdit = { id -> navController.navigate("vehicle_form/$id") }
                                    )
                                }
                                composable(
                                    route = "vehicle_form/{vehicleId}",
                                    arguments = listOf(androidx.navigation.navArgument("vehicleId") { type = androidx.navigation.NavType.StringType })
                                ) { backStackEntry ->
                                    val vehicleId = backStackEntry.arguments?.getString("vehicleId")
                                    com.ezcar24.business.ui.vehicle.VehicleAddEditScreen(
                                        vehicleId = if (vehicleId == "new") null else vehicleId,
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("financial_accounts") {
                                    com.ezcar24.business.ui.finance.FinancialAccountListScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("debts") {
                                    com.ezcar24.business.ui.finance.DebtListScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("settings") {
                                    com.ezcar24.business.ui.settings.SettingsScreen(
                                        onBack = { navController.popBackStack() },
                                        onNavigateToFinancialAccounts = { navController.navigate("financial_accounts") },
                                        onNavigateToRegionSettings = { navController.navigate("region_settings") },
                                        onNavigateToTeamMembers = { navController.navigate("team_members") },
                                        onNavigateToBackupCenter = { navController.navigate("backup_center") },
                                        onNavigateToMonthlyReports = { navController.navigate("monthly_report_settings") },
                                        onNavigateToDataHealth = { navController.navigate("data_health") },
                                        onNavigateToHoldingCostSettings = { navController.navigate("holding_cost_settings_root") },
                                        onNavigateToChangePassword = { navController.navigate("change_password") },
                                        onNavigateToUserGuide = { navController.navigate("user_guide") },
                                        onNavigateToPaywall = { navController.navigate("paywall") },
                                        onSignedOut = {
                                            viewModel.onSignedOut()
                                            navController.navigate("login") {
                                                popUpTo(0) { inclusive = true }
                                            }
                                        }
                                    )
                                }
                                composable("holding_cost_settings_root") {
                                    com.ezcar24.business.ui.settings.HoldingCostSettingsScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("region_settings") {
                                    com.ezcar24.business.ui.settings.RegionLanguageSettingsScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("change_password") {
                                    com.ezcar24.business.ui.settings.ChangePasswordScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("user_guide") {
                                    com.ezcar24.business.ui.settings.UserGuideScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("team_members") {
                                    com.ezcar24.business.ui.settings.TeamMembersScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("backup_center") {
                                    com.ezcar24.business.ui.settings.BackupCenterScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("monthly_report_settings") {
                                    com.ezcar24.business.ui.settings.MonthlyReportSettingsScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("data_health") {
                                    com.ezcar24.business.ui.settings.DataHealthScreen(
                                        onBack = { navController.popBackStack() }
                                    )
                                }
                                composable("paywall") {
                                    val subscriptionManager = remember {
                                        (application as? com.ezcar24.business.Ezcar24Application)
                                            ?.let { app ->
                                                dagger.hilt.android.EntryPointAccessors.fromApplication(
                                                    app,
                                                    com.ezcar24.business.data.billing.SubscriptionManagerEntryPoint::class.java
                                                ).subscriptionManager()
                                            }
                                    }
                                    if (subscriptionManager != null) {
                                        com.ezcar24.business.ui.settings.PaywallScreen(
                                            subscriptionManager = subscriptionManager,
                                            onDismiss = { navController.popBackStack() }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        lifecycleScope.launch {
            if (authRepository.handleDeepLink(uri) == AuthDeepLinkResult.PASSWORD_RESET) {
                showPasswordReset.value = true
            }
        }
    }
}
