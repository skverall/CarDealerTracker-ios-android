package com.ezcar24.business.ui.vehicle

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.SubcomposeAsyncImage
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.ui.components.*
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import java.math.BigDecimal
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VehicleDetailScreen(
    vehicleId: String,
    onBack: () -> Unit,
    onEdit: (String) -> Unit,
    viewModel: VehicleViewModel = hiltViewModel()
) {
    LaunchedEffect(vehicleId) {
        viewModel.selectVehicle(vehicleId)
    }

    val uiState by viewModel.uiState.collectAsState()
    val detailState by viewModel.detailUiState.collectAsState()
    val vehicle = detailState.vehicle
    var showDeleteDialog by remember { mutableStateOf(false) }
    val shareScope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vehicle Details") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (vehicle != null) {
                        TextButton(onClick = { onEdit(vehicle.id.toString()) }) {
                            Text("Edit", color = EzcarGreen, fontWeight = FontWeight.SemiBold)
                        }
                        val context = androidx.compose.ui.platform.LocalContext.current
                        IconButton(onClick = {
                            shareScope.launch {
                                val shareLink = viewModel.createVehicleShareLink(vehicle.id)
                                var shareText = "Check out this vehicle: ${vehicle.make} ${vehicle.model} ${vehicle.year}\nPrice: ${formatCurrency(vehicle.salePrice ?: vehicle.askingPrice ?: vehicle.purchasePrice)}"
                                if (!shareLink.isNullOrBlank()) {
                                    shareText += "\n\nView all photos: $shareLink"
                                }
                                val sendIntent = android.content.Intent().apply {
                                    action = android.content.Intent.ACTION_SEND
                                    putExtra(android.content.Intent.EXTRA_TEXT, shareText)
                                    type = "text/plain"
                                }
                                val shareIntent = android.content.Intent.createChooser(sendIntent, null)
                                context.startActivity(shareIntent)
                            }
                        }) {
                            Icon(Icons.Default.Share, contentDescription = "Share", tint = EzcarGreen)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        },
        containerColor = EzcarBackgroundLight
    ) { paddingValues ->
        if (detailState.isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = EzcarGreen)
            }
        } else if (vehicle == null) {
            Box(Modifier.fillMaxSize().padding(paddingValues), contentAlignment = Alignment.Center) {
                Text("Vehicle not found", style = MaterialTheme.typography.bodyLarge)
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                VehiclePhotoSection(
                    vehicleId = vehicle.id,
                    photoUrls = detailState.photoUrls
                )

                VehicleHeaderCard(vehicle = vehicle, detailState = detailState)

                if (detailState.alerts.isNotEmpty()) {
                    InventoryAlertList(alerts = detailState.alerts)
                }

                FinancialSummaryCard(
                    data = FinancialSummaryData(
                        purchasePrice = detailState.financialSummary.purchasePrice,
                        totalExpenses = detailState.financialSummary.totalExpenses,
                        holdingCost = detailState.financialSummary.holdingCost,
                        totalCost = detailState.financialSummary.totalCost,
                        expenseBreakdown = detailState.financialSummary.expenseBreakdown,
                        askingPrice = vehicle.askingPrice,
                        salePrice = vehicle.salePrice,
                        projectedROI = detailState.financialSummary.projectedROI,
                        actualROI = detailState.financialSummary.actualROI,
                        daysInInventory = detailState.inventoryStats?.daysInInventory ?: 0,
                        agingBucket = detailState.inventoryStats?.agingBucket ?: "0-30"
                    ),
                    onEditAskingPrice = if (vehicle.status != "sold") {
                        { viewModel.updateAskingPrice(detailState.financialSummary.recommendedPrice) }
                    } else null
                )

                if (vehicle.status != "sold") {
                    RecommendedPricingCard(
                        breakEvenPrice = detailState.financialSummary.breakEvenPrice,
                        recommendedPrice = detailState.financialSummary.recommendedPrice,
                        currentAskingPrice = vehicle.askingPrice,
                        onUpdateAskingPrice = { newPrice ->
                            viewModel.updateAskingPrice(newPrice)
                        }
                    )

                    if (detailState.financialSummary.holdingCost > BigDecimal.ZERO) {
                        HoldingCostCard(
                            holdingCost = detailState.financialSummary.holdingCost,
                            totalCost = detailState.financialSummary.totalCost,
                            dailyRate = detailState.financialSummary.dailyHoldingCost,
                            daysInInventory = detailState.inventoryStats?.daysInInventory ?: 0
                        )
                    }
                }

                ExpensesSection(
                    expenses = detailState.expenses,
                    totalExpenses = detailState.financialSummary.totalExpenses
                )

                OutlinedButton(
                    onClick = { showDeleteDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.Red),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color.Red)
                ) {
                    Icon(Icons.Default.Delete, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Delete Vehicle")
                }

                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }

    if (showDeleteDialog && vehicle != null) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete Vehicle?") },
            text = { Text("This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteVehicle(vehicle.id)
                        showDeleteDialog = false
                        onBack()
                    }
                ) {
                    Text("Delete", color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun VehiclePhotoSection(vehicleId: java.util.UUID, photoUrls: List<String>) {
    val primaryUrl = photoUrls.firstOrNull() ?: CloudSyncEnvironment.vehicleImageUrl(vehicleId)

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFE0E0E0)),
            contentAlignment = Alignment.Center
        ) {
            if (primaryUrl != null) {
                SubcomposeAsyncImage(
                    model = primaryUrl,
                    contentDescription = "Vehicle Photo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    error = {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.DirectionsCar,
                                contentDescription = null,
                                modifier = Modifier.size(64.dp),
                                tint = Color.Gray
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("No photo available", color = Color.Gray)
                        }
                    },
                    loading = {
                        CircularProgressIndicator(color = EzcarGreen, modifier = Modifier.size(32.dp))
                    }
                )
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.DirectionsCar,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = Color.Gray
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Tap Edit to add photo", color = Color.Gray)
                }
            }
        }

        if (photoUrls.size > 1) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                photoUrls.forEach { url ->
                    SubcomposeAsyncImage(
                        model = url,
                        contentDescription = "Vehicle Photo",
                        modifier = Modifier
                            .size(width = 120.dp, height = 80.dp)
                            .clip(RoundedCornerShape(10.dp)),
                        contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                        loading = {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = EzcarGreen, strokeWidth = 2.dp)
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun VehicleHeaderCard(
    vehicle: com.ezcar24.business.data.local.Vehicle,
    detailState: VehicleDetailUiState
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "${vehicle.make ?: ""} ${vehicle.model ?: ""}".trim().ifEmpty { "Vehicle" },
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Year: ${vehicle.year ?: "N/A"}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    VehicleStatusBadge(status = vehicle.status)
                    detailState.inventoryStats?.let { stats ->
                        AgingBucketBadge(daysInInventory = stats.daysInInventory)
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("VIN:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                Text(vehicle.vin, fontWeight = FontWeight.Medium)
            }

            Spacer(modifier = Modifier.height(4.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Purchase Date:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                Text(
                    SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(vehicle.purchaseDate),
                    fontWeight = FontWeight.Medium
                )
            }

            detailState.inventoryStats?.let { stats ->
                Spacer(modifier = Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Days in Inventory:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "${stats.daysInInventory} days (${stats.agingBucket})",
                        fontWeight = FontWeight.Medium,
                        color = when (stats.agingBucket) {
                            "0-30" -> EzcarGreen
                            "31-60" -> EzcarWarning
                            "61-90" -> EzcarOrange
                            else -> EzcarDanger
                        }
                    )
                }
            }

            if (!vehicle.notes.isNullOrBlank()) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))
                Text("Notes", style = MaterialTheme.typography.labelMedium, color = Color.Gray)
                Spacer(modifier = Modifier.height(4.dp))
                Text(vehicle.notes, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun ExpensesSection(
    expenses: List<com.ezcar24.business.data.local.Expense>,
    totalExpenses: BigDecimal
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Expenses (${expenses.size})",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    formatCurrency(totalExpenses),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarOrange
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (expenses.isEmpty()) {
                Text(
                    "No expenses recorded for this vehicle",
                    color = Color.Gray,
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                expenses.take(5).forEach { expense ->
                    ExpenseRow(expense = expense)
                    if (expense != expenses.take(5).last()) {
                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 8.dp),
                            color = Color(0xFFE5E5EA)
                        )
                    }
                }

                if (expenses.size > 5) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "+${expenses.size - 5} more expenses",
                        color = Color.Gray,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    )
                }
            }
        }
    }
}

@Composable
private fun ExpenseRow(expense: com.ezcar24.business.data.local.Expense) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = expense.expenseDescription ?: expense.category,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(expense.date),
                style = MaterialTheme.typography.bodySmall,
                color = Color.Gray
            )
        }
        Text(
            text = formatCurrency(expense.amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun VehicleStatusBadge(status: String) {
    val (text, color) = when (status) {
        "owned" -> "Owned" to Color.Gray
        "on_sale" -> "On Sale" to EzcarGreen
        "in_transit" -> "In Transit" to EzcarPurple
        "under_service" -> "Service" to EzcarOrange
        "sold" -> "Sold" to EzcarBlueBright
        else -> status.replaceFirstChar { it.uppercase() } to EzcarGreen
    }

    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}

@Composable
fun FinancialDetailRow(
    label: String,
    amount: BigDecimal?,
    color: Color = Color.Black,
    isBold: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            color = if (isBold) Color.Black else Color.Gray,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            text = formatCurrency(amount),
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium,
            color = color
        )
    }
}

@Composable
fun FinancialDetailRow(
    label: String,
    value: String,
    color: Color = Color.Black,
    isBold: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            label,
            color = if (isBold) Color.Black else Color.Gray,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            text = value,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Medium,
            color = color
        )
    }
}

private fun formatCurrency(amount: BigDecimal?): String {
    return amount?.let {
        NumberFormat.getCurrencyInstance(Locale.US).format(it).replace("$", "AED ")
    } ?: "-"
}
