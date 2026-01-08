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
import com.ezcar24.business.ui.theme.*
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun ExpenseScreen(
    viewModel: ExpenseViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showAddSheet by remember { mutableStateOf(false) }
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
            Column {
                ExpenseHeader(
                    totalAmount = uiState.totalAmount,
                    dateFilter = uiState.dateFilter
                )
                ExpenseFilters(
                    uiState = uiState,
                    onDateFilterSelect = viewModel::setDateFilter,
                    onCategorySelect = viewModel::setCategoryFilter,
                    onVehicleSelect = viewModel::setVehicleFilter
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
            onSave = { amount, date, desc, cat, veh, usr, acc ->
                viewModel.saveExpense(amount, date, desc, cat, veh, usr, acc)
                showAddSheet = false
            },
            vehicles = uiState.vehicles,
            users = uiState.users,
            accounts = uiState.accounts
        )
    }
}

@Composable
fun ExpenseHeader(
    totalAmount: java.math.BigDecimal,
    dateFilter: DateFilter
) {
    val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
    val displayAmount = currencyFormat.format(totalAmount).replace("$", "AED ")

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
                style = MaterialTheme.typography.displaySmall, // Large Title 
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            
            // Search Icon & others could go here, or remain in a separate toolbar row if needed. 
            // For now, sticking to the visual header.
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
                style = MaterialTheme.typography.displayMedium, // Approx 34sp
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            
            // Placeholder for percentage badge if we had data for it
            // Spacer(modifier = Modifier.width(12.dp))
            // Badge(text = "↘ 74%", color = EzcarSuccess.copy(alpha = 0.2f), textColor = EzcarSuccess)
        }
    }
}

@Composable
fun ExpenseFilters(
    uiState: ExpenseUiState,
    onDateFilterSelect: (DateFilter) -> Unit,
    onCategorySelect: (String) -> Unit,
    onVehicleSelect: (com.ezcar24.business.data.local.Vehicle?) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.background(MaterialTheme.colorScheme.background)
    ) {
         // Vehicle Dropdown Chip
        item {
            FilterChip(
                selected = uiState.selectedVehicle != null,
                onClick = { /* TODO: Open Vehicle Selection Sheet */ },
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
        }

        // Employee Dropdown Chip
        item {
             FilterChip(
                selected = uiState.selectedUser != null,
                onClick = { /* TODO: Open User Selection */ },
                label = { 
                    Text(
                        text = "Employee",
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
        }

        // Category Dropdown Chip
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
        
        // Date Filters as pills at the end or separate? 
        // iOS screenshot shows dropdowns. 
        // We'll keep date filter as standard chips for now or integreate into "This Week" header logic likely.
        // For parity with screenshot, these look like general property filters.
    }
}

@Composable
fun ExpenseList(
    expenses: List<Expense>,
    padding: PaddingValues,
    onDelete: (Expense) -> Unit
) {
    // Group by Date Bucket (Today, Yesterday, etc.)
    val grouped = expenses.groupBy { getDateBucket(it.date) }
    
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            top = padding.calculateTopPadding() + 8.dp,
            bottom = 80.dp // Space for Nav
        )
    ) {
        grouped.forEach { (bucket, list) ->
            item {
                Text(
                    text = bucket,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = Color.Gray,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
            
            items(list, key = { it.id }) { expense ->
                ExpenseRowItem(expense, onDelete)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseRowItem(expense: Expense, onDelete: (Expense) -> Unit) {
    val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
    val dateFormat = SimpleDateFormat("h:mm a", Locale.getDefault())
    val fullDateFormat = SimpleDateFormat("dd MMM, h:mm a", Locale.getDefault())

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = {
            if (it == SwipeToDismissBoxValue.EndToStart) {
                onDelete(expense)
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
                    .padding(horizontal = 20.dp, vertical = 4.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(color)
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.White)
            }
        },
        content = {
            // iOS Style Item
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 4.dp),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Row(
                    modifier = Modifier
                        .padding(16.dp)
                        .fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Icon Circle
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(Color(0xFFF2F4F8)), // Light Gray
                        contentAlignment = Alignment.Center
                    ) {
                        val icon = when (expense.category?.lowercase()) {
                            "vehicle" -> Icons.Default.DirectionsCar
                            "personal" -> Icons.Default.Person
                            "marketing" -> Icons.Default.Campaign
                            "bills" -> Icons.Default.Receipt
                            "office" -> Icons.Default.Business
                            else -> Icons.Default.ShoppingBag
                        }
                        // Use EzcarNavy or specific colors per category
                        val tint = EzcarNavy
                        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
                    }
                    
                    Spacer(modifier = Modifier.width(16.dp))
                    
                    // Main Content
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = expense.category?.replaceFirstChar { it.titlecase() } ?: "Expense",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Bold
                        )
                        
                        val subtitle = if (!expense.expenseDescription.isNullOrBlank()) {
                            expense.expenseDescription
                        } else {
                            // Fallback to Entity/Date
                             fullDateFormat.format(expense.date)
                        }
                        
                        Text(
                            text = subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray,
                            maxLines = 1
                        )
                         
                         // Date line if description is present, similar to iOS user/date line
                        if (!expense.expenseDescription.isNullOrBlank()) {
                             Text(
                                text = fullDateFormat.format(expense.date),
                                style = MaterialTheme.typography.labelSmall,
                                color = Color.Gray.copy(alpha=0.6f)
                            )
                        }
                    }
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    // Right Side: Amount & Badge
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = currencyFormat.format(expense.amount).replace("$", "AED "),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                        
                        Spacer(modifier = Modifier.height(4.dp))
                        
                        // Badge
                        val categoryLower = expense.category?.lowercase() ?: "general"
                        val (badgeText, badgeColor) = when (categoryLower) {
                            "vehicle" -> "Vehicle" to EzcarBlueBright
                            "personal" -> "Personal" to EzcarOrange
                            else -> categoryLower.replaceFirstChar{it.titlecase()} to Color.Gray
                        }
                        
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = badgeColor.copy(alpha = 0.1f) // Light BG handled by surface? Or manual
                        ) {
                             // Actually better to use a simple Box or styling on Text
                             // Reuse simple badge logic
                             Text(
                                 text = badgeText,
                                 style = MaterialTheme.typography.labelSmall, // Tiny font
                                 color = Color.White,
                                 modifier = Modifier
                                    .background(badgeColor, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                             )
                        }
                    }
                }
            }
        }
    )
}


fun getDateBucket(date: Date): String {
    val now = System.currentTimeMillis()
    val diff = now - date.time
    val dayMillis = 86400000L
    return when {
        diff < dayMillis -> "Today"
        diff < 2 * dayMillis -> "Yesterday"
        diff < 7 * dayMillis -> "Last 7 Days"
        diff < 30 * dayMillis -> "Last 30 Days"
        else -> "Older"
    }
}

fun getCategoryIcon(category: String): ImageVector {
    return when (category.lowercase()) {
        "vehicle" -> Icons.Default.DirectionsCar
        "personal" -> Icons.Default.Person
        "employee" -> Icons.Default.Work
        "office" -> Icons.Default.Business
        "marketing" -> Icons.Default.Campaign
        else -> Icons.Default.Receipt
    }
}
