package com.ezcar24.business.ui.crm

import android.content.Context
import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.ui.components.crm.LeadCard
import com.ezcar24.business.ui.components.crm.LeadSourceBadge
import com.ezcar24.business.ui.components.crm.LeadSourceSelector
import com.ezcar24.business.ui.components.crm.LeadStageBadge
import com.ezcar24.business.ui.components.crm.LeadStageSelector
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.util.rememberRegionSettingsManager

@OptIn(ExperimentalMaterialApi::class, ExperimentalMaterial3Api::class)
@Composable
fun LeadManagementScreen(
    onBack: () -> Unit,
    onLeadClick: (String) -> Unit,
    onAddLead: () -> Unit,
    viewModel: LeadManagementViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val context = LocalContext.current
    var showFilters by remember { mutableStateOf(false) }
    var showSortMenu by remember { mutableStateOf(false) }
    
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Lead Management") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    Box {
                        IconButton(onClick = { showSortMenu = true }) {
                            Icon(Icons.Default.Sort, contentDescription = "Sort")
                        }
                        DropdownMenu(
                            expanded = showSortMenu,
                            onDismissRequest = { showSortMenu = false }
                        ) {
                            LeadSortOption.values().forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(getSortOptionLabel(option)) },
                                    onClick = {
                                        viewModel.onSortOptionSelected(option)
                                        showSortMenu = false
                                    }
                                )
                            }
                        }
                    }
                    IconButton(onClick = { showFilters = !showFilters }) {
                        Icon(Icons.Default.FilterList, contentDescription = "Filter")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddLead,
                containerColor = EzcarBlueBright
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add Lead", tint = Color.White)
            }
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
                // Search Bar
                item {
                    OutlinedTextField(
                        value = uiState.searchQuery,
                        onValueChange = { viewModel.onSearchQueryChange(it) },
                        placeholder = { Text("Search leads...") },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search)
                    )
                }

                // Summary Cards
                item {
                    LeadSummaryCards(
                        totalLeads = uiState.allLeads.size,
                        activeLeads = viewModel.getActiveLeadsCount(),
                        pipelineValue = viewModel.getTotalPipelineValue(),
                        newLeadsToday = viewModel.getNewLeadsTodayCount(),
                        currencyCode = regionState.selectedRegion.currencyCode
                    )
                }

                uiState.statusMessage?.let { statusMessage ->
                    item {
                        LeadManagementBanner(
                            message = statusMessage,
                            isError = false,
                            onDismiss = viewModel::clearStatusMessage
                        )
                    }
                }

                uiState.error?.let { errorMessage ->
                    item {
                        LeadManagementBanner(
                            message = errorMessage,
                            isError = true,
                            onDismiss = viewModel::clearError
                        )
                    }
                }

                // Filters
                if (showFilters) {
                    item {
                        FilterSection(
                            selectedStage = uiState.selectedStage,
                            onStageSelected = { viewModel.onStageFilterSelected(it) },
                            selectedSource = uiState.selectedSource,
                            onSourceSelected = { viewModel.onSourceFilterSelected(it) },
                            onClearFilters = { viewModel.clearFilters() }
                        )
                    }
                }

                // Source Breakdown
                item {
                    SourceBreakdownSection(
                        breakdown = viewModel.getSourceBreakdown()
                    )
                }

                // Results Count
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "${uiState.filteredLeads.size} leads found",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                        if (uiState.selectedStage != null || uiState.selectedSource != null || uiState.searchQuery.isNotBlank()) {
                            TextButton(onClick = { viewModel.clearFilters() }) {
                                Text("Clear filters")
                            }
                        }
                    }
                }

                // Leads List
                if (uiState.filteredLeads.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(200.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text(
                                    text = "No leads found",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = Color.Gray
                                )
                                if (uiState.searchQuery.isNotBlank() || uiState.selectedStage != null || uiState.selectedSource != null) {
                                    TextButton(onClick = { viewModel.clearFilters() }) {
                                        Text("Clear filters to see all leads")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    items(uiState.filteredLeads) { lead ->
                        LeadCard(
                            client = lead,
                            onClick = { onLeadClick(lead.id.toString()) },
                            onCall = { openDialer(context, lead.phone) },
                            onMessage = { openWhatsApp(context, lead.phone) },
                            onEmail = if (lead.email != null) {
                                { openEmail(context, lead.email) }
                            } else null,
                            onChangeStage = { newStage ->
                                viewModel.updateLeadStage(lead, newStage)
                            }
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
private fun LeadManagementBanner(
    message: String,
    isError: Boolean,
    onDismiss: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = if (isError) Color(0xFFFFF1F0) else Color(0xFFF3FAF6)
        ),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isError) Color(0xFFB42318) else Color(0xFF067647),
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = onDismiss) {
                Text("Dismiss")
            }
        }
    }
}

private fun openDialer(context: Context, phone: String?) {
    val value = phone?.trim().orEmpty()
    if (value.isBlank()) return
    context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$value")))
}

private fun openWhatsApp(context: Context, phone: String?) {
    val digits = phone.orEmpty().replace(Regex("[^0-9]"), "")
    if (digits.isBlank()) return
    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits")))
}

private fun openEmail(context: Context, email: String?) {
    val value = email?.trim().orEmpty()
    if (value.isBlank()) return
    context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$value")))
}

@Composable
private fun LeadSummaryCards(
    totalLeads: Int,
    activeLeads: Int,
    pipelineValue: java.math.BigDecimal,
    newLeadsToday: Int,
    currencyCode: String
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SummaryCard(
            value = totalLeads.toString(),
            label = "Total",
            color = EzcarNavy,
            modifier = Modifier.weight(1f)
        )
        SummaryCard(
            value = activeLeads.toString(),
            label = "Active",
            color = EzcarBlueBright,
            modifier = Modifier.weight(1f)
        )
        SummaryCard(
            value = newLeadsToday.toString(),
            label = "New Today",
            color = EzcarSuccess,
            modifier = Modifier.weight(1f)
        )
    }
    
    Spacer(modifier = Modifier.height(12.dp))
    
    Card(
        colors = CardDefaults.cardColors(containerColor = EzcarNavy),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Pipeline Value ($currencyCode)",
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.7f)
            )
            Text(
                text = regionSettingsManager.formatCurrency(pipelineValue),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }
    }
}

@Composable
private fun SummaryCard(
    value: String,
    label: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f)),
        modifier = modifier,
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = value,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = color
            )
            Text(
                text = label,
                fontSize = 12.sp,
                color = color.copy(alpha = 0.8f)
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSection(
    selectedStage: LeadStage?,
    onStageSelected: (LeadStage?) -> Unit,
    selectedSource: LeadSource?,
    onSourceSelected: (LeadSource?) -> Unit,
    onClearFilters: () -> Unit
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Filters",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(onClick = onClearFilters) {
                    Text("Clear all")
                }
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            // Stage Filter
            Text(
                text = "Stage",
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = selectedStage == null,
                    onClick = { onStageSelected(null) },
                    label = { Text("All") }
                )
                LeadStage.values().forEach { stage ->
                    FilterChip(
                        selected = selectedStage == stage,
                        onClick = { onStageSelected(stage) },
                        label = { Text(getStageDisplayName(stage)) }
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Source Filter
            Text(
                text = "Source",
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SourceBreakdownSection(
    breakdown: Map<LeadSource?, Int>
) {
    if (breakdown.isEmpty()) return
    
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
                text = "Source Breakdown",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            
            Spacer(modifier = Modifier.height(12.dp))
            
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                breakdown.entries.sortedByDescending { it.value }.forEach { (source, count) ->
                    if (source != null) {
                        SourceCountChip(source = source, count = count)
                    }
                }
            }
        }
    }
}

@Composable
private fun SourceCountChip(
    source: LeadSource,
    count: Int
) {
    val color = when (source) {
        LeadSource.facebook -> Color(0xFF1877F2)
        LeadSource.dubizzle -> EzcarOrange
        LeadSource.instagram -> Color(0xFFE4405F)
        LeadSource.referral -> EzcarPurple
        LeadSource.walk_in -> EzcarGreen
        LeadSource.phone -> EzcarNavy
        LeadSource.website -> EzcarBlueBright
        LeadSource.other -> Color.Gray
    }
    
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        LeadSourceBadge(source = source)
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = count.toString(),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
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
        LeadStage.closed_won -> "Won"
        LeadStage.closed_lost -> "Lost"
    }
}

private fun getSortOptionLabel(option: LeadSortOption): String {
    return when (option) {
        LeadSortOption.NEWEST -> "Newest first"
        LeadSortOption.OLDEST -> "Oldest first"
        LeadSortOption.PRIORITY_HIGH -> "Priority: High to Low"
        LeadSortOption.PRIORITY_LOW -> "Priority: Low to High"
        LeadSortOption.VALUE_HIGH -> "Value: High to Low"
        LeadSortOption.VALUE_LOW -> "Value: Low to High"
        LeadSortOption.NAME_ASC -> "Name: A to Z"
        LeadSortOption.NAME_DESC -> "Name: Z to A"
    }
}
