package com.ezcar24.business.ui.settings

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.TrendingDown
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Category
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.repository.AccountRepository
import com.ezcar24.business.data.repository.MonthlyReportCategorySummary
import com.ezcar24.business.data.repository.MonthlyReportPartSaleSummary
import com.ezcar24.business.data.repository.MonthlyReportRepository
import com.ezcar24.business.data.repository.MonthlyReportSnapshot
import com.ezcar24.business.data.repository.MonthlyReportVehicleSaleSummary
import com.ezcar24.business.data.repository.ReportMonth
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarBlueBright
import com.ezcar24.business.ui.theme.EzcarDanger
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarPurple
import com.ezcar24.business.util.RegionSettingsManager
import com.ezcar24.business.util.UserFacingErrorContext
import com.ezcar24.business.util.UserFacingErrorMapper
import com.ezcar24.business.util.localizedUiString
import com.ezcar24.business.util.rememberRegionSettingsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class MonthlyReportPreviewUiState(
    val organizationName: String? = null,
    val snapshot: MonthlyReportSnapshot? = null,
    val isLoading: Boolean = false,
    val isExporting: Boolean = false,
    val errorMessage: String? = null,
    val shareUri: Uri? = null,
    val shareMimeType: String? = null
)

@HiltViewModel
class MonthlyReportPreviewViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val accountRepository: AccountRepository,
    private val monthlyReportRepository: MonthlyReportRepository,
    private val regionSettingsManager: RegionSettingsManager
) : ViewModel() {
    private val reportMonth = ReportMonth.previousCalendarMonth()
    private val _uiState = MutableStateFlow(MonthlyReportPreviewUiState())
    val uiState: StateFlow<MonthlyReportPreviewUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            accountRepository.activeOrganization.collectLatest { organization ->
                _uiState.update { it.copy(organizationName = organization?.organizationName) }
                loadSnapshot()
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            loadSnapshot()
        }
    }

    fun reportMonthTitle(): String {
        return reportMonth.displayTitle()
    }

    fun clearShareUri() {
        _uiState.update { it.copy(shareUri = null, shareMimeType = null) }
    }

    fun exportPdf() {
        val snapshot = _uiState.value.snapshot ?: return
        val organizationName = _uiState.value.organizationName
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isExporting = true,
                    errorMessage = null
                )
            }
            try {
                val pdfBytes = withContext(Dispatchers.IO) {
                    MonthlyReportPdfRenderer.build(
                        context = context,
                        regionSettingsManager = regionSettingsManager,
                        snapshot = snapshot,
                        organizationName = organizationName
                    )
                }
                val fileName = "monthly-report-${snapshot.reportMonth.year}-${snapshot.reportMonth.month.toString().padStart(2, '0')}-${timestamp()}.pdf"
                val uri = withContext(Dispatchers.IO) {
                    writeBytesToDownloads(fileName, "application/pdf", pdfBytes)
                }
                if (uri == null) {
                    _uiState.update {
                        it.copy(
                            isExporting = false,
                            errorMessage = context.localizedUiString("Report export failed")
                        )
                    }
                } else {
                    _uiState.update {
                        it.copy(
                            isExporting = false,
                            shareUri = uri,
                            shareMimeType = "application/pdf"
                        )
                    }
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        isExporting = false,
                        errorMessage = error.message ?: context.localizedUiString("Report export failed")
                    )
                }
            }
        }
    }

    private suspend fun loadSnapshot() {
        _uiState.update {
            it.copy(
                isLoading = true,
                errorMessage = null
            )
        }
        try {
            val snapshot = monthlyReportRepository.loadLocalSnapshot(reportMonth)
            _uiState.update {
                it.copy(
                    snapshot = snapshot,
                    isLoading = false
                )
            }
        } catch (error: Exception) {
            _uiState.update {
                it.copy(
                    isLoading = false,
                    errorMessage = UserFacingErrorMapper.map(
                        error,
                        UserFacingErrorContext.LOAD_MONTHLY_REPORT_PREVIEW
                    )
                )
            }
        }
    }

    private fun writeBytesToDownloads(fileName: String, mimeType: String, bytes: ByteArray): Uri? {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Car Dealer Tracker")
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        resolver.openOutputStream(uri)?.use { stream ->
            stream.write(bytes)
        } ?: return null
        return uri
    }

    private fun timestamp(): String {
        return SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MonthlyReportPreviewScreen(
    onBack: () -> Unit,
    viewModel: MonthlyReportPreviewViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val reportMonthTitle = remember { viewModel.reportMonthTitle() }
    val regionSettingsManager = rememberRegionSettingsManager()
    val context = LocalContext.current

    LaunchedEffect(uiState.shareUri) {
        val uri = uiState.shareUri ?: return@LaunchedEffect
        val mimeType = uiState.shareMimeType ?: "application/pdf"
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, context.localizedUiString("Share File")))
        viewModel.clearShareUri()
    }

    Scaffold(
        containerColor = EzcarBackgroundLight,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = reportMonthTitle,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                        uiState.organizationName?.let {
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = localizedUiString("Back"),
                            tint = EzcarNavy
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = viewModel::exportPdf,
                        enabled = uiState.snapshot != null && !uiState.isLoading && !uiState.isExporting
                    ) {
                        if (uiState.isExporting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = EzcarNavy
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Description,
                                contentDescription = localizedUiString("Generate PDF Report"),
                                tint = EzcarNavy
                            )
                        }
                    }
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = !uiState.isLoading
                    ) {
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = EzcarNavy
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Default.Refresh,
                                contentDescription = localizedUiString("Refresh"),
                                tint = EzcarNavy
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = EzcarBackgroundLight)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            val snapshot = uiState.snapshot

            item {
                MonthlyPreviewSummaryCard(
                    title = reportMonthTitle,
                    snapshot = snapshot,
                    isLoading = uiState.isLoading,
                    formatCurrency = regionSettingsManager::formatCurrency
                )
            }

            uiState.errorMessage?.let { message ->
                item {
                    MonthlyPreviewStatusCard(message)
                }
            }

            if (snapshot != null) {
                item {
                    MonthlyPreviewExecutiveBrief(snapshot, regionSettingsManager::formatCurrency)
                }
                item {
                    MonthlyPreviewFinancialOverview(snapshot, regionSettingsManager::formatCurrency)
                }
                item {
                    MonthlyPreviewExpenseMix(snapshot.expenseCategories, regionSettingsManager::formatCurrency)
                }
                item {
                    MonthlyPreviewSalesSection(snapshot, regionSettingsManager::formatCurrency)
                }
                item {
                    MonthlyPreviewCashAndInventorySection(snapshot, regionSettingsManager::formatCurrency)
                }
                item {
                    MonthlyPreviewProfitWatchlist(snapshot, regionSettingsManager::formatCurrency)
                }
            }
        }
    }
}

@Composable
private fun MonthlyPreviewSummaryCard(
    title: String,
    snapshot: MonthlyReportSnapshot?,
    isLoading: Boolean,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = localizedUiString("Previous calendar month"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy
                )
                snapshot?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = it.periodLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = EzcarBlueBright
                    )
                }
            }
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                    color = EzcarNavy
                )
            }
        }

        snapshot?.let {
            Spacer(modifier = Modifier.height(18.dp))
            MonthlyPreviewMetricGrid(
                items = listOf(
                    PreviewMetric("Revenue", formatCurrency(it.executiveSummary.totalRevenue), EzcarBlueBright),
                    PreviewMetric("Realized sales profit", formatCurrency(it.executiveSummary.realizedSalesProfit), EzcarGreen),
                    PreviewMetric("Monthly expenses", formatCurrency(it.executiveSummary.monthlyExpenses), EzcarOrange),
                    PreviewMetric("Net cash movement", formatCurrency(it.executiveSummary.netCashMovement), EzcarPurple)
                )
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = localizedUiString("Structured around realized sales profit, monthly expenses, and cash movement instead of one synthetic net figure."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun MonthlyPreviewExecutiveBrief(
    snapshot: MonthlyReportSnapshot,
    formatCurrency: (BigDecimal?) -> String
) {
    val summary = snapshot.executiveSummary
    val signal = when {
        summary.realizedSalesProfit > BigDecimal.ZERO && summary.netCashMovement >= BigDecimal.ZERO ->
            PreviewSignal("Healthy month", "Profit and cash movement are both positive.", EzcarGreen, Icons.AutoMirrored.Filled.TrendingUp)
        summary.realizedSalesProfit < BigDecimal.ZERO ->
            PreviewSignal("Profit pressure", "Sold units closed below their tracked cost basis.", EzcarDanger, Icons.AutoMirrored.Filled.TrendingDown)
        summary.netCashMovement < BigDecimal.ZERO ->
            PreviewSignal("Cash outflow", "Withdrawals are higher than deposits for the month.", EzcarOrange, Icons.Default.Payments)
        else ->
            PreviewSignal("Quiet month", "No strong positive or negative signal in this period.", EzcarBlueBright, Icons.Default.Assessment)
    }

    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Executive brief")
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = localizedUiString("A faster operator-level scan before the detailed tables."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(14.dp))
        MonthlyPreviewSignalCard(signal)
        Spacer(modifier = Modifier.height(14.dp))
        MonthlyPreviewMetricGrid(
            items = listOf(
                PreviewMetric("Vehicle sales", snapshot.vehicleSales.size.toString(), EzcarNavy),
                PreviewMetric("Part sales", snapshot.partSales.size.toString(), EzcarOrange),
                PreviewMetric("Inventory capital", formatCurrency(summary.inventoryCapital), EzcarBlueBright),
                PreviewMetric("Parts stock cost", formatCurrency(summary.partsInventoryCost), EzcarPurple)
            )
        )
        Spacer(modifier = Modifier.height(14.dp))
        MonthlyPreviewComposition(
            title = "Revenue composition",
            firstLabel = "Vehicles",
            firstValue = summary.vehicleRevenue,
            secondLabel = "Parts",
            secondValue = summary.partRevenue,
            formatCurrency = formatCurrency
        )
        Spacer(modifier = Modifier.height(12.dp))
        MonthlyPreviewComposition(
            title = "Capital parked in stock",
            firstLabel = "Vehicles",
            firstValue = summary.inventoryCapital,
            secondLabel = "Parts",
            secondValue = summary.partsInventoryCost,
            formatCurrency = formatCurrency
        )
    }
}

@Composable
private fun MonthlyPreviewFinancialOverview(
    snapshot: MonthlyReportSnapshot,
    formatCurrency: (BigDecimal?) -> String
) {
    val summary = snapshot.executiveSummary
    val rows = listOf(
        PreviewBarMetric("Vehicle revenue", summary.vehicleRevenue, EzcarBlueBright),
        PreviewBarMetric("Part revenue", summary.partRevenue, EzcarOrange),
        PreviewBarMetric("Vehicle profit", summary.vehicleProfit, if (summary.vehicleProfit < BigDecimal.ZERO) EzcarDanger else EzcarGreen),
        PreviewBarMetric("Part profit", summary.partProfit, if (summary.partProfit < BigDecimal.ZERO) EzcarDanger else EzcarGreen),
        PreviewBarMetric("Monthly expenses", summary.monthlyExpenses, EzcarOrange),
        PreviewBarMetric("Net cash movement", summary.netCashMovement, if (summary.netCashMovement < BigDecimal.ZERO) EzcarDanger else EzcarPurple)
    )
    val maxValue = rows.maxOfOrNull { it.amount.absOrZero() }?.takeIf { it > BigDecimal.ZERO } ?: BigDecimal.ONE

    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Financial overview")
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = localizedUiString("Fast visual comparison of the month's core metrics."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(14.dp))
        rows.forEachIndexed { index, item ->
            if (index > 0) {
                Spacer(modifier = Modifier.height(12.dp))
            }
            MonthlyPreviewBarRow(item, maxValue, formatCurrency)
        }
    }
}

@Composable
private fun MonthlyPreviewExpenseMix(
    categories: List<MonthlyReportCategorySummary>,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Expense mix")
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = localizedUiString("Top categories from expenses recorded inside the report month."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(14.dp))
        if (categories.isEmpty()) {
            MonthlyPreviewEmptyText("No expenses recorded in this month.")
        } else {
            categories.take(6).forEachIndexed { index, category ->
                if (index > 0) {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                MonthlyPreviewCategoryRow(category, formatCurrency)
            }
        }
    }
}

@Composable
private fun MonthlyPreviewSalesSection(
    snapshot: MonthlyReportSnapshot,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Vehicle sales")
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = localizedUiString("Closed vehicle deals for this report month."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(14.dp))
        if (snapshot.vehicleSales.isEmpty()) {
            MonthlyPreviewEmptyText("No vehicle sales recorded in this month.")
        } else {
            snapshot.vehicleSales.take(5).forEachIndexed { index, sale ->
                if (index > 0) {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                MonthlyPreviewVehicleSaleRow(sale, formatCurrency)
            }
        }
        Spacer(modifier = Modifier.height(18.dp))
        MonthlyPreviewSectionTitle("Part sales")
        Spacer(modifier = Modifier.height(14.dp))
        if (snapshot.partSales.isEmpty()) {
            MonthlyPreviewEmptyText("No part sales recorded in this month.")
        } else {
            snapshot.partSales.take(5).forEachIndexed { index, sale ->
                if (index > 0) {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                MonthlyPreviewPartSaleRow(sale, formatCurrency)
            }
        }
    }
}

@Composable
private fun MonthlyPreviewCashAndInventorySection(
    snapshot: MonthlyReportSnapshot,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Cash movement")
        Spacer(modifier = Modifier.height(14.dp))
        MonthlyPreviewMetricGrid(
            items = listOf(
                PreviewMetric("Deposits", formatCurrency(snapshot.cashMovement.depositsTotal), EzcarGreen),
                PreviewMetric("Withdrawals", formatCurrency(snapshot.cashMovement.withdrawalsTotal), EzcarDanger),
                PreviewMetric("Net movement", formatCurrency(snapshot.cashMovement.netMovement), EzcarPurple),
                PreviewMetric("Transactions", snapshot.cashMovement.transactionCount.toString(), EzcarBlueBright)
            )
        )
        Spacer(modifier = Modifier.height(18.dp))
        MonthlyPreviewSectionTitle("Inventory snapshot")
        Spacer(modifier = Modifier.height(14.dp))
        MonthlyPreviewMetricGrid(
            items = listOf(
                PreviewMetric("Vehicles in stock", snapshot.inventory.vehicleCount.toString(), EzcarNavy),
                PreviewMetric("Vehicle capital", formatCurrency(snapshot.inventory.vehicleCapital), EzcarBlueBright),
                PreviewMetric("Parts in stock", snapshot.inventory.partsUnitsInStock.stripTrailingZeros().toPlainString(), EzcarOrange),
                PreviewMetric("Parts stock cost", formatCurrency(snapshot.inventory.partsInventoryCost), EzcarPurple)
            )
        )
    }
}

@Composable
private fun MonthlyPreviewProfitWatchlist(
    snapshot: MonthlyReportSnapshot,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewCard {
        MonthlyPreviewSectionTitle("Top profitable vehicles")
        Spacer(modifier = Modifier.height(14.dp))
        if (snapshot.topProfitableVehicles.isEmpty()) {
            MonthlyPreviewEmptyText("No profitable vehicle sales in this month.")
        } else {
            snapshot.topProfitableVehicles.forEachIndexed { index, sale ->
                if (index > 0) {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                MonthlyPreviewWatchlistRow(sale, formatCurrency, EzcarGreen)
            }
        }
        Spacer(modifier = Modifier.height(18.dp))
        MonthlyPreviewSectionTitle("Loss-making vehicles")
        Spacer(modifier = Modifier.height(14.dp))
        if (snapshot.lossMakingVehicles.isEmpty()) {
            MonthlyPreviewEmptyText("No loss-making vehicle sales in this month.")
        } else {
            snapshot.lossMakingVehicles.forEachIndexed { index, sale ->
                if (index > 0) {
                    Spacer(modifier = Modifier.height(12.dp))
                }
                MonthlyPreviewWatchlistRow(sale, formatCurrency, EzcarDanger)
            }
        }
    }
}

@Composable
private fun MonthlyPreviewMetricGrid(items: List<PreviewMetric>) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.chunked(2).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                rowItems.forEach { item ->
                    MonthlyPreviewMetricTile(
                        item = item,
                        modifier = Modifier.weight(1f)
                    )
                }
                if (rowItems.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun MonthlyPreviewMetricTile(
    item: PreviewMetric,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = item.tint.copy(alpha = 0.10f)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                text = localizedUiString(item.title),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = item.value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = item.tint,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun MonthlyPreviewSignalCard(signal: PreviewSignal) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = signal.tint.copy(alpha = 0.10f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(signal.tint.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(signal.icon, contentDescription = null, tint = signal.tint)
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = localizedUiString(signal.title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = signal.tint
                )
                Spacer(modifier = Modifier.height(3.dp))
                Text(
                    text = localizedUiString(signal.subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun MonthlyPreviewComposition(
    title: String,
    firstLabel: String,
    firstValue: BigDecimal,
    secondLabel: String,
    secondValue: BigDecimal,
    formatCurrency: (BigDecimal?) -> String
) {
    val total = firstValue + secondValue
    val firstShare = if (total > BigDecimal.ZERO) firstValue.toDouble() / total.toDouble() else 0.0
    Column {
        Text(
            text = localizedUiString(title),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = EzcarNavy
        )
        Spacer(modifier = Modifier.height(8.dp))
        MonthlyPreviewStackedBar(firstShare.toFloat(), EzcarBlueBright, EzcarOrange)
        Spacer(modifier = Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MonthlyPreviewLegend(firstLabel, formatCurrency(firstValue), EzcarBlueBright, Modifier.weight(1f))
            MonthlyPreviewLegend(secondLabel, formatCurrency(secondValue), EzcarOrange, Modifier.weight(1f))
        }
    }
}

@Composable
private fun MonthlyPreviewStackedBar(
    firstShare: Float,
    firstColor: Color,
    secondColor: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(10.dp)
            .clip(RoundedCornerShape(50))
            .background(secondColor.copy(alpha = 0.18f))
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(firstShare.coerceIn(0f, 1f))
                .height(10.dp)
                .background(firstColor)
        )
    }
}

@Composable
private fun MonthlyPreviewLegend(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .padding(top = 4.dp)
                .size(8.dp)
                .background(color, CircleShape)
        )
        Column {
            Text(
                text = localizedUiString(label),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = EzcarNavy
            )
        }
    }
}

@Composable
private fun MonthlyPreviewBarRow(
    item: PreviewBarMetric,
    maxValue: BigDecimal,
    formatCurrency: (BigDecimal?) -> String
) {
    val fraction = (item.amount.absOrZero().toDouble() / maxValue.toDouble()).toFloat().coerceIn(0.04f, 1f)
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = localizedUiString(item.title),
                style = MaterialTheme.typography.bodyMedium,
                color = EzcarNavy,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = formatCurrency(item.amount),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = item.tint
            )
        }
        Spacer(modifier = Modifier.height(7.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.46f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(8.dp)
                    .background(item.tint)
            )
        }
    }
}

@Composable
private fun MonthlyPreviewCategoryRow(
    category: MonthlyReportCategorySummary,
    formatCurrency: (BigDecimal?) -> String
) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .background(EzcarOrange.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Category, contentDescription = null, tint = EzcarOrange, modifier = Modifier.size(17.dp))
            }
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = category.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = EzcarNavy
                )
                Text(
                    text = localizedUiString("%d entries", category.count),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                text = formatCurrency(category.amount),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = EzcarNavy
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(7.dp)
                .clip(RoundedCornerShape(50))
                .background(EzcarOrange.copy(alpha = 0.12f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(category.share.toFloat().coerceIn(0.04f, 1f))
                    .height(7.dp)
                    .background(EzcarOrange)
            )
        }
    }
}

@Composable
private fun MonthlyPreviewVehicleSaleRow(
    sale: MonthlyReportVehicleSaleSummary,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewDataRow(
        icon = Icons.Default.DirectionsCar,
        tint = EzcarBlueBright,
        title = sale.title,
        subtitle = localizedUiString("%s - %s", sale.buyerName, shortDate(sale.soldAt)),
        trailing = formatCurrency(sale.revenue),
        footer = localizedUiString("Profit %s", formatCurrency(sale.realizedProfit)),
        footerColor = if (sale.realizedProfit < BigDecimal.ZERO) EzcarDanger else EzcarGreen
    )
}

@Composable
private fun MonthlyPreviewPartSaleRow(
    sale: MonthlyReportPartSaleSummary,
    formatCurrency: (BigDecimal?) -> String
) {
    MonthlyPreviewDataRow(
        icon = Icons.Default.Inventory2,
        tint = EzcarOrange,
        title = sale.summary,
        subtitle = localizedUiString("%s - %s", sale.buyerName, shortDate(sale.soldAt)),
        trailing = formatCurrency(sale.revenue),
        footer = localizedUiString("Profit %s", formatCurrency(sale.realizedProfit)),
        footerColor = if (sale.realizedProfit < BigDecimal.ZERO) EzcarDanger else EzcarGreen
    )
}

@Composable
private fun MonthlyPreviewWatchlistRow(
    sale: MonthlyReportVehicleSaleSummary,
    formatCurrency: (BigDecimal?) -> String,
    tint: Color
) {
    MonthlyPreviewDataRow(
        icon = if (tint == EzcarDanger) Icons.AutoMirrored.Filled.TrendingDown else Icons.AutoMirrored.Filled.TrendingUp,
        tint = tint,
        title = sale.title,
        subtitle = localizedUiString("%s - Revenue %s", shortDate(sale.soldAt), formatCurrency(sale.revenue)),
        trailing = formatCurrency(sale.realizedProfit),
        footer = localizedUiString("Cost basis %s", formatCurrency(sale.purchasePrice + sale.vehicleExpenses + sale.holdingCost)),
        footerColor = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun MonthlyPreviewDataRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String,
    trailing: String,
    footer: String,
    footerColor: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(tint.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(19.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = EzcarNavy,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.height(3.dp))
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = trailing,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = EzcarNavy,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(modifier = Modifier.height(5.dp))
            Text(
                text = footer,
                style = MaterialTheme.typography.bodySmall,
                color = footerColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun MonthlyPreviewStatusCard(message: String) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = EzcarDanger.copy(alpha = 0.10f)
    ) {
        Text(
            text = localizedUiString(message),
            style = MaterialTheme.typography.bodyMedium,
            color = EzcarDanger,
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp)
        )
    }
}

@Composable
private fun MonthlyPreviewEmptyText(text: String) {
    Text(
        text = localizedUiString(text),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun MonthlyPreviewSectionTitle(title: String) {
    Text(
        text = localizedUiString(title),
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = EzcarNavy
    )
}

@Composable
private fun MonthlyPreviewCard(
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(20.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            content = content
        )
    }
}

private data class PreviewMetric(
    val title: String,
    val value: String,
    val tint: Color
)

private data class PreviewSignal(
    val title: String,
    val subtitle: String,
    val tint: Color,
    val icon: ImageVector
)

private data class PreviewBarMetric(
    val title: String,
    val amount: BigDecimal,
    val tint: Color
)

private fun BigDecimal.absOrZero(): BigDecimal {
    return if (this < BigDecimal.ZERO) negate() else this
}

private fun shortDate(date: Date): String {
    return SimpleDateFormat("MMM d", Locale.getDefault()).format(date)
}
