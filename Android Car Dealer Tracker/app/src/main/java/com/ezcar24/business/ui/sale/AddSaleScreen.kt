package com.ezcar24.business.ui.sale

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
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
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.data.local.PartBatch
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.repository.DealDeskLine
import com.ezcar24.business.data.repository.DealDeskLineCalculationType
import com.ezcar24.business.data.repository.DealDeskPaymentPlan
import com.ezcar24.business.data.repository.DealDeskSettings
import com.ezcar24.business.data.repository.DealDeskSnapshot
import com.ezcar24.business.data.repository.DealDeskTemplateCatalog
import com.ezcar24.business.data.repository.DealDeskTotals
import com.ezcar24.business.ui.parts.PartSaleLineDraft
import com.ezcar24.business.ui.parts.PartSalesViewModel
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.*
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.pow
import kotlinx.coroutines.launch

private enum class SaleEntryKind {
    VEHICLE,
    PARTS
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSaleScreen(
    onDismiss: () -> Unit,
    onSave: () -> Unit,
    viewModel: AddSaleViewModel = hiltViewModel(),
    partSalesViewModel: PartSalesViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val partSalesUiState by partSalesViewModel.uiState.collectAsState()
    val context = LocalContext.current
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val dateFormatter = remember { SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()) }
    val paymentMethods = remember { listOf("Cash", "Bank Transfer", "Cheque", "Finance", "Other") }

    var selectedSaleKind by remember { mutableStateOf(SaleEntryKind.VEHICLE) }
    var amountStr by remember { mutableStateOf("") }
    var buyerName by remember { mutableStateOf("") }
    var buyerPhone by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var vatRefundPercentStr by remember { mutableStateOf("") }
    var selectedVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var selectedClient by remember { mutableStateOf<Client?>(null) }
    var selectedAccount by remember { mutableStateOf<FinancialAccount?>(null) }
    var paymentMethod by remember { mutableStateOf("Cash") }
    var date by remember { mutableStateOf(Date()) }
    var paymentMenuExpanded by remember { mutableStateOf(false) }
    var clientMenuExpanded by remember { mutableStateOf(false) }
    var accountMenuExpanded by remember { mutableStateOf(false) }
    var useDealDesk by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    LaunchedEffect(
        selectedVehicle?.id,
        uiState.dealDeskSettings?.isEnabled,
        uiState.dealDeskSettings?.defaultTemplateCode
    ) {
        useDealDesk = selectedVehicle != null && uiState.dealDeskSettings?.isEnabled == true
    }

    LaunchedEffect(regionState.isPartsEnabled) {
        if (!regionState.isPartsEnabled && selectedSaleKind == SaleEntryKind.PARTS) {
            selectedSaleKind = SaleEntryKind.VEHICLE
        }
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
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .background(EzcarBackgroundLight, CircleShape)
                            .clickable { onDismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = localizedUiString("Close"),
                            tint = Color.Gray
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    Text(
                        localizedUiString("New Sale"),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = EzcarNavy
                    )

                    Spacer(modifier = Modifier.weight(1f))
                    Spacer(modifier = Modifier.size(36.dp))
                }

                Spacer(modifier = Modifier.height(20.dp))

                if (regionState.isPartsEnabled) {
                    SaleTypePicker(
                        selectedKind = selectedSaleKind,
                        onSelected = { selectedSaleKind = it },
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(20.dp))
                }
            }

            if (selectedSaleKind == SaleEntryKind.PARTS && regionState.isPartsEnabled) {
                item {
                    PartSaleFormContent(
                        parts = partSalesUiState.parts,
                        batches = partSalesUiState.batches,
                        accounts = partSalesUiState.accounts,
                        clients = partSalesUiState.clients,
                        dateFormatter = dateFormatter,
                        paymentMethods = paymentMethods,
                        formatCurrency = regionSettingsManager::formatCurrency,
                        onPickDate = { currentDate, onDateSelected ->
                            val calendar = Calendar.getInstance()
                            calendar.time = currentDate
                            DatePickerDialog(
                                context,
                                { _, year, month, day ->
                                    calendar.set(year, month, day)
                                    onDateSelected(calendar.time)
                                },
                                calendar.get(Calendar.YEAR),
                                calendar.get(Calendar.MONTH),
                                calendar.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        },
                        onSavePartSale = { saleDate, accountId, lines, buyerNameValue, buyerPhoneValue, paymentMethodValue, notesValue, clientId ->
                            partSalesViewModel.createSale(
                                saleDate = saleDate,
                                selectedAccountId = accountId,
                                lineItems = lines,
                                buyerName = buyerNameValue,
                                buyerPhone = buyerPhoneValue,
                                paymentMethod = paymentMethodValue,
                                notes = notesValue,
                                selectedClientId = clientId
                            ).also { saved ->
                                if (saved) {
                                    onSave()
                                }
                            }
                        }
                    )
                }
            } else if (selectedVehicle == null) {
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
                    val vehicle = selectedVehicle!!
                    val activeDealDeskSettings = uiState.dealDeskSettings?.takeIf { it.isEnabled }
                    val saleAmount = amountStr.toBigDecimalOrNull()
                    val vatRefundPercent = optionalDecimalFromSaleInput(vatRefundPercentStr)
                        ?.takeIf { it > BigDecimal.ZERO }
                    val vatRefundAmount = calculateVatRefundAmount(saleAmount ?: BigDecimal.ZERO, vatRefundPercent)
                    val totalCost = uiState.vehicleCosts[vehicle.id] ?: vehicle.purchasePrice
                    val estimatedProfit = saleEstimatedProfit(saleAmount, totalCost).add(vatRefundAmount)

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

                    Spacer(modifier = Modifier.height(16.dp))

                    when {
                        activeDealDeskSettings != null -> {
                            DealDeskModeCard(
                                useDealDesk = useDealDesk,
                                onUseDealDeskChange = { useDealDesk = it }
                            )
                        }

                        uiState.isDealDeskSettingsLoading -> {
                            DealDeskInfoCard(
                                icon = Icons.Default.Calculate,
                                title = localizedUiString("Checking Deal Desk"),
                                message = localizedUiString("Loading tax and fee settings for this business.")
                            )
                        }

                        uiState.dealDeskSettingsError != null -> {
                            DealDeskInfoCard(
                                icon = Icons.Default.Info,
                                title = localizedUiString("Classic sale"),
                                message = localizedUiString("Deal Desk settings are unavailable, so this sale uses the standard flow.")
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(20.dp))

                    if (activeDealDeskSettings != null && useDealDesk) {
                        DealDeskSaleContent(
                            vehicle = vehicle,
                            settings = activeDealDeskSettings,
                            accounts = uiState.accounts,
                            clients = uiState.clients,
                            dateFormatter = dateFormatter,
                            onPickDate = { currentDate, onDateSelected ->
                                val calendar = Calendar.getInstance()
                                calendar.time = currentDate
                                DatePickerDialog(
                                    context,
                                    { _, year, month, day ->
                                        calendar.set(year, month, day)
                                        onDateSelected(calendar.time)
                                    },
                                    calendar.get(Calendar.YEAR),
                                    calendar.get(Calendar.MONTH),
                                    calendar.get(Calendar.DAY_OF_MONTH)
                                ).show()
                            },
                            formatCurrency = regionSettingsManager::formatCurrency,
                            currencyCode = regionState.selectedRegion.currencyCode,
                            onSaveDealDeskSale = { request ->
                                viewModel.saveSale(
                                    vehicle = vehicle,
                                    amount = request.saleAmount,
                                    date = request.date,
                                    buyerName = request.buyerName,
                                    buyerPhone = request.buyerPhone,
                                    paymentMethod = request.paymentMethod,
                                    account = request.account,
                                    accountDepositAmount = request.accountDepositAmount,
                                    notes = request.notes,
                                    selectedClient = request.client,
                                    dealDeskSnapshot = request.snapshot
                                )
                                onSave()
                            }
                        )
                    } else {
                        SaleSectionTitle("Sale Details")

                        OutlinedTextField(
                            value = amountStr,
                            onValueChange = { amountStr = sanitizeSaleDecimalInput(it) },
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

                        OutlinedTextField(
                            value = vatRefundPercentStr,
                            onValueChange = { vatRefundPercentStr = sanitizeSaleDecimalInput(it) },
                            label = { Text(localizedUiString("VAT Refund %")) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            suffix = { Text("%") },
                            modifier = Modifier.fillMaxWidth()
                        )

                        if (vatRefundAmount > BigDecimal.ZERO) {
                            Text(
                                text = localizedUiString("VAT Refund Amount: %s", regionSettingsManager.formatCurrency(vatRefundAmount)),
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.SemiBold,
                                color = EzcarSuccess,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 6.dp)
                            )
                        }

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

                        Box(modifier = Modifier.fillMaxWidth()) {
                            SaleSelectorButton(
                                icon = Icons.Default.Person,
                                label = localizedUiString("Client"),
                                value = selectedClient?.name ?: localizedUiString("New / Walk-in Client"),
                                onClick = { clientMenuExpanded = true }
                            )
                            DropdownMenu(
                                expanded = clientMenuExpanded,
                                onDismissRequest = { clientMenuExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(localizedUiString("New / Walk-in Client")) },
                                    onClick = {
                                        selectedClient = null
                                        clientMenuExpanded = false
                                    }
                                )
                                uiState.clients.forEach { client ->
                                    DropdownMenuItem(
                                        text = {
                                            Column {
                                                Text(client.name)
                                                Text(
                                                    listOfNotNull(
                                                        client.phone?.takeIf { it.isNotBlank() },
                                                        client.email?.takeIf { it.isNotBlank() }
                                                    ).joinToString(" · ").ifBlank { localizedUiString("No contact info") },
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = Color.Gray
                                                )
                                            }
                                        },
                                        onClick = {
                                            selectedClient = client
                                            buyerName = client.name
                                            buyerPhone = client.phone.orEmpty()
                                            clientMenuExpanded = false
                                        }
                                    )
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(12.dp))

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

                        Spacer(modifier = Modifier.height(12.dp))

                        OutlinedTextField(
                            value = notes,
                            onValueChange = { notes = it },
                            label = { Text(localizedUiString("Notes")) },
                            minLines = 2,
                            maxLines = 4,
                            modifier = Modifier.fillMaxWidth()
                        )

                        Spacer(modifier = Modifier.height(24.dp))

                        val canSave = saleAmount != null && saleAmount > BigDecimal.ZERO && buyerName.isNotBlank()

                        Button(
                            onClick = {
                                if (saleAmount != null && canSave) {
                                    viewModel.saveSale(
                                        vehicle = vehicle,
                                        amount = saleAmount,
                                        date = date,
                                        buyerName = buyerName,
                                        buyerPhone = buyerPhone,
                                        paymentMethod = paymentMethod,
                                        account = selectedAccount,
                                        notes = notes,
                                        selectedClient = selectedClient,
                                        vatRefundPercent = vatRefundPercent
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
}

private data class DealDeskSaleRequest(
    val saleAmount: BigDecimal,
    val date: Date,
    val buyerName: String,
    val buyerPhone: String,
    val paymentMethod: String,
    val account: FinancialAccount?,
    val accountDepositAmount: BigDecimal,
    val notes: String,
    val client: Client?,
    val snapshot: DealDeskSnapshot
)

private data class PartSaleFormLine(
    val partId: UUID? = null,
    val quantityInput: String = "",
    val unitPriceInput: String = ""
)

@Composable
private fun SaleTypePicker(
    selectedKind: SaleEntryKind,
    onSelected: (SaleEntryKind) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SaleTypePickerButton(
            title = localizedUiString("Vehicle"),
            selected = selectedKind == SaleEntryKind.VEHICLE,
            onClick = { onSelected(SaleEntryKind.VEHICLE) },
            modifier = Modifier.weight(1f)
        )
        SaleTypePickerButton(
            title = localizedUiString("Parts"),
            selected = selectedKind == SaleEntryKind.PARTS,
            onClick = { onSelected(SaleEntryKind.PARTS) },
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun SaleTypePickerButton(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(42.dp),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) EzcarNavy else EzcarBackgroundLight,
            contentColor = if (selected) Color.White else EzcarNavy
        ),
        contentPadding = PaddingValues(horizontal = 10.dp)
    ) {
        Text(
            text = title,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun PartSaleFormContent(
    parts: List<Part>,
    batches: List<PartBatch>,
    accounts: List<FinancialAccount>,
    clients: List<Client>,
    dateFormatter: SimpleDateFormat,
    paymentMethods: List<String>,
    formatCurrency: (BigDecimal) -> String,
    onPickDate: (Date, (Date) -> Unit) -> Unit,
    onSavePartSale: suspend (
        saleDate: Date,
        accountId: UUID,
        lines: List<PartSaleLineDraft>,
        buyerName: String?,
        buyerPhone: String?,
        paymentMethod: String?,
        notes: String?,
        clientId: UUID?
    ) -> Boolean
) {
    val coroutineScope = rememberCoroutineScope()
    var saleDate by remember { mutableStateOf(Date()) }
    var selectedAccountId by remember { mutableStateOf<UUID?>(null) }
    var selectedClientId by remember { mutableStateOf<UUID?>(null) }
    var paymentMethod by remember { mutableStateOf("Cash") }
    var notes by remember { mutableStateOf("") }
    var paymentMenuExpanded by remember { mutableStateOf(false) }
    var clientMenuExpanded by remember { mutableStateOf(false) }
    var accountMenuExpanded by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var lineItems by remember {
        mutableStateOf(listOf(PartSaleFormLine()))
    }

    LaunchedEffect(accounts) {
        val currentStillExists = accounts.any { it.id == selectedAccountId }
        if (!currentStillExists) {
            selectedAccountId = accounts.firstOrNull { it.accountType.contains("cash", ignoreCase = true) }?.id
                ?: accounts.firstOrNull()?.id
        }
    }

    LaunchedEffect(parts) {
        if (lineItems.size == 1 && lineItems.first().partId == null && parts.isNotEmpty()) {
            lineItems = listOf(lineItems.first().copy(partId = parts.first().id))
        }
    }

    val selectedAccount = accounts.firstOrNull { it.id == selectedAccountId }
    val selectedClient = clients.firstOrNull { it.id == selectedClientId }
    val totalRevenue = lineItems.fold(BigDecimal.ZERO) { total, line ->
        val quantity = decimalFromSaleInput(line.quantityInput)
        val unitPrice = decimalFromSaleInput(line.unitPriceInput)
        total.add(quantity.multiply(unitPrice))
    }
    val requestedByPart = lineItems
        .filter { it.partId != null }
        .groupBy { it.partId!! }
        .mapValues { entry ->
            entry.value.fold(BigDecimal.ZERO) { total, line ->
                total.add(decimalFromSaleInput(line.quantityInput))
            }
        }
    val hasStockShortage = requestedByPart.any { (partId, requested) ->
        requested > partQuantityOnHand(partId, batches)
    }
    val validDrafts = lineItems.mapNotNull { line ->
        val partId = line.partId ?: return@mapNotNull null
        val quantity = decimalFromSaleInput(line.quantityInput)
        val unitPrice = decimalFromSaleInput(line.unitPriceInput)
        if (quantity > BigDecimal.ZERO && unitPrice > BigDecimal.ZERO) {
            PartSaleLineDraft(partId = partId, quantity = quantity, unitPrice = unitPrice)
        } else {
            null
        }
    }
    val canSave = selectedAccount != null &&
        parts.isNotEmpty() &&
        validDrafts.size == lineItems.size &&
        !hasStockShortage &&
        !isSaving

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        SaleSectionTitle("Sale Details")

        Card(
            colors = CardDefaults.cardColors(containerColor = Color.White),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SaleSelectorButton(
                    icon = Icons.Default.Today,
                    label = localizedUiString("Sale Date"),
                    value = dateFormatter.format(saleDate),
                    onClick = { onPickDate(saleDate) { saleDate = it } }
                )

                Box(modifier = Modifier.fillMaxWidth()) {
                    SaleSelectorButton(
                        icon = Icons.Default.Person,
                        label = localizedUiString("Client"),
                        value = selectedClient?.name ?: localizedUiString("Select Client"),
                        onClick = { clientMenuExpanded = true }
                    )
                    DropdownMenu(
                        expanded = clientMenuExpanded,
                        onDismissRequest = { clientMenuExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(localizedUiString("None")) },
                            onClick = {
                                selectedClientId = null
                                clientMenuExpanded = false
                            }
                        )
                        clients.forEach { client ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(client.name)
                                        client.phone?.takeIf { it.isNotBlank() }?.let { phone ->
                                            Text(phone, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                        }
                                    }
                                },
                                onClick = {
                                    selectedClientId = client.id
                                    clientMenuExpanded = false
                                }
                            )
                        }
                    }
                }

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

                Box(modifier = Modifier.fillMaxWidth()) {
                    SaleSelectorButton(
                        icon = Icons.Default.AccountBalance,
                        label = localizedUiString("Deposit To"),
                        value = selectedAccount?.accountType ?: localizedUiString("Select Account"),
                        onClick = { accountMenuExpanded = true }
                    )
                    DropdownMenu(
                        expanded = accountMenuExpanded,
                        onDismissRequest = { accountMenuExpanded = false }
                    ) {
                        accounts.forEach { account ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(account.accountType)
                                        Text(formatCurrency(account.balance), style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                    }
                                },
                                onClick = {
                                    selectedAccountId = account.id
                                    accountMenuExpanded = false
                                }
                            )
                        }
                    }
                }

                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text(localizedUiString("Notes")) },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                localizedUiString("Line Items"),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color.Gray
            )
            Spacer(modifier = Modifier.weight(1f))
            TextButton(
                onClick = {
                    lineItems = lineItems + PartSaleFormLine(partId = parts.firstOrNull()?.id)
                },
                enabled = parts.isNotEmpty()
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null)
                Spacer(modifier = Modifier.width(4.dp))
                Text(localizedUiString("Add Item"))
            }
        }

        if (parts.isEmpty()) {
            Text(
                text = localizedUiString("No parts found"),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.Gray,
                modifier = Modifier.fillMaxWidth()
            )
        } else {
            lineItems.forEachIndexed { index, line ->
                PartSaleLineCard(
                    line = line,
                    parts = parts,
                    batches = batches,
                    canRemove = lineItems.size > 1,
                    formatCurrency = formatCurrency,
                    onLineChanged = { updated ->
                        lineItems = lineItems.mapIndexed { itemIndex, item ->
                            if (itemIndex == index) updated else item
                        }
                    },
                    onRemove = {
                        lineItems = lineItems.filterIndexed { itemIndex, _ -> itemIndex != index }
                    }
                )
            }
        }

        Card(
            colors = CardDefaults.cardColors(containerColor = Color.White),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(localizedUiString("Total Revenue"), color = Color.Gray)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(formatCurrency(totalRevenue), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }

                if (hasStockShortage) {
                    Text(
                        text = localizedUiString("Not enough stock for some items."),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                errorMessage?.let { message ->
                    Text(
                        text = localizedUiString(message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }

        Button(
            onClick = {
                val accountId = selectedAccount?.id ?: return@Button
                coroutineScope.launch {
                    errorMessage = null
                    isSaving = true
                    val saved = onSavePartSale(
                        saleDate,
                        accountId,
                        validDrafts,
                        selectedClient?.name,
                        selectedClient?.phone,
                        paymentMethod,
                        notes.ifBlank { null },
                        selectedClientId
                    )
                    if (!saved) {
                        isSaving = false
                        errorMessage = "Could not save sale."
                    }
                }
            },
            enabled = canSave,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy),
            shape = RoundedCornerShape(16.dp)
        ) {
            if (isSaving) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = Color.White
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(localizedUiString("Save"), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun PartSaleLineCard(
    line: PartSaleFormLine,
    parts: List<Part>,
    batches: List<PartBatch>,
    canRemove: Boolean,
    formatCurrency: (BigDecimal) -> String,
    onLineChanged: (PartSaleFormLine) -> Unit,
    onRemove: () -> Unit
) {
    var partMenuExpanded by remember { mutableStateOf(false) }
    val selectedPart = parts.firstOrNull { it.id == line.partId }
    val quantity = decimalFromSaleInput(line.quantityInput)
    val unitPrice = decimalFromSaleInput(line.unitPriceInput)
    val subtotal = quantity.multiply(unitPrice)
    val available = selectedPart?.let { partQuantityOnHand(it.id, batches) } ?: BigDecimal.ZERO

    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    OutlinedButton(
                        onClick = { partMenuExpanded = true },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp)
                    ) {
                        Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                            Text(
                                text = selectedPart?.name ?: localizedUiString("Select Part"),
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (selectedPart != null) {
                                Text(
                                    text = localizedUiString("Available: %s", formatPartQuantity(available)),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (available > BigDecimal.ZERO) EzcarSuccess else MaterialTheme.colorScheme.error
                                )
                            }
                        }
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(
                        expanded = partMenuExpanded,
                        onDismissRequest = { partMenuExpanded = false }
                    ) {
                        parts.forEach { part ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(part.name)
                                        Text(
                                            localizedUiString("Available: %s", formatPartQuantity(partQuantityOnHand(part.id, batches))),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = Color.Gray
                                        )
                                    }
                                },
                                onClick = {
                                    onLineChanged(line.copy(partId = part.id))
                                    partMenuExpanded = false
                                }
                            )
                        }
                    }
                }

                if (canRemove) {
                    IconButton(onClick = onRemove) {
                        Icon(Icons.Default.Delete, contentDescription = localizedUiString("Remove"), tint = MaterialTheme.colorScheme.error)
                    }
                }
            }

            HorizontalDivider()

            Row(
                modifier = Modifier.padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = line.quantityInput,
                    onValueChange = { onLineChanged(line.copy(quantityInput = sanitizeSaleDecimalInput(it))) },
                    label = { Text(localizedUiString("Quantity")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f)
                )
                OutlinedTextField(
                    value = line.unitPriceInput,
                    onValueChange = { onLineChanged(line.copy(unitPriceInput = sanitizeSaleDecimalInput(it))) },
                    label = { Text(localizedUiString("Unit Price")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f)
                )
            }

            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(localizedUiString("Total"), color = Color.Gray)
                Spacer(modifier = Modifier.weight(1f))
                Text(formatCurrency(subtotal), fontWeight = FontWeight.SemiBold, color = EzcarNavy)
            }
        }
    }
}

@Composable
private fun DealDeskModeCard(
    useDealDesk: Boolean,
    onUseDealDeskChange: (Boolean) -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Calculate,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = localizedUiString("Deal Desk is on"),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                    Text(
                        text = localizedUiString("Use the same tax, fee and payment snapshot as iOS."),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { onUseDealDeskChange(true) },
                    enabled = !useDealDesk,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(localizedUiString("Use Deal Desk"), maxLines = 1)
                }

                OutlinedButton(
                    onClick = { onUseDealDeskChange(false) },
                    enabled = useDealDesk,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text(localizedUiString("Use classic sale"), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun DealDeskInfoCard(
    icon: ImageVector,
    title: String,
    message: String
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, contentDescription = null, tint = EzcarNavy)
            Spacer(modifier = Modifier.width(10.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun DealDeskSaleContent(
    vehicle: Vehicle,
    settings: DealDeskSettings,
    accounts: List<FinancialAccount>,
    clients: List<Client>,
    dateFormatter: SimpleDateFormat,
    onPickDate: (Date, (Date) -> Unit) -> Unit,
    formatCurrency: (BigDecimal) -> String,
    currencyCode: String,
    onSaveDealDeskSale: (DealDeskSaleRequest) -> Unit
) {
    val startingSalePrice = remember(vehicle.id) {
        vehicle.askingPrice ?: vehicle.salePrice ?: BigDecimal.ZERO
    }
    var salePriceInput by remember(vehicle.id, settings.defaultTemplateCode, settings.templateVersion) {
        mutableStateOf(initialSaleDecimalText(startingSalePrice))
    }
    var buyerName by remember(vehicle.id) { mutableStateOf("") }
    var buyerPhone by remember(vehicle.id) { mutableStateOf("") }
    var selectedClient by remember(vehicle.id) { mutableStateOf<Client?>(null) }
    var notes by remember(vehicle.id) { mutableStateOf("") }
    var saleDate by remember(vehicle.id) { mutableStateOf(Date()) }
    var selectedAccount by remember(vehicle.id) { mutableStateOf<FinancialAccount?>(null) }
    var paymentMethodCode by remember(vehicle.id) { mutableStateOf("cash") }
    var downPaymentInput by remember(vehicle.id, settings.defaultTemplateCode, settings.templateVersion) {
        mutableStateOf(initialSaleDecimalText(startingSalePrice))
    }
    var aprInput by remember(vehicle.id) { mutableStateOf("") }
    var termMonthsInput by remember(vehicle.id) { mutableStateOf("") }
    var jurisdictionCode by remember(settings.defaultTemplateCode) {
        mutableStateOf(DealDeskTemplateCatalog.defaultJurisdictionCode(settings.defaultTemplateCode))
    }
    var taxLines by remember(settings.defaultTemplateCode, settings.templateVersion, settings.taxOverrides) {
        mutableStateOf(settings.seededTaxLines)
    }
    var feeLines by remember(settings.defaultTemplateCode, settings.templateVersion, settings.feeOverrides) {
        mutableStateOf(settings.seededFeeLines)
    }
    var taxLineInputs by remember(settings.defaultTemplateCode, settings.templateVersion, settings.taxOverrides) {
        mutableStateOf(settings.seededTaxLines.map { initialSaleDecimalText(it.value) })
    }
    var feeLineInputs by remember(settings.defaultTemplateCode, settings.templateVersion, settings.feeOverrides) {
        mutableStateOf(settings.seededFeeLines.map { initialSaleDecimalText(it.value) })
    }
    var paymentMenuExpanded by remember { mutableStateOf(false) }
    var clientMenuExpanded by remember { mutableStateOf(false) }
    var accountMenuExpanded by remember { mutableStateOf(false) }
    var jurisdictionMenuExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(accounts) {
        if (selectedAccount == null && accounts.isNotEmpty()) {
            selectedAccount = accounts.firstOrNull { it.accountType.contains("cash", ignoreCase = true) }
                ?: accounts.first()
        }
    }

    val salePrice = decimalFromSaleInput(salePriceInput)
    val taxTotal = taxLines.fold(BigDecimal.ZERO) { total, line ->
        total.add(line.resolvedSaleAmount(salePrice))
    }
    val feeTotal = feeLines.fold(BigDecimal.ZERO) { total, line ->
        total.add(line.resolvedSaleAmount(salePrice))
    }
    val outTheDoorTotal = salePrice.add(taxTotal).add(feeTotal)
    val rawDownPayment = decimalFromSaleInput(downPaymentInput).coerceAtLeastZero()
    val dueToday = if (paymentMethodCode == "finance") {
        rawDownPayment.coerceAtMostValue(outTheDoorTotal)
    } else {
        outTheDoorTotal
    }
    val amountFinanced = if (paymentMethodCode == "finance") {
        outTheDoorTotal.subtract(dueToday).coerceAtLeastZero()
    } else {
        BigDecimal.ZERO
    }
    val monthlyEstimate = monthlyPaymentEstimate(
        principal = amountFinanced,
        aprPercent = optionalDecimalFromSaleInput(aprInput),
        termMonths = termMonthsInput.toIntOrNull()
    )
    val canSave = salePrice > BigDecimal.ZERO && buyerName.trim().isNotEmpty()
    val paymentOptions = remember {
        listOf("cash", "finance", "bank_transfer", "cheque", "other")
    }
    val jurisdictionOptions = remember(settings.defaultTemplateCode) {
        DealDeskTemplateCatalog.jurisdictionOptions(settings.defaultTemplateCode)
    }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        DealDeskSummaryGrid(
            outTheDoorTotal = outTheDoorTotal,
            dueToday = dueToday,
            amountFinanced = amountFinanced,
            monthlyEstimate = monthlyEstimate,
            formatCurrency = formatCurrency
        )

        DealDeskSection(title = localizedUiString("Price")) {
            if (settings.defaultTemplateCode.name.lowercase(Locale.US) != "generic") {
                Box(modifier = Modifier.fillMaxWidth()) {
                    SaleSelectorButton(
                        icon = Icons.Default.Place,
                        label = localizedUiString("Jurisdiction"),
                        value = jurisdictionOptions.firstOrNull { it.code == jurisdictionCode }?.title ?: jurisdictionCode,
                        onClick = { jurisdictionMenuExpanded = true }
                    )
                    DropdownMenu(
                        expanded = jurisdictionMenuExpanded,
                        onDismissRequest = { jurisdictionMenuExpanded = false }
                    ) {
                        jurisdictionOptions.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.title) },
                                onClick = {
                                    jurisdictionCode = option.code
                                    jurisdictionMenuExpanded = false
                                }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))
            }

            DealDeskTemplateCatalog.setupGuidanceMessage(
                templateCode = settings.defaultTemplateCode,
                taxLines = taxLines,
                feeLines = feeLines
            )?.let { message ->
                Text(
                    text = localizedUiString(message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(12.dp))
            }

            OutlinedTextField(
                value = salePriceInput,
                onValueChange = { salePriceInput = sanitizeSaleDecimalInput(it) },
                label = { Text(localizedUiString("Vehicle sale price (%s)", currencyCode)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(12.dp))

            SaleSelectorButton(
                icon = Icons.Default.Today,
                label = localizedUiString("Sale Date"),
                value = dateFormatter.format(saleDate),
                onClick = { onPickDate(saleDate) { saleDate = it } }
            )

            Spacer(modifier = Modifier.height(12.dp))

            Box(modifier = Modifier.fillMaxWidth()) {
                SaleSelectorButton(
                    icon = Icons.Default.Person,
                    label = localizedUiString("Client"),
                    value = selectedClient?.name ?: localizedUiString("New / Walk-in Client"),
                    onClick = { clientMenuExpanded = true }
                )
                DropdownMenu(
                    expanded = clientMenuExpanded,
                    onDismissRequest = { clientMenuExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(localizedUiString("New / Walk-in Client")) },
                        onClick = {
                            selectedClient = null
                            clientMenuExpanded = false
                        }
                    )
                    clients.forEach { client ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(client.name)
                                    Text(
                                        listOfNotNull(
                                            client.phone?.takeIf { it.isNotBlank() },
                                            client.email?.takeIf { it.isNotBlank() }
                                        ).joinToString(" · ").ifBlank { localizedUiString("No contact info") },
                                        style = MaterialTheme.typography.labelSmall,
                                        color = Color.Gray
                                    )
                                }
                            },
                            onClick = {
                                selectedClient = client
                                buyerName = client.name
                                buyerPhone = client.phone.orEmpty()
                                clientMenuExpanded = false
                            }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

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

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(localizedUiString("Notes")) },
                minLines = 2,
                maxLines = 4,
                modifier = Modifier.fillMaxWidth()
            )
        }

        if (taxLines.isNotEmpty()) {
            DealDeskSection(title = localizedUiString("Taxes")) {
                DealDeskEditableLines(
                    lines = taxLines,
                    inputs = taxLineInputs,
                    currencyCode = currencyCode,
                    onLineChanged = { index, input ->
                        taxLineInputs = taxLineInputs.updateInputValue(index, input)
                        taxLines = taxLines.updateLineValue(index, input)
                    }
                )
            }
        }

        if (feeLines.isNotEmpty()) {
            DealDeskSection(title = localizedUiString("Fees")) {
                DealDeskEditableLines(
                    lines = feeLines,
                    inputs = feeLineInputs,
                    currencyCode = currencyCode,
                    onLineChanged = { index, input ->
                        feeLineInputs = feeLineInputs.updateInputValue(index, input)
                        feeLines = feeLines.updateLineValue(index, input)
                    }
                )
            }
        }

        DealDeskSection(title = localizedUiString("Payments")) {
            Box(modifier = Modifier.fillMaxWidth()) {
                SaleSelectorButton(
                    icon = Icons.Default.CreditCard,
                    label = localizedUiString("Payment Method"),
                    value = localizedUiString(dealDeskPaymentMethodTitle(paymentMethodCode)),
                    onClick = { paymentMenuExpanded = true }
                )
                DropdownMenu(
                    expanded = paymentMenuExpanded,
                    onDismissRequest = { paymentMenuExpanded = false }
                ) {
                    paymentOptions.forEach { code ->
                        DropdownMenuItem(
                            text = { Text(localizedUiString(dealDeskPaymentMethodTitle(code))) },
                            onClick = {
                                paymentMethodCode = code
                                paymentMenuExpanded = false
                            }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Box(modifier = Modifier.fillMaxWidth()) {
                SaleSelectorButton(
                    icon = Icons.Default.AccountBalance,
                    label = localizedUiString("Deposit To"),
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
                    accounts.forEach { account ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(account.accountType)
                                    Text(
                                        formatCurrency(account.balance),
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

            if (paymentMethodCode == "finance") {
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = downPaymentInput,
                    onValueChange = { downPaymentInput = sanitizeSaleDecimalInput(it) },
                    label = { Text(localizedUiString("Down payment (%s)", currencyCode)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = aprInput,
                        onValueChange = { aprInput = sanitizeSaleDecimalInput(it) },
                        label = { Text(localizedUiString("APR %")) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        value = termMonthsInput,
                        onValueChange = { termMonthsInput = it.filter(Char::isDigit) },
                        label = { Text(localizedUiString("Term months")) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.weight(1f)
                    )
                }
            } else {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = localizedUiString("Full customer total is collected today."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Button(
            onClick = {
                val snapshot = DealDeskSnapshot(
                    templateCode = settings.defaultTemplateCode.rpcValue,
                    templateVersion = settings.templateVersion.coerceAtLeast(1),
                    jurisdictionType = DealDeskTemplateCatalog.defaultJurisdictionType(settings.defaultTemplateCode),
                    jurisdictionCode = jurisdictionCode,
                    taxLines = taxLines,
                    feeLines = feeLines,
                    paymentPlan = DealDeskPaymentPlan(
                        methodCode = paymentMethodCode,
                        downPayment = dueToday,
                        aprPercent = optionalDecimalFromSaleInput(aprInput),
                        termMonths = termMonthsInput.toIntOrNull()
                    ),
                    totals = DealDeskTotals(
                        salePrice = salePrice,
                        taxTotal = taxTotal,
                        feeTotal = feeTotal,
                        outTheDoorTotal = outTheDoorTotal,
                        cashReceivedNow = dueToday,
                        amountFinanced = amountFinanced,
                        monthlyPaymentEstimate = monthlyEstimate
                    )
                )
                onSaveDealDeskSale(
                    DealDeskSaleRequest(
                        saleAmount = salePrice,
                        date = saleDate,
                        buyerName = buyerName.trim(),
                        buyerPhone = buyerPhone.trim(),
                        paymentMethod = dealDeskPaymentMethodTitle(paymentMethodCode),
                        account = selectedAccount,
                        accountDepositAmount = dueToday,
                        notes = notes.trim(),
                        client = selectedClient,
                        snapshot = snapshot
                    )
                )
            },
            enabled = canSave,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy),
            shape = RoundedCornerShape(16.dp)
        ) {
            Text(localizedUiString("Save Deal Desk Sale"), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DealDeskSummaryGrid(
    outTheDoorTotal: BigDecimal,
    dueToday: BigDecimal,
    amountFinanced: BigDecimal,
    monthlyEstimate: BigDecimal?,
    formatCurrency: (BigDecimal) -> String
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            DealDeskSummaryMetric(
                label = localizedUiString("Out the door"),
                amount = formatCurrency(outTheDoorTotal),
                modifier = Modifier.weight(1f)
            )
            DealDeskSummaryMetric(
                label = localizedUiString("Due today"),
                amount = formatCurrency(dueToday),
                modifier = Modifier.weight(1f)
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            DealDeskSummaryMetric(
                label = localizedUiString("Financed"),
                amount = formatCurrency(amountFinanced),
                modifier = Modifier.weight(1f)
            )
            DealDeskSummaryMetric(
                label = localizedUiString("Monthly"),
                amount = monthlyEstimate?.let(formatCurrency) ?: "-",
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun DealDeskSummaryMetric(
    label: String,
    amount: String,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(14.dp),
        modifier = modifier
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = amount,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun DealDeskSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
            Spacer(modifier = Modifier.height(12.dp))
            content()
        }
    }
}

@Composable
private fun DealDeskEditableLines(
    lines: List<DealDeskLine>,
    inputs: List<String>,
    currencyCode: String,
    onLineChanged: (Int, String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        lines.forEachIndexed { index, line ->
            DealDeskLineRow(
                line = line,
                valueInput = inputs.getOrNull(index).orEmpty(),
                currencyCode = currencyCode,
                onValueChange = { input -> onLineChanged(index, input) }
            )
        }
    }
}

@Composable
private fun DealDeskLineRow(
    line: DealDeskLine,
    valueInput: String,
    currencyCode: String,
    onValueChange: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = localizedUiString(line.title),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = localizedUiString(line.calculationType.labelSource),
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray
            )
        }

        OutlinedTextField(
            value = valueInput,
            onValueChange = { onValueChange(sanitizeSaleDecimalInput(it)) },
            prefix = if (line.calculationType == DealDeskLineCalculationType.FIXED_AMOUNT) {
                { Text(currencyCode) }
            } else {
                null
            },
            suffix = if (line.calculationType == DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE) {
                { Text("%") }
            } else {
                null
            },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            singleLine = true,
            modifier = Modifier.widthIn(min = 132.dp, max = 156.dp)
        )
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

private fun sanitizeSaleDecimalInput(value: String): String {
    var result = ""
    var hasDecimalSeparator = false

    value.forEach { character ->
        when {
            character.isDigit() -> result += character
            character == '.' && !hasDecimalSeparator -> {
                hasDecimalSeparator = true
                result += character
            }
        }
    }

    return result
}

private fun initialSaleDecimalText(value: BigDecimal): String {
    return if (value.compareTo(BigDecimal.ZERO) == 0) {
        ""
    } else {
        value.stripTrailingZeros().toPlainString()
    }
}

private fun decimalFromSaleInput(value: String): BigDecimal {
    return value.toBigDecimalOrNull() ?: BigDecimal.ZERO
}

private fun optionalDecimalFromSaleInput(value: String): BigDecimal? {
    return value.toBigDecimalOrNull()
}

private fun calculateVatRefundAmount(saleAmount: BigDecimal, percent: BigDecimal?): BigDecimal {
    if (saleAmount <= BigDecimal.ZERO || percent == null || percent <= BigDecimal.ZERO) {
        return BigDecimal.ZERO
    }
    return saleAmount.multiply(percent).divide(BigDecimal("100"), 2, RoundingMode.HALF_UP)
}

private fun DealDeskLine.resolvedSaleAmount(salePrice: BigDecimal): BigDecimal {
    return when (calculationType) {
        DealDeskLineCalculationType.FIXED_AMOUNT -> value
        DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE -> salePrice
            .multiply(value)
            .divide(BigDecimal("100"))
    }
}

private fun List<DealDeskLine>.updateLineValue(index: Int, input: String): List<DealDeskLine> {
    if (index !in indices) return this
    return toMutableList().also { lines ->
        lines[index] = lines[index].copy(value = decimalFromSaleInput(input))
    }
}

private fun List<String>.updateInputValue(index: Int, input: String): List<String> {
    if (index !in indices) return this
    return toMutableList().also { values ->
        values[index] = input
    }
}

private fun BigDecimal.coerceAtLeastZero(): BigDecimal {
    return if (this < BigDecimal.ZERO) BigDecimal.ZERO else this
}

private fun BigDecimal.coerceAtMostValue(maximum: BigDecimal): BigDecimal {
    return if (this > maximum) maximum else this
}

private fun partQuantityOnHand(partId: UUID, batches: List<PartBatch>): BigDecimal {
    return batches
        .filter { it.partId == partId && it.deletedAt == null }
        .fold(BigDecimal.ZERO) { total, batch ->
            total.add(batch.quantityRemaining)
        }
}

private fun formatPartQuantity(value: BigDecimal): String {
    return value.stripTrailingZeros().toPlainString()
}

private fun monthlyPaymentEstimate(
    principal: BigDecimal,
    aprPercent: BigDecimal?,
    termMonths: Int?
): BigDecimal? {
    if (principal <= BigDecimal.ZERO || termMonths == null || termMonths <= 0 || aprPercent == null) {
        return null
    }

    val principalDouble = principal.toDouble()
    val monthlyRate = aprPercent.toDouble() / 1200.0
    val payment = if (monthlyRate == 0.0) {
        principalDouble / termMonths.toDouble()
    } else {
        val factor = (1.0 + monthlyRate).pow(termMonths.toDouble())
        principalDouble * monthlyRate * factor / (factor - 1.0)
    }
    return BigDecimal.valueOf(payment).setScale(2, RoundingMode.HALF_UP)
}

private fun dealDeskPaymentMethodTitle(methodCode: String): String {
    return when (methodCode) {
        "cash" -> "Cash"
        "finance" -> "Finance"
        "bank_transfer" -> "Bank Transfer"
        "cheque" -> "Cheque"
        else -> "Other"
    }
}
