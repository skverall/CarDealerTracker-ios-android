package com.ezcar24.business.ui.vehicle

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.*
import java.math.BigDecimal
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
    val vehicle = uiState.selectedVehicle
    var showDeleteDialog by remember { mutableStateOf(false) }

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
                        // Edit Button
                        TextButton(onClick = { onEdit(vehicle.id.toString()) }) {
                            Text("Edit", color = EzcarGreen, fontWeight = FontWeight.SemiBold)
                        }
                        // Share Button
                        val context = androidx.compose.ui.platform.LocalContext.current
                        IconButton(onClick = {
                            val shareText = "Check out this vehicle: ${vehicle.make} ${vehicle.model} ${vehicle.year}\nPrice: ${formatCurrency(vehicle.salePrice ?: vehicle.askingPrice ?: vehicle.purchasePrice)}"
                            val sendIntent = android.content.Intent().apply {
                                action = android.content.Intent.ACTION_SEND
                                putExtra(android.content.Intent.EXTRA_TEXT, shareText)
                                type = "text/plain"
                            }
                            val shareIntent = android.content.Intent.createChooser(sendIntent, null)
                            context.startActivity(shareIntent)
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
        if (uiState.isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = EzcarGreen)
            }
        } else if (vehicle == null) {
            Box(Modifier.fillMaxSize().padding(paddingValues), contentAlignment = Alignment.Center) {
                Text("Vehicle not found", style = MaterialTheme.typography.bodyLarge)
            }
        } else {
            val totalExpenses = BigDecimal.ZERO // TODO: Get from ViewModel
            val totalCost = vehicle.purchasePrice.add(totalExpenses)
            val profit = vehicle.salePrice?.subtract(totalCost)

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Photo Section with AsyncImage
                val imageUrl = vehicle.photoUrl ?: com.ezcar24.business.data.sync.CloudSyncEnvironment.vehicleImageUrl(vehicle.id)
                
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFFE0E0E0)),
                    contentAlignment = Alignment.Center
                ) {
                    if (imageUrl != null) {
                        coil.compose.SubcomposeAsyncImage(
                            model = imageUrl,
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

                // Vehicle Header Card
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
                            VehicleStatusBadge(status = vehicle.status)
                        }

                        HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))

                        // VIN
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("VIN:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                            Text(vehicle.vin, fontWeight = FontWeight.Medium)
                        }

                        Spacer(modifier = Modifier.height(4.dp))

                        // Purchase Date
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Purchase Date:", color = Color.Gray, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(vehicle.purchaseDate),
                                fontWeight = FontWeight.Medium
                            )
                        }

                        // Notes
                        if (!vehicle.notes.isNullOrBlank()) {
                            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp), color = Color(0xFFE5E5EA))
                            Text("Notes", style = MaterialTheme.typography.labelMedium, color = Color.Gray)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(vehicle.notes!!, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }

                // Financial Summary Card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Financial Summary",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(12.dp))

                        FinancialDetailRow("Purchase Price", vehicle.purchasePrice)

                        if (vehicle.askingPrice != null && vehicle.askingPrice > BigDecimal.ZERO) {
                            FinancialDetailRow("Asking Price", vehicle.askingPrice, color = EzcarGreen)
                        }

                        FinancialDetailRow("Total Expenses", totalExpenses, color = EzcarOrange)

                        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp), color = Color(0xFFE5E5EA))

                        FinancialDetailRow("Total Cost", totalCost, isBold = true, color = EzcarGreen)

                        // Sale details if sold
                        if (vehicle.status == "sold" && vehicle.salePrice != null) {
                            Spacer(modifier = Modifier.height(8.dp))
                            FinancialDetailRow("Sale Price", vehicle.salePrice, color = EzcarGreen)
                            
                            if (vehicle.saleDate != null) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("Sale Date", color = Color.Gray)
                                    Text(SimpleDateFormat("MMM dd, yyyy", Locale.getDefault()).format(vehicle.saleDate))
                                }
                            }

                            if (!vehicle.buyerName.isNullOrBlank()) {
                                FinancialDetailRow("Buyer", vehicle.buyerName, color = Color.Black)
                            }
                            if (!vehicle.buyerPhone.isNullOrBlank()) {
                                FinancialDetailRow("Phone", vehicle.buyerPhone, color = Color.Gray)
                            }
                            if (!vehicle.paymentMethod.isNullOrBlank()) {
                                FinancialDetailRow("Payment", vehicle.paymentMethod, color = Color.Gray)
                            }

                            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp), color = Color(0xFFE5E5EA))

                            if (profit != null) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text("Profit/Loss", fontWeight = FontWeight.Bold)
                                    Text(
                                        text = formatCurrency(profit),
                                        fontWeight = FontWeight.Bold,
                                        color = if (profit >= BigDecimal.ZERO) EzcarGreen else Color.Red
                                    )
                                }
                            }
                        }
                    }
                }

                // Expenses Section (placeholder)
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Expenses (0)",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            "No expenses recorded for this vehicle",
                            color = Color.Gray,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }

                // Delete Button
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

    // Delete Confirmation Dialog
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
