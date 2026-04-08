package com.ezcar24.business.ui.expense

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
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
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun ExpenseScreen(
    viewModel: ExpenseViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var showAddSheet by remember { mutableStateOf(false) }
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            Column {
                ExpenseHeader(
                    totalAmount = uiState.totalAmount,
                    dateFilter = uiState.dateFilter
                )
                ExpenseFilters(
                    uiState = uiState,
                    onDateFilterSelect = viewModel::setDateFilter,
                    onCategorySelect = viewModel::setCategoryFilter,
                    onExpenseTypeSelect = viewModel::setExpenseTypeFilter,
                    onVehicleSelect = viewModel::setVehicleFilter,
                    onUserSelect = viewModel::setUserFilter
                )
            }
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddSheet = true },
                containerColor = EzcarNavy,
                contentColor = Color.White
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add Expense")
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .pullRefresh(pullRefreshState)
        ) {
            if (uiState.filteredExpenses.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = Icons.Default.MonetizationOn,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = Color.Gray.copy(alpha = 0.5f)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = "No expenses found",
                            style = MaterialTheme.typography.titleMedium,
                            color = Color.Gray
                        )
                    }
                }
            } else {
                ExpenseList(
                    expenses = uiState.filteredExpenses,
                    padding = PaddingValues(top = 0.dp),
                    onDelete = viewModel::deleteExpense
                )
            }
            PullRefreshIndicator(
                refreshing = uiState.isLoading,
                state = pullRefreshState,
                modifier = Modifier.align(Alignment.TopCenter),
                backgroundColor = Color.White,
                contentColor = EzcarNavy
            )
        }
    }

    if (showAddSheet) {
        AddExpenseSheet(
            onDismiss = { showAddSheet = false },
            onSave = { amount, date, desc, cat, veh, usr, acc, expenseType ->
                viewModel.saveExpense(amount, date, desc, cat, veh, usr, acc, expenseType)
                showAddSheet = false
            },
            vehicles = uiState.vehicles,
            users = uiState.users,
            accounts = uiState.accounts,
            currencyCode = regionState.selectedRegion.currencyCode
        )
    }
}

@Composable
fun ExpenseHeader(
    totalAmount: java.math.BigDecimal,
    dateFilter: DateFilter
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val displayAmount = regionSettingsManager.formatCurrency(totalAmount)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Expenses",
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = dateFilter.label,
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = displayAmount,
                style = MaterialTheme.typography.displayMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }
    }
}

@Composable
fun ExpenseFilters(
    uiState: ExpenseUiState,
    onDateFilterSelect: (DateFilter) -> Unit,
    onCategorySelect: (String) -> Unit,
    onExpenseTypeSelect: (ExpenseCategoryType?) -> Unit,
    onVehicleSelect: (com.ezcar24.business.data.local.Vehicle?) -> Unit,
    onUserSelect: (com.ezcar24.business.data.local.User?) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.background(MaterialTheme.colorScheme.background)
    ) {
        item {
            var expanded by remember { mutableStateOf(false) }
            Box {
                FilterChip(
                    selected = uiState.selectedVehicle != null,
                    onClick = { expanded = true },
                    label = {
                        val display = listOfNotNull(
                            uiState.selectedVehicle?.make,
                            uiState.selectedVehicle?.model
                        ).joinToString(" ").ifBlank { "Vehicle" }
                        Text(
                            text = display,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(containerColor = Color.White, labelColor = Color.Black),
                    border = null,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.height(40.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text("All Vehicles") },
                        onClick = {
                            onVehicleSelect(null)
                            expanded = false
                        }
                    )
                    uiState.vehicles.forEach { vehicle ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    listOfNotNull(vehicle.make, vehicle.model)
                                        .joinToString(" ")
                                        .ifBlank { vehicle.vin }
                                )
                            },
                            onClick = {
                                onVehicleSelect(vehicle)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }

        item {
            var expanded by remember { mutableStateOf(false) }
            Box {
                FilterChip(
                    selected = uiState.selectedUser != null,
                    onClick = { expanded = true },
                    label = {
                        Text(
                            text = uiState.selectedUser?.name ?: "Employee",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(containerColor = Color.White, labelColor = Color.Black),
                    border = null,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.height(40.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text("All Employees") },
                        onClick = {
                            onUserSelect(null)
                            expanded = false
                        }
                    )
                    uiState.users.forEach { user ->
                        DropdownMenuItem(
                            text = { Text(user.name) },
                            onClick = {
                                onUserSelect(user)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }

        item {
            var expanded by remember { mutableStateOf(false) }
            Box {
                FilterChip(
                    selected = uiState.selectedCategory != "All",
                    onClick = { expanded = true },
                    label = {
                        Text(
                            text = if (uiState.selectedCategory == "All") "Category" else uiState.selectedCategory,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(containerColor = Color.White, labelColor = Color.Black),
                    border = null,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.height(40.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    val categories = listOf("All", "Vehicle", "Personal", "Employee", "Bills", "Marketing")
                    categories.forEach { cat ->
                        DropdownMenuItem(
                            text = { Text(cat) },
                            onClick = {
                                onCategorySelect(cat)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }

        item {
            var expanded by remember { mutableStateOf(false) }
            Box {
                FilterChip(
                    selected = uiState.selectedExpenseType != null,
                    onClick = { expanded = true },
                    label = {
                        val text = when (uiState.selectedExpenseType) {
                            ExpenseCategoryType.HOLDING_COST -> "Holding Cost"
                            ExpenseCategoryType.IMPROVEMENT -> "Improvement"
                            ExpenseCategoryType.OPERATIONAL -> "Operational"
                            null -> "Expense Type"
                        }
                        Text(
                            text = text,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(containerColor = Color.White, labelColor = Color.Black),
                    border = null,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.height(40.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text("All Types") },
                        onClick = {
                            onExpenseTypeSelect(null)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Holding Cost") },
                        onClick = {
                            onExpenseTypeSelect(ExpenseCategoryType.HOLDING_COST)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Improvement") },
                        onClick = {
                            onExpenseTypeSelect(ExpenseCategoryType.IMPROVEMENT)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Operational") },
                        onClick = {
                            onExpenseTypeSelect(ExpenseCategoryType.OPERATIONAL)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun ExpenseList(
    expenses: List<Expense>,
    padding: PaddingValues,
    onDelete: (Expense) -> Unit
) {
    val grouped = expenses.groupBy { getDateBucket(it.date) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding() + 8.dp,
            bottom = 80.dp
        )
    ) {
        grouped.forEach { (bucket, list) ->
            item {
                Text(
                    text = bucket,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color.Gray,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                )
            }

            items(list) { expense ->
                ExpenseItem(expense = expense, onDelete = onDelete)
            }
        }
    }
}

@Composable
fun ExpenseItem(
    expense: Expense,
    onDelete: (Expense) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val dateFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White)
            .clickable { }
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .background(getCategoryColor(expense.category), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = getCategoryIcon(expense.category),
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(24.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = expense.expenseDescription ?: expense.category,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = "${dateFormat.format(expense.date)} • ${getExpenseTypeLabel(expense.expenseType)}",
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
        }

        Text(
            text = regionSettingsManager.formatCurrency(expense.amount),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            color = Color.Black
        )
    }
}

private fun getDateBucket(date: Date): String {
    val now = System.currentTimeMillis()
    val diff = now - date.time
    val dayMillis = 86400000L

    return when {
        diff < dayMillis -> "Today"
        diff < 2 * dayMillis -> "Yesterday"
        diff < 7 * dayMillis -> "This Week"
        diff < 30 * dayMillis -> "This Month"
        else -> "Older"
    }
}

private fun getCategoryColor(category: String): Color {
    return when (category.lowercase()) {
        "vehicle" -> EzcarNavy
        "personal" -> EzcarPurple
        "employee" -> EzcarOrange
        "office", "bills" -> EzcarBlueBright
        "marketing" -> EzcarGreen
        else -> Color.Gray
    }
}

private fun getCategoryIcon(category: String): ImageVector {
    return when (category.lowercase()) {
        "vehicle" -> Icons.Default.DirectionsCar
        "personal" -> Icons.Default.Person
        "employee" -> Icons.Default.Work
        "office", "bills" -> Icons.Default.Business
        "marketing" -> Icons.Default.Campaign
        else -> Icons.Default.Receipt
    }
}

private fun getExpenseTypeLabel(type: ExpenseCategoryType): String {
    return when (type) {
        ExpenseCategoryType.HOLDING_COST -> "Holding Cost"
        ExpenseCategoryType.IMPROVEMENT -> "Improvement"
        ExpenseCategoryType.OPERATIONAL -> "Operational"
    }
}
