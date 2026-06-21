package com.ezcar24.business.ui.parts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.border
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Surface
import androidx.compose.material3.IconButton
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardType
import com.ezcar24.business.util.AppLanguage
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.FinancialAccount
import com.ezcar24.business.data.local.Part
import com.ezcar24.business.ui.theme.EzcarBackground
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.util.rememberRegionSettingsManager
import com.ezcar24.business.util.toBigDecimalOrZero
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.launch
import com.ezcar24.business.util.localizedUiString

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PartsDashboardScreen(
    inventoryViewModel: PartsInventoryViewModel = hiltViewModel(),
    salesViewModel: PartSalesViewModel = hiltViewModel()
) {
    val scope = rememberCoroutineScope()
    val inventoryState by inventoryViewModel.uiState.collectAsState()
    val salesState by salesViewModel.uiState.collectAsState()
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var selectedTab by remember { mutableStateOf(0) }
    var showAddPartDialog by remember { mutableStateOf(false) }
    var showReceiveStockDialog by remember { mutableStateOf(false) }
    var showAddSaleDialog by remember { mutableStateOf(false) }
    var selectedPartDetail by remember { mutableStateOf<PartInventoryItem?>(null) }
    var preferredReceiveStockPartId by remember { mutableStateOf<UUID?>(null) }
    var preferredSalePartId by remember { mutableStateOf<UUID?>(null) }

    Scaffold(
        containerColor = EzcarBackground,
        floatingActionButton = {
            var showFabMenu by remember { mutableStateOf(false) }
            Box(contentAlignment = Alignment.BottomEnd) {
                FloatingActionButton(
                    onClick = {
                        if (selectedTab == 0) {
                            showFabMenu = true
                        } else {
                            showAddSaleDialog = true
                        }
                    },
                    containerColor = EzcarNavy,
                    contentColor = Color.White
                ) {
                    Icon(Icons.Default.Add, contentDescription = localizedUiString("Add"))
                }

                DropdownMenu(
                    expanded = showFabMenu,
                    onDismissRequest = { showFabMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(localizedUiString("Add Part")) },
                        leadingIcon = { Icon(Icons.Default.Add, null) },
                        onClick = {
                            showAddPartDialog = true
                            showFabMenu = false
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(localizedUiString("Receive Stock")) },
                        leadingIcon = { Icon(Icons.Default.AllInbox, null) },
                        onClick = {
                            showReceiveStockDialog = true
                            showFabMenu = false
                        }
                    )
                }
            }
        }
    ) { padding ->
        val totalValue = inventoryState.parts.fold(BigDecimal.ZERO) { total, item -> total + item.inventoryValue }
        val lowStockCount = inventoryState.parts.count { it.quantityOnHand <= BigDecimal("2") }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(EzcarBackground),
            contentPadding = PaddingValues(bottom = 100.dp)
        ) {
            // 1. Title
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(EzcarBackground)
                        .statusBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                ) {
                    Text(
                        text = localizedUiString("Parts"),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                }
            }

            // 2. Tab Switcher
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(Color.White)
                        .border(1.dp, EzcarNavy.copy(alpha = 0.08f), RoundedCornerShape(24.dp))
                        .padding(4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    val tabs = listOf(localizedUiString("Inventory"), localizedUiString("Sales"))
                    tabs.forEachIndexed { index, title ->
                        val isSelected = selectedTab == index
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(20.dp))
                                .background(if (isSelected) EzcarNavy else Color.Transparent)
                                .clickable { selectedTab = index }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = title,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else Color.Gray,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }
            }

            // 3. Search Bar
            item {
                val searchQuery = if (selectedTab == 0) inventoryState.searchQuery else salesState.searchQuery
                val onSearchQueryChanged: (String) -> Unit = {
                    if (selectedTab == 0) {
                        inventoryViewModel.onSearchQueryChanged(it)
                    } else {
                        salesViewModel.onSearchQueryChanged(it)
                    }
                }

                TextField(
                    value = searchQuery,
                    onValueChange = onSearchQueryChanged,
                    leadingIcon = {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = null,
                            tint = Color.Gray
                        )
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = localizedUiString("Clear"),
                                tint = Color.Gray,
                                modifier = Modifier.clickable { onSearchQueryChanged("") }
                            )
                        }
                    },
                    placeholder = {
                        Text(
                            text = localizedUiString(if (selectedTab == 0) "Search parts" else "Search sales"),
                            color = Color.Gray.copy(alpha = 0.8f)
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .border(0.5.dp, Color.Gray.copy(alpha = 0.1f), RoundedCornerShape(12.dp)),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.White,
                        unfocusedContainerColor = Color.White,
                        disabledContainerColor = Color.White,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent
                    ),
                    singleLine = true
                )
            }

            // 4. Stats cards
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    PartsStatsCard(
                        title = localizedUiString("Total Value"),
                        value = regionSettingsManager.formatCurrencyCompact(totalValue),
                        icon = Icons.Default.AllInbox,
                        gradientColors = listOf(Color(0xFF1A263D), Color(0xFF0C1324))
                    )
                    PartsStatsCard(
                        title = localizedUiString("Low Stock"),
                        value = lowStockCount.toString(),
                        icon = Icons.Default.Warning,
                        gradientColors = if (lowStockCount > 0) {
                            listOf(Color(0xFFFF5252), Color(0xFFFF7A00))
                        } else {
                            listOf(Color(0xFF8E8E93), Color(0xFFC7C7CC))
                        }
                    )
                    PartsStatsCard(
                        title = localizedUiString("Parts"),
                        value = inventoryState.parts.size.toString(),
                        icon = Icons.Default.Tag,
                        gradientColors = listOf(Color(0xFF8940FF), Color(0xFFB57AFF))
                    )
                }
            }

            if (selectedTab == 0) {
                // 5. Category Filters & Low Stock Toggle
                item {
                    Row(
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CategoryFilter(
                            categories = inventoryState.categories,
                            selectedCategory = inventoryState.selectedCategory,
                            onSelected = { inventoryViewModel.setCategory(it) }
                        )
                        LowStockToggle(
                            enabled = inventoryState.showLowStockOnly,
                            onToggle = { inventoryViewModel.toggleLowStockOnly(it) }
                        )
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                }

                // 6. Grouped Parts list
                val groupedParts = inventoryState.filteredParts.groupBy { item ->
                    val cat = item.part.category?.trim() ?: ""
                    if (cat.isEmpty()) "__uncategorized" else cat
                }.toList().sortedBy { (cat, _) ->
                    if (cat == "__uncategorized") "Uncategorized" else cat
                }

                if (groupedParts.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(text = localizedUiString("No parts found"), color = Color.Gray)
                        }
                    }
                } else {
                    groupedParts.forEach { (category, items) ->
                        item {
                            CategoryHeader(category = category, count = items.size)
                        }
                        item {
                            Card(
                                modifier = Modifier
                                    .padding(horizontal = 16.dp, vertical = 4.dp)
                                    .fillMaxWidth(),
                                shape = RoundedCornerShape(16.dp),
                                colors = CardDefaults.cardColors(containerColor = Color.White),
                                border = BorderStroke(0.5.dp, Color.Gray.copy(alpha = 0.08f)),
                                elevation = CardDefaults.cardElevation(2.dp)
                            ) {
                                Column {
                                    items.forEachIndexed { index, item ->
                                        PartRowNew(
                                            item = item,
                                            formatCurrency = regionSettingsManager::formatCurrency,
                                            onClick = { selectedPartDetail = item }
                                        )
                                        if (index < items.size - 1) {
                                            HorizontalDivider(
                                                color = Color.Gray.copy(alpha = 0.1f),
                                                thickness = 0.5.dp,
                                                modifier = Modifier.padding(horizontal = 16.dp)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // Sales Tab content
                item {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                val sales = salesState.filteredSales.ifEmpty { salesState.sales }
                if (sales.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(text = localizedUiString("No sales found"), color = Color.Gray)
                        }
                    }
                } else {
                    item {
                        Card(
                            modifier = Modifier
                                .padding(horizontal = 16.dp)
                                .fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.White),
                            border = BorderStroke(0.5.dp, Color.Gray.copy(alpha = 0.08f)),
                            elevation = CardDefaults.cardElevation(2.dp)
                        ) {
                            Column {
                                sales.forEachIndexed { index, item ->
                                    PartSaleRowNew(
                                        item = item,
                                        formatCurrency = regionSettingsManager::formatCurrency,
                                        onDelete = { salesViewModel.deleteSale(item.sale) }
                                    )
                                    if (index < sales.size - 1) {
                                        HorizontalDivider(
                                            color = Color.Gray.copy(alpha = 0.1f),
                                            thickness = 0.5.dp,
                                            modifier = Modifier.padding(horizontal = 16.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAddPartDialog) {
        AddPartDialog(
            accounts = inventoryState.accounts,
            onDismiss = { showAddPartDialog = false },
            onSave = { name, code, category, notes, addInitialStock, quantity, unitCost, batchLabel, accountId ->
                inventoryViewModel.addPart(
                    name = name,
                    code = code,
                    category = category,
                    notes = notes,
                    addInitialStock = addInitialStock,
                    initialQuantity = quantity,
                    unitCost = unitCost,
                    batchLabel = batchLabel,
                    selectedAccountId = accountId
                )
                showAddPartDialog = false
            }
        )
    }

    if (showReceiveStockDialog) {
        ReceiveStockDialog(
            parts = inventoryState.parts.map { it.part },
            accounts = inventoryState.accounts,
            preferredPartId = preferredReceiveStockPartId,
            onDismiss = {
                preferredReceiveStockPartId = null
                showReceiveStockDialog = false
            },
            onSave = { partId, quantity, unitCost, batchLabel, notes, purchaseDate, accountId ->
                inventoryViewModel.receiveStock(
                    partId = partId,
                    quantity = quantity,
                    unitCost = unitCost,
                    batchLabel = batchLabel,
                    notes = notes,
                    purchaseDate = purchaseDate,
                    selectedAccountId = accountId
                )
                preferredReceiveStockPartId = null
                showReceiveStockDialog = false
            }
        )
    }

    if (showAddSaleDialog) {
        AddPartSaleDialog(
            parts = salesState.parts,
            accounts = salesState.accounts,
            clients = salesState.clients,
            preferredPartId = preferredSalePartId,
            onDismiss = {
                preferredSalePartId = null
                showAddSaleDialog = false
            },
            onSave = { saleDate, accountId, lines, buyerName, buyerPhone, paymentMethod, notes, clientId ->
                scope.launch {
                    val success = salesViewModel.createSale(
                        saleDate = saleDate,
                        selectedAccountId = accountId,
                        lineItems = lines,
                        buyerName = buyerName,
                        buyerPhone = buyerPhone,
                        paymentMethod = paymentMethod,
                        notes = notes,
                        selectedClientId = clientId
                    )
                    if (success) {
                        preferredSalePartId = null
                        showAddSaleDialog = false
                    }
                }
            }
        )
    }

    selectedPartDetail?.let { item ->
        PartDetailBottomSheet(
            item = item,
            batches = salesState.batches.filter { it.partId == item.part.id },
            formatCurrency = regionSettingsManager::formatCurrency,
            onDismiss = { selectedPartDetail = null },
            onReceiveStock = {
                preferredReceiveStockPartId = item.part.id
                selectedPartDetail = null
                showReceiveStockDialog = true
            },
            onAddSale = {
                preferredSalePartId = item.part.id
                selectedPartDetail = null
                showAddSaleDialog = true
            }
        )
    }
}

private fun localizedPartCategory(category: String, language: AppLanguage): String {
    val trimmedLower = category.trim().lowercase()
    return when (language) {
        AppLanguage.RUSSIAN -> {
            when (trimmedLower) {
                "engine" -> "Двигатель"
                "body" -> "Кузов"
                "electrical" -> "Электрика"
                "suspension" -> "Подвеска"
                "interior" -> "Салон"
                "other" -> "Другое"
                else -> category
            }
        }
        AppLanguage.UZBEK -> {
            when (trimmedLower) {
                "engine" -> "Dvigatel"
                "body" -> "Kuzov"
                "electrical" -> "Elektrika"
                "suspension" -> "Osma qism"
                "interior" -> "Salon"
                "other" -> "Boshqa"
                else -> category
            }
        }
        AppLanguage.ARABIC -> {
            when (trimmedLower) {
                "engine" -> "محرك"
                "body" -> "جسم"
                "electrical" -> "كهربائي"
                "suspension" -> "تعليق"
                "interior" -> "الداخلية"
                "other" -> "آخر"
                else -> category
            }
        }
        AppLanguage.JAPANESE -> {
            when (trimmedLower) {
                "engine" -> "エンジン"
                "body" -> "ボディ"
                "electrical" -> "電装"
                "suspension" -> "サスペンション"
                "interior" -> "内装"
                "other" -> "その他"
                else -> category
            }
        }
        AppLanguage.KOREAN -> {
            when (trimmedLower) {
                "engine" -> "엔진"
                "body" -> "바디"
                "electrical" -> "전기"
                "suspension" -> "서스펜션"
                "interior" -> "인테리어"
                "other" -> "기타"
                else -> category
            }
        }
        AppLanguage.PORTUGUESE_BRAZIL -> {
            when (trimmedLower) {
                "engine" -> "Motor"
                "body" -> "Carroceria"
                "electrical" -> "Elétrica"
                "suspension" -> "Suspensão"
                "interior" -> "Interior"
                "other" -> "Outros"
                else -> category
            }
        }
        else -> {
            when (trimmedLower) {
                "engine" -> "Engine"
                "body" -> "Body"
                "electrical" -> "Electrical"
                "suspension" -> "Suspension"
                "interior" -> "Interior"
                "other" -> "Other"
                else -> category
            }
        }
    }
}

private fun storedPartCategory(displayValue: String, language: AppLanguage): String {
    val trimmed = displayValue.trim()
    val lower = trimmed.lowercase()
    if (lower.isEmpty()) return ""

    // Check English
    if (lower == "engine") return "Engine"
    if (lower == "body") return "Body"
    if (lower == "electrical") return "Electrical"
    if (lower == "suspension") return "Suspension"
    if (lower == "interior") return "Interior"
    if (lower == "other") return "Other"

    // Check Russian
    if (lower == "двигатель") return "Engine"
    if (lower == "кузов") return "Body"
    if (lower == "электрика") return "Electrical"
    if (lower == "подвеска") return "Suspension"
    if (lower == "салон") return "Interior"
    if (lower == "другое") return "Other"

    // Check Uzbek
    if (lower == "dvigatel") return "Engine"
    if (lower == "kuzov") return "Body"
    if (lower == "elektrika") return "Electrical"
    if (lower == "osma qism" || lower == "osma") return "Suspension"
    if (lower == "salon") return "Interior"
    if (lower == "boshqa") return "Other"

    // Check Arabic
    if (lower == "محرك") return "Engine"
    if (lower == "جسم") return "Body"
    if (lower == "كهربائي") return "Electrical"
    if (lower == "تعليق") return "Suspension"
    if (lower == "الداخلية") return "Interior"
    if (lower == "آخر") return "Other"

    // Check Japanese
    if (lower == "エンジン") return "Engine"
    if (lower == "ボディ") return "Body"
    if (lower == "電装") return "Electrical"
    if (lower == "サスペンション") return "Suspension"
    if (lower == "内装") return "Interior"
    if (lower == "その他") return "Other"

    // Check Korean
    if (lower == "엔진") return "Engine"
    if (lower == "바디") return "Body"
    if (lower == "전기") return "Electrical"
    if (lower == "서스펜션") return "Suspension"
    if (lower == "인테리어") return "Interior"
    if (lower == "기타") return "Other"

    if (lower == "motor") return "Engine"
    if (lower == "carroceria") return "Body"
    if (lower == "elétrica" || lower == "eletrica") return "Electrical"
    if (lower == "suspensão" || lower == "suspensao") return "Suspension"
    if (lower == "interior") return "Interior"
    if (lower == "outros" || lower == "outro") return "Other"

    return trimmed
}

@Composable
private fun CategoryHeader(category: String, count: Int) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val language = regionState.selectedLanguage

    val localizedCat = if (category.trim().lowercase() in listOf("__uncategorized", "")) {
        localizedUiString("Uncategorized")
    } else {
        localizedPartCategory(category, language)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(EzcarNavy.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Tag,
                    contentDescription = null,
                    tint = EzcarNavy,
                    modifier = Modifier.size(12.dp)
                )
            }
            Text(
                text = localizedCat,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = Color.Gray
            )
        }
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(EzcarNavy.copy(alpha = 0.08f))
                .padding(horizontal = 8.dp, vertical = 3.dp)
        ) {
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
        }
    }
}

@Composable
private fun PartRowNew(
    item: PartInventoryItem,
    formatCurrency: (BigDecimal) -> String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp, horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Circle icon
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(EzcarNavy.copy(alpha = 0.06f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.AllInbox,
                contentDescription = null,
                tint = EzcarNavy,
                modifier = Modifier.size(16.dp)
            )
        }

        // Name and Code details
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = item.part.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            if (!item.part.code.isNullOrBlank()) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(EzcarNavy.copy(alpha = 0.06f))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = item.part.code ?: "",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = EzcarNavy
                    )
                }
            }
        }

        // Quantity and Value details
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            val isLow = item.quantityOnHand <= BigDecimal("2")
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(if (isLow) Color(0xFFFFEBEB) else EzcarNavy.copy(alpha = 0.08f))
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = item.quantityOnHand.stripTrailingZeros().toPlainString(),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (isLow) Color.Red else EzcarNavy
                )
            }
            Text(
                text = formatCurrency(item.inventoryValue),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = Color.Gray
            )
        }
    }
}

@Composable
private fun PartSaleRowNew(
    item: PartSaleItemSummary,
    formatCurrency: (BigDecimal) -> String,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp, horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Circle Cart icon
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(EzcarGreen.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.ShoppingCart,
                contentDescription = null,
                tint = EzcarGreen,
                modifier = Modifier.size(16.dp)
            )
        }

        // Buyer Name and Date details
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = item.buyerName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(item.saleDate),
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray
            )
            if (item.itemsSummary.isNotEmpty()) {
                Text(
                    text = item.itemsSummary,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray.copy(alpha = 0.8f)
                )
            }
        }

        // Price and Delete option
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = formatCurrency(item.totalAmount),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            TextButton(
                onClick = onDelete,
                contentPadding = PaddingValues(0.dp),
                modifier = Modifier.height(24.dp)
            ) {
                Text(
                    text = localizedUiString("Delete"),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Red
                )
            }
        }
    }
}

@Composable
private fun PartsStatsCard(
    title: String,
    value: String,
    icon: ImageVector,
    gradientColors: List<Color>,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .width(140.dp)
            .height(105.dp),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(0.5.dp, Color.White.copy(alpha = 0.35f)),
        elevation = CardDefaults.cardElevation(4.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Brush.linearGradient(gradientColors))
                .padding(12.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                // Icon circle
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.2f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                }

                // Text values
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = value,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = title,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.85f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}



@Composable
private fun CategoryFilter(
    categories: List<String>,
    selectedCategory: String?,
    onSelected: (String?) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val language = regionState.selectedLanguage

    var expanded by remember { mutableStateOf(false) }
    Box {
        Text(
            text = selectedCategory?.let { localizedPartCategory(it, language) } ?: localizedUiString("All Categories"),
            modifier = Modifier
                .clip(RoundedCornerShape(20.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(horizontal = 12.dp, vertical = 8.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(localizedUiString("All Categories")) }, onClick = {
                onSelected(null)
                expanded = false
            })
            categories.forEach { category ->
                DropdownMenuItem(text = { Text(localizedPartCategory(category, language)) }, onClick = {
                    onSelected(category)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun LowStockToggle(enabled: Boolean, onToggle: (Boolean) -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (enabled) EzcarBlueBright else EzcarBackgroundLight)
            .clickable { onToggle(!enabled) }
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Text(
            text = localizedUiString("Low Stock"),
            color = if (enabled) Color.White else Color.Black
        )
    }
}

private data class SuggestedCategory(
    val storedValue: String,
    val icon: ImageVector
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddPartDialog(
    accounts: List<FinancialAccount>,
    onDismiss: () -> Unit,
    onSave: (
        name: String,
        code: String?,
        category: String?,
        notes: String?,
        addInitialStock: Boolean,
        quantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        accountId: UUID?
    ) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    val language = regionState.selectedLanguage

    var name by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var categoryStored by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var addInitialStock by remember { mutableStateOf(false) }
    var quantity by remember { mutableStateOf("") }
    var unitCost by remember { mutableStateOf("") }
    var batchLabel by remember { mutableStateOf("") }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }

    // Validation
    val hasName = name.trim().isNotEmpty()
    val isFormValid = if (addInitialStock) {
        val qty = quantity.toBigDecimalOrNull() ?: BigDecimal.ZERO
        hasName && qty > BigDecimal.ZERO && selectedAccountId != null
    } else {
        hasName
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background,
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .size(44.dp)
                        .background(MaterialTheme.colorScheme.surface, CircleShape)
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = localizedUiString("Close"),
                        tint = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.size(24.dp)
                    )
                }

                Text(
                    text = localizedUiString("Add Part"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onBackground
                )

                // Spacer for symmetry
                Spacer(modifier = Modifier.size(44.dp))
            }

            Box(modifier = Modifier.weight(1f)) {
                // Scrollable Form
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 120.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp)
                ) {
                    // Part Name Hero Input
                    item {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(
                                text = localizedUiString("PART NAME").uppercase(Locale.getDefault()),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                                letterSpacing = 1.sp
                            )

                            androidx.compose.foundation.text.BasicTextField(
                                value = name,
                                onValueChange = { name = it },
                                textStyle = MaterialTheme.typography.titleLarge.copy(
                                    fontWeight = FontWeight.Bold,
                                    textAlign = TextAlign.Center,
                                    color = MaterialTheme.colorScheme.onBackground,
                                    fontSize = 24.sp
                                ),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp),
                                decorationBox = { innerTextField ->
                                    Box(
                                        contentAlignment = Alignment.Center,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        if (name.isEmpty()) {
                                            Text(
                                                text = localizedUiString("e.g. Brake Pads"),
                                                style = MaterialTheme.typography.titleLarge.copy(
                                                    fontWeight = FontWeight.Bold,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                                                    fontSize = 24.sp,
                                                    textAlign = TextAlign.Center
                                                )
                                            )
                                        }
                                        innerTextField()
                                    }
                                }
                            )
                        }
                    }

                    // Category Quick Selector Chips
                    item {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(
                                text = localizedUiString("CATEGORY").uppercase(Locale.getDefault()),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                                letterSpacing = 1.sp
                            )

                            val suggestedCategories = remember {
                                listOf(
                                    SuggestedCategory("Engine", Icons.Default.Build),
                                    SuggestedCategory("Body", Icons.Default.DirectionsCar),
                                    SuggestedCategory("Electrical", Icons.Default.Bolt),
                                    SuggestedCategory("Suspension", Icons.Default.Construction),
                                    SuggestedCategory("Interior", Icons.Default.Weekend),
                                    SuggestedCategory("Other", Icons.Default.MoreHoriz)
                                )
                            }

                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                suggestedCategories.forEach { cat ->
                                    val isSelected = categoryStored.trim().equals(cat.storedValue, ignoreCase = true)
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                        modifier = Modifier
                                            .clickable {
                                                categoryStored = cat.storedValue
                                            }
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(52.dp)
                                                .clip(CircleShape)
                                                .background(
                                                    if (isSelected) EzcarBlueBright else MaterialTheme.colorScheme.surfaceVariant
                                                ),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(
                                                imageVector = cat.icon,
                                                contentDescription = null,
                                                tint = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.size(22.dp)
                                            )
                                        }
                                        Text(
                                            text = localizedPartCategory(cat.storedValue, language),
                                            style = MaterialTheme.typography.labelSmall,
                                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                                            color = if (isSelected) EzcarBlueBright else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Details Card Group
                    item {
                        Surface(
                            color = MaterialTheme.colorScheme.surface,
                            shape = RoundedCornerShape(16.dp),
                            border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)),
                            shadowElevation = 1.dp,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column {
                                // Part Code Input
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.QrCode,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                        modifier = Modifier.size(24.dp)
                                    )
                                    Spacer(modifier = Modifier.width(12.dp))
                                    TextField(
                                        value = code,
                                        onValueChange = { code = it },
                                        placeholder = { Text(localizedUiString("Part Code / SKU")) },
                                        singleLine = true,
                                        colors = TextFieldDefaults.colors(
                                            focusedContainerColor = Color.Transparent,
                                            unfocusedContainerColor = Color.Transparent,
                                            disabledContainerColor = Color.Transparent,
                                            focusedIndicatorColor = Color.Transparent,
                                            unfocusedIndicatorColor = Color.Transparent
                                        ),
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }

                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                                    modifier = Modifier.padding(start = 52.dp)
                                )

                                // Custom Category Input
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Label,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                        modifier = Modifier.size(24.dp)
                                    )
                                    Spacer(modifier = Modifier.width(12.dp))
                                    TextField(
                                        value = localizedPartCategory(categoryStored, language),
                                        onValueChange = { newVal ->
                                            categoryStored = storedPartCategory(newVal, language)
                                        },
                                        placeholder = { Text(localizedUiString("Category")) },
                                        singleLine = true,
                                        colors = TextFieldDefaults.colors(
                                            focusedContainerColor = Color.Transparent,
                                            unfocusedContainerColor = Color.Transparent,
                                            disabledContainerColor = Color.Transparent,
                                            focusedIndicatorColor = Color.Transparent,
                                            unfocusedIndicatorColor = Color.Transparent
                                        ),
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }

                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                                    modifier = Modifier.padding(start = 52.dp)
                                )

                                // Notes Input
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.Top
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Description,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                        modifier = Modifier
                                            .size(24.dp)
                                            .padding(top = 12.dp)
                                    )
                                    Spacer(modifier = Modifier.width(12.dp))
                                    TextField(
                                        value = notes,
                                        onValueChange = { notes = it },
                                        placeholder = { Text(localizedUiString("Notes")) },
                                        minLines = 3,
                                        maxLines = 5,
                                        colors = TextFieldDefaults.colors(
                                            focusedContainerColor = Color.Transparent,
                                            unfocusedContainerColor = Color.Transparent,
                                            disabledContainerColor = Color.Transparent,
                                            focusedIndicatorColor = Color.Transparent,
                                            unfocusedIndicatorColor = Color.Transparent
                                        ),
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                        }
                    }

                    // Initial Stock Toggle Button
                    item {
                        Surface(
                            color = MaterialTheme.colorScheme.surface,
                            shape = RoundedCornerShape(16.dp),
                            border = BorderStroke(
                                1.dp,
                                if (addInitialStock) EzcarBlueBright.copy(alpha = 0.4f) else Color.Transparent
                            ),
                            shadowElevation = 1.dp,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { addInitialStock = !addInitialStock }
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(44.dp)
                                        .clip(CircleShape)
                                        .background(
                                            if (addInitialStock) EzcarBlueBright.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant
                                        ),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = if (addInitialStock) Icons.Default.CheckCircle else Icons.Default.AllInbox,
                                        contentDescription = null,
                                        tint = if (addInitialStock) EzcarBlueBright else MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(22.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.width(16.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = localizedUiString("Initial Stock"),
                                        style = MaterialTheme.typography.bodyLarge,
                                        fontWeight = FontWeight.Medium,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        text = localizedUiString("Add stock quantity and costs now"),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                Icon(
                                    imageVector = if (addInitialStock) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
                                    contentDescription = null,
                                    tint = if (addInitialStock) EzcarBlueBright else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                    modifier = Modifier.size(24.dp)
                                )
                            }
                        }
                    }

                    // Initial Stock Card (Expanded if enabled)
                    if (addInitialStock) {
                        item {
                            Surface(
                                color = MaterialTheme.colorScheme.surface,
                                shape = RoundedCornerShape(16.dp),
                                border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.2f)),
                                shadowElevation = 1.dp,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column {
                                    // Quantity
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Numbers,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            modifier = Modifier.size(24.dp)
                                        )
                                        Spacer(modifier = Modifier.width(12.dp))
                                        TextField(
                                            value = quantity,
                                            onValueChange = { newVal ->
                                                quantity = newVal.filter { it.isDigit() || it == '.' }
                                            },
                                            placeholder = { Text(localizedUiString("Quantity")) },
                                            singleLine = true,
                                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                            colors = TextFieldDefaults.colors(
                                                focusedContainerColor = Color.Transparent,
                                                unfocusedContainerColor = Color.Transparent,
                                                disabledContainerColor = Color.Transparent,
                                                focusedIndicatorColor = Color.Transparent,
                                                unfocusedIndicatorColor = Color.Transparent
                                            ),
                                            modifier = Modifier.fillMaxWidth()
                                        )
                                    }

                                    HorizontalDivider(
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                                        modifier = Modifier.padding(start = 52.dp)
                                    )

                                    // Unit Cost
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.AttachMoney,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            modifier = Modifier.size(24.dp)
                                        )
                                        Spacer(modifier = Modifier.width(12.dp))
                                        TextField(
                                            value = unitCost,
                                            onValueChange = { newVal ->
                                                unitCost = newVal.filter { it.isDigit() || it == '.' }
                                            },
                                            placeholder = { Text(localizedUiString("Unit Cost")) },
                                            singleLine = true,
                                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                            colors = TextFieldDefaults.colors(
                                                focusedContainerColor = Color.Transparent,
                                                unfocusedContainerColor = Color.Transparent,
                                                disabledContainerColor = Color.Transparent,
                                                focusedIndicatorColor = Color.Transparent,
                                                unfocusedIndicatorColor = Color.Transparent
                                            ),
                                            modifier = Modifier.fillMaxWidth()
                                        )
                                    }

                                    HorizontalDivider(
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                                        modifier = Modifier.padding(start = 52.dp)
                                    )

                                    // Batch Label
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 6.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.LocalShipping,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            modifier = Modifier.size(24.dp)
                                        )
                                        Spacer(modifier = Modifier.width(12.dp))
                                        TextField(
                                            value = batchLabel,
                                            onValueChange = { batchLabel = it },
                                            placeholder = { Text(localizedUiString("Batch Label")) },
                                            singleLine = true,
                                            colors = TextFieldDefaults.colors(
                                                focusedContainerColor = Color.Transparent,
                                                unfocusedContainerColor = Color.Transparent,
                                                disabledContainerColor = Color.Transparent,
                                                focusedIndicatorColor = Color.Transparent,
                                                unfocusedIndicatorColor = Color.Transparent
                                            ),
                                            modifier = Modifier.fillMaxWidth()
                                        )
                                    }

                                    HorizontalDivider(
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
                                        modifier = Modifier.padding(start = 52.dp)
                                    )

                                    // Account Picker Dropdown
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp, vertical = 12.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.CreditCard,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            modifier = Modifier.size(24.dp)
                                        )
                                        Spacer(modifier = Modifier.width(12.dp))
                                        Box(modifier = Modifier.weight(1f)) {
                                            AccountDropdown(
                                                accounts = accounts,
                                                selectedAccountId = selectedAccountId,
                                                onSelected = { selectedAccountId = it }
                                            )
                                        }
                                    }

                                    // Total Cost Summary
                                    val qtyVal = quantity.toBigDecimalOrNull() ?: BigDecimal.ZERO
                                    val costVal = unitCost.toBigDecimalOrNull() ?: BigDecimal.ZERO
                                    if (qtyVal > BigDecimal.ZERO) {
                                        val totalCost = qtyVal.multiply(costVal)
                                        val formattedTotal = regionSettingsManager.formatCurrency(totalCost)
                                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.1f))
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                                                .padding(16.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = localizedUiString("Total Cost"),
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                            Text(
                                                text = formattedTotal,
                                                style = MaterialTheme.typography.titleMedium,
                                                fontWeight = FontWeight.Bold,
                                                color = MaterialTheme.colorScheme.onSurface
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Save Button (Z-Index overlay floating at the bottom)
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                                    MaterialTheme.colorScheme.background
                                )
                            )
                        )
                        .padding(horizontal = 20.dp, vertical = 20.dp)
                ) {
                    Button(
                        onClick = {
                            onSave(
                                name.trim(),
                                code.ifBlank { null },
                                categoryStored.ifBlank { null },
                                notes.ifBlank { null },
                                addInitialStock,
                                quantity.toBigDecimalOrZero(),
                                unitCost.toBigDecimalOrZero(),
                                batchLabel.ifBlank { null },
                                selectedAccountId
                            )
                        },
                        enabled = isFormValid,
                        shape = RoundedCornerShape(20.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = EzcarBlueBright,
                            contentColor = Color.White,
                            disabledContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
                            disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(54.dp)
                    ) {
                        Text(
                            text = localizedUiString("Save"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ReceiveStockDialog(
    parts: List<Part>,
    accounts: List<FinancialAccount>,
    preferredPartId: UUID? = null,
    onDismiss: () -> Unit,
    onSave: (
        partId: UUID,
        quantity: BigDecimal,
        unitCost: BigDecimal,
        batchLabel: String?,
        notes: String?,
        purchaseDate: Date,
        accountId: UUID?
    ) -> Unit
) {
    var selectedPartId by remember(preferredPartId, parts) {
        mutableStateOf(preferredPartId ?: parts.firstOrNull()?.id)
    }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }
    var quantity by remember { mutableStateOf("") }
    var unitCost by remember { mutableStateOf("") }
    var batchLabel by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var purchaseDate by remember { mutableStateOf(Date()) }
    var showDatePicker by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedUiString("Receive Stock")) },
        text = {
            Column {
                PartDropdown(parts = parts, selectedPartId = selectedPartId, onSelected = { selectedPartId = it })
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = { Text(localizedUiString("Quantity")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(
                    value = unitCost,
                    onValueChange = { unitCost = it },
                    label = { Text(localizedUiString("Unit Cost")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(value = batchLabel, onValueChange = { batchLabel = it }, label = { Text(localizedUiString("Batch Label")) })
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text(localizedUiString("Notes")) })
                Text(
                    text = localizedUiString(
                        "Purchase Date: %s",
                        SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(purchaseDate)
                    ),
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clickable { showDatePicker = true }
                )
                AccountDropdown(
                    accounts = accounts,
                    selectedAccountId = selectedAccountId,
                    onSelected = { selectedAccountId = it }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val partId = selectedPartId ?: return@TextButton
                onSave(
                    partId,
                    quantity.toBigDecimalOrZero(),
                    unitCost.toBigDecimalOrZero(),
                    batchLabel.ifBlank { null },
                    notes.ifBlank { null },
                    purchaseDate,
                    selectedAccountId
                )
            }) {
                Text(localizedUiString("Save"))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) } }
    )

    if (showDatePicker) {
        SimpleDatePickerDialog(
            onDismiss = { showDatePicker = false },
            onDateSelected = {
                purchaseDate = it
                showDatePicker = false
            }
        )
    }
}

@Composable
private fun AddPartSaleDialog(
    parts: List<Part>,
    accounts: List<FinancialAccount>,
    clients: List<Client>,
    preferredPartId: UUID? = null,
    onDismiss: () -> Unit,
    onSave: (
        saleDate: Date,
        accountId: UUID,
        lines: List<PartSaleLineDraft>,
        buyerName: String?,
        buyerPhone: String?,
        paymentMethod: String?,
        notes: String?,
        clientId: UUID?
    ) -> Unit
) {
    var saleDate by remember { mutableStateOf(Date()) }
    var showDatePicker by remember { mutableStateOf(false) }
    var selectedAccountId by remember { mutableStateOf<UUID?>(accounts.firstOrNull()?.id) }
    var buyerName by remember { mutableStateOf("") }
    var buyerPhone by remember { mutableStateOf("") }
    var paymentMethod by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var selectedClientId by remember { mutableStateOf<UUID?>(null) }
    var lineItems by remember { mutableStateOf(listOf<PartSaleLineDraft>()) }
    var showLineDialog by remember(preferredPartId) { mutableStateOf(preferredPartId != null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedUiString("Add Sale")) },
        text = {
            Column {
                Text(
                    text = localizedUiString(
                        "Sale Date: %s",
                        SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(saleDate)
                    ),
                    modifier = Modifier
                        .padding(bottom = 8.dp)
                        .clickable { showDatePicker = true }
                )
                AccountDropdown(
                    accounts = accounts,
                    selectedAccountId = selectedAccountId,
                    onSelected = { selectedAccountId = it }
                )
                ClientDropdown(
                    clients = clients,
                    selectedClientId = selectedClientId,
                    onSelected = { selectedClientId = it }
                )
                OutlinedTextField(value = buyerName, onValueChange = { buyerName = it }, label = { Text(localizedUiString("Buyer Name")) })
                OutlinedTextField(value = buyerPhone, onValueChange = { buyerPhone = it }, label = { Text(localizedUiString("Buyer Phone")) })
                OutlinedTextField(value = paymentMethod, onValueChange = { paymentMethod = it }, label = { Text(localizedUiString("Payment Method")) })
                OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text(localizedUiString("Notes")) })
                Spacer(modifier = Modifier.height(8.dp))
                Text(localizedUiString("Line Items"), fontWeight = FontWeight.Bold)
                lineItems.forEach { line ->
                    val partName = parts.firstOrNull { it.id == line.partId }?.name ?: localizedUiString("Part")
                    Text(localizedUiString("%s: %s x %s", partName, line.quantity, line.unitPrice))
                }
                TextButton(onClick = { showLineDialog = true }) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(localizedUiString("Add Line Item"))
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val accountId = selectedAccountId ?: return@TextButton
                onSave(
                    saleDate,
                    accountId,
                    lineItems,
                    buyerName.ifBlank { null },
                    buyerPhone.ifBlank { null },
                    paymentMethod.ifBlank { null },
                    notes.ifBlank { null },
                    selectedClientId
                )
            }) {
                Text(localizedUiString("Save"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) }
        }
    )

    if (showLineDialog) {
        AddLineItemDialog(
            parts = parts,
            preferredPartId = preferredPartId,
            onDismiss = { showLineDialog = false },
            onSave = { partId, quantity, unitPrice ->
                lineItems = lineItems + PartSaleLineDraft(partId, quantity, unitPrice)
                showLineDialog = false
            }
        )
    }

    if (showDatePicker) {
        SimpleDatePickerDialog(
            onDismiss = { showDatePicker = false },
            onDateSelected = {
                saleDate = it
                showDatePicker = false
            }
        )
    }
}

@Composable
private fun AddLineItemDialog(
    parts: List<Part>,
    preferredPartId: UUID? = null,
    onDismiss: () -> Unit,
    onSave: (partId: UUID, quantity: BigDecimal, unitPrice: BigDecimal) -> Unit
) {
    var selectedPartId by remember(preferredPartId, parts) {
        mutableStateOf(preferredPartId ?: parts.firstOrNull()?.id)
    }
    var quantity by remember { mutableStateOf("") }
    var unitPrice by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedUiString("Add Line Item")) },
        text = {
            Column {
                PartDropdown(parts = parts, selectedPartId = selectedPartId, onSelected = { selectedPartId = it })
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = { Text(localizedUiString("Quantity")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(
                    value = unitPrice,
                    onValueChange = { unitPrice = it },
                    label = { Text(localizedUiString("Unit Price")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val partId = selectedPartId ?: return@TextButton
                onSave(partId, quantity.toBigDecimalOrZero(), unitPrice.toBigDecimalOrZero())
            }) {
                Text(localizedUiString("Add"))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) } }
    )
}

@Composable
private fun PartDropdown(
    parts: List<Part>,
    selectedPartId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = parts.firstOrNull { it.id == selectedPartId }?.name ?: localizedUiString("Select Part")
    Box {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            parts.forEach { part ->
                DropdownMenuItem(text = { Text(part.name) }, onClick = {
                    onSelected(part.id)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun AccountDropdown(
    accounts: List<FinancialAccount>,
    selectedAccountId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = accounts.firstOrNull { it.id == selectedAccountId }?.accountType ?: localizedUiString("Select Account")
    Box(modifier = Modifier.padding(top = 8.dp)) {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            accounts.forEach { account ->
                DropdownMenuItem(text = { Text(account.accountType) }, onClick = {
                    onSelected(account.id)
                    expanded = false
                })
            }
        }
    }
}

@Composable
private fun ClientDropdown(
    clients: List<Client>,
    selectedClientId: UUID?,
    onSelected: (UUID?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedName = clients.firstOrNull { it.id == selectedClientId }?.name ?: localizedUiString("Select Client")
    Box(modifier = Modifier.padding(top = 8.dp)) {
        Text(
            text = selectedName,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(EzcarBackgroundLight)
                .clickable { expanded = true }
                .padding(12.dp)
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(localizedUiString("None")) }, onClick = {
                onSelected(null)
                expanded = false
            })
            clients.forEach { client ->
                DropdownMenuItem(text = { Text(client.name) }, onClick = {
                    onSelected(client.id)
                    expanded = false
                })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SimpleDatePickerDialog(
    onDismiss: () -> Unit,
    onDateSelected: (Date) -> Unit
) {
    val datePickerState = androidx.compose.material3.rememberDatePickerState()
    androidx.compose.material3.DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    datePickerState.selectedDateMillis?.let {
                        onDateSelected(Date(it))
                    }
                }
            ) {
                Text(localizedUiString("OK"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedUiString("Cancel")) }
        }
    ) {
        androidx.compose.material3.DatePicker(state = datePickerState)
    }
}
