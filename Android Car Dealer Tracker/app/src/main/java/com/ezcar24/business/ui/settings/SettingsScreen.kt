package com.ezcar24.business.ui.settings

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.Date
import android.content.Intent
import android.net.Uri

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onNavigateToFinancialAccounts: () -> Unit,
    onNavigateToTeamMembers: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    
    // Permission launcher for notifications
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        viewModel.onPermissionResult(granted)
    }
    
    // Request permission when needed
    LaunchedEffect(uiState.needsNotificationPermission) {
        if (uiState.needsNotificationPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Scaffold(
        containerColor = EzcarBackgroundLight, // Light theme background
        topBar = {
            Column {
                TopAppBar(
                    title = { 
                        Text(
                            "Account",
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        ) 
                    },
                    actions = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.Gray)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = EzcarBackgroundLight
                    )
                )
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
            contentPadding = PaddingValues(bottom = 40.dp)
        ) {
            // --- Header: User Profile ---
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 20.dp)
                        .shadow(4.dp, RoundedCornerShape(20.dp))
                        .background(Color.White, RoundedCornerShape(20.dp))
                        .padding(vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Avatar
                    Box(
                        modifier = Modifier
                            .size(100.dp)
                            .background(EzcarNavy.copy(alpha = 0.1f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = uiState.currentUser?.email?.take(2)?.uppercase() ?: "??",
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    // Name/Email
                    Text(
                        text = uiState.currentUser?.email ?: "Not Signed In",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    
                    // Member Since
                    val dateStr = try {
                        uiState.currentUser?.createdAt?.let { 
                            // kotlinx.datetime.Instant to java.util.Date
                            SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(Date(it.toEpochMilliseconds()))
                        } ?: "Unknown"
                    } catch (e: Exception) {
                        "Unknown"
                    }
                    Text(
                        text = "Member since $dateStr",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                    
                    Spacer(modifier = Modifier.height(8.dp))
                    // Verified Badge
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .background(EzcarSuccess.copy(alpha = 0.1f), CircleShape)
                            .padding(horizontal = 12.dp, vertical = 6.dp)
                    ) {
                        Icon(Icons.Default.Verified, contentDescription = null, tint = EzcarSuccess, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Verified Account", style = MaterialTheme.typography.labelSmall, color = EzcarSuccess, fontWeight = FontWeight.Bold)
                    }
                }
            }
            
            // --- Subscription Card ---
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 24.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .shadow(2.dp, RoundedCornerShape(16.dp))
                            .background(Color.White, RoundedCornerShape(16.dp))
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = if (uiState.isPro) Icons.Default.Star else Icons.Default.StarBorder,
                            contentDescription = null,
                            tint = if (uiState.isPro) EzcarOrange else Color.Gray,
                            modifier = Modifier.size(32.dp)
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                if (uiState.isPro) "Dealer Pro" else "Free Plan",
                                fontWeight = FontWeight.Bold,
                                color = Color.Black
                            )
                            Text(
                                if (uiState.isPro) "Active Subscription" else "Upgrade to unlock features",
                                style = MaterialTheme.typography.bodySmall,
                                color = if (uiState.isPro) EzcarSuccess else Color.Gray
                            )
                        }
                        
                        Button(
                            onClick = { /* TODO: Manage/Upgrade */ },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (uiState.isPro) EzcarBackgroundLight else EzcarNavy,
                                contentColor = if (uiState.isPro) EzcarNavy else Color.White
                            ),
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
                            modifier = Modifier.height(36.dp)
                        ) {
                            Text(if (uiState.isPro) "Manage" else "Upgrade", fontSize = 12.sp)
                        }
                    }
                }
            }

            // --- Menu Sections ---
            
            // Finance
            item {
                SettingsSection(title = "Finance") {
                    SettingsRow(
                        title = "Financial Accounts",
                        icon = Icons.Default.AccountBalance,
                        color = EzcarGreen,
                        onClick = onNavigateToFinancialAccounts
                    )
                }
            }
            
            // Notifications
            item {
                SettingsSection(title = "Notifications") {
                    SwitchSettingsRow(
                        title = "Reminders & Deadlines",
                        subtitle = "Get notified about client reminders and debt due dates",
                        icon = Icons.Default.Notifications,
                        color = EzcarOrange,
                        checked = uiState.notificationsEnabled,
                        onCheckedChange = { viewModel.toggleNotifications(it) }
                    )
                }
            }
            
            // Management
            item {
                SettingsSection(title = "Management") {
                    SettingsRow(
                        title = "Team Members",
                        icon = Icons.Default.Group,
                        color = EzcarBlueBright,
                        onClick = onNavigateToTeamMembers
                    )
                    Divider()
                    SettingsRow(
                        title = "Backup & Export",
                        icon = Icons.Default.CloudUpload,
                        color = EzcarOrange,
                        onClick = { viewModel.triggerBackup() }
                    )
                    Divider()
                    SettingsRow(
                        title = "Data Health",
                        icon = Icons.Default.MonitorHeart,
                        color = Color.Cyan, // Teal
                        onClick = { viewModel.runDiagnostics() },
                        subtitle = uiState.diagnosticsResult
                    )
                    Divider()
                    SettingsRow(
                        title = "Sync Now",
                        icon = Icons.Default.Sync,
                        color = EzcarBlueBright,
                        onClick = { viewModel.triggerSync() },
                        isLoading = uiState.isBackupLoading, // Use backup loading state for sync spinner
                        subtitle = if (uiState.lastBackupDate != null) "Last sync: just now" else "Last sync: Never"
                    )
                }
            }
            
            // Account
            item {
                SettingsSection(title = "Account") {
                    SettingsRow(
                        title = "Sign Out",
                        icon = Icons.Default.ExitToApp,
                        color = EzcarDanger,
                        textColor = EzcarDanger,
                        onClick = { viewModel.signOut() },
                        showChevron = false,
                        isLoading = uiState.isSigningOut
                    )
                }
            }
            
            // Security
            item {
                SettingsSection(title = "Security") {
                    SettingsRow(
                        title = "Change Password",
                        icon = Icons.Default.Lock,
                        color = EzcarPurple,
                        onClick = { /* TODO */ }
                    )
                    Divider()
                    SettingsRow(
                        title = "Delete Account",
                        icon = Icons.Default.Delete,
                        color = EzcarDanger,
                        onClick = { /* TODO */ }
                    )
                }
            }
            
            // Legal
            item {
                SettingsSection(title = "Legal") {
                    SettingsRow(
                        title = "Terms of Use",
                        icon = Icons.Default.Description,
                        color = Color.Gray,
                        onClick = { 
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))
                            context.startActivity(intent)
                        }
                    )
                    Divider()
                    SettingsRow(
                        title = "Privacy Policy",
                        icon = Icons.Default.PrivacyTip,
                        color = Color.Gray,
                        onClick = {
                             val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.ezcar24.com/en/privacy-policy"))
                             context.startActivity(intent)
                        }
                    )
                }
            }
            
            item {
                 Text(
                    "Ezcar Business v1.0.8",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray,
                    modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }
    }
}

@Composable
fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = Color.Gray,
            modifier = Modifier.padding(start = 12.dp, bottom = 8.dp)
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(1.dp, RoundedCornerShape(12.dp))
                .background(Color.White, RoundedCornerShape(12.dp))
                .clip(RoundedCornerShape(12.dp))
        ) {
            content()
        }
    }
}

@Composable
fun SettingsRow(
    title: String,
    icon: ImageVector,
    color: Color,
    subtitle: String? = null,
    textColor: Color = Color.Black,
    showChevron: Boolean = true,
    isLoading: Boolean = false,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .background(color.copy(alpha = 0.1f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(16.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = textColor)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }
        
        if (isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.Gray)
        } else if (showChevron) {
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = Color.LightGray, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun Divider() {
    androidx.compose.material3.HorizontalDivider(
        color = Color.LightGray.copy(alpha = 0.2f), 
        thickness = 1.dp, 
        modifier = Modifier.padding(start = 64.dp)
    )
}

@Composable
fun SwitchSettingsRow(
    title: String,
    icon: ImageVector,
    color: Color,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .background(color.copy(alpha = 0.1f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(16.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(16.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = Color.Black)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }
        
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = EzcarGreen,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = Color.LightGray
            )
        )
    }
}
