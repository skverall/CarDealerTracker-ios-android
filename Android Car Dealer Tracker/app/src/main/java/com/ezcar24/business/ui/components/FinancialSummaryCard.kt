package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal
import java.math.RoundingMode
import com.ezcar24.business.util.localizedUiString

data class FinancialSummaryData(
    val purchasePrice: BigDecimal,
    val totalExpenses: BigDecimal,
    val holdingCost: BigDecimal,
    val totalCost: BigDecimal,
    val expenseBreakdown: Map<ExpenseCategoryType, BigDecimal> = emptyMap(),
    val askingPrice: BigDecimal? = null,
    val salePrice: BigDecimal? = null,
    val projectedROI: BigDecimal? = null,
    val actualROI: BigDecimal? = null,
    val daysInInventory: Int = 0,
    val agingBucket: String = "0-30",
    val dailyHoldingCost: BigDecimal = BigDecimal.ZERO,
    val reportUrl: String? = null
)

@Composable
fun FinancialSummaryCard(
    data: FinancialSummaryData,
    onEditAskingPrice: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Color.White, RoundedCornerShape(12.dp))
        .padding(16.dp)
    ) {
        Text(
            text = localizedUiString("Financial Summary"),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )

        Spacer(modifier = Modifier.height(16.dp))

        if (data.daysInInventory > 0 && data.salePrice == null) {
            FinancialDetailTextRow(
                label = localizedUiString("Days in Inventory:"),
                value = localizedUiString("%1\$d days (%2\$s)", data.daysInInventory, data.agingBucket),
                valueColor = when (data.agingBucket) {
                    "0-30" -> EzcarGreen
                    "31-60" -> EzcarOrange
                    "61-90" -> EzcarOrange
                    else -> EzcarOrange
                }
            )

            HorizontalDivider(
                modifier = Modifier.padding(vertical = 12.dp),
                color = Color(0xFFE5E5EA)
            )
        }

        if (data.askingPrice != null && data.askingPrice > BigDecimal.ZERO) {
            FinancialRow(
                label = localizedUiString("Asking Price"),
                amount = data.askingPrice,
                color = EzcarNavy
            )
        }

        data.reportUrl?.trim()?.takeIf { it.isNotEmpty() }?.let { reportUrl ->
            ReportLinkRow(reportUrl = reportUrl)
        }

        FinancialRow(
            label = localizedUiString("Purchase Price"),
            amount = data.purchasePrice,
            color = Color.Black
        )

        if (data.expenseBreakdown.isNotEmpty()) {
            data.expenseBreakdown.forEach { (type, amount) ->
                if (amount > BigDecimal.ZERO) {
                    FinancialRow(
                        label = localizedUiString(getExpenseTypeLabel(type)),
                        amount = amount,
                        color = Color.Gray,
                        isIndented = true
                    )
                }
            }
        } else {
            FinancialRow(
                label = localizedUiString("Expenses"),
                amount = data.totalExpenses,
                color = Color.Gray,
                isIndented = true
            )
        }

        if (data.holdingCost > BigDecimal.ZERO) {
            FinancialRow(
                label = localizedUiString("%1\$s (%2\$d days)", localizedUiString("Holding Cost"), data.daysInInventory),
                amount = data.holdingCost,
                color = EzcarOrange,
                isIndented = true
            )

            if (data.dailyHoldingCost > BigDecimal.ZERO) {
                FinancialRow(
                    label = localizedUiString("Holding Cost / Day"),
                    amount = data.dailyHoldingCost,
                    color = EzcarOrange,
                    isIndented = true
                )
            }
        }

        HorizontalDivider(
            modifier = Modifier.padding(vertical = 12.dp),
            color = Color(0xFFE5E5EA)
        )

        FinancialRow(
            label = localizedUiString("Total Cost"),
            amount = data.totalCost,
            color = EzcarGreen,
            isBold = true
        )

        if (data.askingPrice != null && data.askingPrice > BigDecimal.ZERO) {
            data.projectedROI?.let { roi ->
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 12.dp),
                    color = Color(0xFFE5E5EA)
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = localizedUiString("Projected ROI"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                    ROIBadge(roiPercent = roi)
                }
            }
        }

        if (data.salePrice != null && data.salePrice > BigDecimal.ZERO) {
            Spacer(modifier = Modifier.height(12.dp))
            FinancialRow(
                label = localizedUiString("Sale Price"),
                amount = data.salePrice,
                color = EzcarSuccess
            )

            data.actualROI?.let { roi ->
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = localizedUiString("Actual ROI"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.Gray
                    )
                    ROIBadge(roiPercent = roi)
                }
            }
        }
    }
}

@Composable
fun RecommendedPricingCard(
    breakEvenPrice: BigDecimal,
    recommendedPrice: BigDecimal,
    currentAskingPrice: BigDecimal?,
    onUpdateAskingPrice: ((BigDecimal) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var showEditDialog by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(EzcarNavy.copy(alpha = 0.05f), RoundedCornerShape(12.dp))
        .padding(16.dp)
    ) {
        Text(
            text = localizedUiString("Pricing Recommendations"),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = EzcarNavy
        )

        Spacer(modifier = Modifier.height(16.dp))

        FinancialRow(
            label = localizedUiString("Break-even Price"),
            amount = breakEvenPrice,
            color = Color.Gray
        )

        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = localizedUiString("Recommended (20% ROI)"),
                style = MaterialTheme.typography.bodyMedium,
                color = EzcarGreen,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = regionSettingsManager.formatCurrency(recommendedPrice),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Bold,
                color = EzcarGreen
            )
        }

        if (currentAskingPrice != null && currentAskingPrice > BigDecimal.ZERO) {
            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(color = Color.LightGray.copy(alpha = 0.3f))
            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = localizedUiString("Current Asking Price"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.Black
                )

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = regionSettingsManager.formatCurrency(currentAskingPrice),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Bold,
                        color = Color.Black
                    )

                    if (onUpdateAskingPrice != null) {
                        Spacer(modifier = Modifier.width(8.dp))
                        IconButton(
                            onClick = { showEditDialog = true },
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Edit,
                                contentDescription = localizedUiString("Edit"),
                                tint = EzcarNavy,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            val difference = currentAskingPrice.subtract(recommendedPrice)
            val percentDiff = if (recommendedPrice.compareTo(BigDecimal.ZERO) > 0) {
                difference.multiply(BigDecimal(100)).divide(recommendedPrice, 1, RoundingMode.HALF_UP)
            } else {
                BigDecimal.ZERO
            }

            if (difference.compareTo(BigDecimal.ZERO) != 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = if (difference > BigDecimal.ZERO) {
                        localizedUiString(
                            "%1\$s above recommended",
                            "${regionSettingsManager.formatCurrency(difference)} (${percentDiff.abs().toInt()}%)"
                        )
                    } else {
                        localizedUiString(
                            "%1\$s below recommended",
                            "${regionSettingsManager.formatCurrency(difference.abs())} (${percentDiff.abs().toInt()}%)"
                        )
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = if (difference > BigDecimal.ZERO) EzcarGreen else EzcarOrange
                )
            }
        }
    }

    if (showEditDialog && onUpdateAskingPrice != null) {
        EditAskingPriceDialog(
            currentPrice = currentAskingPrice ?: BigDecimal.ZERO,
            recommendedPrice = recommendedPrice,
            currencyCode = regionState.selectedRegion.currencyCode,
            onDismiss = { showEditDialog = false },
            onConfirm = { newPrice ->
                onUpdateAskingPrice(newPrice)
                showEditDialog = false
            }
        )
    }
}

@Composable
private fun FinancialRow(
    label: String,
    amount: BigDecimal,
    color: Color,
    isBold: Boolean = false,
    isIndented: Boolean = false
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .padding(start = if (isIndented) 16.dp else 0.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isBold) Color.Black else color,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal
        )
        Text(
            text = regionSettingsManager.formatCurrency(amount),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isBold) FontWeight.Bold else FontWeight.SemiBold,
            color = color
        )
    }
}

@Composable
private fun EditAskingPriceDialog(
    currentPrice: BigDecimal,
    recommendedPrice: BigDecimal,
    currencyCode: String,
    onDismiss: () -> Unit,
    onConfirm: (BigDecimal) -> Unit
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val regionState by regionSettingsManager.state.collectAsState()
    var priceText by remember { mutableStateOf(currentPrice.toPlainString()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedUiString("Update Asking Price")) },
        text = {
            Column {
                Text(
                    text = localizedUiString("Recommended: %1\$s", regionSettingsManager.formatCurrency(recommendedPrice)),
                    style = MaterialTheme.typography.bodyMedium,
                    color = EzcarGreen
                )
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedTextField(
                    value = priceText,
                    onValueChange = { priceText = it },
                    label = { Text(localizedUiString("Asking Price")) },
                    prefix = { Text(currencyCode) },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    priceText.toBigDecimalOrNull()?.let { onConfirm(it) }
                }
            ) {
                Text(localizedUiString("Save"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedUiString("Cancel"))
            }
        }
    )
}

private fun getExpenseTypeLabel(type: ExpenseCategoryType): String {
    return when (type) {
        ExpenseCategoryType.HOLDING_COST -> "Holding Cost"
        ExpenseCategoryType.IMPROVEMENT -> "Improvements"
        ExpenseCategoryType.OPERATIONAL -> "Operational"
    }
}

@Composable
private fun ReportLinkRow(reportUrl: String) {
    val uriHandler = LocalUriHandler.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = localizedUiString("Inspection Report"),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )
        TextButton(onClick = { runCatching { uriHandler.openUri(reportUrl) } }) {
            Text(localizedUiString("View Report"))
            Spacer(modifier = Modifier.width(4.dp))
            Icon(
                imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                contentDescription = null,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
private fun FinancialDetailTextRow(
    label: String,
    value: String,
    valueColor: Color = Color.Black
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor,
            fontWeight = FontWeight.Medium
        )
    }
}
