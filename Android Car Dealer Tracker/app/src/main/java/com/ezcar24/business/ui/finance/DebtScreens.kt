package com.ezcar24.business.ui.finance

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Debt
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarDanger
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale
import androidx.compose.material.icons.filled.Phone
import androidx.compose.ui.unit.sp
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebtListScreen(
    onBack: () -> Unit,
    viewModel: DebtViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var showPaymentDialog by remember { mutableStateOf<Debt?>(null) }
    
    if (uiState.selectedDebt != null) {
        DebtDetailScreen(
            debt = uiState.selectedDebt!!,
            payments = uiState.debtPayments,
            onBack = { viewModel.clearSelection() },
            onPay = { showPaymentDialog = uiState.selectedDebt!! },
            onDelete = { 
                viewModel.deleteDebt(uiState.selectedDebt!!.id) 
                viewModel.clearSelection()
            }
        )
        // Show Payment Dialog ON TOP of Detail Screen if needed
        if (showPaymentDialog != null) {
             PaymentDialog(
                debt = showPaymentDialog!!,
                accounts = uiState.accounts,
                onDismiss = { showPaymentDialog = null },
                onConfirm = { amount, accountId ->
                    viewModel.recordPayment(showPaymentDialog!!.id, amount, accountId)
                    showPaymentDialog = null
                }
            )
        }
        return
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Debts", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = "Add", tint = EzcarBlueBright)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White)
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            DebtsContent(
                viewModel = viewModel,
                showAddDialog = showAddDialog,
                onAddDialogDismiss = { showAddDialog = false },
                onAddClick = { showAddDialog = true }
            )
        }
    }
}

@Composable
fun DebtsContent(
    viewModel: DebtViewModel = hiltViewModel(),
    showAddDialog: Boolean = false,
    onAddDialogDismiss: () -> Unit = {},
    onAddClick: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    // Local state for dialogs that are internal to the content
    // We lift showAddDialog to caller if we want the caller's Add button to trigger it?
    // Actually, distinct screens might have different Add buttons.
    // In DebtListScreen, Add is in TopBar.
    // In SalesScreen, Add Sale is in TopBar. 
    // If I switch to Debts tab in SalesScreen, does the Title change to "Debts"?
    // The SalesScreen TopBar has "Add Sale" icon.
    // If I am in Debt tab, maybe I should show "Add Debt"?
    // For now, let's keep internal state but allow external trigger if needed.
    
    // We need to sync the external 'showAddDialog' with internal or just pass it in.
    // Let's use a MutableState if we want internal control, but here we passed it.
    // But wait, if SalesScreen has its own Add button, how does it signal this?
    // SalesScreen has "Add Circle".
    // I will expose `openAddDialog` functionality?
    // Or just put the add button inside the content (FAB)?
    // DebtListScreen used TopBar action. 
    // SalesScreen TopBar is common.
    // Let's make DebtsContent handle the DIALOGS logic.
    
    var internalAddDialog by remember { mutableStateOf(false) }
    // If external `showAddDialog` is true, we show it? 
    // It's cleaner to let DebtsContent manage its own dialogs, and expose a "trigger" mechanism?
    // Or simply: DebtsContent doesn't need to know about the TopBar button, 
    // BUT the user needs to be able to click Add.
    // In SalesScreen, the Add button creates a Sale.
    // Should it create a Debt if in Debt tab?
    // Getting complicated.
    
    // Simplest: Add a FAB inside DebtsContent for "Add Debt", independent of TopBar.
    // Or reuse the params.
    
    var isAddDialogOpen by remember { mutableStateOf(showAddDialog) }
    // Sync external trigger
    LaunchedEffect(showAddDialog) {
        if (showAddDialog) isAddDialogOpen = true
    }

    var showPaymentDialog by remember { mutableStateOf<Debt?>(null) }
    var editingDebt by remember { mutableStateOf<Debt?>(null) }

    if (isAddDialogOpen || editingDebt != null) {
        DebtDialog(
            debt = editingDebt,
            onDismiss = { 
                isAddDialogOpen = false
                onAddDialogDismiss()
                editingDebt = null
            },
            onSave = { name, phone, amount, direction, notes ->
                viewModel.saveDebt(editingDebt?.id?.toString(), name, phone, amount, direction, notes)
                isAddDialogOpen = false
                onAddDialogDismiss()
                editingDebt = null
            }
        )
    }

    if (showPaymentDialog != null) {
        PaymentDialog(
            debt = showPaymentDialog!!,
            accounts = uiState.accounts,
            onDismiss = { showPaymentDialog = null },
            onConfirm = { amount, accountId ->
                viewModel.recordPayment(showPaymentDialog!!.id, amount, accountId)
                showPaymentDialog = null
            }
        )
    }

    Column {
        // Tabs
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surface),
            verticalAlignment = Alignment.CenterVertically
        ) {
           TabButton(
               text = "Owed to Me",
               selected = uiState.selectedTab == "owed_to_me",
               onClick = { viewModel.setTab("owed_to_me") },
               modifier = Modifier.weight(1f)
           )
           TabButton(
               text = "I Owe",
               selected = uiState.selectedTab == "owed_by_me",
               onClick = { viewModel.setTab("owed_by_me") },
               modifier = Modifier.weight(1f)
           )
        }

        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(uiState.filteredDebts) { debt ->
                DebtItem(
                    debt = debt,
                    onClick = { editingDebt = debt },
                    onPayClick = { showPaymentDialog = debt },
                    onDelete = { viewModel.deleteDebt(debt.id) }
                )
            }
        }
    }
}

@Composable
fun TabButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .padding(2.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal
        )
    }
}

@Composable
fun DebtItem(
    debt: Debt,
    onClick: () -> Unit,
    onPayClick: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = debt.counterpartyName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    if (!debt.notes.isNullOrEmpty()) {
                        Text(
                            text = debt.notes,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray,
                            maxLines = 1
                        )
                    }
                }
                Text(
                    text = NumberFormat.getCurrencyInstance(Locale.US).format(debt.amount).replace("$", "AED "),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (debt.direction == "owed_to_me") EzcarGreen else EzcarDanger
                )
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(modifier = Modifier.height(8.dp))
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onDelete) {
                    Text("Delete", color = Color.Gray)
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = onPayClick,
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text("Record Payment")
                }
            }
        }
    }
}

@Composable
fun DebtDialog(
    debt: Debt?,
    onDismiss: () -> Unit,
    onSave: (String, String, BigDecimal, String, String) -> Unit
) {
    var name by remember { mutableStateOf(debt?.counterpartyName ?: "") }
    var phone by remember { mutableStateOf(debt?.counterpartyPhone ?: "") }
    var amount by remember { mutableStateOf(debt?.amount?.toPlainString() ?: "") }
    var direction by remember { mutableStateOf(debt?.direction ?: "owed_to_me") }
    var notes by remember { mutableStateOf(debt?.notes ?: "") }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(
                modifier = Modifier
                    .padding(24.dp)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = if (debt == null) "New Debt" else "Edit Debt",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Bold
                )

                // Direction Toggle
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    TabButton(
                        text = "They Owe Me",
                        selected = direction == "owed_to_me",
                        onClick = { direction = "owed_to_me" },
                        modifier = Modifier.weight(1f)
                    )
                    TabButton(
                        text = "I Owe Them",
                        selected = direction == "owed_by_me",
                        onClick = { direction = "owed_by_me" },
                        modifier = Modifier.weight(1f)
                    )
                }

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it },
                    label = { Text("Amount") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (Optional)") },
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = Color.Gray)
                    }
                    Button(
                        onClick = {
                            val bal = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
                            onSave(name, phone, bal, direction, notes)
                        },
                        enabled = name.isNotBlank() && amount.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text("Save")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebtDetailScreen(
    debt: Debt,
    payments: List<com.ezcar24.business.data.local.DebtPayment>,
    onBack: () -> Unit,
    onPay: () -> Unit,
    onDelete: () -> Unit
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(debt.counterpartyName, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Default.Delete, contentDescription = "Delete", tint = EzcarDanger)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
             // Main Info Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = Color.White),
                shape = RoundedCornerShape(16.dp),
                elevation = CardDefaults.cardElevation(2.dp)
            ) {
                Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = if (debt.direction == "owed_to_me") "OWES YOU" else "YOU OWE",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.Gray,
                            letterSpacing = 1.1.sp
                        )
                        if (debt.dueDate != null) {
                            Text(
                                "Due: ${java.text.SimpleDateFormat("MMM dd", Locale.getDefault()).format(debt.dueDate)}",
                                style = MaterialTheme.typography.labelSmall,
                                color = EzcarDanger
                            )
                        }
                    }
                    Text(
                        text = NumberFormat.getCurrencyInstance(Locale.US).format(debt.amount).replace("$", "AED "),
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Bold,
                        color = if (debt.direction == "owed_to_me") EzcarGreen else EzcarDanger
                    )
                    
                    if (!debt.counterpartyPhone.isNullOrBlank()) {
                         Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(16.dp), tint = Color.Gray)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(debt.counterpartyPhone, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    
                     if (!debt.notes.isNullOrBlank()) {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp), color = Color.Gray.copy(alpha=0.1f))
                        Text(debt.notes, style = MaterialTheme.typography.bodyMedium, color = Color.Gray)
                    }
                }
            }

            // Action Button
            Button(
                onClick = onPay,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(if (debt.direction == "owed_to_me") "Record Payment Received" else "Record Payment Sent")
            }

            Text(
                text = "HISTORY",
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray,
                modifier = Modifier.padding(start = 4.dp, top = 8.dp)
            )

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f)
            ) {
                 if (payments.isEmpty()) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                            Text("No payment history", color = Color.Gray)
                        }
                    }
                }
                items(payments) { payment ->
                    PaymentItem(payment)
                }
            }
        }
    }
}



@Composable
fun PaymentItem(payment: com.ezcar24.business.data.local.DebtPayment) {
     Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(0.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Payment",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = java.text.SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(payment.date),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
            Text(
                text = NumberFormat.getCurrencyInstance(Locale.US).format(payment.amount).replace("$", "AED "),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentDialog(
    debt: Debt,
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onConfirm: (BigDecimal, UUID) -> Unit
) {
    var amount by remember { mutableStateOf("") } // Default to empty, user enters amount
    var selectedAccountId by remember { mutableStateOf<UUID?>(null) }
    var expanded by remember { mutableStateOf(false) }

    // Auto-select first account if available
    LaunchedEffect(accounts) {
        if (accounts.isNotEmpty() && selectedAccountId == null) {
            selectedAccountId = accounts.first().id
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
        ) {
            Column(
                modifier = Modifier
                    .padding(24.dp)
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "Record Payment",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Recording payment for ${debt.counterpartyName}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.Gray
                )

                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it },
                    label = { Text("Payment Amount") },
                    placeholder = { Text("Max: ${debt.amount}") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                // Account Selection Dropdown
                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = !expanded },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    val selectedAccount = accounts.find { it.id == selectedAccountId }
                    OutlinedTextField(
                        value = selectedAccount?.accountType ?: "Select Account",
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                        modifier = Modifier.menuAnchor().fillMaxWidth()
                    )
                    ExposedDropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        accounts.forEach { account ->
                            DropdownMenuItem(
                                text = { Text("${account.accountType} (${NumberFormat.getCurrencyInstance(Locale.US).format(account.balance)})") },
                                onClick = {
                                    selectedAccountId = account.id
                                    expanded = false
                                }
                            )
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = Color.Gray)
                    }
                    Button(
                        onClick = {
                            val payAmount = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
                            if (selectedAccountId != null) {
                                onConfirm(payAmount, selectedAccountId!!)
                            }
                        },
                        enabled = amount.isNotBlank() && selectedAccountId != null,
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text("Confirm")
                    }
                }
            }
        }
    }
}
