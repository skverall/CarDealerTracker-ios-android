package com.ezcar24.business.ui.finance

import android.app.DatePickerDialog
import android.app.TimePickerDialog
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
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Debt
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebtListScreen(
    onBack: () -> Unit,
    canDeleteRecords: Boolean = true,
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
            canDelete = canDeleteRecords,
            onDeletePayment = { payment ->
                if (canDeleteRecords) {
                    viewModel.deletePayment(payment)
                }
            },
            onDelete = { 
                if (canDeleteRecords) {
                    viewModel.deleteDebt(uiState.selectedDebt!!.id)
                    viewModel.clearSelection()
                }
            }
        )
        if (showPaymentDialog != null) {
             PaymentDialog(
                debt = showPaymentDialog!!,
                accounts = uiState.accounts,
                onDismiss = { showPaymentDialog = null },
                onConfirm = { amount, accountId, date, paymentMethod, note ->
                    viewModel.recordPayment(
                        showPaymentDialog!!.id,
                        amount,
                        accountId,
                        date,
                        paymentMethod,
                        note
                    )
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
                title = { Text(localizedUiString("Debts"), fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = localizedUiString("Back"))
                    }
                },
                actions = {
                    IconButton(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = localizedUiString("Add"), tint = EzcarBlueBright)
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
                canDeleteRecords = canDeleteRecords
            )
        }
    }
}

@Composable
fun DebtsContent(
    viewModel: DebtViewModel = hiltViewModel(),
    showAddDialog: Boolean = false,
    onAddDialogDismiss: () -> Unit = {},
    canDeleteRecords: Boolean = true
) {
    val uiState by viewModel.uiState.collectAsState()
    var internalAddDialog by remember { mutableStateOf(false) }
    var isAddDialogOpen by remember { mutableStateOf(showAddDialog) }
    LaunchedEffect(showAddDialog) {
        if (showAddDialog) isAddDialogOpen = true
    }

    var showPaymentDialog by remember { mutableStateOf<Debt?>(null) }
    var editingDebt by remember { mutableStateOf<Debt?>(null) }

    val selectedDebt = uiState.selectedDebt
    if (selectedDebt != null) {
        DebtDetailScreen(
            debt = selectedDebt,
            payments = uiState.debtPayments,
            onBack = { viewModel.clearSelection() },
            onPay = { showPaymentDialog = selectedDebt },
            canDelete = canDeleteRecords,
            onDeletePayment = { payment ->
                if (canDeleteRecords) {
                    viewModel.deletePayment(payment)
                }
            },
            onDelete = {
                if (canDeleteRecords) {
                    viewModel.deleteDebt(selectedDebt.id)
                    viewModel.clearSelection()
                }
            }
        )
        if (showPaymentDialog != null) {
            PaymentDialog(
                debt = showPaymentDialog!!,
                accounts = uiState.accounts,
                onDismiss = { showPaymentDialog = null },
                onConfirm = { amount, accountId, date, paymentMethod, note ->
                    viewModel.recordPayment(
                        showPaymentDialog!!.id,
                        amount,
                        accountId,
                        date,
                        paymentMethod,
                        note
                    )
                    showPaymentDialog = null
                }
            )
        }
        return
    }

    if (isAddDialogOpen || editingDebt != null) {
        DebtDialog(
            debt = editingDebt,
            onDismiss = { 
                isAddDialogOpen = false
                onAddDialogDismiss()
                editingDebt = null
            },
            onSave = { name, phone, amount, direction, dueDate, notes ->
                viewModel.saveDebt(editingDebt?.id?.toString(), name, phone, amount, direction, dueDate, notes)
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
            onConfirm = { amount, accountId, date, paymentMethod, note ->
                viewModel.recordPayment(
                    showPaymentDialog!!.id,
                    amount,
                    accountId,
                    date,
                    paymentMethod,
                    note
                )
                showPaymentDialog = null
            }
        )
    }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 16.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surface),
            verticalAlignment = Alignment.CenterVertically
        ) {
           TabButton(
               text = localizedUiString("They Owe Me"),
               selected = uiState.selectedTab == "owed_to_me",
               onClick = { viewModel.setTab("owed_to_me") },
               modifier = Modifier.weight(1f)
           )
           TabButton(
               text = localizedUiString("I Owe Them"),
               selected = uiState.selectedTab == "owed_by_me",
               onClick = { viewModel.setTab("owed_by_me") },
               modifier = Modifier.weight(1f)
           )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 12.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surface),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TabButton(
                text = localizedUiString("Open"),
                selected = uiState.selectedStatusFilter == "open",
                onClick = { viewModel.setStatusFilter("open") },
                modifier = Modifier.weight(1f)
            )
            TabButton(
                text = localizedUiString("Paid"),
                selected = uiState.selectedStatusFilter == "paid",
                onClick = { viewModel.setStatusFilter("paid") },
                modifier = Modifier.weight(1f)
            )
            TabButton(
                text = localizedUiString("All"),
                selected = uiState.selectedStatusFilter == "all",
                onClick = { viewModel.setStatusFilter("all") },
                modifier = Modifier.weight(1f)
            )
        }

        OutlinedTextField(
            value = uiState.searchText,
            onValueChange = viewModel::onSearchTextChange,
            placeholder = { Text(localizedUiString("Search by name, phone...")) },
            leadingIcon = {
                Icon(Icons.Default.Search, contentDescription = null)
            },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 12.dp)
        )

        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (uiState.filteredDebts.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 40.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = localizedUiString("No debts found"),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray
                        )
                    }
                }
            }
            items(uiState.filteredDebts) { debt ->
                DebtItem(
                    debt = debt,
                    onClick = { viewModel.selectDebt(debt) },
                    onEditClick = { editingDebt = debt },
                    onPayClick = { showPaymentDialog = debt },
                    canDelete = canDeleteRecords,
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
    onEditClick: () -> Unit,
    onPayClick: () -> Unit,
    canDelete: Boolean = true,
    onDelete: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val dueDateFormatter = remember { SimpleDateFormat("MMM dd", Locale.getDefault()) }
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
                    if (!debt.counterpartyPhone.isNullOrBlank()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(top = 4.dp)
                        ) {
                            Icon(
                                Icons.Default.Phone,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = Color.Gray
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = debt.counterpartyPhone,
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.Gray,
                                maxLines = 1
                            )
                        }
                    }
                    if (debt.dueDate != null) {
                        Text(
                            text = localizedUiString("Due: %s", dueDateFormatter.format(debt.dueDate)),
                            style = MaterialTheme.typography.bodySmall,
                            color = if (debt.amount > BigDecimal.ZERO) EzcarDanger else Color.Gray,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                    }
                    if (!debt.notes.isNullOrEmpty()) {
                        Text(
                            text = debt.notes,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.Gray,
                            modifier = Modifier.padding(top = 4.dp),
                            maxLines = 1
                        )
                    }
                }
                Text(
                    text = regionSettingsManager.formatCurrency(debt.amount),
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
                TextButton(onClick = onEditClick) {
                    Text(localizedUiString("Edit"), color = EzcarBlueBright)
                }
                Spacer(modifier = Modifier.width(8.dp))
                if (canDelete) {
                    TextButton(onClick = onDelete) {
                        Text(localizedUiString("Delete"), color = Color.Gray)
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Button(
                    onClick = onPayClick,
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text(localizedUiString("Record Payment"))
                }
            }
        }
    }
}

@Composable
fun DebtDialog(
    debt: Debt?,
    onDismiss: () -> Unit,
    onSave: (String, String, BigDecimal, String, Date?, String) -> Unit
) {
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var name by remember { mutableStateOf(debt?.counterpartyName ?: "") }
    var phone by remember { mutableStateOf(debt?.counterpartyPhone ?: "") }
    var amount by remember { mutableStateOf(debt?.amount?.toPlainString() ?: "") }
    var direction by remember { mutableStateOf(debt?.direction ?: "owed_to_me") }
    var includeDueDate by remember { mutableStateOf(debt?.dueDate != null) }
    var dueDate by remember { mutableStateOf(debt?.dueDate ?: Date()) }
    var notes by remember { mutableStateOf(debt?.notes ?: "") }
    val dueDateFormatter = remember { SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()) }

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
                    text = localizedUiString(if (debt == null) "New Debt" else "Edit Debt"),
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Bold
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    TabButton(
                        text = localizedUiString("They Owe Me"),
                        selected = direction == "owed_to_me",
                        onClick = { direction = "owed_to_me" },
                        modifier = Modifier.weight(1f)
                    )
                    TabButton(
                        text = localizedUiString("I Owe Them"),
                        selected = direction == "owed_by_me",
                        onClick = { direction = "owed_by_me" },
                        modifier = Modifier.weight(1f)
                    )
                }

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedUiString("Name")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedTextField(
                    value = phone,
                    onValueChange = { phone = it },
                    label = { Text(localizedUiString("Phone Number")) },
                    leadingIcon = {
                        Icon(Icons.Default.Phone, contentDescription = null)
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it },
                    label = { Text(localizedUiString("Amount (%s)", regionState.selectedRegion.currencyCode)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
                        .clickable { includeDueDate = !includeDueDate }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedUiString("Due Date"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f)
                    )
                    Switch(
                        checked = includeDueDate,
                        onCheckedChange = { includeDueDate = it }
                    )
                }

                if (includeDueDate) {
                    OutlinedButton(
                        onClick = {
                            val calendar = Calendar.getInstance().apply { time = dueDate }
                            DatePickerDialog(
                                context,
                                { _, year, month, day ->
                                    calendar.set(Calendar.YEAR, year)
                                    calendar.set(Calendar.MONTH, month)
                                    calendar.set(Calendar.DAY_OF_MONTH, day)
                                    calendar.set(Calendar.HOUR_OF_DAY, 0)
                                    calendar.set(Calendar.MINUTE, 0)
                                    calendar.set(Calendar.SECOND, 0)
                                    calendar.set(Calendar.MILLISECOND, 0)
                                    dueDate = calendar.time
                                },
                                calendar.get(Calendar.YEAR),
                                calendar.get(Calendar.MONTH),
                                calendar.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(localizedUiString("Due Date: %s", dueDateFormatter.format(dueDate)))
                    }
                }

                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text(localizedUiString("Notes (Optional)")) },
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text(localizedUiString("Cancel"), color = Color.Gray)
                    }
                    Button(
                        onClick = {
                            val bal = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
                            onSave(name, phone, bal, direction, if (includeDueDate) dueDate else null, notes)
                        },
                        enabled = name.isNotBlank() && (amount.toBigDecimalOrNull() ?: BigDecimal.ZERO) > BigDecimal.ZERO,
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text(localizedUiString("Save"))
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
    canDelete: Boolean = true,
    onDeletePayment: (com.ezcar24.business.data.local.DebtPayment) -> Unit = {},
    onDelete: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(debt.counterpartyName, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = localizedUiString("Back"))
                    }
                },
                actions = {
                    if (canDelete) {
                        IconButton(onClick = onDelete) {
                            Icon(Icons.Default.Delete, contentDescription = localizedUiString("Delete"), tint = EzcarDanger)
                        }
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
                            text = localizedUiString(if (debt.direction == "owed_to_me") "OWES YOU" else "YOU OWE"),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.Gray,
                            letterSpacing = 1.1.sp
                        )
                        if (debt.dueDate != null) {
                            Text(
                                localizedUiString("Due: %s", java.text.SimpleDateFormat("MMM dd", Locale.getDefault()).format(debt.dueDate)),
                                style = MaterialTheme.typography.labelSmall,
                                color = EzcarDanger
                            )
                        }
                    }
                    Text(
                        text = regionSettingsManager.formatCurrency(debt.amount),
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

            Button(
                onClick = onPay,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(localizedUiString(if (debt.direction == "owed_to_me") "Record Payment Received" else "Record Payment Sent"))
            }

            Text(
                text = localizedUiString("HISTORY"),
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
                            Text(localizedUiString("No payment history"), color = Color.Gray)
                        }
                    }
                }
                items(payments) { payment ->
                    PaymentItem(
                        payment = payment,
                        canDelete = canDelete,
                        onDelete = { onDeletePayment(payment) }
                    )
                }
            }
        }
    }
}



@Composable
fun PaymentItem(
    payment: com.ezcar24.business.data.local.DebtPayment,
    canDelete: Boolean = true,
    onDelete: () -> Unit = {}
) {
    val regionSettingsManager = rememberRegionSettingsManager()
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
                    text = payment.note?.takeIf { it.isNotBlank() } ?: localizedUiString("Payment"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                payment.paymentMethod?.takeIf { it.isNotBlank() }?.let { method ->
                    Text(
                        text = localizedUiString(method),
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
                Text(
                    text = java.text.SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(payment.date),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = regionSettingsManager.formatCurrency(payment.amount),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black
                )
                if (canDelete) {
                    IconButton(onClick = onDelete) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = localizedUiString("Delete Payment"),
                            tint = Color.Gray.copy(alpha = 0.6f),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentDialog(
    debt: Debt,
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onConfirm: (BigDecimal, UUID, Date, String, String) -> Unit
) {
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var amount by remember { mutableStateOf("") }
    var selectedAccountId by remember { mutableStateOf<UUID?>(null) }
    var expanded by remember { mutableStateOf(false) }
    var methodExpanded by remember { mutableStateOf(false) }
    var paymentDate by remember { mutableStateOf(Date()) }
    var paymentMethod by remember { mutableStateOf("Cash") }
    var note by remember { mutableStateOf("") }
    val paymentMethods = remember { listOf("Cash", "Bank Transfer", "Cheque", "Other") }
    val parsedAmount = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
    val isFormValid = parsedAmount > BigDecimal.ZERO && parsedAmount <= debt.amount && selectedAccountId != null
    val dateFormatter = remember { SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.getDefault()) }

    LaunchedEffect(accounts) {
        if (accounts.isNotEmpty() && selectedAccountId == null) {
            selectedAccountId = accounts.firstOrNull { it.accountType.equals("cash", ignoreCase = true) }?.id
                ?: accounts.first().id
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
                    text = localizedUiString("Record Payment"),
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = localizedUiString("Recording payment for %s", debt.counterpartyName),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.Gray
                )

                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it },
                    label = { Text(localizedUiString("Payment Amount (%s)", regionState.selectedRegion.currencyCode)) },
                    placeholder = { Text(localizedUiString("Max: %s", regionSettingsManager.formatCurrency(debt.amount))) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedButton(
                    onClick = {
                        val calendar = Calendar.getInstance().apply { time = paymentDate }
                        DatePickerDialog(
                            context,
                            { _, year, month, day ->
                                calendar.set(Calendar.YEAR, year)
                                calendar.set(Calendar.MONTH, month)
                                calendar.set(Calendar.DAY_OF_MONTH, day)
                                TimePickerDialog(
                                    context,
                                    { _, hour, minute ->
                                        calendar.set(Calendar.HOUR_OF_DAY, hour)
                                        calendar.set(Calendar.MINUTE, minute)
                                        calendar.set(Calendar.SECOND, 0)
                                        calendar.set(Calendar.MILLISECOND, 0)
                                        paymentDate = calendar.time
                                    },
                                    calendar.get(Calendar.HOUR_OF_DAY),
                                    calendar.get(Calendar.MINUTE),
                                    true
                                ).show()
                            },
                            calendar.get(Calendar.YEAR),
                            calendar.get(Calendar.MONTH),
                            calendar.get(Calendar.DAY_OF_MONTH)
                        ).show()
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(localizedUiString("Date: %s", dateFormatter.format(paymentDate)))
                }

                ExposedDropdownMenuBox(
                    expanded = methodExpanded,
                    onExpandedChange = { methodExpanded = !methodExpanded },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OutlinedTextField(
                        value = localizedUiString(paymentMethod),
                        onValueChange = {},
                        readOnly = true,
                        label = { Text(localizedUiString("Method")) },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = methodExpanded) },
                        colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                        modifier = Modifier.menuAnchor().fillMaxWidth()
                    )
                    ExposedDropdownMenu(
                        expanded = methodExpanded,
                        onDismissRequest = { methodExpanded = false }
                    ) {
                        paymentMethods.forEach { method ->
                            DropdownMenuItem(
                                text = { Text(localizedUiString(method)) },
                                onClick = {
                                    paymentMethod = method
                                    methodExpanded = false
                                }
                            )
                        }
                    }
                }

                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text(localizedUiString("Note (Optional)")) },
                    minLines = 2,
                    modifier = Modifier.fillMaxWidth()
                )

                ExposedDropdownMenuBox(
                    expanded = expanded,
                    onExpandedChange = { expanded = !expanded },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    val selectedAccount = accounts.find { it.id == selectedAccountId }
                    OutlinedTextField(
                        value = selectedAccount?.accountType ?: localizedUiString("Select Account"),
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
                                text = { Text(localizedUiString("%s (%s)", account.accountType, regionSettingsManager.formatCurrency(account.balance))) },
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
                        Text(localizedUiString("Cancel"), color = Color.Gray)
                    }
                    Button(
                        onClick = {
                            if (selectedAccountId != null) {
                                onConfirm(parsedAmount, selectedAccountId!!, paymentDate, paymentMethod, note)
                            }
                        },
                        enabled = isFormValid,
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text(localizedUiString("Confirm"))
                    }
                }
            }
        }
    }
}
