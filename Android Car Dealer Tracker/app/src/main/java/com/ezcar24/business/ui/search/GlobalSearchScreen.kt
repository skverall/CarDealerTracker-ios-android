package com.ezcar24.business.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalSearchScreen(
    onBack: () -> Unit,
    onOpenVehicle: (String) -> Unit,
    onOpenClient: (String?) -> Unit,
    viewModel: GlobalSearchViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val dateFormatter = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text("Search") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackground)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
        ) {
            OutlinedTextField(
                value = uiState.query,
                onValueChange = viewModel::onQueryChanged,
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                placeholder = { Text("Search vehicles, clients, expenses") },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
            )

            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                if (uiState.vehicleResults.isNotEmpty()) {
                    item { SectionHeader(title = "Vehicles") }
                    items(uiState.vehicleResults) { vehicle ->
                        VehicleSearchRow(vehicle = vehicle, onClick = { onOpenVehicle(vehicle.id.toString()) })
                    }
                }

                if (uiState.clientResults.isNotEmpty()) {
                    item { SectionHeader(title = "Clients") }
                    items(uiState.clientResults) { client ->
                        ClientSearchRow(client = client, onClick = { onOpenClient(client.id.toString()) })
                    }
                }

                if (uiState.expenseResults.isNotEmpty()) {
                    item { SectionHeader(title = "Expenses") }
                    items(uiState.expenseResults) { expense ->
                        ExpenseSearchRow(
                            expense = expense,
                            dateFormatter = dateFormatter,
                            formatCurrency = regionSettingsManager::formatCurrency
                        )
                    }
                }

                if (uiState.query.isNotBlank() &&
                    uiState.vehicleResults.isEmpty() &&
                    uiState.clientResults.isEmpty() &&
                    uiState.expenseResults.isEmpty()
                ) {
                    item {
                        Text(
                            text = "No results",
                            modifier = Modifier.padding(top = 16.dp),
                            color = Color.Gray
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(vertical = 8.dp)
    )
}

@Composable
private fun VehicleSearchRow(vehicle: Vehicle, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
            Text("${vehicle.make ?: ""} ${vehicle.model ?: ""}".trim(), fontWeight = FontWeight.Bold)
            Text(vehicle.vin, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
        TextButtonInline(text = "Open", onClick = onClick)
    }
}

@Composable
private fun ClientSearchRow(client: Client, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
            Text(client.name, fontWeight = FontWeight.Bold)
            val subtitle = listOfNotNull(client.phone, client.email).joinToString(" • ")
            if (subtitle.isNotBlank()) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }
        TextButtonInline(text = "Open", onClick = onClick)
    }
}

@Composable
private fun ExpenseSearchRow(
    expense: Expense,
    dateFormatter: SimpleDateFormat,
    formatCurrency: (java.math.BigDecimal) -> String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
            Text(expense.expenseDescription ?: expense.category, fontWeight = FontWeight.Bold)
            Text(dateFormatter.format(expense.date), style = MaterialTheme.typography.bodySmall, color = Color.Gray)
        }
        Text(formatCurrency(expense.amount))
    }
}

@Composable
private fun TextButtonInline(text: String, onClick: () -> Unit) {
    androidx.compose.material3.TextButton(onClick = onClick) {
        Text(text)
    }
}
