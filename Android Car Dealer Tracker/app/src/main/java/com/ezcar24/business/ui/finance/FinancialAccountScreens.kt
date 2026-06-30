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
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
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
import com.ezcar24.business.util.FinancialAccountKind
import com.ezcar24.business.util.composeFinancialAccountType
import com.ezcar24.business.util.financialAccountDisplayTitle
import com.ezcar24.business.util.financialAccountKindFor
import com.ezcar24.business.util.financialAccountShortTitle
import com.ezcar24.business.util.financialAccountSubtitleTitle
import com.ezcar24.business.util.parseFinancialAccountType
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
    filterKind: FinancialAccountKind? = null,
    viewModel: FinancialAccountViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingAccount by remember { mutableStateOf<FinancialAccount?>(null) }
    val accountGroups = remember(uiState.accounts, filterKind) {
        groupedFinancialAccounts(uiState.accounts, filterKind)
    }
    val screenTitle = filterKind?.titleSource ?: "Financial Accounts"

    if (uiState.errorMessage != null) {
        AlertDialog(
            onDismissRequest = viewModel::clearErrorMessage,
            title = { Text(localizedUiString("Account Error")) },
            text = { Text(localizedUiString(uiState.errorMessage ?: "")) },
            confirmButton = {
                TextButton(onClick = viewModel::clearErrorMessage) {
                    Text(localizedUiString("OK"))
                }
            }
        )
    }

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
            onUpdateAccount = { name, onSaved ->
                viewModel.saveAccount(
                    uiState.selectedAccount!!.id.toString(),
                    name,
                    uiState.selectedAccount!!.balance,
                    onSaved
                )
            }
        )
        return
    }

    if (showAddDialog || editingAccount != null) {
        AccountDialog(
            account = editingAccount,
            preselectedKind = filterKind,
            onDismiss = {
                showAddDialog = false
                editingAccount = null
            },
            onSave = { name, balance ->
                viewModel.saveAccount(editingAccount?.id?.toString(), name, balance) {
                    showAddDialog = false
                    editingAccount = null
                }
            }
        )
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text(localizedUiString(screenTitle), fontWeight = FontWeight.Bold) },
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
                .padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            if (accountGroups.isEmpty()) {
                EmptyAccountsState(
                    filterKind = filterKind,
                    onCreateDefaults = { viewModel.createDefaultAccounts() },
                    onAddAccount = { showAddDialog = true }
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    accountGroups.forEach { group ->
                        item(key = "header-${group.kind.routeValue}") {
                            Text(
                                text = localizedUiString(group.kind.titleSource).uppercase(Locale.getDefault()),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = Color.Gray,
                                modifier = Modifier.padding(start = 4.dp, top = 2.dp)
                            )
                        }
                        items(group.accounts, key = { it.id }) { account ->
                            AccountItem(
                                account = account,
                                onClick = { viewModel.selectAccount(account) }
                            )
                        }
                        item(key = "footer-${group.kind.routeValue}") {
                            Text(
                                text = localizedUiString("Tap an account to view transactions."),
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.Gray,
                                modifier = Modifier.padding(start = 4.dp, top = 2.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

private data class FinancialAccountGroup(
    val kind: FinancialAccountKind,
    val accounts: List<FinancialAccount>
)

private fun groupedFinancialAccounts(
    accounts: List<FinancialAccount>,
    filterKind: FinancialAccountKind?
): List<FinancialAccountGroup> {
    val grouped = accounts.groupBy { financialAccountKindFor(it.accountType) }
    val kindsToShow = filterKind?.let { listOf(it) } ?: FinancialAccountKind.entries
    return kindsToShow.mapNotNull { kind ->
        val sortedAccounts = grouped[kind]
            ?.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { financialAccountDisplayTitle(it.accountType) })
            .orEmpty()
        if (sortedAccounts.isEmpty()) null else FinancialAccountGroup(kind, sortedAccounts)
    }
}

private fun accountKindIcon(kind: FinancialAccountKind): ImageVector {
    return when (kind) {
        FinancialAccountKind.CASH -> Icons.Default.AttachMoney
        FinancialAccountKind.BANK -> Icons.Default.AccountBalance
        FinancialAccountKind.CREDIT_CARD -> Icons.Default.CreditCard
        FinancialAccountKind.OTHER -> Icons.Default.MoreHoriz
    }
}

private fun accountKindColor(kind: FinancialAccountKind): Color {
    return when (kind) {
        FinancialAccountKind.CASH -> EzcarGreen
        FinancialAccountKind.BANK -> EzcarBlueBright
        FinancialAccountKind.CREDIT_CARD -> Color(0xFF856EF2)
        FinancialAccountKind.OTHER -> Color.Gray
    }
}

@Composable
fun EmptyAccountsState(
    filterKind: FinancialAccountKind?,
    onCreateDefaults: () -> Unit,
    onAddAccount: () -> Unit
) {
    val kindTitle = filterKind?.let { localizedUiString(it.titleSource) }
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
                    imageVector = accountKindIcon(filterKind ?: FinancialAccountKind.BANK),
                    contentDescription = null,
                    tint = accountKindColor(filterKind ?: FinancialAccountKind.BANK),
                    modifier = Modifier.size(28.dp)
                )
            }
            Text(
                text = kindTitle?.let { localizedUiString("No %s accounts found", it) }
                    ?: localizedUiString("No Accounts Found"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Black
            )
            Text(
                text = kindTitle?.let { localizedUiString("Tap Add Account to create a %s account.", it.lowercase(Locale.getDefault())) }
                    ?: localizedUiString("Create accounts to track cash, bank balances and every transaction."),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray
            )
            if (filterKind == null) {
                Button(
                    onClick = onCreateDefaults,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Text(localizedUiString("Create Cash + Bank"))
                }
            }
            OutlinedButton(
                onClick = onAddAccount,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp)
            ) {
                Text(kindTitle?.let { localizedUiString("Add %s", it) } ?: localizedUiString("Add Custom Account"))
            }
        }
    }
}

@Composable
fun AccountItem(
    account: FinancialAccount,
    onClick: () -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val kind = financialAccountKindFor(account.accountType)
    val subtitle = financialAccountSubtitleTitle(account.accountType)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(0.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 14.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .background(accountKindColor(kind).copy(alpha = 0.12f), RoundedCornerShape(20.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = accountKindIcon(kind),
                    contentDescription = null,
                    tint = accountKindColor(kind),
                    modifier = Modifier.size(21.dp)
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = localizedUiString(financialAccountShortTitle(account.accountType)),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    color = Color.Black,
                    maxLines = 1
                )
                if (subtitle != null) {
                    Text(
                        text = localizedUiString(subtitle),
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.Gray,
                        maxLines = 1
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = regionSettingsManager.formatCurrency(account.balance),
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.Black,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
                Text(
                    text = localizedUiString("Current Balance"),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray,
                    maxLines = 1
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = Color.Gray.copy(alpha = 0.55f),
                modifier = Modifier.size(18.dp)
            )
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
    onUpdateAccount: (String, () -> Unit) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    var showTransactionDialog by remember { mutableStateOf<String?>(null) }
    var transactionPendingDelete by remember { mutableStateOf<AccountTransaction?>(null) }
    var showEditAccountDialog by remember { mutableStateOf(false) }

    if (showEditAccountDialog) {
        AccountDialog(
            account = account,
            onDismiss = { showEditAccountDialog = false },
            onSave = { name, _ ->
                onUpdateAccount(name) {
                    showEditAccountDialog = false
                }
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
                title = { Text(localizedUiString("Account Transactions"), fontWeight = FontWeight.Bold) },
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
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarDanger),
                    shape = RoundedCornerShape(12.dp)
                ) {
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountDialog(
    account: FinancialAccount?,
    preselectedKind: FinancialAccountKind? = null,
    onDismiss: () -> Unit,
    onSave: (String, BigDecimal) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val parsedAccountType = remember(account) { parseFinancialAccountType(account?.accountType) }
    val initialKind = account?.let { parsedAccountType.kind } ?: preselectedKind ?: FinancialAccountKind.BANK
    var selectedKind by remember(account, preselectedKind) { mutableStateOf(initialKind) }
    var kindMenuExpanded by remember { mutableStateOf(false) }
    var name by remember(account) { mutableStateOf(accountNameForEdit(account)) }
    var balance by remember { mutableStateOf(account?.balance?.toPlainString() ?: "") }
    val isEditing = account != null
    val availableKinds = remember(isEditing, preselectedKind) {
        when {
            preselectedKind != null -> listOf(preselectedKind)
            isEditing -> FinancialAccountKind.entries
            else -> listOf(FinancialAccountKind.CASH, FinancialAccountKind.BANK, FinancialAccountKind.CREDIT_CARD)
        }
    }
    val requiresName = selectedKind == FinancialAccountKind.BANK || selectedKind == FinancialAccountKind.CREDIT_CARD

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

                if (preselectedKind == null) {
                    ExposedDropdownMenuBox(
                        expanded = kindMenuExpanded,
                        onExpandedChange = { kindMenuExpanded = it }
                    ) {
                        OutlinedTextField(
                            value = localizedUiString(selectedKind.titleSource),
                            onValueChange = {},
                            readOnly = true,
                            label = { Text(localizedUiString("Account Type")) },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = kindMenuExpanded) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        )
                        ExposedDropdownMenu(
                            expanded = kindMenuExpanded,
                            onDismissRequest = { kindMenuExpanded = false }
                        ) {
                            availableKinds.forEach { kind ->
                                DropdownMenuItem(
                                    text = { Text(localizedUiString(kind.titleSource)) },
                                    onClick = {
                                        selectedKind = kind
                                        kindMenuExpanded = false
                                    },
                                    leadingIcon = {
                                        Icon(
                                            imageVector = accountKindIcon(kind),
                                            contentDescription = null,
                                            tint = accountKindColor(kind)
                                        )
                                    }
                                )
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedUiString("Account Name")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    leadingIcon = {
                        Icon(
                            imageVector = accountKindIcon(selectedKind),
                            contentDescription = null,
                            tint = Color.Gray
                        )
                    }
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
                            onSave(composeFinancialAccountType(selectedKind, name), bal)
                        },
                        enabled = !requiresName || name.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarBlueBright)
                    ) {
                        Text(localizedUiString("Save"))
                    }
                }
            }
        }
    }
}

private fun accountNameForEdit(account: FinancialAccount?): String {
    if (account == null) return ""
    val parsed = parseFinancialAccountType(account.accountType)
    return parsed.name ?: if (parsed.kind == FinancialAccountKind.OTHER) account.accountType.trim() else ""
}
