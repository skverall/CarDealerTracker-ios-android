package com.ezcar24.business.ui.settings

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.repository.OrganizationMembership
import com.ezcar24.business.data.repository.ReferralStats
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onNavigateToFinancialAccounts: () -> Unit,
    onNavigateToRegionSettings: () -> Unit,
    onNavigateToTeamMembers: () -> Unit,
    onNavigateToBackupCenter: () -> Unit,
    onNavigateToDataHealth: () -> Unit,
    onNavigateToHoldingCostSettings: () -> Unit,
    onNavigateToChangePassword: () -> Unit = {},
    onNavigateToUserGuide: () -> Unit = {},
    onNavigateToPaywall: () -> Unit = {},
    onSignedOut: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val context = LocalContext.current
    val appVersion = remember(context) {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0.0"
        }.getOrDefault("1.0.0")
    }
    var showCreateBusinessDialog by remember { mutableStateOf(false) }
    var showJoinTeamDialog by remember { mutableStateOf(false) }
    var pendingShare by remember { mutableStateOf(false) }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        viewModel.onPermissionResult(granted)
    }

    LaunchedEffect(uiState.needsNotificationPermission) {
        if (uiState.needsNotificationPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(uiState.signedOut) {
        if (uiState.signedOut) {
            viewModel.consumeSignedOut()
            onSignedOut()
        }
    }

    LaunchedEffect(uiState.referralCode, uiState.isFetchingReferralCode, pendingShare) {
        if (pendingShare && !uiState.isFetchingReferralCode) {
            val referralCode = uiState.referralCode
            if (!referralCode.isNullOrBlank()) {
                shareDealerInvite(context, referralCode)
            }
            pendingShare = false
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Account",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                },
                navigationIcon = {},
                actions = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            if (uiState.errorMessage != null) {
                item {
                    StatusCard(
                        text = uiState.errorMessage ?: "",
                        color = EzcarDanger,
                        onDismiss = viewModel::clearErrorMessage
                    )
                }
            }

            if (uiState.statusMessage != null) {
                item {
                    StatusCard(
                        text = uiState.statusMessage ?: "",
                        color = EzcarGreen,
                        onDismiss = viewModel::clearStatusMessage
                    )
                }
            }

            item {
                AccountHeaderCard(
                    email = uiState.currentUser?.email ?: "Guest Mode",
                    createdAt = uiState.currentUser?.createdAt?.toEpochMilliseconds()?.let(::Date),
                    activeOrganization = uiState.activeOrganization,
                    organizations = uiState.organizations,
                    isSwitchingOrganization = uiState.isSwitchingOrganization || uiState.isLoadingAccount,
                    onSelectOrganization = viewModel::switchOrganization,
                    onCreateBusiness = { showCreateBusinessDialog = true }
                )
            }

            item {
                SubscriptionCard(
                    isPro = uiState.isPro,
                    onClick = onNavigateToPaywall
                )
            }

            item {
                ReferralCard(
                    referralCode = uiState.referralCode,
                    referralStats = uiState.referralStats,
                    isLoading = uiState.isFetchingReferralCode,
                    onInviteClick = {
                        if (!uiState.referralCode.isNullOrBlank()) {
                            shareDealerInvite(context, uiState.referralCode!!)
                        } else {
                            pendingShare = true
                            viewModel.refreshReferralCode()
                        }
                    },
                    onCopyCode = {
                        val referralCode = uiState.referralCode
                        if (referralCode.isNullOrBlank()) {
                            viewModel.refreshReferralCode()
                        } else {
                            copyToClipboard(context, "Dealer invite code", referralCode)
                        }
                    },
                    onJoinTeam = { showJoinTeamDialog = true }
                )
            }

            item {
                SettingsSection(title = "General") {
                    NotificationRow(
                        checked = uiState.notificationsEnabled,
                        onCheckedChange = viewModel::toggleNotifications
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Region & Language",
                        subtitle = "${regionState.selectedRegion.displayName} • ${regionState.selectedLanguage.nativeName}",
                        icon = Icons.Default.Public,
                        color = EzcarBlueBright,
                        onClick = onNavigateToRegionSettings
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Holding Cost Settings",
                        subtitle = "Align inventory carrying cost with iOS analytics",
                        icon = Icons.Default.Calculate,
                        color = EzcarOrange,
                        onClick = onNavigateToHoldingCostSettings
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Financial Accounts",
                        subtitle = "Cash, bank and account movement",
                        icon = Icons.Default.AccountBalance,
                        color = EzcarGreen,
                        onClick = onNavigateToFinancialAccounts
                    )
                }
            }

            item {
                SettingsSection(title = "Management") {
                    SettingsRow(
                        title = "Team Members",
                        subtitle = uiState.activeOrganization?.let { "Manage ${it.organizationName} access and roles" }
                            ?: "Manage dealer access and roles",
                        icon = Icons.Default.Group,
                        color = EzcarBlueBright,
                        onClick = onNavigateToTeamMembers
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Backup & Export",
                        subtitle = "Snapshots, export, and recovery",
                        icon = Icons.Default.CloudUpload,
                        color = EzcarOrange,
                        onClick = onNavigateToBackupCenter
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Data Health",
                        subtitle = "Duplicates, sync state and diagnostics",
                        icon = Icons.Default.MonitorHeart,
                        color = Color(0xFF22A6A1),
                        onClick = onNavigateToDataHealth
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Sync Now",
                        subtitle = uiState.lastBackupDate?.let { "Last sync ${formatDate(it)}" }
                            ?: "Manually force a cloud sync",
                        icon = Icons.Default.Sync,
                        color = EzcarNavy,
                        isLoading = uiState.isBackupLoading || uiState.isSwitchingOrganization,
                        onClick = viewModel::triggerSync
                    )
                }
            }

            item {
                SettingsSection(title = "Security") {
                    SettingsRow(
                        title = "Change Password",
                        subtitle = "Update your login credentials",
                        icon = Icons.Default.Lock,
                        color = EzcarPurple,
                        onClick = onNavigateToChangePassword
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Delete Account & Data",
                        subtitle = "Request permanent removal of your account and all data",
                        icon = Icons.Default.DeleteForever,
                        color = EzcarDanger,
                        onClick = {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://www.ezcar24.com/en/delete-account")
                                )
                            )
                        }
                    )
                }
            }

            item {
                SettingsSection(title = "Support") {
                    SettingsRow(
                        title = "Contact Developer",
                        subtitle = "Email support for sync or account issues",
                        icon = Icons.Default.Email,
                        color = EzcarBlueBright,
                        onClick = {
                            val intent = Intent(
                                Intent.ACTION_SENDTO,
                                Uri.parse("mailto:aydmaxx@gmail.com?subject=Feedback:%20Car%20Dealer%20Tracker")
                            )
                            context.startActivity(intent)
                        }
                    )
                }
            }

            item {
                SettingsSection(title = "Legal") {
                    SettingsRow(
                        title = "Terms of Use",
                        icon = Icons.Default.Description,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        onClick = {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://www.ezcar24.com/en/terms-of-use")
                                )
                            )
                        }
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "Privacy Policy",
                        icon = Icons.Default.PrivacyTip,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        onClick = {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://www.ezcar24.com/en/privacy-policy")
                                )
                            )
                        }
                    )
                    SectionDivider()
                    SettingsRow(
                        title = "User Guide",
                        icon = Icons.Default.Book,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        onClick = onNavigateToUserGuide
                    )
                }
            }

            item {
                Button(
                    onClick = viewModel::signOut,
                    enabled = !uiState.isSigningOut,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        contentColor = EzcarDanger
                    ),
                    shape = RoundedCornerShape(18.dp),
                    contentPadding = PaddingValues(horizontal = 18.dp, vertical = 16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Sign Out",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        if (uiState.isSigningOut) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = EzcarDanger
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.ExitToApp,
                                contentDescription = null
                            )
                        }
                    }
                }
            }

            item {
                Text(
                    text = "Car Dealer Tracker v$appVersion",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 24.dp)
                )
            }
        }
    }

    if (showCreateBusinessDialog) {
        CreateBusinessDialog(
            isSaving = uiState.isSwitchingOrganization,
            onDismiss = { showCreateBusinessDialog = false },
            onCreate = {
                showCreateBusinessDialog = false
                viewModel.createOrganization(it)
            }
        )
    }

    if (showJoinTeamDialog) {
        JoinTeamByCodeDialog(
            onDismiss = { showJoinTeamDialog = false },
            onJoin = {
                showJoinTeamDialog = false
                viewModel.joinTeamByCode(it)
            }
        )
    }
}

@Composable
private fun StatusCard(
    text: String,
    color: Color,
    onDismiss: () -> Unit
) {
    Surface(
        color = color.copy(alpha = 0.12f),
        shape = RoundedCornerShape(18.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = color,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = null,
                    tint = color
                )
            }
        }
    }
}

@Composable
private fun AccountHeaderCard(
    email: String,
    createdAt: Date?,
    activeOrganization: OrganizationMembership?,
    organizations: List<OrganizationMembership>,
    isSwitchingOrganization: Boolean,
    onSelectOrganization: (UUID) -> Unit,
    onCreateBusiness: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(24.dp),
        shadowElevation = 10.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .background(EzcarNavy.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = email.take(2).uppercase(Locale.getDefault()).ifBlank { "??" },
                    style = MaterialTheme.typography.displaySmall,
                    color = EzcarNavy
                )
            }
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = email,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = createdAt?.let { "Member since ${formatDate(it)}" } ?: "Guest session",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Box(modifier = Modifier.fillMaxWidth()) {
                Surface(
                    shape = RoundedCornerShape(18.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !isSwitchingOrganization) { showMenu = true }
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .background(EzcarBlueBright.copy(alpha = 0.12f), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            if (isSwitchingOrganization) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                    color = EzcarBlueBright
                                )
                            } else {
                                Icon(
                                    imageVector = Icons.Default.Business,
                                    contentDescription = null,
                                    tint = EzcarBlueBright
                                )
                            }
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = activeOrganization?.organizationName ?: "Select Business",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = activeOrganization?.role?.replaceFirstChar { it.titlecase(Locale.getDefault()) }
                                    ?: "Tap to switch business",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowDown,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
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
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .background(EzcarGreen.copy(alpha = 0.12f), CircleShape)
                    .padding(horizontal = 12.dp, vertical = 7.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Verified,
                    contentDescription = null,
                    tint = EzcarGreen,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Verified Account",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarGreen
                )
            }
        }
    }
}

@Composable
private fun SubscriptionCard(isPro: Boolean, onClick: () -> Unit = {}) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(20.dp),
        shadowElevation = 6.dp,
        modifier = Modifier.clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .background(
                        if (isPro) EzcarOrange.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant,
                        CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = null,
                    tint = if (isPro) EzcarOrange else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isPro) "Dealer Pro" else "Free Plan",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = if (isPro) "Active subscription" else "Tap to upgrade to Pro",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isPro) EzcarGreen else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ReferralCard(
    referralCode: String?,
    referralStats: ReferralStats?,
    isLoading: Boolean,
    onInviteClick: () -> Unit,
    onCopyCode: () -> Unit,
    onJoinTeam: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        shadowElevation = 8.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .background(Color(0xFFFF5EA8).copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                    imageVector = Icons.Default.CardGiftcard,
                        contentDescription = null,
                        tint = Color(0xFFFF5EA8)
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Invite Dealer",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Share your referral link and grow the team like on iOS.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            referralStats?.bonusAccessUntil?.let {
                Text(
                    text = "Bonus access until ${formatDate(it)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = EzcarGreen,
                    fontWeight = FontWeight.SemiBold
                )
            }

            if (!referralCode.isNullOrBlank()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f), RoundedCornerShape(14.dp))
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = referralCode,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f)
                    )
                    IconButton(onClick = onCopyCode) {
                        Icon(
                            imageVector = Icons.Default.ContentCopy,
                            contentDescription = "Copy code",
                            tint = EzcarNavy
                        )
                    }
                }
            }

            Button(
                onClick = onInviteClick,
                enabled = !isLoading,
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = Color.White
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                } else {
                    Icon(
                        imageVector = if (referralCode.isNullOrBlank()) Icons.Default.Share else Icons.Default.CardGiftcard,
                        contentDescription = null
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(if (referralCode.isNullOrBlank()) "Generate Invite Link" else "Share Invite Link")
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Rewards: ${referralStats?.totalRewards ?: 0} referrals",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = onJoinTeam) {
                    Text("Join Team by Code")
                }
            }
        }
    }
}

@Composable
fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = title.uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 12.dp)
        )
        Surface(
            color = MaterialTheme.colorScheme.surface,
            shape = RoundedCornerShape(22.dp),
            shadowElevation = 8.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                content()
            }
        }
    }
}

@Composable
fun SettingsRow(
    title: String,
    icon: ImageVector,
    color: Color,
    subtitle: String? = null,
    isLoading: Boolean = false,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .background(color.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(18.dp)
            )
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            if (subtitle != null) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun NotificationRow(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .background(EzcarOrange.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Notifications,
                contentDescription = null,
                tint = EzcarOrange,
                modifier = Modifier.size(18.dp)
            )
        }
        Spacer(modifier = Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Reminders & Deadlines",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "Client follow-ups, debts and inventory reminders",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = EzcarGreen
            )
        )
    }
}

@Composable
fun SectionDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
        thickness = 1.dp,
        modifier = Modifier.padding(start = 70.dp)
    )
}

@Composable
private fun CreateBusinessDialog(
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
                onClick = { onCreate(businessName) },
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

@Composable
private fun JoinTeamByCodeDialog(
    onDismiss: () -> Unit,
    onJoin: (String) -> Unit
) {
    var inviteCode by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Join Team by Code") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Paste the invite code you received from the business owner.",
                    style = MaterialTheme.typography.bodyMedium
                )
                OutlinedTextField(
                    value = inviteCode,
                    onValueChange = { inviteCode = it.uppercase(Locale.getDefault()) },
                    label = { Text("Invite code") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onJoin(inviteCode) },
                enabled = inviteCode.trim().isNotEmpty()
            ) {
                Text("Join")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun shareDealerInvite(context: Context, referralCode: String) {
    val inviteUrl = "https://ezcar24.com/?ref=$referralCode"
    val message = "Join EZCar24 Business using my invite code $referralCode. Subscribe and we both get an extra month free.\n$inviteUrl"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, message)
    }
    context.startActivity(Intent.createChooser(intent, "Share invite"))
}

private fun copyToClipboard(context: Context, label: String, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
    Toast.makeText(context, "Invite code copied", Toast.LENGTH_SHORT).show()
}

private fun formatDate(date: Date): String {
    return SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(date)
}
