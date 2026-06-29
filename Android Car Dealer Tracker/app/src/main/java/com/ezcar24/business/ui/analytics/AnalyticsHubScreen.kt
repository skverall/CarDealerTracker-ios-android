package com.ezcar24.business.ui.analytics

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.repository.AIInsightsReport
import com.ezcar24.business.data.repository.AIInsightsUsage
import com.ezcar24.business.ui.components.AutoResizingText
import com.ezcar24.business.ui.dashboard.DashboardTimeRange
import com.ezcar24.business.ui.dashboard.DashboardUiState
import com.ezcar24.business.ui.dashboard.DashboardViewModel
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.ui.theme.EzcarWarning
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnalyticsHubScreen(
    onBack: () -> Unit,
    onNavigateToInventoryAnalytics: () -> Unit,
    onNavigateToLeadFunnel: () -> Unit,
    onNavigateToLeadManagement: () -> Unit,
    onNavigateToDataHealth: () -> Unit,
    onNavigateToSales: () -> Unit,
    onNavigateToExpenses: () -> Unit,
    onNavigateToPaywall: () -> Unit,
    viewModel: DashboardViewModel = hiltViewModel(),
    aiInsightsViewModel: AIInsightsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val aiInsightsState by aiInsightsViewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()

    LaunchedEffect(uiState.selectedRange, uiState.isLoading) {
        if (!uiState.isLoading) {
            aiInsightsViewModel.prepare(uiState.selectedRange)
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = localizedUiString("AI Insights Center"),
                        fontWeight = FontWeight.ExtraBold
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = localizedUiString("Back")
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh(force = false) }) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = localizedUiString("Refresh")
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
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                TimeRangeSelector(
                    selectedRange = uiState.selectedRange,
                    onRangeSelected = viewModel::onTimeRangeChange
                )
            }

            item {
                InsightHeroCard(uiState = uiState)
            }

            item {
                AIInsightsPremiumCard(
                    periodTitle = uiState.selectedRange.displayLabel,
                    state = aiInsightsState,
                    onAction = {
                        if (!aiInsightsState.hasProAccess) {
                            onNavigateToPaywall()
                        } else {
                            aiInsightsViewModel.onPrimaryAction(uiState.selectedRange)
                        }
                    },
                    onSelectReport = aiInsightsViewModel::selectReport,
                    onConfirmRegeneration = { aiInsightsViewModel.confirmRegeneration(uiState.selectedRange) },
                    onCancelRegeneration = aiInsightsViewModel::cancelRegeneration
                )
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    MetricTile(
                        label = localizedUiString("Total Revenue"),
                        value = regionSettingsManager.formatCurrencyCompact(uiState.totalRevenue),
                        color = EzcarBlueBright,
                        modifier = Modifier.weight(1f)
                    )
                    MetricTile(
                        label = localizedUiString("Net Profit"),
                        value = regionSettingsManager.formatCurrencyCompact(uiState.netProfit),
                        color = if (uiState.netProfit >= BigDecimal.ZERO) EzcarSuccess else EzcarDanger,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    MetricTile(
                        label = localizedUiString("Expenses"),
                        value = regionSettingsManager.formatCurrencyCompact(uiState.totalExpensesInPeriod),
                        color = EzcarOrange,
                        modifier = Modifier.weight(1f)
                    )
                    MetricTile(
                        label = localizedUiString("Pipeline"),
                        value = regionSettingsManager.formatCurrencyCompact(uiState.pipelineValue),
                        color = EzcarPurple,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            item {
                InsightDestinationCard(
                    title = localizedUiString("Inventory Analytics"),
                    subtitle = localizedUiString("Open vehicle aging, holding cost and ROI signals."),
                    value = "${uiState.inventoryHealthScore}",
                    valueLabel = localizedUiString("Healthy"),
                    icon = Icons.Default.DirectionsCar,
                    color = EzcarBlueBright,
                    onClick = onNavigateToInventoryAnalytics
                )
            }

            item {
                InsightDestinationCard(
                    title = localizedUiString("Finance Snapshot"),
                    subtitle = localizedUiString("Review revenue, expenses and profit movement."),
                    value = regionSettingsManager.formatCurrencyCompact(uiState.netProfit),
                    valueLabel = localizedUiString("Net Profit"),
                    icon = Icons.Default.AccountBalance,
                    color = EzcarGreen,
                    onClick = onNavigateToSales,
                    secondaryTitle = localizedUiString("Expenses"),
                    secondaryIcon = Icons.Default.CreditCard,
                    secondaryClick = onNavigateToExpenses
                )
            }

            item {
                InsightDestinationCard(
                    title = localizedUiString("CRM Analytics"),
                    subtitle = localizedUiString("Open CRM, leads and follow-up lists."),
                    value = "${String.format("%.1f", uiState.conversionRate)}%",
                    valueLabel = localizedUiString("Conversion"),
                    icon = Icons.Default.People,
                    color = EzcarPurple,
                    onClick = onNavigateToLeadFunnel,
                    secondaryTitle = localizedUiString("Lead Management"),
                    secondaryIcon = Icons.AutoMirrored.Filled.TrendingUp,
                    secondaryClick = onNavigateToLeadManagement
                )
            }

            item {
                InsightDestinationCard(
                    title = localizedUiString("Data Health"),
                    subtitle = localizedUiString("Data Health is the first stop if sync or duplicate issues appear."),
                    value = uiState.queueCount.toString(),
                    valueLabel = localizedUiString("Queued"),
                    icon = Icons.Default.MonitorHeart,
                    color = if (uiState.queueCount > 0) EzcarOrange else EzcarSuccess,
                    onClick = onNavigateToDataHealth
                )
            }

            item {
                Spacer(modifier = Modifier.height(20.dp))
            }
        }
    }
}

@Composable
private fun TimeRangeSelector(
    selectedRange: DashboardTimeRange,
    onRangeSelected: (DashboardTimeRange) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        DashboardTimeRange.entries.forEach { range ->
            FilterChip(
                selected = selectedRange == range,
                onClick = { onRangeSelected(range) },
                label = { Text(range.displayLabel) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = EzcarNavy,
                    selectedLabelColor = Color.White,
                    containerColor = MaterialTheme.colorScheme.surface,
                    labelColor = MaterialTheme.colorScheme.onSurface
                ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = selectedRange == range,
                    borderColor = if (selectedRange == range) EzcarNavy else MaterialTheme.colorScheme.outline
                )
            )
        }
    }
}

@Composable
private fun InsightHeroCard(uiState: DashboardUiState) {
    val pulse = resolvePulse(uiState)

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(26.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    brush = Brush.linearGradient(
                        listOf(
                            pulse.color.copy(alpha = 0.16f),
                            MaterialTheme.colorScheme.surface
                        )
                    )
                )
                .padding(20.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Surface(
                        color = pulse.color,
                        contentColor = Color.White,
                        shape = CircleShape
                    ) {
                        Icon(
                            imageVector = pulse.icon,
                            contentDescription = null,
                            modifier = Modifier
                                .padding(13.dp)
                                .size(24.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(14.dp))

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = localizedUiString("Instant insights for smarter deals"),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            color = pulse.color
                        )
                        Text(
                            text = localizedUiString(pulse.title),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.ExtraBold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                Text(
                    text = localizedUiString(pulse.message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    PulsePill(
                        label = localizedUiString("Inventory"),
                        value = "${uiState.inventoryHealthScore}"
                    )
                    PulsePill(
                        label = localizedUiString("Conversion"),
                        value = "${String.format("%.1f", uiState.conversionRate)}%"
                    )
                    PulsePill(
                        label = localizedUiString("Queued"),
                        value = uiState.queueCount.toString()
                    )
                }
            }
        }
    }
}

@Composable
private fun PulsePill(label: String, value: String) {
    Surface(
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
        shape = CircleShape,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun AIInsightsPremiumCard(
    periodTitle: String,
    state: AIInsightsUiState,
    onAction: () -> Unit,
    onSelectReport: (AIInsightsReport) -> Unit,
    onConfirmRegeneration: () -> Unit,
    onCancelRegeneration: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(24.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        shadowElevation = 3.dp
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            AIInsightsHeader(
                periodTitle = periodTitle,
                hasResponse = state.response != null,
                isLoading = state.isLoading,
                generatedAtMillis = state.generatedAtMillis,
                hasProAccess = state.hasProAccess,
                isCheckingAccess = state.isCheckingAccess
            )

            state.usage?.takeIf { state.hasProAccess }?.let {
                AIInsightsUsageBar(usage = it)
            }

            if (state.isLoading && state.response != null) {
                AIInsightsStatusRow(
                    title = localizedUiString("Generating a fresh report"),
                    subtitle = localizedUiString("Keeping your previous report visible while the new one is prepared."),
                    color = EzcarBlueBright
                )
            }

            if (state.isConfirmingRegeneration && state.response != null && !state.isLoading) {
                AIInsightsRegenerationPrompt(
                    onConfirm = onConfirmRegeneration,
                    onCancel = onCancelRegeneration
                )
            }

            if (state.history.isNotEmpty()) {
                AIInsightsHistorySection(
                    reports = state.history,
                    selectedReportId = state.selectedReportId,
                    onSelectReport = onSelectReport
                )
            }

            when {
                state.isLoading && state.response == null -> AIInsightsLoadingPreview()
                state.response != null -> {
                    AIInsightsSummaryPanel(summary = state.response.summary)
                    AIInsightsTextSection(
                        title = localizedUiString("Insights"),
                        items = state.response.insights
                    )
                    AIInsightsTextSection(
                        title = localizedUiString("Recommendations"),
                        items = state.response.recommendations
                    )
                }
                else -> AIInsightsEmptyState(
                    isSignedIn = state.isSignedIn,
                    hasProAccess = state.hasProAccess,
                    hasData = state.hasData
                )
            }

            state.errorMessage?.let {
                AIInsightsErrorMessage(message = it)
            }

            if (!state.isConfirmingRegeneration) {
                AIInsightsActionButton(
                    title = aiInsightsButtonTitle(state),
                    isLoading = state.isLoading,
                    isEnabled = aiInsightsActionEnabled(state),
                    onClick = onAction
                )
            }
        }
    }
}

@Composable
private fun AIInsightsHeader(
    periodTitle: String,
    hasResponse: Boolean,
    isLoading: Boolean,
    generatedAtMillis: Long?,
    hasProAccess: Boolean,
    isCheckingAccess: Boolean
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(EzcarPurple.copy(alpha = 0.14f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = EzcarPurple,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(14.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = localizedUiString("AI business report"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            val subtitle = when {
                isCheckingAccess -> localizedUiString("Checking Pro access")
                !hasProAccess -> localizedUiString("Unlock AI-generated dealer insights")
                isLoading -> localizedUiString("Generating for %s", periodTitle)
                hasResponse && generatedAtMillis != null -> localizedUiString("Generated %s", generatedAtMillis.displayGeneratedAtText())
                else -> localizedUiString("Ready for %s", periodTitle)
            }
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun AIInsightsUsageBar(usage: AIInsightsUsage) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = localizedUiString("AI usage: %d/%d", usage.used, usage.limit),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = localizedUiString("%d left", usage.remaining),
                style = MaterialTheme.typography.labelMedium,
                color = if (usage.remaining > 0) MaterialTheme.colorScheme.onSurfaceVariant else EzcarWarning
            )
        }
        LinearProgressIndicator(
            progress = { usage.progress },
            modifier = Modifier.fillMaxWidth(),
            color = if (usage.remaining > 0) EzcarPurple else EzcarWarning,
            trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
        )
        usage.resetDisplayText()?.let {
            Text(
                text = localizedUiString("Resets %s", it),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun AIInsightsStatusRow(title: String, subtitle: String, color: Color) {
    Surface(
        color = color.copy(alpha = 0.10f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = color
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun AIInsightsRegenerationPrompt(
    onConfirm: () -> Unit,
    onCancel: () -> Unit
) {
    Surface(
        color = EzcarOrange.copy(alpha = 0.10f),
        shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, EzcarOrange.copy(alpha = 0.22f))
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = localizedUiString("Generate a new report?"),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = localizedUiString("This uses one AI request and replaces the report for the selected range."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = onCancel,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(localizedUiString("Cancel"))
                }
                Button(
                    onClick = onConfirm,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(localizedUiString("Generate"))
                }
            }
        }
    }
}

@Composable
private fun AIInsightsHistorySection(
    reports: List<AIInsightsReport>,
    selectedReportId: String?,
    onSelectReport: (AIInsightsReport) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = localizedUiString("Recent reports"),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            reports.take(8).forEach { report ->
                val selected = selectedReportId == report.id
                Surface(
                    modifier = Modifier
                        .width(220.dp)
                        .clickable { onSelectReport(report) },
                    color = if (selected) EzcarPurple.copy(alpha = 0.14f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f),
                    shape = RoundedCornerShape(16.dp),
                    border = BorderStroke(
                        1.dp,
                        if (selected) EzcarPurple.copy(alpha = 0.45f) else MaterialTheme.colorScheme.outline
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Text(
                            text = report.summary,
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = report.displayDateText(),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AIInsightsSummaryPanel(summary: String) {
    Surface(
        color = EzcarNavy.copy(alpha = 0.08f),
        shape = RoundedCornerShape(18.dp)
    ) {
        Text(
            text = summary,
            modifier = Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun AIInsightsTextSection(title: String, items: List<String>) {
    if (items.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onSurface
        )
        items.take(5).forEachIndexed { index, item ->
            Row(verticalAlignment = Alignment.Top) {
                Surface(
                    color = EzcarPurple.copy(alpha = 0.12f),
                    contentColor = EzcarPurple,
                    shape = CircleShape
                ) {
                    Text(
                        text = (index + 1).toString(),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.ExtraBold
                    )
                }
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = item,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun AIInsightsEmptyState(
    isSignedIn: Boolean,
    hasProAccess: Boolean,
    hasData: Boolean
) {
    val message = when {
        !hasProAccess -> "AI reports are available with Pro access."
        !isSignedIn -> "Sign in to generate reports for your dealership data."
        !hasData -> "Add vehicles, expenses, or sales before generating AI insights."
        else -> "Generate a report to get AI insights for this period."
    }
    Surface(
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f),
        shape = RoundedCornerShape(18.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        Text(
            text = localizedUiString(message),
            modifier = Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun AIInsightsLoadingPreview() {
    AIInsightsStatusRow(
        title = localizedUiString("Generating AI report"),
        subtitle = localizedUiString("Analyzing sales, expenses and inventory for this period."),
        color = EzcarPurple
    )
}

@Composable
private fun AIInsightsErrorMessage(message: String) {
    Surface(
        color = EzcarDanger.copy(alpha = 0.10f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Text(
            text = localizedUiString(message),
            modifier = Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodySmall,
            color = EzcarDanger
        )
    }
}

@Composable
private fun AIInsightsActionButton(
    title: String,
    isLoading: Boolean,
    isEnabled: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = isEnabled,
        modifier = Modifier.fillMaxWidth(),
        shape = CircleShape
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = Color.White
            )
            Spacer(modifier = Modifier.width(10.dp))
        }
        Text(
            text = title,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun aiInsightsButtonTitle(state: AIInsightsUiState): String {
    return when {
        state.isLoading -> "Generating..."
        state.isCheckingAccess -> "Checking..."
        !state.hasProAccess -> "Unlock AI Insights"
        !state.isSignedIn -> "Sign in to generate"
        state.usage?.remaining == 0 -> "Daily limit reached"
        state.response != null -> "Generate new report"
        else -> "Generate report"
    }
}

private fun aiInsightsActionEnabled(state: AIInsightsUiState): Boolean {
    if (state.isLoading || state.isCheckingAccess) return false
    if (!state.hasProAccess) return true
    if (!state.isSignedIn) return false
    if (!state.hasData) return false
    if (state.usage?.remaining == 0) return false
    return true
}

@Composable
private fun MetricTile(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.heightIn(min = 112.dp),
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(20.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .background(color.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(17.dp)
                )
            }
            AutoResizingText(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface,
                minFontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun InsightDestinationCard(
    title: String,
    subtitle: String,
    value: String,
    valueLabel: String,
    icon: ImageVector,
    color: Color,
    onClick: () -> Unit,
    secondaryTitle: String? = null,
    secondaryIcon: ImageVector? = null,
    secondaryClick: (() -> Unit)? = null
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(22.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .background(color.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = color,
                        modifier = Modifier.size(22.dp)
                    )
                }

                Spacer(modifier = Modifier.width(14.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = localizedUiString("Open"),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    AutoResizingText(
                        text = value,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.ExtraBold,
                        color = color,
                        minFontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(
                        text = valueLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                if (secondaryTitle != null && secondaryIcon != null && secondaryClick != null) {
                    Surface(
                        color = color.copy(alpha = 0.12f),
                        contentColor = color,
                        shape = CircleShape,
                        modifier = Modifier.clickable(onClick = secondaryClick)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = secondaryIcon,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(7.dp))
                            Text(
                                text = secondaryTitle,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}

private data class PulseState(
    val title: String,
    val message: String,
    val color: Color,
    val icon: ImageVector
)

private fun resolvePulse(uiState: DashboardUiState): PulseState {
    return when {
        uiState.queueCount > 0 -> PulseState(
            title = "Sync attention",
            message = "There are queued changes waiting to reach the cloud. Open Data Health before relying on reports.",
            color = EzcarOrange,
            icon = Icons.Default.Warning
        )
        uiState.inventoryHealthScore < 65 || uiState.vehiclesOver90Days > 0 -> PulseState(
            title = "Inventory attention",
            message = "Aging units or holding cost pressure need review. Start with inventory analytics.",
            color = EzcarWarning,
            icon = Icons.Default.Warning
        )
        uiState.totalExpensesInPeriod > uiState.totalRevenue && uiState.totalExpensesInPeriod > BigDecimal.ZERO -> PulseState(
            title = "Profit pressure",
            message = "Expenses are outrunning revenue for the selected period. Review sales and expense movement.",
            color = EzcarDanger,
            icon = Icons.Default.Warning
        )
        uiState.pipelineValue > BigDecimal.ZERO && uiState.conversionRate < 10.0 -> PulseState(
            title = "CRM watch",
            message = "Pipeline exists, but conversion is still low. Open CRM follow-ups and lead stages.",
            color = EzcarPurple,
            icon = Icons.Default.People
        )
        else -> PulseState(
            title = "Healthy",
            message = "Revenue, inventory and CRM signals are stable for the selected range.",
            color = EzcarSuccess,
            icon = Icons.Default.CheckCircle
        )
    }
}
