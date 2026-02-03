package com.ezcar24.business.ui.parts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.util.toBigDecimalOrZero
import java.math.BigDecimal
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PartsDashboardScreen(
    inventoryViewModel: PartsInventoryViewModel = hiltViewModel(),
    salesViewModel: PartSalesViewModel = hiltViewModel()
) {
    val inventoryState by inventoryViewModel.uiState.collectAsState()
    val salesState by salesViewModel.uiState.collectAsState()
    var selectedTab by remember { mutableStateOf(0) }
    var showAddPartDialog by remember { mutableStateOf(false) }
    var showReceiveStockDialog by remember { mutableStateOf(false) }
    var showAddSaleDialog by remember { mutableStateOf(false) }

    val currencyFormatter = remember { NumberFormat.getCurrencyInstance(Locale.US) }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            Column(modifier = Modifier.background(EzcarBackground)) {
                Text(
                    text = "Parts",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                )
                OutlinedTextField(
                    value = if (selectedTab == 0) inventoryState.searchQuery else salesState.searchQuery,
                    onValueChange = {
                        if (selectedTab == 0) {
                            inventoryViewModel.onSearchQueryChanged(it)
                        } else {
                            salesViewModel.onSearchQueryChanged(it)
                        }
                    },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    placeholder = { Text(if (selectedTab == 0) "Search parts" else "Search sales") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp)
                )
                TabRow(selectedTabIndex = selectedTab) {
                    Tab(
                        text = { Text("Inventory") },
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 }
                    )
                    Tab(
                        text = { Text("Sales") },
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 }
                    )
                }
            }
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    if (selectedTab == 0) {
                        showAddPartDialog = true
                    } else {
                        showAddSaleDialog = true
                    }
                },
                containerColor = EzcarNavy,
                contentColor = Color.White
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add")
            }
        }
    ) { padding ->
        if (selectedTab == 0) {
            PartsInventoryContent(
                modifier = Modifier.padding(padding),
                state = inventoryState,
                currencyFormatter = currencyFormatter,
                onToggleLowStock = { inventoryViewModel.toggleLowStockOnly(it) },
                onCategorySelected = { inventoryViewModel.setCategory(it) },
                onReceiveStock = { showReceiveStockDialog = true }
            )
        } else {
            PartsSalesContent(
                modifier = Modifier.padding(padding),
                state = salesState,
                currencyFormatter = currencyFormatter,
                onDeleteSale = { salesViewModel.deleteSale(it.sale) }
            )
        }
    }

    if (showAddPartDialog) {
        AddPartDialog(
            accounts = inventoryState.accounts,
            onDismiss = { showAddPartDialog = false },
            onSave = { name, code, category, notes, addInitialStock, quantity, unitCost, batchLabel, accountId ->
                inventoryViewModel.addPart(
                    name = name,
                    code = code,
                    category = category,
                    notes = notes,
                    addInitialStock = addInitialStock,
                    initialQuantity = quantity,
                    unitCost = unitCost,
                    batchLabel = batchLabel,
                    selectedAccountId = accountId
                )
                showAddPartDialog = false
            }
        )
    }

    if (showReceiveStockDialog) {
        ReceiveStockDialog(
            parts = inventoryState.parts.map { it.part },
            accounts = inventoryState.accounts,
            onDismiss = { showReceiveStockDialog = false },
            onSave = { partId, quantity, unitCost, batchLabel, notes, purchaseDate, accountId ->
                inventoryViewModel.receiveStock(
                    partId = partId,
                    quantity = quantity,
                    unitCost = unitCost,
                    batchLabel = batchLabel,
                    notes = notes,
                    purchaseDate = purchaseDate,
                    selectedAccountId = accountId
                )
                showReceiveStockDialog = false
            }
        )
    }

    if (showAddSaleDialog) {
        AddPartSaleDialog(
            parts = salesState.parts,
            accounts = salesState.accounts,
            clients = salesState.clients,
            onDismiss = { showAddSaleDialog = false },
            onSave = { saleDate, accountId, lines, buyerName, buyerPhone, paymentMethod, notes, clientId ->
                val success = salesViewModel.createSale(
                    saleDate = saleDate,
                    selectedAccountId = accountId,
                    lineItems = lines,
                    buyerName = buyerName,
                    buyerPhone = buyerPhone,
                    paymentMethod = paymentMethod,
                    notes = notes,
                    selectedClientId = clientId
                )
                if (success) {
                    showAddSaleDialog = false
                }
            }
        )
    }
}

@Composable
private fun PartsInventoryContent(
    modifier: Modifier = Modifier,
    state: PartsInventoryUiState,
    currencyFormatter: NumberFormat,
    onToggleLowStock: (Boolean) -> Unit,
    onCategorySelected: (String?) -> Unit,
    onReceiveStock: () -> Unit
) {
    val totalValue = state.parts.fold(BigDecimal.ZERO) { total, item -> total + item.inventoryValue }
    val lowStockCount = state.parts.count { it.quantityOnHand <= BigDecimal("2") }

    Column(modifier = modifier.fillMaxSize()) {
        Card(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = EzcarBackgroundLight)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Inventory Overview", fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column {
                        Text("Total Value", style = MaterialTheme.typography.labelMedium)
                        Text(currencyFormatter.format(totalValue), fontWeight = FontWeight.Bold)
                    }
                    Column {
                        Text("Parts", style = MaterialTheme.typography.labelMedium)
                        Text(state.parts.size.toString(), fontWeight = FontWeight.Bold)
                    }
                    Column {
                        Text("Low Stock", style = MaterialTheme.typography.labelMedium)
                        Text(lowStockCount.toString(), fontWeight = FontWeight.Bold, color = EzcarBlueBright)
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            CategoryFilter(
                categories = state.categories,
                selectedCategory = state.selectedCategory,
                onSelected = onCategorySelected
            )
            LowStockToggle(
                enabled = state.showLowStockOnly,
                onToggle = onToggleLowStock
            )
        }

        Divider(modifier = Modifier.padding(vertical = 8.dp))

        LazyColumn(
            contentPadding = PaddingValues(bottom = 96.dp),
            modifier = Modifier.fillMaxSize()
        ) {
            items(state.filteredParts) { item ->
                PartRow(item = item, currencyFormatter = currencyFormatter)
            }
        }

        Button(
            onClick = onReceiveStock,
            modifier = Modifier
                .align(Alignment.End)
                .padding(16.dp)
        ) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Receive Stock")
        }
    }
}

@Composable
private fun PartsSalesContent(
    modifier: Modifier = Modifier,
    state: PartSalesUiState,
    currencyFormatter: NumberFormat,
    onDeleteSale: (PartSaleItemSummary) -> Unit
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        modifier = modifier.fillMaxSize()
    ) {
        items(state.filteredSales.ifEmpty { state.sales }) { item ->
            PartSaleRow(item = item, currencyFormatter = currencyFormatter, onDelete = { onDeleteSale(item) })
        }
    }
}

@Composable
private fun PartRow(item: PartInventoryItem, currencyFormatter: NumberFormat) {
    Card(
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(item.part.name, fontWeight = FontWeight.Bold)
            if (!item.part.category.isNullOrBlank()) {
                Text(item.part.category ?: "", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("On Hand: ${item.quantityOnHand.stripTrailingZeros().toPlainString()}")
                Text(currencyFormatter.format(item.inventoryValue))
            }
        }
    }
}

@Composable
private fun PartSaleRow(
    item: PartSaleItemSummary,
    currencyFormatter: NumberFormat,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier
            .padding(vertical = 6.dp)
            .fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(item.buyerName, fontWeight = FontWeight.Bold)
                Text(currencyFormatter.format(item.totalAmount), fontWeight = FontWeight.Bold)
            }
            if (item.itemsSummary.isNotEmpty()) {
                Text(item.itemsSummary, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
            Spacer(modifier = Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(item.saleDate))
                TextButton(onClick = onDelete) { Text("Delete") }
            }
        }
    }
}

@Composable
private fun CategoryFilter(
    categories: List<String>,
    selectedCategory: String?,
    onSelected: (String?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Text(
            text = selectedCategory ?: "All Categories",
            modifier = Modifier
                .clip(RoundedCornerShape(20.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(horizontal = 12.dp, vertical = 8.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("All Categories") }, onClick = {
                onSelected(null)
                expanded = false
            })
            categories.forEach { category ->
                DropdownMenuItem(text = { Text(category) }, onClick = {
                    onSelected(category)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun LowStockToggle(enabled: Boolean, onToggle: (Boolean) -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (enabled) EzcarBlueBright else EzcarBackgroundLight)
            .clickable { onToggle(!enabled) }
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Text(
            text = "Low Stock",
            color = if (enabled) Color.White else Color.Black
        )
    }
}

@Composable
private fun AddPartDialog(
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onSave: (
        name: String,
        code: String?,
        category: String?,
        notes: String?,
        addInitialStock: Boolean,
        quantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        accountId: UUID?
    ) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var addInitialStock by remember { mutableStateOf(false) }
    var quantity by remember { mutableStateOf("") }
    var unitCost by remember { mutableStateOf("") }
    var batchLabel by remember { mutableStateOf("") }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Part") },
        text = {
            Column {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") })
                OutlinedTextField(value = code, onValueChange = { code = it }, label = { Text("Code") })
                OutlinedTextField(value = category, onValueChange = { category = it }, label = { Text("Category") })
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text("Notes") })
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Initial Stock")
                    Spacer(modifier = Modifier.width(12.dp))
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (addInitialStock) EzcarGreen else EzcarBackgroundLight)
                            .clickable { addInitialStock = !addInitialStock }
                            .padding(horizontal = 12.dp, vertical = 6.dp)
                    ) {
                        Text(if (addInitialStock) "On" else "Off", color = if (addInitialStock) Color.White else Color.Black)
                    }
                }
                if (addInitialStock) {
                    OutlinedTextField(
                        value = quantity,
                        onValueChange = { quantity = it },
                        label = { Text("Quantity") },
                        keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                    )
                    OutlinedTextField(
                        value = unitCost,
                        onValueChange = { unitCost = it },
                        label = { Text("Unit Cost") },
                        keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                    )
                    OutlinedTextField(value = batchLabel, onValueChange = { batchLabel = it }, label = { Text("Batch Label") })
                    AccountDropdown(
                        accounts = accounts,
                        selectedAccountId = selectedAccountId,
                        onSelected = { selectedAccountId = it }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onSave(
                    name,
                    code.ifBlank { null },
                    category.ifBlank { null },
                    notes.ifBlank { null },
                    addInitialStock,
                    quantity.toBigDecimalOrZero(),
                    unitCost.toBigDecimalOrZero(),
                    batchLabel.ifBlank { null },
                    selectedAccountId
                )
            }) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun ReceiveStockDialog(
    parts: List<Part>,
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onSave: (
        partId: UUID,
        quantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        notes: String?,
        purchaseDate: Date,
        accountId: UUID?
    ) -> Unit
) {
    var selectedPartId by remember { mutableStateOf<UUID?>(parts.firstOrNull()?.id) }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }
    var quantity by remember { mutableStateOf("") }
    var unitCost by remember { mutableStateOf("") }
    var batchLabel by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var purchaseDate by remember { mutableStateOf(Date()) }
    var showDatePicker by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Receive Stock") },
        text = {
            Column {
                PartDropdown(parts = parts, selectedPartId = selectedPartId, onSelected = { selectedPartId = it })
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = { Text("Quantity") },
                    keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(
                    value = unitCost,
                    onValueChange = { unitCost = it },
                    label = { Text("Unit Cost") },
                    keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(value = batchLabel, onValueChange = { batchLabel = it }, label = { Text("Batch Label") })
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text("Notes") })
                Text(
                    text = "Purchase Date: ${SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(purchaseDate)}",
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clickable { showDatePicker = true }
                )
                AccountDropdown(
                    accounts = accounts,
                    selectedAccountId = selectedAccountId,
                    onSelected = { selectedAccountId = it }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val partId = selectedPartId ?: return@TextButton
                onSave(
                    partId,
                    quantity.toBigDecimalOrZero(),
                    unitCost.toBigDecimalOrZero(),
                    batchLabel.ifBlank { null },
                    notes.ifBlank { null },
                    purchaseDate,
                    selectedAccountId
                )
            }) {
                Text("Save")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )

    if (showDatePicker) {
        SimpleDatePickerDialog(
            onDismiss = { showDatePicker = false },
            onDateSelected = {
                purchaseDate = it
                showDatePicker = false
            }
        )
    }
}

@Composable
private fun AddPartSaleDialog(
    parts: List<Part>,
    accounts: List<FinancialAccount>,
    clients: List<Client>,
    onDismiss: () -> Unit,
    onSave: (
        saleDate: Date,
        accountId: UUID,
        lines: List<PartSaleLineDraft>,
        buyerName: String?,
        buyerPhone: String?,
        paymentMethod: String?,
        notes: String?,
        clientId: UUID?
    ) -> Unit
) {
    var saleDate by remember { mutableStateOf(Date()) }
    var showDatePicker by remember { mutableStateOf(false) }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }
    var buyerName by remember { mutableStateOf("") }
    var buyerPhone by remember { mutableStateOf("") }
    var paymentMethod by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var selectedClientId by remember { mutableStateOf<UUID?>(null) }
    var lineItems by remember { mutableStateOf(listOf<PartSaleLineDraft>()) }
    var showLineDialog by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Sale") },
        text = {
            Column {
                Text(
                    text = "Sale Date: ${SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(saleDate)}",
                    modifier = Modifier
                        .padding(bottom = 8.dp)
                        .clickable { showDatePicker = true }
                )
                AccountDropdown(
                    accounts = accounts,
                    selectedAccountId = selectedAccountId,
                    onSelected = { selectedAccountId = it }
                )
                ClientDropdown(
                    clients = clients,
                    selectedClientId = selectedClientId,
                    onSelected = { selectedClientId = it }
                )
                OutlinedTextField(value = buyerName, onValueChange = { buyerName = it }, label = { Text("Buyer Name") })
                OutlinedTextField(value = buyerPhone, onValueChange = { buyerPhone = it }, label = { Text("Buyer Phone") })
                OutlinedTextField(value = paymentMethod, onValueChange = { paymentMethod = it }, label = { Text("Payment Method") })
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text("Notes") })
                Spacer(modifier = Modifier.height(8.dp))
                Text("Line Items", fontWeight = FontWeight.Bold)
                lineItems.forEach { line ->
                    val partName = parts.firstOrNull { it.id == line.partId }?.name ?: "Part"
                    Text("${partName}: ${line.quantity} x ${line.unitPrice}")
                }
                TextButton(onClick = { showLineDialog = true }) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Add Line Item")
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val accountId = selectedAccountId ?: return@TextButton
                onSave(
                    saleDate,
                    accountId,
                    lineItems,
                    buyerName.ifBlank { null },
                    buyerPhone.ifBlank { null },
                    paymentMethod.ifBlank { null },
                    notes.ifBlank { null },
                    selectedClientId
                )
            }) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )

    if (showLineDialog) {
        AddLineItemDialog(
            parts = parts,
            onDismiss = { showLineDialog = false },
            onSave = { partId, quantity, unitPrice ->
                lineItems = lineItems + PartSaleLineDraft(partId, quantity, unitPrice)
                showLineDialog = false
            }
        )
    }

    if (showDatePicker) {
        SimpleDatePickerDialog(
            onDismiss = { showDatePicker = false },
            onDateSelected = {
                saleDate = it
                showDatePicker = false
            }
        )
    }
}

@Composable
private fun AddLineItemDialog(
    parts: List<Part>,
    onDismiss: () -> Unit,
    onSave: (partId: UUID, quantity: BigDecimal, unitPrice: BigDecimal) -> Unit
) {
    var selectedPartId by remember { mutableStateOf<UUID?>(parts.firstOrNull()?.id) }
    var quantity by remember { mutableStateOf("") }
    var unitPrice by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Line Item") },
        text = {
            Column {
                PartDropdown(parts = parts, selectedPartId = selectedPartId, onSelected = { selectedPartId = it })
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = { Text("Quantity") },
                    keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(
                    value = unitPrice,
                    onValueChange = { unitPrice = it },
                    label = { Text("Unit Price") },
                    keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val partId = selectedPartId ?: return@TextButton
                onSave(partId, quantity.toBigDecimalOrZero(), unitPrice.toBigDecimalOrZero())
            }) {
                Text("Add")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun PartDropdown(
    parts: List<Part>,
    selectedPartId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = parts.firstOrNull { it.id == selectedPartId }?.name ?: "Select Part"
    Box {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            parts.forEach { part ->
                DropdownMenuItem(text = { Text(part.name) }, onClick = {
                    onSelected(part.id)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun AccountDropdown(
    accounts: List<FinancialAccount>,
    selectedAccountId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = accounts.firstOrNull { it.id == selectedAccountId }?.accountType ?: "Select Account"
    Box(modifier = Modifier.padding(top = 8.dp)) {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            accounts.forEach { account ->
                DropdownMenuItem(text = { Text(account.accountType) }, onClick = {
                    onSelected(account.id)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun ClientDropdown(
    clients: List<Client>,
    selectedClientId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = clients.firstOrNull { it.id == selectedClientId }?.name ?: "Select Client"
    Box(modifier = Modifier.padding(top = 8.dp)) {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("None") }, onClick = {
                onSelected(null)
                expanded = false
            })
            clients.forEach { client ->
                DropdownMenuItem(text = { Text(client.name) }, onClick = {
                    onSelected(client.id)
                    expanded = false
                })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SimpleDatePickerDialog(
    onDismiss: () -> Unit,
    onDateSelected: (Date) -> Unit
) {
    val datePickerState = androidx.compose.material3.rememberDatePickerState()
    androidx.compose.material3.DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    datePickerState.selectedDateMillis?.let {
                        onDateSelected(Date(it))
                    }
                }
            ) {
                Text("OK")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    ) {
        androidx.compose.material3.DatePicker(state = datePickerState)
    }
}
