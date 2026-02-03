package com.ezcar24.business.ui.settings

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.EzcarBackground
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupCenterScreen(
    onBack: () -> Unit,
    viewModel: BackupCenterViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var startDate by remember { mutableStateOf(Date()) }
    var endDate by remember { mutableStateOf(Date()) }
    var showStartPicker by remember { mutableStateOf(false) }
    var showEndPicker by remember { mutableStateOf(false) }
    val dateFormatter = remember { SimpleDateFormat("MMM d, yyyy", Locale.getDefault()) }

    LaunchedEffect(uiState.shareUri) {
        val uri = uiState.shareUri ?: return@LaunchedEffect
        val mimeType = uiState.shareMimeType ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Share File"))
        viewModel.clearShareUri()
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text("Backup & Export") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackground)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Quick Exports", fontWeight = FontWeight.Bold)
                        ExportButton(
                            title = "Export expenses CSV",
                            icon = Icons.Default.Receipt,
                            isLoading = uiState.isProcessing,
                            onClick = { viewModel.exportExpensesCsv() }
                        )
                        ExportButton(
                            title = "Export vehicles CSV",
                            icon = Icons.Default.DirectionsCar,
                            isLoading = uiState.isProcessing,
                            onClick = { viewModel.exportVehiclesCsv() }
                        )
                        ExportButton(
                            title = "Export clients CSV",
                            icon = Icons.Default.Person,
                            isLoading = uiState.isProcessing,
                            onClick = { viewModel.exportClientsCsv() }
                        )
                    }
                }
            }

            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Custom Range Report", fontWeight = FontWeight.Bold)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            DateField(
                                label = "Start",
                                value = dateFormatter.format(startDate),
                                onClick = { showStartPicker = true }
                            )
                            DateField(
                                label = "End",
                                value = dateFormatter.format(endDate),
                                onClick = { showEndPicker = true }
                            )
                        }
                        Button(
                            onClick = {
                                val normalizedStart = if (startDate.after(endDate)) endDate else startDate
                                val normalizedEnd = if (startDate.after(endDate)) startDate else endDate
                                viewModel.exportReportPdf(normalizedStart, normalizedEnd)
                            },
                            enabled = !uiState.isProcessing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 12.dp)
                                .height(44.dp)
                        ) {
                            Text("Generate PDF Report")
                        }
                    }
                }
            }

            if (uiState.message != null) {
                item {
                    Text(
                        text = uiState.message ?: "",
                        color = Color.Red,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Full Backup & Archive", fontWeight = FontWeight.Bold)
                        Button(
                            onClick = {
                                val normalizedStart = if (startDate.after(endDate)) endDate else startDate
                                val normalizedEnd = if (startDate.after(endDate)) startDate else endDate
                                viewModel.buildArchive(normalizedStart, normalizedEnd)
                            },
                            enabled = !uiState.isProcessing,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 12.dp)
                                .height(44.dp)
                        ) {
                            Text("Build JSON Archive")
                        }
                    }
                }
            }
        }
    }

    if (showStartPicker) {
        SimpleDatePickerDialog(
            onDismiss = { showStartPicker = false },
            onDateSelected = {
                startDate = it
                showStartPicker = false
            }
        )
    }

    if (showEndPicker) {
        SimpleDatePickerDialog(
            onDismiss = { showEndPicker = false },
            onDateSelected = {
                endDate = it
                showEndPicker = false
            }
        )
    }
}

@Composable
private fun ExportButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp)
            .height(44.dp),
        enabled = !isLoading
    ) {
        Icon(icon, contentDescription = null)
        Text(title, modifier = Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun DateField(
    label: String,
    value: String,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .padding(horizontal = 4.dp)
            .background(Color(0xFFF5F5F5), RoundedCornerShape(8.dp))
            .padding(12.dp)
            .clickable { onClick() }
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SimpleDatePickerDialog(
    onDismiss: () -> Unit,
    onDateSelected: (Date) -> Unit
) {
    val state = androidx.compose.material3.rememberDatePickerState()
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            androidx.compose.material3.TextButton(
                onClick = {
                    state.selectedDateMillis?.let { onDateSelected(Date(it)) }
                }
            ) {
                Text("OK")
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    ) {
        DatePicker(state = state)
    }
}
