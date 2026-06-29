package com.ezcar24.business.ui.expense

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.expenseDisplayDateTime
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import com.ezcar24.business.util.localizedUiString

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun ExpenseScreen(
    viewModel: ExpenseViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val context = androidx.compose.ui.platform.LocalContext.current
    var showAddSheet by remember { mutableStateOf(false) }
    var selectedExpense by remember { mutableStateOf<Expense?>(null) }
    val vehicleTitlesById = remember(uiState.vehicles) {
        uiState.vehicles.associate { vehicle ->
            vehicle.id to listOfNotNull(vehicle.make, vehicle.model)
                .joinToString(" ")
                .ifBlank { vehicle.vin }
        }
    }
    val userNamesById = remember(uiState.users) {
        uiState.users.associate { it.id to it.name }
    }
    val pullRefreshState = rememberPullRefreshState(
        refreshing = uiState.isLoading,
        onRefresh = { viewModel.refresh() }
    )

    Scaffold(
        containerColor = EzcarBackgroundLight,
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddSheet = true },
                containerColor = EzcarNavy,
                contentColor = Color.White
            ) {
                Icon(Icons.Default.Add, contentDescription = localizedUiString("Add Expense"))
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .pullRefresh(pullRefreshState)
        ) {
            ExpenseList(
                expenses = uiState.filteredExpenses,
                padding = PaddingValues(top = 0.dp),
                onExpenseClick = { selectedExpense = it },
                userNamesById = userNamesById,
                header = {
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
            )
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
            onSave = { amount, date, desc, cat, veh, usr, acc, expenseType, receipt ->
                viewModel.saveExpense(amount, date, desc, cat, veh, usr, acc, expenseType, receipt)
                showAddSheet = false
            },
            onSaveTemplate = viewModel::saveTemplate,
            onCreateUser = viewModel::createUser,
            onCreateAccount = viewModel::createAccount,
            vehicles = uiState.vehicles,
            users = uiState.users,
            accounts = uiState.accounts,
            templates = uiState.templates,
            currencyCode = regionState.selectedRegion.currencyCode
        )
    }

    selectedExpense?.let { expense ->
        ExpenseDetailBottomSheet(
            expense = expense,
            vehicleTitle = expense.vehicleId?.let(vehicleTitlesById::get),
            onDismiss = { selectedExpense = null },
            onSaveComment = viewModel::updateExpenseComment,
            onViewReceipt = { viewModel.openExpenseReceipt(context, it) },
            onReplaceReceipt = { targetExpense, receipt, onUpdated ->
                viewModel.replaceExpenseReceipt(targetExpense, receipt, onUpdated)
            },
            onRemoveReceipt = { targetExpense, onUpdated ->
                viewModel.removeExpenseReceipt(targetExpense, onUpdated)
            }
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
            .background(EzcarBackgroundLight)
            .statusBarsPadding()
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                localizedUiString("Expenses"),
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Physical Credit Card Style Header
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(190.dp)
                .shadow(10.dp, RoundedCornerShape(20.dp))
                .background(
                    brush = Brush.linearGradient(
                        colors = listOf(Color(0xFF1E2E4F), Color(0xFF0C1324))
                    ),
                    shape = RoundedCornerShape(20.dp)
                )
                .clip(RoundedCornerShape(20.dp))
        ) {
            // Wave meshes
            androidx.compose.foundation.Canvas(modifier = Modifier.matchParentSize()) {
                val w = size.width
                val h = size.height
                drawCircle(
                    color = Color(0xFF2E85EB).copy(alpha = 0.08f),
                    radius = h * 0.9f,
                    center = Offset(w * 0.8f, h * 0.9f)
                )
                drawCircle(
                    color = Color(0xFF4785E6).copy(alpha = 0.05f),
                    radius = h * 0.6f,
                    center = Offset(w * 0.1f, h * 0.2f)
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedUiString("Car Dealer Tracker"),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )

                    // Overlapping circles (Mastercard logo style)
                    Box(modifier = Modifier.width(38.dp).height(24.dp)) {
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .background(Color(0xFFEB001B).copy(alpha = 0.9f), CircleShape)
                        )
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .align(Alignment.CenterEnd)
                                .background(Color(0xFFFA8C38).copy(alpha = 0.9f), CircleShape)
                        )
                    }
                }

                // EMV gold chip
                Box(
                    modifier = Modifier
                        .size(width = 42.dp, height = 30.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFE5B842))
                        .padding(2.dp)
                ) {
                    androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                        val w = size.width
                        val h = size.height
                        drawLine(color = Color(0xFFB58405), start = Offset(w * 0.33f, 0f), end = Offset(w * 0.33f, h), strokeWidth = 1.dp.toPx())
                        drawLine(color = Color(0xFFB58405), start = Offset(w * 0.67f, 0f), end = Offset(w * 0.67f, h), strokeWidth = 1.dp.toPx())
                        drawLine(color = Color(0xFFB58405), start = Offset(0f, h * 0.5f), end = Offset(w, h * 0.5f), strokeWidth = 1.dp.toPx())
                    }
                }

                Column {
                    val periodText = when (dateFilter) {
                        DateFilter.ALL -> "ALL TIME"
                        DateFilter.TODAY -> "TODAY"
                        DateFilter.WEEK -> "THIS WEEK"
                        DateFilter.MONTH -> "THIS MONTH"
                    }
                    Text(
                        text = localizedUiString(periodText),
                        style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 1.5.sp),
                        color = Color.White.copy(alpha = 0.6f),
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = displayAmount,
                        style = MaterialTheme.typography.headlineLarge.copy(fontSize = 32.sp),
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
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
        modifier = Modifier.background(EzcarBackgroundLight)
    ) {
        item {
            var expanded by remember { mutableStateOf(false) }
            val isSelected = uiState.dateFilter != DateFilter.ALL
            Box {
                FilterChip(
                    selected = isSelected,
                    onClick = { expanded = true },
                    label = {
                        Text(
                            text = localizedUiString(uiState.dateFilter.label),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) EzcarNavy else Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = if (isSelected) EzcarNavy else Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.White,
                        labelColor = Color.Gray,
                        selectedContainerColor = Color.White,
                        selectedLabelColor = EzcarNavy
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E8F0)),
                    shape = CircleShape,
                    modifier = Modifier.height(38.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DateFilter.values().forEach { filter ->
                        DropdownMenuItem(
                            text = { Text(localizedUiString(filter.label)) },
                            onClick = {
                                onDateFilterSelect(filter)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }

        item {
            var expanded by remember { mutableStateOf(false) }
            val isSelected = uiState.selectedVehicle != null
            Box {
                FilterChip(
                    selected = isSelected,
                    onClick = { expanded = true },
                    label = {
                        val display = listOfNotNull(
                            uiState.selectedVehicle?.make,
                            uiState.selectedVehicle?.model
                        ).joinToString(" ").ifBlank { localizedUiString("Vehicle") }
                        Text(
                            text = display,
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) EzcarNavy else Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = if (isSelected) EzcarNavy else Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.White,
                        labelColor = Color.Gray,
                        selectedContainerColor = Color.White,
                        selectedLabelColor = EzcarNavy
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E8F0)),
                    shape = CircleShape,
                    modifier = Modifier.height(38.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text(localizedUiString("All Vehicles")) },
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
            val isSelected = uiState.selectedUser != null
            Box {
                FilterChip(
                    selected = isSelected,
                    onClick = { expanded = true },
                    label = {
                        Text(
                            text = uiState.selectedUser?.name ?: localizedUiString("Employee"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) EzcarNavy else Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = if (isSelected) EzcarNavy else Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.White,
                        labelColor = Color.Gray,
                        selectedContainerColor = Color.White,
                        selectedLabelColor = EzcarNavy
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E8F0)),
                    shape = CircleShape,
                    modifier = Modifier.height(38.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text(localizedUiString("All Employees")) },
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
            val isSelected = uiState.selectedCategory != "All"
            Box {
                FilterChip(
                    selected = isSelected,
                    onClick = { expanded = true },
                    label = {
                        Text(
                            text = localizedUiString(if (uiState.selectedCategory == "All") "Category" else uiState.selectedCategory),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) EzcarNavy else Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = if (isSelected) EzcarNavy else Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.White,
                        labelColor = Color.Gray,
                        selectedContainerColor = Color.White,
                        selectedLabelColor = EzcarNavy
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E8F0)),
                    shape = CircleShape,
                    modifier = Modifier.height(38.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    val categories = listOf("All", "Vehicle", "Personal", "Employee", "Bills", "Marketing")
                    categories.forEach { cat ->
                        DropdownMenuItem(
                            text = { Text(localizedUiString(cat)) },
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
            val isSelected = uiState.selectedExpenseType != null
            Box {
                FilterChip(
                    selected = isSelected,
                    onClick = { expanded = true },
                    label = {
                        val text = when (uiState.selectedExpenseType) {
                            ExpenseCategoryType.HOLDING_COST -> "Holding Cost"
                            ExpenseCategoryType.IMPROVEMENT -> "Improvement"
                            ExpenseCategoryType.OPERATIONAL -> "Operational"
                            null -> "Expense Type"
                        }
                        Text(
                            text = localizedUiString(text),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) EzcarNavy else Color.Gray
                        )
                    },
                    trailingIcon = { Icon(Icons.Default.KeyboardArrowDown, null, tint = if (isSelected) EzcarNavy else Color.Gray, modifier = Modifier.size(16.dp)) },
                    colors = FilterChipDefaults.filterChipColors(
                        containerColor = Color.White,
                        labelColor = Color.Gray,
                        selectedContainerColor = Color.White,
                        selectedLabelColor = EzcarNavy
                    ),
                    border = BorderStroke(1.dp, Color(0xFFE2E8F0)),
                    shape = CircleShape,
                    modifier = Modifier.height(38.dp)
                )
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text(localizedUiString("All Types")) },
                        onClick = {
                            onExpenseTypeSelect(null)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedUiString("Holding Cost")) },
                        onClick = {
                            onExpenseTypeSelect(ExpenseCategoryType.HOLDING_COST)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedUiString("Improvement")) },
                        onClick = {
                            onExpenseTypeSelect(ExpenseCategoryType.IMPROVEMENT)
                            expanded = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedUiString("Operational")) },
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
    onExpenseClick: (Expense) -> Unit,
    userNamesById: Map<UUID, String>,
    header: @Composable () -> Unit = {}
) {
    val grouped = remember(expenses) {
        expenses.groupBy { getDateBucket(expenseDisplayDateTime(it)) }.toList()
    }
    val regionSettingsManager = rememberRegionSettingsManager()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding() + 8.dp,
            bottom = 100.dp
        )
    ) {
        item(key = "expense-header") {
            header()
        }

        if (expenses.isEmpty()) {
            item(key = "expense-empty") {
                ExpenseEmptyState()
            }
        }

        grouped.forEach { (bucket, list) ->
            item(key = "expense-bucket-$bucket") {
                val subtotal = remember(list) {
                    list.map { it.amount }.fold(java.math.BigDecimal.ZERO, java.math.BigDecimal::add)
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedUiString(bucket),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )
                    Text(
                        text = regionSettingsManager.formatCurrency(subtotal),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            itemsIndexed(
                items = list,
                key = { _, expense -> expense.id }
            ) { index, expense ->
                val userName = expense.userId?.let { userNamesById[it] }.orEmpty()
                val shape = when {
                    list.size == 1 -> RoundedCornerShape(16.dp)
                    index == 0 -> RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
                    index == list.lastIndex -> RoundedCornerShape(bottomStart = 16.dp, bottomEnd = 16.dp)
                    else -> RoundedCornerShape(0.dp)
                }
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = if (index == 0) 4.dp else 0.dp, bottom = if (index == list.lastIndex) 4.dp else 0.dp),
                    shape = shape,
                    color = Color.White,
                    shadowElevation = if (index == 0) 2.dp else 0.dp,
                    border = BorderStroke(1.dp, Color.Black.copy(alpha = 0.03f))
                ) {
                    Column {
                        ExpenseItemRow(
                            expense = expense,
                            userName = userName,
                            formattedAmount = regionSettingsManager.formatCurrency(expense.amount),
                            onClick = onExpenseClick
                        )
                        if (index < list.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                color = Color.Gray.copy(alpha = 0.12f),
                                thickness = 0.5.dp
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ExpenseItemRow(
    expense: Expense,
    userName: String,
    formattedAmount: String,
    onClick: (Expense) -> Unit
) {
    val subtitleDateFormat = remember { SimpleDateFormat("d MMM, h:mm a", Locale.getDefault()) }
    val displayDateTime = remember(expense.date, expense.createdAt) { expenseDisplayDateTime(expense) }
    val expenseTypeText = localizedUiString(getExpenseTypeLabel(expense.expenseType))

    val subtitle = remember(userName, displayDateTime, expenseTypeText) {
        "${if (userName.isNotEmpty()) "$userName • " else ""}${subtitleDateFormat.format(displayDateTime)} • $expenseTypeText"
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(expense) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Light Circle Icon
        Box(
            modifier = Modifier
                .size(38.dp)
                .background(getCategoryColor(expense.category).copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = getCategoryIcon(expense.category),
                contentDescription = null,
                tint = getCategoryColor(expense.category),
                modifier = Modifier.size(18.dp)
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = expense.expenseDescription ?: expense.category,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                fontWeight = FontWeight.Bold,
                color = Color.Black,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp),
                color = Color.Gray,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = formattedAmount,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                fontWeight = FontWeight.SemiBold,
                color = Color.Black
            )
            Spacer(modifier = Modifier.height(4.dp))
            Box(
                modifier = Modifier
                    .background(getCategoryColor(expense.category).copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            ) {
                Text(
                    text = localizedUiString(expense.category),
                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                    color = getCategoryColor(expense.category),
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun ExpenseEmptyState() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 96.dp),
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
                text = localizedUiString("No expenses found"),
                style = MaterialTheme.typography.titleMedium,
                color = Color.Gray
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = localizedUiString("Add your first expense to start tracking spending."),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray.copy(alpha = 0.72f)
            )
        }
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
