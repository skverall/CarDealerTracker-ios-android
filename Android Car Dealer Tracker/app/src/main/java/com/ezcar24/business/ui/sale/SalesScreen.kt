package com.ezcar24.business.ui.sale

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.*
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale
import com.ezcar24.business.ui.finance.DebtsContent

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun SalesScreen(
    salesViewModel: SalesViewModel = hiltViewModel(),
    debtViewModel: com.ezcar24.business.ui.finance.DebtViewModel = hiltViewModel()
) {
    val salesUiState by salesViewModel.uiState.collectAsState()
    val debtUiState by debtViewModel.uiState.collectAsState()
    
    var selectedTab by remember { mutableStateOf(0) }
    var showAddSheet by remember { mutableStateOf(false) }
    var showAddDebtDialog by remember { mutableStateOf(false) }
    var isSearching by remember { mutableStateOf(false) }
    
    val pullRefreshState = rememberPullRefreshState(
        refreshing = salesUiState.isLoading || debtUiState.isLoading,
        onRefresh = { 
            salesViewModel.refresh()
            debtViewModel.loadData()
        }
    )

    LaunchedEffect(Unit) {
        salesViewModel.loadData()
        debtViewModel.loadData()
    }
    
    // Search Logic
    val searchText = if (selectedTab == 0) salesUiState.searchText else debtUiState.searchText
    val onSearchTextChange: (String) -> Unit = if (selectedTab == 0) salesViewModel::onSearchTextChange else debtViewModel::onSearchTextChange
    val onCloseSearch = {
        if (selectedTab == 0) salesViewModel.onSearchTextChange("") else debtViewModel.onSearchTextChange("")
        isSearching = false
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                SalesTopBar(
                    title = if (selectedTab == 0) "Sales History" else "Debts",
                    searchText = searchText,
                    isSearching = isSearching,
                    onSearchTextChange = onSearchTextChange,
                    onSearchClick = { isSearching = true },
                    onCloseSearch = onCloseSearch,
                    onAddClick = { 
                        if (selectedTab == 0) showAddSheet = true 
                        else showAddDebtDialog = true
                    }
                )
                SalesTabs(
                    selectedTab = selectedTab,
                    onTabSelected = { 
                        selectedTab = it 
                        isSearching = false // Reset search mode when switching tabs
                    }
                )
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (selectedTab == 0) {
                // Sales Tab
                Box(modifier = Modifier.pullRefresh(pullRefreshState)) {
                    if (salesUiState.filteredSales.isEmpty()) {
                        EmptySalesState(PaddingValues())
                    } else {
                        SalesList(
                            sales = salesUiState.filteredSales,
                            padding = PaddingValues(top = 0.dp),
                            onDelete = salesViewModel::deleteSale
                        )
                    }
                    PullRefreshIndicator(
                        refreshing = salesUiState.isLoading,
                        state = pullRefreshState,
                        modifier = Modifier.align(Alignment.TopCenter),
                        backgroundColor = Color.White,
                        contentColor = EzcarNavy
                    )
                }
            } else {
                // Debts Tab
                DebtsContent(
                    viewModel = debtViewModel,
                    showAddDialog = showAddDebtDialog,
                    onAddDialogDismiss = { showAddDebtDialog = false }
                )
            }
        }
    }

    if (showAddSheet) {
        AddSaleScreen(
            onDismiss = { showAddSheet = false },
            onSave = { 
                // Creating a sale will be handled inside AddSaleScreen ViewModel or via callback 
                // For this architecture, AddSaleScreen will likely have its own ViewModel injected or logic
                // But following Expenses pattern... let's stick to simple callback or internal VM.
                // Given complexity, AddSaleScreen probably needs its own VM or access to DAOs directly.
                // I will make AddSaleScreen self-contained or passed VM later.
                // For now, let's assume AddSaleScreen handles saving internally via Hilt VM.
                salesViewModel.loadData() // Refresh after save
                showAddSheet = false
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SalesTopBar(
    title: String,
    searchText: String,
    isSearching: Boolean,
    onSearchTextChange: (String) -> Unit,
    onSearchClick: () -> Unit,
    onCloseSearch: () -> Unit,
    onAddClick: () -> Unit
) {
    if (isSearching) {
        TopAppBar(
            title = {
                 TextField(
                     value = searchText,
                     onValueChange = onSearchTextChange,
                     placeholder = { Text("Search...") },
                     colors = TextFieldDefaults.colors(
                         focusedContainerColor = Color.Transparent,
                         unfocusedContainerColor = Color.Transparent,
                         focusedIndicatorColor = Color.Transparent,
                         unfocusedIndicatorColor = Color.Transparent
                     ),
                     singleLine = true,
                     modifier = Modifier.fillMaxWidth()
                 )
            },
            actions = {
                 IconButton(onClick = onCloseSearch) {
                     Icon(Icons.Default.Close, contentDescription = "Close", tint = EzcarNavy)
                 }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White)
        )
    } else {
        TopAppBar(
            title = {
                Text(
                    title,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
            },
            actions = {
                IconButton(onClick = onSearchClick) {
                    Icon(Icons.Default.Search, contentDescription = "Search", tint = EzcarNavy)
                }
                IconButton(onClick = onAddClick) {
                    Icon(Icons.Default.AddCircle, contentDescription = "Add", tint = EzcarNavy)
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White)
        )
    }
}

@Composable
fun SalesTabs(selectedTab: Int, onTabSelected: (Int) -> Unit) {
    TabRow(
        selectedTabIndex = selectedTab,
        containerColor = Color.White,
        contentColor = EzcarNavy,
        indicator = { tabPositions ->
            TabRowDefaults.SecondaryIndicator(
                modifier = Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                color = EzcarNavy
            )
        }
    ) {
        Tab(
            selected = selectedTab == 0,
            onClick = { onTabSelected(0) },
            text = { Text("Sales") }
        )
        Tab(
            selected = selectedTab == 1,
            onClick = { onTabSelected(1) },
            text = { Text("Debts") }
        )
    }
}

@Composable
fun SalesList(
    sales: List<SaleItem>,
    padding: PaddingValues,
    onDelete: (com.ezcar24.business.data.local.Sale) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding() + 8.dp,
            bottom = 80.dp,
            start = 16.dp, 
            end = 16.dp
        ),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(sales, key = { it.sale.id.toString() }) { item ->
            SaleCard(item = item, onDelete = { onDelete(item.sale) })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaleCard(item: SaleItem, onDelete: () -> Unit) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = {
            if (it == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val color = if (dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart) EzcarDanger else Color.Transparent
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(16.dp))
                    .background(color)
                    .padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.White)
            }
        },
        content = {
            Card(
                colors = CardDefaults.cardColors(containerColor = Color.White),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                shape = RoundedCornerShape(16.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    // Header
                    Row(verticalAlignment = Alignment.Top) {
                        Column {
                            Text(
                                text = item.vehicleName,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = EzcarNavy
                            )
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.size(12.dp), tint = Color.Gray)
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(
                                    text = item.buyerName,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color.Gray
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        Text(
                            text = java.text.SimpleDateFormat("d MMM", Locale.getDefault()).format(item.saleDate),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.Gray,
                            modifier = Modifier
                                .background(EzcarBackgroundLight, CircleShape)
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }

                    HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp).alpha(0.5f))

                    // Financial Grid
                    Row(modifier = Modifier.fillMaxWidth()) {
                        FinancialColumn(
                            title = "REVENUE", 
                            amount = item.salePrice, 
                            color = EzcarNavy,
                            modifier = Modifier.weight(1f)
                        )
                        Box(modifier = Modifier.width(1.dp).height(30.dp).background(Color.LightGray))
                        FinancialColumn(
                            title = "COST", 
                            amount = item.costPrice, 
                            color = Color.Gray,
                            modifier = Modifier.weight(1f)
                        )
                        Box(modifier = Modifier.width(1.dp).height(30.dp).background(Color.LightGray))
                        FinancialColumn(
                            title = "NET PROFIT", 
                            amount = item.netProfit, 
                            color = if (item.netProfit >= BigDecimal.ZERO) EzcarSuccess else EzcarDanger,
                            isBold = true,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    )
}

@Composable
fun FinancialColumn(
    title: String, 
    amount: BigDecimal, 
    color: Color, 
    isBold: Boolean = false,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = Color.Gray,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = NumberFormat.getCurrencyInstance(Locale.US).format(amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal,
            color = color
        )
    }
}

@Composable
fun EmptySalesState(padding: PaddingValues) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.MonetizationOn,
                contentDescription = null,
                modifier = Modifier.size(80.dp),
                tint = Color.LightGray
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "No Sales Yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
            Text(
                text = "Record your first sale to see profit analytics.",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
        }
    }
}

// AddSaleScreen will be in a separate file
