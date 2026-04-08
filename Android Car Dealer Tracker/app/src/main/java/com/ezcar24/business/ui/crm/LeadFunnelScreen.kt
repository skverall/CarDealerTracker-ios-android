package com.ezcar24.business.ui.crm

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.ui.components.crm.FunnelVisualization
import com.ezcar24.business.ui.components.crm.LeadCardCompact
import com.ezcar24.business.ui.components.crm.LeadSourceBadge
import com.ezcar24.business.ui.components.crm.LeadSourceSelector
import com.ezcar24.business.ui.components.crm.LeadStageBadge
import com.ezcar24.business.ui.components.crm.PipelineValueCard
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.NumberFormat

@OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class)
@Composable
fun LeadFunnelScreen(
    onBack: () -> Unit,
    onLeadClick: (String) -> Unit,
    viewModel: LeadFunnelViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showFilters by remember { mutableStateOf(false) }
    
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    LaunchedEffect(Unit) {
        viewModel.loadFunnelData()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Lead Funnel") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    IconButton(onClick = { showFilters = !showFilters }) {
                        Icon(Icons.Default.FilterList, contentDescription = "Filter")
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .pullRefresh(pullRefreshState)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Pipeline Value Card
                item {
                    PipelineValueCard(
                        totalValue = uiState.pipelineValue,
                        weightedValue = uiState.weightedPipelineValue,
                        leadCount = uiState.funnelMetrics.activeLeads
                    )
                }

                // Filters
                if (showFilters) {
                    item {
                        FilterSection(
                            selectedSource = uiState.selectedSource,
                            onSourceSelected = { viewModel.onSourceFilterSelected(it) }
                        )
                    }
                }

                // Funnel Visualization
                item {
                    FunnelVisualization(
                        metrics = uiState.funnelMetrics,
                        onStageClick = { stage ->
                            viewModel.onStageSelected(
                                if (uiState.selectedStage == stage) null else stage
                            )
                        }
                    )
                }

                // Daily Activity Summary
                item {
                    DailyActivityCard(activity = uiState.dailyActivity)
                }

                // Source Performance
                if (uiState.sourcePerformance.isNotEmpty()) {
                    item {
                        SourcePerformanceSection(
                            performance = uiState.sourcePerformance
                        )
                    }
                }

                // Selected Stage Leads
                uiState.selectedStage?.let { stage ->
                    item {
                        Column {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "${getStageDisplayName(stage)} Leads",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )
                                TextButton(
                                    onClick = { viewModel.onStageSelected(null) }
                                ) {
                                    Text("Clear")
                                }
                            }
                            
                            Spacer(modifier = Modifier.height(8.dp))
                            
                            if (uiState.leadsInSelectedStage.isEmpty()) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(100.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = "No leads in this stage",
                                        color = Color.Gray
                                    )
                                }
                            }
                        }
                    }

                    items(uiState.leadsInSelectedStage) { lead ->
                        LeadCardCompact(
                            client = lead,
                            onClick = { onLeadClick(lead.id.toString()) }
                        )
                    }
                }
            }

            PullRefreshIndicator(
                refreshing = uiState.isLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }
    }
}

@Composable
private fun FilterSection(
    selectedSource: LeadSource?,
    onSourceSelected: (LeadSource?) -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Filters",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(12.dp))
            
            Text(
                text = "Lead Source",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            LeadSourceSelector(
                selectedSource = selectedSource,
                onSourceSelected = onSourceSelected
            )
        }
    }
}

@Composable
private fun DailyActivityCard(activity: com.ezcar24.business.util.calculator.DailyActivitySummary) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Today's Activity",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                ActivityItem(
                    icon = "\u260e",
                    count = activity.callsCount,
                    label = "Calls",
                    color = EzcarGreen
                )
                ActivityItem(
                    icon = "\u263a",
                    count = activity.meetingsCount,
                    label = "Meetings",
                    color = EzcarPurple
                )
                ActivityItem(
                    icon = "\u2709",
                    count = activity.messagesCount,
                    label = "Messages",
                    color = EzcarBlueBright
                )
                ActivityItem(
                    icon = "\u2605",
                    count = activity.newLeadsCount,
                    label = "New Leads",
                    color = EzcarOrange
                )
            }
        }
    }
}

@Composable
private fun ActivityItem(
    icon: String,
    count: Int,
    label: String,
    color: Color
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(color.copy(alpha = 0.1f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = icon,
                fontSize = 20.sp,
                color = color
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = count.toString(),
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Black
        )
        Text(
            text = label,
            fontSize = 11.sp,
            color = Color.Gray
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SourcePerformanceSection(
    performance: Map<LeadSource, com.ezcar24.business.util.calculator.SourcePerformance>
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Text(
                text = "Source Performance",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                performance.values.forEach { sourcePerf ->
                    SourcePerformanceItem(performance = sourcePerf)
                }
            }
        }
    }
}

@Composable
private fun SourcePerformanceItem(
    performance: com.ezcar24.business.util.calculator.SourcePerformance
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val formatter = NumberFormat.getPercentInstance(regionState.selectedRegion.locale)
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 1
    
    Card(
        colors = CardDefaults.cardColors(
            containerColor = when (performance.source) {
                LeadSource.facebook -> Color(0xFF1877F2).copy(alpha = 0.1f)
                LeadSource.dubizzle -> EzcarOrange.copy(alpha = 0.1f)
                LeadSource.instagram -> Color(0xFFE4405F).copy(alpha = 0.1f)
                LeadSource.referral -> EzcarPurple.copy(alpha = 0.1f)
                LeadSource.walk_in -> EzcarGreen.copy(alpha = 0.1f)
                LeadSource.phone -> EzcarNavy.copy(alpha = 0.1f)
                LeadSource.website -> EzcarBlueBright.copy(alpha = 0.1f)
                LeadSource.other -> Color.Gray.copy(alpha = 0.1f)
            }
        ),
        modifier = Modifier.width(160.dp),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(12.dp)
        ) {
            LeadSourceBadge(source = performance.source)
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                text = "${performance.leadCount} leads",
                fontSize = 12.sp,
                color = Color.DarkGray
            )
            
            Text(
                text = formatter.format(performance.conversionRate / 100),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = when {
                    performance.conversionRate >= 30 -> EzcarSuccess
                    performance.conversionRate >= 15 -> EzcarGreen
                    else -> EzcarOrange
                }
            )
            
            Text(
                text = "${performance.convertedCount} converted",
                fontSize = 11.sp,
                color = Color.Gray
            )
        }
    }
}

private fun getStageDisplayName(stage: LeadStage): String {
    return when (stage) {
        LeadStage.new -> "New"
        LeadStage.contacted -> "Contacted"
        LeadStage.qualified -> "Qualified"
        LeadStage.negotiation -> "Negotiation"
        LeadStage.offer -> "Offer"
        LeadStage.test_drive -> "Test Drive"
        LeadStage.closed_won -> "Closed Won"
        LeadStage.closed_lost -> "Closed Lost"
    }
}
