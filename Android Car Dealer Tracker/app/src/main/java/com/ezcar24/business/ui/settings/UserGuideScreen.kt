package com.ezcar24.business.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private data class GuideSection(
    val title: String,
    val bullets: List<String>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserGuideScreen(onBack: () -> Unit) {
    val sections = listOf(
        GuideSection(
            title = "Dashboard",
            bullets = listOf(
                "Track cash, revenue, profit and active inventory from one place.",
                "Use range chips to switch from today to all-time analytics.",
                "Run manual sync when Android data feels behind the iOS app."
            )
        ),
        GuideSection(
            title = "Vehicles",
            bullets = listOf(
                "Inventory and sold vehicles live in the same list with fast filters.",
                "Swipe vehicles to delete or mark them as sold.",
                "Open a vehicle to review total cost, expenses and sale performance."
            )
        ),
        GuideSection(
            title = "Management",
            bullets = listOf(
                "Financial Accounts keeps account balances aligned with sales and expenses.",
                "Backup & Export is the recovery point for snapshots and reports.",
                "Data Health is the first stop if sync or duplicate issues appear."
            )
        ),
        GuideSection(
            title = "Support",
            bullets = listOf(
                "Use Contact Developer from Account for sync or subscription issues.",
                "Privacy Policy and Terms of Use are available from the Legal section."
            )
        )
    )

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("User Guide") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            sections.forEach { section ->
                item {
                    Surface(
                        color = MaterialTheme.colorScheme.surface,
                        shape = RoundedCornerShape(22.dp),
                        shadowElevation = 8.dp,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier.padding(18.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Text(
                                text = section.title,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                            )
                            section.bullets.forEach { bullet ->
                                Text(
                                    text = "\u2022 $bullet",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
