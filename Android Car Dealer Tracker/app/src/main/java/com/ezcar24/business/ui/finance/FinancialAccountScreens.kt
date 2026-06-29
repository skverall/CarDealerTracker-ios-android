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
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
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
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.AccountTransaction
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import com.ezcar24.business.util.localizedUiString

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinancialAccountListScreen(
    onBack: () -> Unit,
    viewModel: FinancialAccountViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingAccount by remember { mutableStateOf<FinancialAccount?>(null) }

    if (uiState.selectedAccount != null) {
        FinancialAccountDetailScreen(
            account = uiState.selectedAccount!!,
            transactions = uiState.transactions,
            onBack = { viewModel.clearSelection() },
            onAddTransaction = { amount, type, date, note ->
                viewModel.addTransaction(uiState.selectedAccount!!.id, amount, type, date, note)
            },
            onDeleteTransaction = { transaction ->
                viewModel.deleteTransaction(transaction)
            },
            onUpdateAccount = { name ->
                viewModel.saveAccount(uiState.selectedAccount!!.id.toString(), name, uiState.selectedAccount!!.balance)
            }
        )
        return
    }

    if (showAddDialog || editingAccount != null) {
        AccountDialog(
            account = editingAccount,
            onDismiss = { 
                showAddDialog = false
                editingAccount = null
            },
            onSave = { name, balance ->
                viewModel.saveAccount(editingAccount?.id?.toString(), name, balance)
                showAddDialog = false
                editingAccount = null
            }
        )
    }

    Scaffold(
        containerColor = EzcarBackground, // Light gray background
        topBar = {
            TopAppBar(
                title = { Text(localizedUiString("Financial Accounts"), fontWeight = FontWeight.Bold) },
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
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.White.copy(alpha = 0.9f)
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .padding(16.dp)
        ) {
            // Total Balance Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = EzcarBlueBright),
                shape = RoundedCornerShape(16.dp),
                elevation = CardDefaults.cardElevation(4.dp)
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Total Balance",
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = regionSettingsManager.formatCurrency(uiState.totalBalance),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Text(
                text = "ACCOUNTS",
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray,
                modifier = Modifier.padding(start = 4.dp)
            )
            
            Spacer(modifier = Modifier.height(8.dp))

            if (uiState.accounts.isEmpty()) {
                EmptyAccountsState(
                    onCreateDefaults = { viewModel.createDefaultAccounts() },
                    onAddAccount = { showAddDialog = true }
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(uiState.accounts) { account ->
                        AccountItem(
                            account = account,
                            onClick = { viewModel.selectAccount(account) },
                            onDelete = { viewModel.deleteAccount(account.id) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun EmptyAccountsState(
    onCreateDefaults: () -> Unit,
    onAddAccount: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(20.dp),
        elevation = CardDefaults.cardElevation(3.dp)
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .background(EzcarBlueBright.copy(alpha = 0.12f), RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.AccountBalance,
                    contentDescription = null,
                    tint = EzcarBlueBright,
                    modifier = Modifier.size(28.dp)
                )
            }
            Text(
                text = localizedUiString("No Accounts Found"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            Text(
                text = localizedUiString("Create accounts to track cash, bank balances and every transaction."),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
            Button(
                onClick = onCreateDefaults,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                shape = RoundedCornerShape(14.dp)
            ) {
                Text(localizedUiString("Create Cash + Bank"))
            }
            OutlinedButton(
                onClick = onAddAccount,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp)
            ) {
                Text(localizedUiString("Add Custom Account"))
            }
        }
    }
}

@Composable
fun AccountItem(
    account: FinancialAccount,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
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
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = account.accountType,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Black
                )
            }
            
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = regionSettingsManager.formatCurrency(account.balance),
                    style = MaterialTheme.typography.bodyLarge,
                    color = EzcarGreen,
                    fontWeight = FontWeight.Bold
                )
                if (account.accountType.lowercase() != "cash") { 
                     IconButton(onClick = onDelete) {
                         Icon(Icons.Default.Delete, contentDescription = localizedUiString("Delete"), tint = Color.Gray.copy(alpha=0.5f), modifier = Modifier.size(20.dp))
                     }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinancialAccountDetailScreen(
    account: FinancialAccount,
    transactions: List<AccountTransaction>,
    onBack: () -> Unit,
    onAddTransaction: (BigDecimal, String, Date, String) -> Unit,
    onDeleteTransaction: (AccountTransaction) -> Unit,
    onUpdateAccount: (String) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var showTransactionDialog by remember { mutableStateOf<String?>(null) } // "deposit" or "withdrawal"
    var transactionPendingDelete by remember { mutableStateOf<AccountTransaction?>(null) }
    var showEditAccountDialog by remember { mutableStateOf(false) }

    if (showEditAccountDialog) {
        AccountDialog(
            account = account,
            onDismiss = { showEditAccountDialog = false },
            onSave = { name, _ ->
                onUpdateAccount(name)
                showEditAccountDialog = false
            }
        )
    }

    if (showTransactionDialog != null) {
        TransactionDialog(
            type = showTransactionDialog!!,
            onDismiss = { showTransactionDialog = null },
            onConfirm = { amount, date, note ->
                onAddTransaction(amount, showTransactionDialog!!, date, note)
                showTransactionDialog = null
            }
        )
    }

    transactionPendingDelete?.let { transaction ->
        AlertDialog(
            onDismissRequest = { transactionPendingDelete = null },
            title = { Text(localizedUiString("Delete Transaction")) },
            text = { Text(localizedUiString("This will remove the transaction and update the account balance.")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteTransaction(transaction)
                        transactionPendingDelete = null
                    }
                ) {
                    Text(localizedUiString("Delete"), color = EzcarDanger)
                }
            },
            dismissButton = {
                TextButton(onClick = { transactionPendingDelete = null }) {
                    Text(localizedUiString("Cancel"))
                }
            }
        )
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text(account.accountType, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = localizedUiString("Back"))
                    }
                },
                actions = {
                    IconButton(onClick = { showEditAccountDialog = true }) {
                        Icon(Icons.Default.Edit, contentDescription = localizedUiString("Edit Account"), tint = EzcarBlueBright)
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
            // Balance Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = EzcarBlueBright),
                shape = RoundedCornerShape(16.dp),
                elevation = CardDefaults.cardElevation(4.dp)
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = localizedUiString("Current Balance"),
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                    Text(
                        text = regionSettingsManager.formatCurrency(account.balance),
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }

            // Action Buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Button(
                    onClick = { showTransactionDialog = "deposit" },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarGreen),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(localizedUiString("Deposit"))
                }
                Button(
                    onClick = { showTransactionDialog = "withdrawal" },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarDanger), // Need to ensure EzcarDanger is available or use Red
                    shape = RoundedCornerShape(12.dp)
                ) {
                     // Icon minus?
                    Text(localizedUiString("Withdraw"))
                }
            }

            Text(
                text = "TRANSACTIONS",
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray,
                modifier = Modifier.padding(start = 4.dp, top = 8.dp)
            )

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f)
            ) {
                if (transactions.isEmpty()) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                            Text(localizedUiString("No transactions yet"), color = Color.Gray)
                        }
                    }
                }
                items(transactions) { tx ->
                    TransactionItem(
                        tx = tx,
                        onDelete = { transactionPendingDelete = tx }
                    )
                }
            }
        }
    }
}

@Composable
fun TransactionItem(
    tx: AccountTransaction,
    onDelete: () -> Unit
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
                    text = tx.note?.takeIf { it.isNotBlank() } ?: tx.transactionType.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = java.text.SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault()).format(tx.date),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = (if (tx.transactionType == "withdrawal") "- " else "+ ") + regionSettingsManager.formatCurrency(tx.amount),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (tx.transactionType == "withdrawal") Color.Red else EzcarGreen
                )
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = localizedUiString("Delete Transaction"),
                        tint = Color.Gray.copy(alpha = 0.6f),
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun TransactionDialog(
    type: String,
    onDismiss: () -> Unit,
    onConfirm: (BigDecimal, Date, String) -> Unit
) {
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var amount by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var transactionDate by remember { mutableStateOf(Date()) }
    val parsedAmount = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
    val dateFormatter = remember { SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.getDefault()) }

    Dialog(onDismissRequest = onDismiss) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = localizedUiString(if (type == "deposit") "Add Deposit" else "Withdraw Funds"),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it },
                    label = { Text(localizedUiString("Amount (%s)", regionState.selectedRegion.currencyCode)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedButton(
                    onClick = {
                        val calendar = Calendar.getInstance().apply { time = transactionDate }
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
                                        transactionDate = calendar.time
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
                    Text(localizedUiString("Date: %s", dateFormatter.format(transactionDate)))
                }

                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text(localizedUiString("Note (Optional)")) },
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel"), color = Color.Gray) }
                    Button(
                        onClick = {
                            onConfirm(parsedAmount, transactionDate, note.trim())
                        },
                        enabled = parsedAmount > BigDecimal.ZERO,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (type == "deposit") EzcarGreen else EzcarDanger
                        )
                    ) {
                        Text(localizedUiString("Confirm"))
                    }
                }
            }
        }
    }
}

@Composable
fun AccountDialog(
    account: FinancialAccount?,
    onDismiss: () -> Unit,
    onSave: (String, BigDecimal) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var name by remember { mutableStateOf(account?.accountType ?: "") }
    var balance by remember { mutableStateOf(account?.balance?.toPlainString() ?: "") }
    val isEditing = account != null

    Dialog(onDismissRequest = onDismiss) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White),
            elevation = CardDefaults.cardElevation(8.dp)
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = if (account == null) localizedUiString("Add Account") else localizedUiString("Edit Account"),
                    style = MaterialTheme.typography.titleLarge,
                    color = Color.Black,
                    fontWeight = FontWeight.Bold
                )

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedUiString("Account Name")) },
                    singleLine = true
                )

                if (isEditing) {
                    Text(
                        text = localizedUiString(
                            "Current Balance: %s",
                            regionSettingsManager.formatCurrency(account?.balance ?: BigDecimal.ZERO)
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                } else {
                    OutlinedTextField(
                        value = balance,
                        onValueChange = { balance = it },
                        label = { Text(localizedUiString("Starting Balance (%s)", regionState.selectedRegion.currencyCode)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
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
                            val bal = balance.toBigDecimalOrNull() ?: BigDecimal.ZERO
                            onSave(name, bal)
                        },
                        enabled = name.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text(localizedUiString("Save"))
                    }
                }
            }
        }
    }
}
