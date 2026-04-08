package com.ezcar24.business.ui.settings

import android.content.ContentValues
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.ActiveDatabaseProvider
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.DateUtils
import com.ezcar24.business.util.RegionSettingsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class BackupCenterUiState(
    val isProcessing: Boolean = false,
    val message: String? = null,
    val shareUri: Uri? = null,
    val shareMimeType: String? = null
)

@HiltViewModel
class BackupCenterViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val databaseProvider: ActiveDatabaseProvider,
    private val cloudSyncManager: CloudSyncManager,
    private val regionSettingsManager: RegionSettingsManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(BackupCenterUiState())
    val uiState = _uiState.asStateFlow()

    fun clearShareUri() {
        _uiState.update { it.copy(shareUri = null, shareMimeType = null) }
    }

    fun exportExpensesCsv() {
        exportCsv("expenses") { buildExpensesCsv(null, null) }
    }

    fun exportVehiclesCsv() {
        exportCsv("vehicles") { buildVehiclesCsv() }
    }

    fun exportClientsCsv() {
        exportCsv("clients") { buildClientsCsv() }
    }

    fun exportReportPdf(startDate: Date, endDate: Date) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, message = null) }
            try {
                val pdfBytes = withContext(Dispatchers.IO) { buildReportPdf(startDate, endDate) }
                val fileName = "report-${timestamp()}.pdf"
                val uri = withContext(Dispatchers.IO) { writeBytesToDownloads(fileName, "application/pdf", pdfBytes) }
                if (uri == null) {
                    _uiState.update { it.copy(isProcessing = false, message = "Report export failed") }
                } else {
                    _uiState.update { it.copy(isProcessing = false, shareUri = uri, shareMimeType = "application/pdf") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isProcessing = false, message = e.message ?: "Report export failed") }
            }
        }
    }

    fun buildArchive(startDate: Date, endDate: Date) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, message = null) }
            try {
                val archiveBytes = withContext(Dispatchers.IO) { buildArchiveJson(startDate, endDate) }
                val fileName = "ezcar-backup-${timestamp()}.json"
                val uri = withContext(Dispatchers.IO) { writeBytesToDownloads(fileName, "application/json", archiveBytes) }
                val dealerId = CloudSyncEnvironment.currentDealerId
                if (dealerId != null) {
                    cloudSyncManager.uploadBackupArchive(fileName, dealerId, archiveBytes)
                }
                if (uri == null) {
                    _uiState.update { it.copy(isProcessing = false, message = "Archive export failed") }
                } else {
                    _uiState.update { it.copy(isProcessing = false, shareUri = uri, shareMimeType = "application/json") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isProcessing = false, message = e.message ?: "Archive export failed") }
            }
        }
    }

    private fun exportCsv(prefix: String, buildCsv: suspend () -> String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, message = null) }
            try {
                val csv = withContext(Dispatchers.IO) { buildCsv() }
                val fileName = "${prefix}-${timestamp()}.csv"
                val uri = withContext(Dispatchers.IO) { writeCsvToDownloads(fileName, csv) }
                if (uri == null) {
                    _uiState.update { it.copy(isProcessing = false, message = "Export failed") }
                } else {
                    _uiState.update { it.copy(isProcessing = false, shareUri = uri, shareMimeType = "text/csv") }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isProcessing = false, message = e.message ?: "Export failed") }
            }
        }
    }

    private suspend fun buildExpensesCsv(startDate: Date?, endDate: Date?): String {
        val db = databaseProvider.currentDatabase()
        val expenses = db.expenseDao().getAllIncludingDeleted()
            .filter { it.deletedAt == null }
            .filter { expense ->
                val date = expense.date
                val afterStart = startDate == null || !date.before(startDate)
                val beforeEnd = endDate == null || !date.after(endDate)
                afterStart && beforeEnd
            }
        val vehicles = db.vehicleDao().getAllIncludingDeleted().associateBy { it.id }
        val users = db.userDao().getAllIncludingDeleted().associateBy { it.id }
        val accounts = db.financialAccountDao().getAllIncludingDeleted().associateBy { it.id }
        val df = SimpleDateFormat("MM/dd/yyyy HH:mm", Locale.US)

        val header = listOf(
            "Date",
            "Description",
            "Category",
            "Amount",
            "Vehicle",
            "User",
            "Account"
        )
        val rows = expenses.map { expense ->
            val dateStr = df.format(expense.date)
            val vehicle = vehicles[expense.vehicleId]
            val vehicleName = listOfNotNull(vehicle?.make, vehicle?.model).joinToString(" ")
            val userName = users[expense.userId]?.name ?: ""
            val accountName = accounts[expense.accountId]?.accountType ?: ""
            listOf(
                dateStr,
                expense.expenseDescription ?: "",
                expense.category,
                expense.amount.toPlainString(),
                vehicleName,
                userName,
                accountName
            )
        }
        return buildCsv(header, rows)
    }

    private suspend fun buildVehiclesCsv(): String {
        val db = databaseProvider.currentDatabase()
        val vehicles = db.vehicleDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        val header = listOf("VIN", "Make", "Model", "Year", "Purchase Price", "Status", "Notes", "Created At")
        val rows = vehicles.map { vehicle ->
            listOf(
                vehicle.vin,
                vehicle.make ?: "",
                vehicle.model ?: "",
                vehicle.year?.toString() ?: "",
                vehicle.purchasePrice.toPlainString(),
                vehicle.status,
                vehicle.notes ?: "",
                df.format(vehicle.createdAt)
            )
        }
        return buildCsv(header, rows)
    }

    private suspend fun buildClientsCsv(): String {
        val db = databaseProvider.currentDatabase()
        val clients = db.clientDao().getAllIncludingDeleted().filter { it.deletedAt == null }
        val df = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        val header = listOf("Name", "Phone", "Email", "Notes", "Created At", "Next Reminder")
        val rows = clients.map { client ->
            val reminder = db.clientReminderDao().getByClient(client.id).firstOrNull()
            val reminderDate = reminder?.dueDate?.let { df.format(it) } ?: ""
            listOf(
                client.name,
                client.phone ?: "",
                client.email ?: "",
                client.notes ?: "",
                df.format(client.createdAt),
                reminderDate
            )
        }
        return buildCsv(header, rows)
    }

    private suspend fun buildReportPdf(startDate: Date, endDate: Date): ByteArray {
        val data = prepareReportData(startDate, endDate)
        val pdf = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(612, 792, 1).create()
        val page = pdf.startPage(pageInfo)
        val canvas = page.canvas

        val titlePaint = Paint().apply {
            textSize = 22f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val sectionPaint = Paint().apply {
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val bodyPaint = Paint().apply {
            textSize = 12f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        }

        var y = 50f
        canvas.drawText("Car Dealer Tracker", 40f, y, bodyPaint)
        y += 20f
        canvas.drawText("Executive Summary", 40f, y, titlePaint)
        y += 30f

        val rangeText = "Period: ${data.rangeLabel}"
        canvas.drawText(rangeText, 40f, y, bodyPaint)
        y += 24f

        canvas.drawText("Financial Overview", 40f, y, sectionPaint)
        y += 20f
        drawKeyValue(canvas, "Total Sales", data.totalSales, 40f, y, bodyPaint)
        y += 18f
        drawKeyValue(canvas, "Total Expenses", data.totalExpenses, 40f, y, bodyPaint)
        y += 18f
        drawKeyValue(canvas, "Estimated Profit", data.totalProfit, 40f, y, bodyPaint)
        y += 18f
        drawKeyValue(canvas, "Sold Vehicles", data.soldCount.toString(), 40f, y, bodyPaint)
        y += 18f
        drawKeyValue(canvas, "Inventory Count", data.inventoryCount.toString(), 40f, y, bodyPaint)
        y += 28f

        canvas.drawText("Top Sold Vehicles", 40f, y, sectionPaint)
        y += 20f
        data.topSoldVehicles.take(5).forEach { line ->
            canvas.drawText(line, 40f, y, bodyPaint)
            y += 16f
        }

        pdf.finishPage(page)

        val output = ByteArrayOutputStream()
        pdf.writeTo(output)
        pdf.close()
        return output.toByteArray()
    }

    private suspend fun buildArchiveJson(startDate: Date, endDate: Date): ByteArray {
        val stamp = timestamp()
        val expensesCsv = buildExpensesCsv(startDate, endDate)
        val vehiclesCsv = buildVehiclesCsv()
        val clientsCsv = buildClientsCsv()
        val pdfBytes = buildReportPdf(startDate, endDate)
        val metadata = prepareReportData(startDate, endDate)

        val payload = BackupArchivePayload(
            generatedAt = DateUtils.formatDateAndTime(Date()),
            rangeStart = DateUtils.formatDateAndTime(startDate),
            rangeEnd = DateUtils.formatDateAndTime(endDate),
            metadata = BackupMetadata(
                totalExpenses = metadata.totalExpenses,
                totalSales = metadata.totalSales,
                totalProfit = metadata.totalProfit,
                inventoryCount = metadata.inventoryCount,
                soldCount = metadata.soldCount
            ),
            files = listOf(
                ArchiveFilePayload(
                    name = "expenses-${stamp}.csv",
                    contentType = "text/csv",
                    base64 = Base64.encodeToString(expensesCsv.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                ),
                ArchiveFilePayload(
                    name = "vehicles-${stamp}.csv",
                    contentType = "text/csv",
                    base64 = Base64.encodeToString(vehiclesCsv.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                ),
                ArchiveFilePayload(
                    name = "clients-${stamp}.csv",
                    contentType = "text/csv",
                    base64 = Base64.encodeToString(clientsCsv.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                ),
                ArchiveFilePayload(
                    name = "report-${stamp}.pdf",
                    contentType = "application/pdf",
                    base64 = Base64.encodeToString(pdfBytes, Base64.NO_WRAP)
                )
            )
        )

        val json = Json { prettyPrint = true }
        return json.encodeToString(payload).toByteArray(Charsets.UTF_8)
    }

    private suspend fun prepareReportData(startDate: Date, endDate: Date): ReportData {
        val db = databaseProvider.currentDatabase()
        val expenses = db.expenseDao().getAllIncludingDeleted()
            .filter { it.deletedAt == null }
            .filter { !it.date.before(startDate) && !it.date.after(endDate) }
        val vehicles = db.vehicleDao().getAllIncludingDeleted().filter { it.deletedAt == null }

        val inventoryCount = vehicles.count { it.status != "sold" }
        val soldVehicles = vehicles.filter { it.status == "sold" && it.saleDate != null }
            .filter { sale ->
                val date = sale.saleDate ?: return@filter false
                !date.before(startDate) && !date.after(endDate)
            }

        val totalExpenses = expenses.fold(BigDecimal.ZERO) { total, expense -> total + expense.amount }
        val totalSales = soldVehicles.fold(BigDecimal.ZERO) { total, vehicle ->
            total + (vehicle.salePrice ?: BigDecimal.ZERO)
        }

        val expensesByVehicle = expenses.filter { it.vehicleId != null }.groupBy { it.vehicleId }
        val totalProfit = soldVehicles.fold(BigDecimal.ZERO) { total, vehicle ->
            val salePrice = vehicle.salePrice ?: BigDecimal.ZERO
            val purchasePrice = vehicle.purchasePrice
            val vehicleExpenses = expensesByVehicle[vehicle.id].orEmpty().fold(BigDecimal.ZERO) { sum, exp -> sum + exp.amount }
            total + (salePrice - purchasePrice - vehicleExpenses)
        }

        val dateFormatter = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
        val rangeLabel = "${dateFormatter.format(startDate)} - ${dateFormatter.format(endDate)}"
        val topSold = soldVehicles.sortedByDescending { it.salePrice ?: BigDecimal.ZERO }.map { vehicle ->
            val title = listOfNotNull(vehicle.make, vehicle.model).joinToString(" ").ifBlank { vehicle.vin }
            val price = regionSettingsManager.formatCurrency(vehicle.salePrice ?: BigDecimal.ZERO)
            "$title • $price"
        }

        return ReportData(
            rangeLabel = rangeLabel,
            totalExpenses = regionSettingsManager.formatCurrency(totalExpenses),
            totalSales = regionSettingsManager.formatCurrency(totalSales),
            totalProfit = regionSettingsManager.formatCurrency(totalProfit),
            inventoryCount = inventoryCount,
            soldCount = soldVehicles.size,
            topSoldVehicles = topSold
        )
    }

    private fun drawKeyValue(canvas: Canvas, label: String, value: String, x: Float, y: Float, paint: Paint) {
        canvas.drawText(label, x, y, paint)
        val textWidth = paint.measureText(value)
        canvas.drawText(value, 560f - textWidth, y, paint)
    }

    private fun buildCsv(header: List<String>, rows: List<List<String>>): String {
        val builder = StringBuilder()
        builder.append(header.joinToString(",") { escapeCsv(it) })
        builder.append("\n")
        for (row in rows) {
            builder.append(row.joinToString(",") { escapeCsv(it) })
            builder.append("\n")
        }
        return builder.toString()
    }

    private fun escapeCsv(value: String): String {
        val escaped = value.replace("\"", "\"\"")
        return "\"$escaped\""
    }

    private fun writeCsvToDownloads(fileName: String, content: String): Uri? {
        return writeBytesToDownloads(fileName, "text/csv", content.toByteArray(Charsets.UTF_8))
    }

    private fun writeBytesToDownloads(fileName: String, mimeType: String, bytes: ByteArray): Uri? {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Ezcar24")
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        resolver.openOutputStream(uri)?.use { stream ->
            stream.write(bytes)
        }
        return uri
    }

    private fun timestamp(): String {
        return SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
    }
}

@Serializable
private data class BackupArchivePayload(
    val generatedAt: String,
    val rangeStart: String,
    val rangeEnd: String,
    val metadata: BackupMetadata,
    val files: List<ArchiveFilePayload>
)

@Serializable
private data class BackupMetadata(
    val totalExpenses: String,
    val totalSales: String,
    val totalProfit: String,
    val inventoryCount: Int,
    val soldCount: Int
)

@Serializable
private data class ArchiveFilePayload(
    val name: String,
    val contentType: String,
    val base64: String
)

private data class ReportData(
    val rangeLabel: String,
    val totalExpenses: String,
    val totalSales: String,
    val totalProfit: String,
    val inventoryCount: Int,
    val soldCount: Int,
    val topSoldVehicles: List<String>
)
