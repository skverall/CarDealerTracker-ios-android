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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
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
import androidx.hilt.navigation.compose.hiltViewModel
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
    viewModel: DashboardViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()

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

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
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
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
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
                    Text(
                        text = value,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.ExtraBold,
                        color = color,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
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
