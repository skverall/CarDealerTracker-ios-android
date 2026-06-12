package com.ezcar24.business.ui.sale

import android.app.DatePickerDialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.*
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSaleScreen(
    onDismiss: () -> Unit,
    onSave: () -> Unit,
    viewModel: AddSaleViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val dateFormatter = remember { SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()) }
    val paymentMethods = remember { listOf("Cash", "Bank Transfer", "Cheque", "Finance", "Other") }

    var amountStr by remember { mutableStateOf("") }
    var buyerName by remember { mutableStateOf("") }
    var buyerPhone by remember { mutableStateOf("") }
    var selectedVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var selectedAccount by remember { mutableStateOf<FinancialAccount?>(null) }
    var paymentMethod by remember { mutableStateOf("Cash") }
    var date by remember { mutableStateOf(Date()) }
    var paymentMenuExpanded by remember { mutableStateOf(false) }
    var accountMenuExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.fillMaxHeight(0.9f)) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            contentPadding = PaddingValues(bottom = 32.dp)
        ) {
            item {
                Text(
                    localizedUiString("New Sale"),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )

                Spacer(modifier = Modifier.height(20.dp))
            }

            if (selectedVehicle == null) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = EzcarBackgroundLight),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 60.dp),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.DirectionsCar, contentDescription = null, tint = EzcarNavy)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                localizedUiString("Select Vehicle from Inventory"),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                    
                    Text(
                        localizedUiString("Available Vehicles:"),
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
                    )

                    if (uiState.isLoading) {
                        CircularProgressIndicator(
                            color = EzcarNavy,
                            modifier = Modifier.padding(vertical = 24.dp)
                        )
                    } else if (uiState.availableVehicles.isEmpty()) {
                        Text(
                            localizedUiString("No available vehicles"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        Text(
                            localizedUiString("Add a vehicle first to record a sale."),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.Gray,
                            modifier = Modifier.padding(top = 6.dp, bottom = 20.dp)
                        )
                    }
                }

                items(uiState.availableVehicles.size) { i ->
                    val v = uiState.availableVehicles[i]
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 56.dp)
                            .clickable { selectedVehicle = v }
                            .padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.DirectionsCar, contentDescription = null, tint = EzcarNavy)
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(saleVehicleTitle(v).ifBlank { localizedUiString("Vehicle") }, fontWeight = FontWeight.Bold)
                            Text(localizedUiString("VIN: %s", v.vin), style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    HorizontalDivider()
                }
            } else {
                item {
                    val vehicle = selectedVehicle
                    val saleAmount = amountStr.toBigDecimalOrNull()
                    val totalCost = vehicle?.let {
                        uiState.vehicleCosts[it.id] ?: it.purchasePrice
                    } ?: BigDecimal.ZERO
                    val estimatedProfit = saleEstimatedProfit(saleAmount, totalCost)

                    Card(
                        colors = CardDefaults.cardColors(containerColor = EzcarBackgroundLight),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(localizedUiString("SELECTED VEHICLE"), style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                Text(
                                    saleVehicleTitle(vehicle).ifBlank { localizedUiString("Vehicle") },
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Spacer(modifier = Modifier.weight(1f))
                            IconButton(onClick = { selectedVehicle = null }) {
                                Icon(Icons.Default.Close, contentDescription = localizedUiString("Change"))
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                    SaleSectionTitle("Sale Details")

                    OutlinedTextField(
                        value = amountStr,
                        onValueChange = { amountStr = it },
                        label = { Text(localizedUiString("Sale Price (%s)", regionState.selectedRegion.currencyCode)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    SaleFinancialPreviewCard(
                        totalCost = totalCost,
                        salePrice = saleAmount ?: BigDecimal.ZERO,
                        estimatedProfit = estimatedProfit,
                        canViewFinancials = uiState.canViewFinancials,
                        formatCurrency = regionSettingsManager::formatCurrency
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    SaleSelectorButton(
                        icon = Icons.Default.Today,
                        label = localizedUiString("Sale Date"),
                        value = dateFormatter.format(date),
                        onClick = {
                            val calendar = Calendar.getInstance()
                            calendar.time = date
                            DatePickerDialog(
                                context,
                                { _, year, month, day ->
                                    calendar.set(year, month, day)
                                    date = calendar.time
                                },
                                calendar.get(Calendar.YEAR),
                                calendar.get(Calendar.MONTH),
                                calendar.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        }
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Box(modifier = Modifier.fillMaxWidth()) {
                        SaleSelectorButton(
                            icon = Icons.Default.CreditCard,
                            label = localizedUiString("Payment Method"),
                            value = localizedUiString(paymentMethod),
                            onClick = { paymentMenuExpanded = true }
                        )
                        DropdownMenu(
                            expanded = paymentMenuExpanded,
                            onDismissRequest = { paymentMenuExpanded = false }
                        ) {
                            paymentMethods.forEach { method ->
                                DropdownMenuItem(
                                    text = { Text(localizedUiString(method)) },
                                    onClick = {
                                        paymentMethod = method
                                        paymentMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                    SaleSectionTitle("Deposit To")

                    Box(modifier = Modifier.fillMaxWidth()) {
                        SaleSelectorButton(
                            icon = Icons.Default.AccountBalance,
                            label = localizedUiString("Account"),
                            value = selectedAccount?.accountType ?: localizedUiString("None"),
                            onClick = { accountMenuExpanded = true }
                        )
                        DropdownMenu(
                            expanded = accountMenuExpanded,
                            onDismissRequest = { accountMenuExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text(localizedUiString("None")) },
                                onClick = {
                                    selectedAccount = null
                                    accountMenuExpanded = false
                                }
                            )
                            uiState.accounts.forEach { account ->
                                DropdownMenuItem(
                                    text = {
                                        Column {
                                            Text(account.accountType)
                                            Text(
                                                regionSettingsManager.formatCurrency(account.balance),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = Color.Gray
                                            )
                                        }
                                    },
                                    onClick = {
                                        selectedAccount = account
                                        accountMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))
                    SaleSectionTitle("Buyer Details")

                    OutlinedTextField(
                        value = buyerName,
                        onValueChange = { buyerName = it },
                        label = { Text(localizedUiString("Buyer Name")) },
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    
                    OutlinedTextField(
                        value = buyerPhone,
                        onValueChange = { buyerPhone = it },
                        label = { Text(localizedUiString("Buyer Phone")) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(24.dp))

                    val canSave = saleAmount != null && saleAmount > BigDecimal.ZERO && buyerName.isNotBlank()

                    Button(
                        onClick = {
                            if (selectedVehicle != null && saleAmount != null && canSave) {
                                viewModel.saveSale(
                                    vehicle = selectedVehicle!!,
                                    amount = saleAmount,
                                    date = date,
                                    buyerName = buyerName,
                                    buyerPhone = buyerPhone,
                                    paymentMethod = paymentMethod,
                                    account = selectedAccount
                                )
                                onSave()
                            }
                        },
                        enabled = canSave,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        Text(localizedUiString("Complete Sale"), fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun SaleFinancialPreviewCard(
    totalCost: BigDecimal,
    salePrice: BigDecimal,
    estimatedProfit: BigDecimal,
    canViewFinancials: Boolean,
    formatCurrency: (BigDecimal) -> String
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                localizedUiString("Financial Preview"),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = Color.Gray
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                if (canViewFinancials) {
                    SaleFinancialMetric(
                        label = localizedUiString("Total Cost"),
                        amount = totalCost,
                        color = MaterialTheme.colorScheme.onSurface,
                        formatCurrency = formatCurrency,
                        modifier = Modifier.weight(1f)
                    )
                }

                SaleFinancialMetric(
                    label = localizedUiString("Sale Price"),
                    amount = salePrice,
                    color = EzcarNavy,
                    formatCurrency = formatCurrency,
                    modifier = Modifier.weight(1f)
                )

                if (canViewFinancials) {
                    SaleFinancialMetric(
                        label = localizedUiString("Estimated Profit"),
                        amount = estimatedProfit,
                        color = if (estimatedProfit >= BigDecimal.ZERO) EzcarSuccess else EzcarDanger,
                        formatCurrency = formatCurrency,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun SaleFinancialMetric(
    label: String,
    amount: BigDecimal,
    color: Color,
    formatCurrency: (BigDecimal) -> String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.Gray,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            formatCurrency(amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun saleVehicleTitle(vehicle: Vehicle?): String {
    return listOfNotNull(
        vehicle?.year?.toString(),
        vehicle?.make?.takeIf { it.isNotBlank() },
        vehicle?.model?.takeIf { it.isNotBlank() }
    ).joinToString(" ")
}

@Composable
private fun SaleSectionTitle(title: String) {
    Text(
        localizedUiString(title),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = Color.Gray,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp)
    )
}

@Composable
private fun SaleSelectorButton(
    icon: ImageVector,
    label: String,
    value: String,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp),
        shape = RoundedCornerShape(12.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Icon(icon, contentDescription = null, tint = EzcarNavy)
        Spacer(modifier = Modifier.width(12.dp))
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.Start
        ) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        }
        Icon(Icons.Default.ArrowDropDown, contentDescription = null, tint = EzcarNavy)
    }
}
