package com.ezcar24.business.ui.client

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.ui.theme.*
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import com.ezcar24.business.util.localizedUiString

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class, ExperimentalMaterialApi::class)
@Composable
fun ClientListScreen(
    onNavigateToDetail: (String?) -> Unit,
    viewModel: ClientViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showFilters by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            ClientTopBar(
                onFilterClick = { showFilters = !showFilters },
                onAddClick = { onNavigateToDetail(null) }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pullRefresh(pullRefreshState)
        ) {
            Column {
            // Search Bar
            SearchBar(
                searchText = uiState.searchText, 
                onSearchChange = viewModel::onSearchTextChange
            )

            // Filter Chips
            if (showFilters) {
                ClientFilters(
                    selectedFilter = uiState.dateFilter,
                    onFilterSelected = viewModel::onDateFilterChange
                )
            }

            if (uiState.filteredClients.isEmpty()) {
                EmptyClientState()
            } else {
                ClientGroupedList(
                    clients = uiState.filteredClients,
                    onClientClick = { onNavigateToDetail(it.id.toString()) },
                    onCallClick = { client ->
                        client.phone?.let { phone ->
                            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
                            context.startActivity(intent)
                        }
                    },
                    onWhatsAppClick = { client ->
                        client.phone?.let { phone ->
                            val url = "https://wa.me/${phone.replace(Regex("[^0-9]"), "")}"
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            context.startActivity(intent)
                        }
                    },
                    onSmsClick = { client ->
                        client.phone?.let { phone ->
                            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
                            context.startActivity(intent)
                        }
                    }
                )
            } // else
            }
            PullRefreshIndicator(
                refreshing = uiState.isLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter),
                backgroundColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.primary
            )
        }
    } // Scaffold
}

@Composable
fun ClientTopBar(
    onFilterClick: () -> Unit,
    onAddClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = localizedUiString("Clients"),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(onClick = onFilterClick) {
                Icon(
                    imageVector = Icons.Default.FilterList,
                    contentDescription = localizedUiString("Filter"),
                    tint = EzcarNavy
                )
            }
        }

        IconButton(
            onClick = onAddClick,
            modifier = Modifier
                .size(48.dp)
                .background(EzcarNavy, CircleShape)
        ) {
            Icon(
                imageVector = Icons.Default.Add,
                contentDescription = localizedUiString("Add Client"),
                tint = Color.White
            )
        }
    }
}

@Composable
fun SearchBar(searchText: String, onSearchChange: (String) -> Unit) {
    TextField(
        value = searchText,
        onValueChange = onSearchChange,
        placeholder = { Text(localizedUiString("Search by name, phone..."), color = Color.Gray) },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = Color.Gray) },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(56.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent
        ),
        singleLine = true
    )
}

@Composable
fun ClientFilters(selectedFilter: DateFilterType, onFilterSelected: (DateFilterType) -> Unit) {
    val filters = DateFilterType.values()
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(vertical = 12.dp)
    ) {
        items(filters) { filter ->
            val isSelected = filter == selectedFilter
            FilterChip(
                selected = isSelected,
                onClick = { onFilterSelected(filter) },
                    label = { Text(localizedUiString(filter.labelSource())) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = EzcarNavy,
                        selectedLabelColor = Color.White,
                        containerColor = MaterialTheme.colorScheme.surface,
                        labelColor = EzcarNavy
                    ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = isSelected,
                    borderColor = if (isSelected) EzcarNavy else Color.Transparent
                ),
                modifier = Modifier.heightIn(min = 48.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ClientGroupedList(
    clients: List<Client>,
    onClientClick: (Client) -> Unit,
    onCallClick: (Client) -> Unit,
    onWhatsAppClick: (Client) -> Unit,
    onSmsClick: (Client) -> Unit
) {
    val grouped = clients.groupBy { clientStatusGroupKey(it.status) }
    val statusOrder = listOf("new", "contacted", "viewing", "negotiation", "sold")

    LazyColumn(
        contentPadding = PaddingValues(bottom = 80.dp)
    ) {
        statusOrder.forEach { status ->
            val statusClients = grouped[status]
            if (!statusClients.isNullOrEmpty()) {
                stickyHeader {
                    ClientStatusHeader(status = status, count = statusClients.size)
                }
                items(statusClients) { client ->
                    ClientRow(
                        client = client,
                        onClick = { onClientClick(client) },
                        onCall = { onCallClick(client) },
                        onWhatsApp = { onWhatsAppClick(client) },
                        onSms = { onSmsClick(client) }
                    )
                }
            }
        }
    }
}

@Composable
fun ClientStatusHeader(status: String, count: Int) {
    val displayStatus = localizedUiString(clientStatusSectionLabelSource(status))
        .uppercase(Locale.getDefault())
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background.copy(alpha = 0.95f)) // Use correct background
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = displayStatus,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = count.toString(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
fun ClientRow(
    client: Client,
    onClick: () -> Unit,
    onCall: () -> Unit,
    onWhatsApp: () -> Unit,
    onSms: () -> Unit
) {
    val statusColor = when(clientStatusGroupKey(client.status)) {
        "new" -> EzcarNavy
        "contacted" -> EzcarOrange
        "viewing" -> Color(0xFFFF9800)
        "negotiation" -> EzcarBlueBright
        "sold" -> EzcarGreen
        else -> EzcarNavy
    }
    
    val statusDisplayName = localizedUiString(clientStatusLabelSource(client.status))
    val todayText = localizedUiString("Today")
    val yesterdayText = localizedUiString("Yesterday")
    val interestText = client.requestDetails?.takeIf { it.isNotBlank() }.orEmpty()
    val activityText = remember(client.createdAt, todayText, yesterdayText) {
        formatClientActivityDate(client.createdAt, todayText, yesterdayText)
    }
    val initials = remember(client.name) {
        client.name
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
            .take(2)
            .mapNotNull { it.firstOrNull()?.uppercaseChar()?.toString() }
            .joinToString("")
            .ifBlank { "?" }
    }
    
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.65f))
    ) {
        Row(
            modifier = Modifier
                .padding(12.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(EzcarNavy, EzcarBlueBright))),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = initials,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    maxLines = 1
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top
                ) {
                    Text(
                        text = client.name.ifBlank { localizedUiString("Unknown Client") },
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (activityText.isNotBlank()) {
                        Text(
                            text = activityText,
                            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                }

                if (interestText.isNotBlank()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.DirectionsCar,
                            contentDescription = null,
                            tint = EzcarNavy,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = interestText,
                            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.sp),
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = statusDisplayName,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = statusColor,
                        modifier = Modifier
                            .background(
                                color = statusColor.copy(alpha = 0.12f),
                                shape = RoundedCornerShape(50)
                            )
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    if (!client.phone.isNullOrBlank()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            ClientCircleActionButton(
                                icon = Icons.Default.Phone,
                                background = Brush.verticalGradient(listOf(EzcarNavy, EzcarNavy.copy(alpha = 0.85f))),
                                contentDescription = localizedUiString("Call"),
                                onClick = onCall
                            )
                            ClientCircleActionButton(
                                icon = Icons.AutoMirrored.Filled.Message,
                                background = Brush.verticalGradient(listOf(Color(0xFF1DB954), Color(0xFF0A942F))),
                                contentDescription = localizedUiString("WhatsApp"),
                                onClick = onWhatsApp
                            )
                            ClientCircleActionButton(
                                icon = Icons.AutoMirrored.Filled.Message,
                                background = Brush.verticalGradient(listOf(EzcarBlueBright, EzcarBlueBright.copy(alpha = 0.85f))),
                                contentDescription = localizedUiString("SMS"),
                                onClick = onSms
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ClientCircleActionButton(
    icon: ImageVector,
    background: Brush,
    contentDescription: String,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(background)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = Color.White,
            modifier = Modifier.size(14.dp)
        )
    }
}

private fun formatClientActivityDate(date: Date, todayText: String, yesterdayText: String): String {
    val calendar = Calendar.getInstance().apply { time = date }
    val now = Calendar.getInstance()
    return when {
        calendar.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            calendar.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR) -> {
            "$todayText ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)}"
        }
        calendar.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
            calendar.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR) - 1 -> yesterdayText
        else -> SimpleDateFormat("d MMM", Locale.getDefault()).format(date)
    }
}

@Composable
fun EmptyClientState() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.PersonSearch,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = Color.Gray.copy(alpha = 0.5f)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = localizedUiString("No Clients Found"),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            localizedUiString("Tap + to add a new client"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f)
        )
    }
}

private fun DateFilterType.labelSource(): String {
    return when (this) {
        DateFilterType.ALL -> "All"
        DateFilterType.TODAY -> "Today"
        DateFilterType.WEEK -> "Week"
        DateFilterType.MONTH -> "Month"
    }
}

private fun clientStatusLabelSource(status: String?): String {
    return when (clientStatusGroupKey(status)) {
        "new" -> "New"
        "contacted" -> "Contacted"
        "viewing" -> "Viewing"
        "negotiation" -> "Negotiation"
        "sold" -> "Sold"
        else -> "New"
    }
}

private fun clientStatusSectionLabelSource(status: String): String {
    return when (clientStatusGroupKey(status)) {
        "new" -> "New"
        "contacted" -> "Contacted"
        "viewing" -> "Viewing"
        "negotiation" -> "Negotiation"
        "sold" -> "Sold"
        else -> "New"
    }
}

private fun clientStatusGroupKey(status: String?): String {
    return when (status) {
        "contacted", "engaged", "in_progress" -> "contacted"
        "viewing" -> "viewing"
        "negotiation", "completed" -> "negotiation"
        "sold", "purchased" -> "sold"
        else -> "new"
    }
}
