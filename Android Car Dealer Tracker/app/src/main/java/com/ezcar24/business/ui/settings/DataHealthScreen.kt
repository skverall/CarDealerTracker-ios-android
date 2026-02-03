package com.ezcar24.business.ui.settings

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.sync.SyncEntityCount
import com.ezcar24.business.data.sync.SyncQueueSummaryItem
import com.ezcar24.business.ui.theme.EzcarBackground
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataHealthScreen(
    onBack: () -> Unit,
    viewModel: DataHealthViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val formatter = SimpleDateFormat("MMM d, yyyy HH:mm", Locale.getDefault())

    LaunchedEffect(Unit) {
        viewModel.runDiagnostics()
    }

    Scaffold(
        containerColor = EzcarBackground,
        topBar = {
            TopAppBar(
                title = { Text("Data Health") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.runDiagnostics() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
                Button(
                    onClick = { viewModel.runDiagnostics() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                ) {
                    Text(if (uiState.isRunning) "Running..." else "Run Diagnostics")
                }
            }

            if (uiState.errorMessage != null) {
                item {
                    Text(
                        text = uiState.errorMessage ?: "",
                        color = Color.Red,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            val report = uiState.report
            if (report != null) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = Color.White),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Summary", fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("Last Sync: ${report.lastSyncAt?.let { formatter.format(it) } ?: "Never"}")
                            Text("Queue: ${report.offlineQueueCount}")
                            Text("Syncing: ${if (report.isSyncing) "Yes" else "No"}")
                        }
                    }
                }

                if (report.offlineQueueSummary.isNotEmpty()) {
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = Color.White),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text("Offline Queue", fontWeight = FontWeight.Bold)
                                Spacer(modifier = Modifier.height(8.dp))
                                QueueSummaryList(report.offlineQueueSummary)
                            }
                        }
                    }
                }

                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = Color.White),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Entity Counts", fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.height(8.dp))
                            EntityCountsList(report.entityCounts)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun QueueSummaryList(items: List<SyncQueueSummaryItem>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { item ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("${item.entity.displayName} • ${item.operation.displayName}")
                Text(item.count.toString())
            }
        }
    }
}

@Composable
private fun EntityCountsList(items: List<SyncEntityCount>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { item ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(item.entity.displayName)
                    Text(
                        text = "Local ${item.localCount} • Remote ${item.remoteCount ?: "-"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.Gray
                    )
                }
                if (item.remoteCount != null) {
                    val delta = item.remoteCount - item.localCount
                    val deltaText = if (delta >= 0) "+$delta" else delta.toString()
                    Text(deltaText)
                }
            }
        }
    }
}
