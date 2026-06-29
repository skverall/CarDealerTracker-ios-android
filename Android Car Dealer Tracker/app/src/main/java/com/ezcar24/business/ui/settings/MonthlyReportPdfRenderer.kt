package com.ezcar24.business.ui.settings

import android.content.Context
import android.graphics.Color as AndroidColor
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import com.ezcar24.business.data.repository.MonthlyReportSnapshot
import com.ezcar24.business.util.RegionSettingsManager
import com.ezcar24.business.util.localizedUiString
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object MonthlyReportPdfRenderer {
    fun build(
        context: Context,
        regionSettingsManager: RegionSettingsManager,
        snapshot: MonthlyReportSnapshot,
        organizationName: String?,
        reportTitle: String = context.localizedUiString("Report: %s", snapshot.reportMonth.displayTitle()),
        periodPrefix: String = context.localizedUiString("Previous calendar month")
    ): ByteArray {
        val pdf = PdfDocument()
        val pageWidth = 612
        val pageHeight = 792
        val left = 42f
        val right = 570f
        val bottom = 744f
        val generatedFormatter = SimpleDateFormat("MMM d, yyyy HH:mm", Locale.getDefault())

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(38, 64, 102)
            textSize = 22f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val sectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(38, 64, 102)
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(31, 41, 55)
            textSize = 11.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        }
        val mutedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(100, 116, 139)
            textSize = 10.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        }
        val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(38, 64, 102)
            textSize = 11.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = AndroidColor.rgb(226, 232, 240)
            strokeWidth = 1f
        }

        var pageNumber = 1
        var page = pdf.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create())
        var canvas = page.canvas
        var y = 48f

        fun startNewPage() {
            pdf.finishPage(page)
            pageNumber += 1
            page = pdf.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create())
            canvas = page.canvas
            y = 48f
            canvas.drawText(reportTitle, left, y, sectionPaint)
            y += 28f
        }

        fun ensureSpace(required: Float) {
            if (y + required > bottom) {
                startNewPage()
            }
        }

        fun fitText(text: String, paint: Paint, maxWidth: Float): String {
            if (paint.measureText(text) <= maxWidth) {
                return text
            }
            var trimmed = text
            while (trimmed.isNotEmpty() && paint.measureText("$trimmed...") > maxWidth) {
                trimmed = trimmed.dropLast(1)
            }
            return if (trimmed.isEmpty()) "..." else "$trimmed..."
        }

        fun drawKeyValue(label: String, value: String) {
            ensureSpace(22f)
            canvas.drawText(context.localizedUiString(label), left, y, bodyPaint)
            val fittedValue = fitText(value, valuePaint, 230f)
            canvas.drawText(fittedValue, right - valuePaint.measureText(fittedValue), y, valuePaint)
            y += 19f
        }

        fun drawSection(title: String) {
            ensureSpace(34f)
            y += 8f
            canvas.drawText(context.localizedUiString(title), left, y, sectionPaint)
            y += 9f
            canvas.drawLine(left, y, right, y, linePaint)
            y += 16f
        }

        fun drawLine(text: String, paint: Paint = bodyPaint) {
            ensureSpace(17f)
            canvas.drawText(fitText(text, paint, right - left), left, y, paint)
            y += 16f
        }

        fun money(amount: BigDecimal): String {
            return regionSettingsManager.formatCurrency(amount)
        }

        fun drawEmpty(message: String) {
            drawLine(context.localizedUiString(message), mutedPaint)
        }

        canvas.drawText(context.localizedUiString("Car Dealer Tracker"), left, y, mutedPaint)
        y += 26f
        canvas.drawText(reportTitle, left, y, titlePaint)
        y += 24f
        organizationName?.takeIf { it.isNotBlank() }?.let {
            canvas.drawText(fitText(it, bodyPaint, right - left), left, y, bodyPaint)
            y += 18f
        }
        canvas.drawText("$periodPrefix: ${snapshot.periodLabel}", left, y, bodyPaint)
        y += 17f
        canvas.drawText(context.localizedUiString("Generated %s", generatedFormatter.format(snapshot.generatedAt)), left, y, mutedPaint)
        y += 20f
        canvas.drawLine(left, y, right, y, linePaint)
        y += 14f

        val summary = snapshot.executiveSummary
        drawSection("Executive brief")
        drawKeyValue("Total revenue", money(summary.totalRevenue))
        drawKeyValue("Realized sales profit", money(summary.realizedSalesProfit))
        drawKeyValue("Monthly expenses", money(summary.monthlyExpenses))
        drawKeyValue("Net cash movement", money(summary.netCashMovement))

        drawSection("Financial overview")
        drawKeyValue("Vehicle revenue", money(summary.vehicleRevenue))
        drawKeyValue("Part revenue", money(summary.partRevenue))
        drawKeyValue("Vehicle profit", money(summary.vehicleProfit))
        drawKeyValue("Part profit", money(summary.partProfit))
        drawKeyValue("Inventory capital", money(summary.inventoryCapital))
        drawKeyValue("Parts stock cost", money(summary.partsInventoryCost))

        drawSection("Expense mix")
        if (snapshot.expenseCategories.isEmpty()) {
            drawEmpty("No expenses recorded in this month.")
        } else {
            snapshot.expenseCategories.take(8).forEach { category ->
                drawLine("${category.title} - ${money(category.amount)} - ${context.localizedUiString("%d entries", category.count)}")
            }
        }

        drawSection("Vehicle sales")
        if (snapshot.vehicleSales.isEmpty()) {
            drawEmpty("No vehicle sales recorded in this month.")
        } else {
            snapshot.vehicleSales.take(8).forEach { sale ->
                drawLine("${sale.title} - ${shortDate(sale.soldAt)} - ${money(sale.revenue)} - ${context.localizedUiString("Profit %s", money(sale.realizedProfit))}")
            }
        }

        drawSection("Part sales")
        if (snapshot.partSales.isEmpty()) {
            drawEmpty("No part sales recorded in this month.")
        } else {
            snapshot.partSales.take(8).forEach { sale ->
                drawLine("${sale.summary} - ${shortDate(sale.soldAt)} - ${money(sale.revenue)} - ${context.localizedUiString("Profit %s", money(sale.realizedProfit))}")
            }
        }

        drawSection("Cash movement")
        drawKeyValue("Deposits", money(snapshot.cashMovement.depositsTotal))
        drawKeyValue("Withdrawals", money(snapshot.cashMovement.withdrawalsTotal))
        drawKeyValue("Net movement", money(snapshot.cashMovement.netMovement))
        drawKeyValue("Transactions", snapshot.cashMovement.transactionCount.toString())

        drawSection("Inventory snapshot")
        drawKeyValue("Vehicles in stock", snapshot.inventory.vehicleCount.toString())
        drawKeyValue("Vehicle capital", money(snapshot.inventory.vehicleCapital))
        drawKeyValue("Parts in stock", snapshot.inventory.partsUnitsInStock.stripTrailingZeros().toPlainString())
        drawKeyValue("Parts stock cost", money(snapshot.inventory.partsInventoryCost))

        drawSection("Top profitable vehicles")
        if (snapshot.topProfitableVehicles.isEmpty()) {
            drawEmpty("No profitable vehicle sales in this month.")
        } else {
            snapshot.topProfitableVehicles.forEach { sale ->
                drawLine("${sale.title} - ${money(sale.realizedProfit)}")
            }
        }

        drawSection("Loss-making vehicles")
        if (snapshot.lossMakingVehicles.isEmpty()) {
            drawEmpty("No loss-making vehicle sales in this month.")
        } else {
            snapshot.lossMakingVehicles.forEach { sale ->
                drawLine("${sale.title} - ${money(sale.realizedProfit)}")
            }
        }

        pdf.finishPage(page)
        val output = ByteArrayOutputStream()
        pdf.writeTo(output)
        pdf.close()
        return output.toByteArray()
    }

    private fun shortDate(date: Date): String {
        return SimpleDateFormat("MMM d", Locale.getDefault()).format(date)
    }
}
