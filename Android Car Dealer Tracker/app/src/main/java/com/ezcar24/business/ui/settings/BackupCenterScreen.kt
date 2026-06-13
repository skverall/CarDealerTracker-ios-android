package com.ezcar24.business.ui.settings

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.ui.theme.EzcarSurfaceMutedLight
import com.ezcar24.business.ui.theme.EzcarTextSecondaryLight
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.ezcar24.business.util.localizedUiString

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
        context.startActivity(Intent.createChooser(intent, context.localizedUiString("Share File")))
        viewModel.clearShareUri()
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text(localizedUiString("Backup & Export")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = localizedUiString("Back"))
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
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            item {
                BackupHeader()
            }

            item {
                BackupSection(title = "Quick Exports") {
                    ExportActionRow(
                        title = "Export expenses CSV",
                        icon = Icons.Default.Receipt,
                        color = EzcarBlueBright,
                        isLoading = uiState.isProcessing,
                        onClick = { viewModel.exportExpensesCsv() }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    ExportActionRow(
                        title = "Export vehicles CSV",
                        icon = Icons.Default.DirectionsCar,
                        color = EzcarPurple,
                        isLoading = uiState.isProcessing,
                        onClick = { viewModel.exportVehiclesCsv() }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 72.dp))
                    ExportActionRow(
                        title = "Export clients CSV",
                        icon = Icons.Default.Person,
                        color = EzcarOrange,
                        isLoading = uiState.isProcessing,
                        onClick = { viewModel.exportClientsCsv() }
                    )
                }
            }

            item {
                BackupSection(title = "Custom Range Report") {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            DateField(
                                label = "Start",
                                value = dateFormatter.format(startDate),
                                onClick = { showStartPicker = true },
                                modifier = Modifier.weight(1f)
                            )
                            DateField(
                                label = "End",
                                value = dateFormatter.format(endDate),
                                onClick = { showEndPicker = true },
                                modifier = Modifier.weight(1f)
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
                                .padding(top = 14.dp)
                                .height(48.dp)
                        ) {
                            if (uiState.isProcessing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                    color = Color.White
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                            } else {
                                Icon(Icons.Default.Description, contentDescription = null)
                                Spacer(modifier = Modifier.width(8.dp))
                            }
                            Text(localizedUiString("Generate PDF Report"))
                        }
                    }
                }
            }

            if (uiState.message != null) {
                item {
                    StatusMessageCard(message = uiState.message ?: "")
                }
            }

            item {
                BackupSection(title = "Full Backup & Archive") {
                    ExportActionRow(
                        title = "Build JSON Archive",
                        subtitle = "Includes CSVs + PDF Report",
                        icon = Icons.Default.CloudUpload,
                        color = EzcarGreen,
                        isLoading = uiState.isProcessing,
                        onClick = {
                            val normalizedStart = if (startDate.after(endDate)) endDate else startDate
                            val normalizedEnd = if (startDate.after(endDate)) startDate else endDate
                            viewModel.buildArchive(normalizedStart, normalizedEnd)
                        }
                    )
                    Text(
                        text = localizedUiString("Cloud backup runs when your business account is active."),
                        style = MaterialTheme.typography.bodySmall,
                        color = EzcarTextSecondaryLight,
                        modifier = Modifier.padding(start = 72.dp, end = 16.dp, bottom = 16.dp)
                    )
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
private fun BackupHeader() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Surface(
            modifier = Modifier.size(58.dp),
            shape = CircleShape,
            color = EzcarBlueBright.copy(alpha = 0.12f)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.CloudUpload,
                    contentDescription = null,
                    tint = EzcarBlueBright,
                    modifier = Modifier.size(30.dp)
                )
            }
        }

        Text(
            text = localizedUiString("Data Management"),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = localizedUiString("Create local backups, generate PDF reports, or archive your entire dataset to the cloud."),
            style = MaterialTheme.typography.bodyMedium,
            color = EzcarTextSecondaryLight,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 12.dp)
        )
    }
}

@Composable
private fun BackupSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = localizedUiString(title).uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = EzcarTextSecondaryLight,
            modifier = Modifier.padding(start = 8.dp)
        )
        Card(
            colors = CardDefaults.cardColors(containerColor = Color.White),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(content = content)
        }
    }
}

@Composable
private fun ExportActionRow(
    title: String,
    subtitle: String? = null,
    icon: ImageVector,
    color: Color,
    isLoading: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isLoading, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier.size(40.dp),
            shape = CircleShape,
            color = color.copy(alpha = 0.12f)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(20.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = localizedUiString(title),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium
            )
            if (subtitle != null) {
                Text(
                    text = localizedUiString(subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = EzcarTextSecondaryLight
                )
            }
        }

        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp
            )
        } else {
            Icon(
                imageVector = Icons.Default.Share,
                contentDescription = null,
                tint = EzcarTextSecondaryLight,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun DateField(
    label: String,
    value: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .height(64.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(10.dp),
        color = EzcarSurfaceMutedLight
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Text(localizedUiString(label), style = MaterialTheme.typography.labelSmall, color = EzcarTextSecondaryLight)
            Text(value, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun StatusMessageCard(message: String) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = localizedUiString(message),
            color = Color.Red,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(14.dp)
        )
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
                Text(localizedUiString("OK"))
            }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) }
        }
    ) {
        DatePicker(state = state)
    }
}
