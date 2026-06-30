package com.ezcar24.business.ui.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.SyncEntityCount
import com.ezcar24.business.data.sync.SyncDiagnosticsReport
import com.ezcar24.business.data.sync.SyncQueueSummaryItem
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarTextSecondaryLight
import java.text.SimpleDateFormat
import java.util.Locale
import com.ezcar24.business.util.localizedUiString
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataHealthScreen(
    onBack: () -> Unit,
    canCleanDuplicates: Boolean = false,
    viewModel: DataHealthViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val formatter = SimpleDateFormat("MMM d, yyyy HH:mm", Locale.getDefault())
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.runDiagnostics()
    }

    LaunchedEffect(copied) {
        if (copied) {
            delay(2_000)
            copied = false
        }
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text(localizedUiString("Data Health")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = localizedUiString("Back"))
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.runDiagnostics() },
                        enabled = !uiState.isRunning && !uiState.isRefreshing
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = localizedUiString("Refresh"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackground)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                DiagnosticsControls(
                    uiState = uiState,
                    canCleanDuplicates = canCleanDuplicates,
                    onRunDiagnostics = viewModel::runDiagnostics,
                    onForceRefresh = viewModel::runFullRefresh,
                    onCleanDuplicates = viewModel::cleanUpDuplicates,
                    copied = copied,
                    onCopyReport = {
                        val reportText = uiState.report?.let { diagnosticsExportText(context, it, formatter) }
                        if (reportText == null) {
                            Toast.makeText(context, context.localizedUiString("Report not available"), Toast.LENGTH_SHORT).show()
                        } else {
                            copyDiagnosticsReport(context, reportText)
                            copied = true
                        }
                    },
                    onShareReport = {
                        val reportText = uiState.report?.let { diagnosticsExportText(context, it, formatter) }
                        if (reportText == null) {
                            Toast.makeText(context, context.localizedUiString("Report not available"), Toast.LENGTH_SHORT).show()
                        } else {
                            shareDiagnosticsReport(context, reportText)
                        }
                    }
                )
            }

            if (uiState.errorMessage != null) {
                item {
                    DataHealthMessageCard(message = uiState.errorMessage ?: "", color = EzcarDanger)
                }
            }

            if (uiState.statusMessage != null) {
                item {
                    DataHealthMessageCard(message = uiState.statusMessage ?: "", color = EzcarGreen)
                }
            }

            val report = uiState.report
            if (report != null) {
                item {
                    SummaryCard(report = report, formatter = formatter)
                }

                if (report.offlineQueueSummary.isNotEmpty()) {
                    item {
                        DataHealthCard(title = "Offline Queue") {
                            QueueSummaryList(report.offlineQueueSummary)
                        }
                    }
                }

                item {
                    DataHealthCard(title = "Entity Counts") {
                        EntityCountsList(report.entityCounts)
                    }
                }
            }
        }
    }
}

@Composable
private fun DiagnosticsControls(
    uiState: DataHealthUiState,
    canCleanDuplicates: Boolean,
    onRunDiagnostics: () -> Unit,
    onForceRefresh: () -> Unit,
    onCleanDuplicates: () -> Unit,
    copied: Boolean,
    onCopyReport: () -> Unit,
    onShareReport: () -> Unit
) {
    val isBusy = uiState.isRunning || uiState.isRefreshing || uiState.isDeduplicating

    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Surface(
                modifier = Modifier.size(52.dp),
                shape = CircleShape,
                color = EzcarBlueBright.copy(alpha = 0.12f)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.MonitorHeart,
                        contentDescription = null,
                        tint = EzcarBlueBright,
                        modifier = Modifier.size(28.dp)
                    )
                }
            }

            Text(
                text = localizedUiString("Sync Diagnostics"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = localizedUiString("Run a quick check to compare local data, remote data, and queued changes."),
                style = MaterialTheme.typography.bodySmall,
                color = EzcarTextSecondaryLight
            )
            DiagnosticsButton(
                text = if (uiState.isRunning) "Running..." else "Run Diagnostics",
                icon = Icons.Default.MonitorHeart,
                color = EzcarBlueBright,
                contentColor = Color.White,
                isLoading = uiState.isRunning,
                enabled = !isBusy,
                onClick = onRunDiagnostics
            )
            DiagnosticsButton(
                text = if (uiState.isRefreshing) "Refreshing..." else "Force Full Refresh",
                icon = Icons.Default.Sync,
                color = EzcarOrange,
                contentColor = Color.Black,
                isLoading = uiState.isRefreshing,
                enabled = !isBusy,
                onClick = onForceRefresh
            )
            if (canCleanDuplicates) {
                DiagnosticsButton(
                    text = if (uiState.isDeduplicating) "Cleaning duplicates..." else "Clean Up Duplicates",
                    icon = Icons.Default.Check,
                    color = EzcarPurple.copy(alpha = if (uiState.isDeduplicating) 0.35f else 0.12f),
                    contentColor = EzcarPurple,
                    isLoading = uiState.isDeduplicating,
                    enabled = !isBusy,
                    onClick = onCleanDuplicates
                )
            }
            if (uiState.report != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    DiagnosticsButton(
                        text = if (copied) "Copied" else "Copy Report",
                        icon = if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                        color = EzcarGreen.copy(alpha = if (copied) 0.22f else 0.12f),
                        contentColor = if (copied) EzcarGreen else MaterialTheme.colorScheme.onSurface,
                        isLoading = false,
                        enabled = !isBusy,
                        modifier = Modifier.weight(1f),
                        onClick = onCopyReport
                    )
                    DiagnosticsButton(
                        text = "Share Report",
                        icon = Icons.Default.Share,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                        contentColor = MaterialTheme.colorScheme.onSurface,
                        isLoading = false,
                        enabled = !isBusy,
                        modifier = Modifier.weight(1f),
                        onClick = onShareReport
                    )
                }
            }
        }
    }
}

@Composable
private fun DiagnosticsButton(
    text: String,
    icon: ImageVector,
    color: Color,
    contentColor: Color,
    isLoading: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.height(48.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = color,
            contentColor = contentColor,
            disabledContainerColor = color.copy(alpha = 0.42f),
            disabledContentColor = contentColor.copy(alpha = 0.76f)
        )
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = contentColor
            )
        } else {
            Icon(icon, contentDescription = null)
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text(localizedUiString(text), fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SummaryCard(
    report: SyncDiagnosticsReport,
    formatter: SimpleDateFormat
) {
    DataHealthCard(
        title = "Summary",
        trailing = {
            HealthBadge(report)
        }
    ) {
        SummaryRow("Last Sync", report.lastSyncAt?.let { formatter.format(it) } ?: localizedUiString("Never"))
        SummaryRow("Diagnostics", formatter.format(report.generatedAt))
        SummaryRow("Queue Items", report.offlineQueueCount.toString())
        report.oldestQueuedAt?.let { oldestQueuedAt ->
            SummaryRow("Oldest Queued", formatter.format(oldestQueuedAt))
        }
        SummaryRow("Syncing", localizedUiString(if (report.isSyncing) "Yes" else "No"))
        report.remoteFetchError?.let { remoteError ->
            Text(
                text = localizedUiString("Remote check failed: %s", remoteError),
                style = MaterialTheme.typography.bodySmall,
                color = EzcarOrange,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
private fun DataHealthCard(
    title: String,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = localizedUiString(title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                trailing?.invoke()
            }
            Spacer(modifier = Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedUiString(label),
            style = MaterialTheme.typography.bodySmall,
            color = EzcarTextSecondaryLight
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun HealthBadge(report: SyncDiagnosticsReport) {
    val label = diagnosticHealthLabel(report)
    val color = diagnosticHealthColor(label)

    Surface(
        shape = RoundedCornerShape(50),
        color = color.copy(alpha = 0.14f)
    ) {
        Text(
            text = localizedUiString(label),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = color,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
        )
    }
}

@Composable
private fun QueueSummaryList(items: List<SyncQueueSummaryItem>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { item ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(localizedUiString("%s • %s", localizedUiString(item.entity.displayName), localizedUiString(item.operation.displayName)))
                Text(item.count.toString())
            }
        }
    }
}

@Composable
private fun EntityCountsList(items: List<SyncEntityCount>) {
    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
        items.forEachIndexed { index, item ->
            if (index > 0) {
                HorizontalDivider()
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(localizedUiString(item.entity.displayName), fontWeight = FontWeight.Medium)
                    Text(
                        text = localizedUiString("Local %d • Remote %s", item.localCount, item.remoteCount?.toString() ?: "-"),
                        style = MaterialTheme.typography.bodySmall,
                        color = EzcarTextSecondaryLight
                    )
                }
                if (item.remoteCount != null) {
                    val delta = item.remoteCount - item.localCount
                    if (delta != 0) {
                        val deltaText = if (delta >= 0) "+$delta" else delta.toString()
                        Text(
                            text = deltaText,
                            color = if (delta > 0) EzcarOrange else EzcarGreen,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DataHealthMessageCard(message: String, color: Color) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = localizedUiString(message),
            color = color,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(14.dp)
        )
    }
}

private fun diagnosticHealthLabel(report: SyncDiagnosticsReport): String {
    return when {
        report.remoteFetchError != null -> "Degraded"
        report.isSyncing || report.offlineQueueCount > 0 -> "In progress"
        else -> "Healthy"
    }
}

private fun diagnosticHealthColor(label: String): Color {
    return when (label) {
        "Healthy" -> EzcarGreen
        "Degraded" -> EzcarOrange
        else -> EzcarBlueBright
    }
}

private fun copyDiagnosticsReport(context: Context, reportText: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(
        ClipData.newPlainText(
            context.localizedUiString("Sync diagnostics report"),
            reportText
        )
    )
    Toast.makeText(context, context.localizedUiString("Copied to clipboard"), Toast.LENGTH_SHORT).show()
}

private fun shareDiagnosticsReport(context: Context, reportText: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, context.localizedUiString("Sync diagnostics report"))
        putExtra(Intent.EXTRA_TEXT, reportText)
    }
    context.startActivity(
        Intent.createChooser(intent, context.localizedUiString("Share Report"))
    )
}

private fun diagnosticsExportText(
    context: Context,
    report: SyncDiagnosticsReport,
    formatter: SimpleDateFormat
): String {
    val dealerId = CloudSyncEnvironment.currentDealerId?.toString() ?: "Unknown"
    val health = diagnosticHealthLabel(report)
    val lines = mutableListOf(
        "SYNC DIAGNOSTICS REPORT",
        "Generated: ${formatter.format(report.generatedAt)}",
        "Dealer: $dealerId",
        "Device: ${Build.MANUFACTURER} ${Build.MODEL}".trim(),
        "System: Android ${Build.VERSION.RELEASE}",
        "App Version: ${appVersionString(context)}",
        "Health: $health",
        "Last Sync: ${report.lastSyncAt?.let { formatter.format(it) } ?: "Never"}",
        "Queue Items: ${report.offlineQueueCount}",
        "Oldest Queued: ${report.oldestQueuedAt?.let { formatter.format(it) } ?: "Never"}",
        "Syncing: ${if (report.isSyncing) "Yes" else "No"}"
    )

    report.remoteFetchError?.takeIf { it.isNotBlank() }?.let { error ->
        lines.add("Remote Fetch Error: $error")
    }

    if (report.offlineQueueSummary.isNotEmpty()) {
        lines.add("")
        lines.add("QUEUE SUMMARY")
        report.offlineQueueSummary.forEach { item ->
            lines.add("- ${item.entity.displayName}: ${item.operation.displayName} x${item.count}")
        }
    }

    if (report.entityCounts.isNotEmpty()) {
        lines.add("")
        lines.add("ENTITY COUNTS")
        report.entityCounts.forEach { item ->
            val remote = item.remoteCount?.toString() ?: "-"
            val delta = item.remoteCount?.let { it - item.localCount }
            val deltaText = if (delta != null && delta != 0) " delta ${if (delta > 0) "+$delta" else delta}" else ""
            lines.add("- ${item.entity.displayName}: local ${item.localCount}, remote $remote$deltaText")
        }
    }

    return lines.joinToString("\n")
}

private fun appVersionString(context: Context): String {
    return runCatching {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionName = packageInfo.versionName ?: "Unknown"
        "$versionName (${packageInfo.longVersionCode})"
    }.getOrDefault("Unknown")
}
