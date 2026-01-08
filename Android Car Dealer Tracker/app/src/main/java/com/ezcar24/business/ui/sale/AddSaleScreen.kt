package com.ezcar24.business.ui.sale

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.theme.*
import com.ezcar24.business.util.*
import java.math.BigDecimal
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSaleScreen(
    onDismiss: () -> Unit,
    onSave: () -> Unit,
    viewModel: AddSaleViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    var amountStr by remember { mutableStateOf("") }
    var buyerName by remember { mutableStateOf("") }
    var buyerPhone by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var selectedVehicle by remember { mutableStateOf<Vehicle?>(null) }
    var selectedAccount by remember { mutableStateOf<FinancialAccount?>(null) }
    var paymentMethod by remember { mutableStateOf("Cash") }
    var date by remember { mutableStateOf(Date()) }

    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.fillMaxHeight(0.9f)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "New Sale",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Vehicle Selector
            if (selectedVehicle == null) {
                OutlinedButton(
                    onClick = { /* Open full list dialog? For now simple dropdown logic below */ },
                    modifier = Modifier.fillMaxWidth().height(60.dp),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Icon(Icons.Default.DirectionsCar, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Select Vehicle from Inventory")
                }
                
                // Show list of available vehicles immediately if none selected?
                Text("Available Vehicles:", style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 16.dp))
                LazyColumn(modifier = Modifier.height(200.dp)) {
                    items(uiState.availableVehicles.size) { i ->
                        val v = uiState.availableVehicles[i]
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedVehicle = v }
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.DirectionsCar, contentDescription = null, tint = EzcarNavy)
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text("${v.year} ${v.make} ${v.model}", fontWeight = FontWeight.Bold)
                                Text("VIN: ${v.vin}", style = MaterialTheme.typography.labelSmall)
                            }
                        }
                        HorizontalDivider()
                    }
                }
            } else {
                // Selected Vehicle Card
                Card(
                    colors = CardDefaults.cardColors(containerColor = EzcarBackgroundLight),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("SELECTED VEHICLE", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                            Text("${selectedVehicle?.make} ${selectedVehicle?.model}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        IconButton(onClick = { selectedVehicle = null }) {
                            Icon(Icons.Default.Close, contentDescription = "Change")
                        }
                    }
                }
                
                Spacer(modifier = Modifier.height(20.dp))
                
                // Sale Amount
                OutlinedTextField(
                    value = amountStr,
                    onValueChange = { amountStr = it },
                    label = { Text("Sale Price (AED)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Buyer Info
                OutlinedTextField(
                    value = buyerName,
                    onValueChange = { buyerName = it },
                    label = { Text("Buyer Name") },
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(12.dp))
                
                OutlinedTextField(
                    value = buyerPhone,
                    onValueChange = { buyerPhone = it },
                    label = { Text("Buyer Phone") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(24.dp))

                Button(
                    onClick = {
                         val amt = amountStr.toBigDecimalOrNull()
                         if (selectedVehicle != null && amt != null && buyerName.isNotBlank()) {
                             viewModel.saveSale(
                                 vehicle = selectedVehicle!!,
                                 amount = amt,
                                 date = date,
                                 buyerName = buyerName,
                                 buyerPhone = buyerPhone,
                                 paymentMethod = paymentMethod,
                                 account = selectedAccount
                             )
                             onSave()
                         }
                    },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = EzcarNavy),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text("Complete Sale", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
