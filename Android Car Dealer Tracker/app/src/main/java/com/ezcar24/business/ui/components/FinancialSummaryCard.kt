package com.ezcar24.business.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ezcar24.business.ui.theme.EzcarGreen
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.ui.theme.EzcarOrange
import com.ezcar24.business.ui.theme.EzcarSuccess
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.math.BigDecimal

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
    val agingBucket: String = "0-30"
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
            text = "Financial Summary",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )

        Spacer(modifier = Modifier.height(16.dp))

        FinancialRow(
            label = "Purchase Price",
            amount = data.purchasePrice,
            color = Color.Black
        )

        if (data.expenseBreakdown.isNotEmpty()) {
            data.expenseBreakdown.forEach { (type, amount) ->
                if (amount > BigDecimal.ZERO) {
                    FinancialRow(
                        label = "  ${getExpenseTypeLabel(type)}",
                        amount = amount,
                        color = Color.Gray,
                        isIndented = true
                    )
                }
            }
        } else {
            FinancialRow(
                label = "  Expenses",
                amount = data.totalExpenses,
                color = Color.Gray,
                isIndented = true
            )
        }

        if (data.holdingCost > BigDecimal.ZERO) {
            FinancialRow(
                label = "  Holding Cost (${data.daysInInventory} days)",
                amount = data.holdingCost,
                color = EzcarOrange,
                isIndented = true
            )
        }

        HorizontalDivider(
            modifier = Modifier.padding(vertical = 12.dp),
            color = Color(0xFFE5E5EA)
        )

        FinancialRow(
            label = "Total Cost",
            amount = data.totalCost,
            color = EzcarGreen,
            isBold = true
        )

        if (data.askingPrice != null && data.askingPrice > BigDecimal.ZERO) {
            Spacer(modifier = Modifier.height(12.dp))
            FinancialRow(
                label = "Asking Price",
                amount = data.askingPrice,
                color = EzcarNavy
            )

            data.projectedROI?.let { roi ->
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Projected ROI",
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
                label = "Sale Price",
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
                        text = "Actual ROI",
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
            text = "Pricing Recommendations",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = EzcarNavy
        )

        Spacer(modifier = Modifier.height(16.dp))

        FinancialRow(
            label = "Break-even Price",
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
                text = "Recommended (20% ROI)",
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
                    text = "Current Asking Price",
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
                                contentDescription = "Edit",
                                tint = EzcarNavy,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            val difference = currentAskingPrice.subtract(recommendedPrice)
            val percentDiff = if (recommendedPrice.compareTo(BigDecimal.ZERO) > 0) {
                difference.multiply(BigDecimal(100)).divide(recommendedPrice, 1, BigDecimal.ROUND_HALF_UP)
            } else {
                BigDecimal.ZERO
            }

            if (difference.compareTo(BigDecimal.ZERO) != 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = if (difference > BigDecimal.ZERO) {
                        "+${regionSettingsManager.formatCurrency(difference)} (${percentDiff.toInt()}% above recommended)"
                    } else {
                        "${regionSettingsManager.formatCurrency(difference)} (${percentDiff.abs().toInt()}% below recommended)"
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
        title = { Text("Update Asking Price") },
        text = {
            Column {
                Text(
                    text = "Recommended: ${regionSettingsManager.formatCurrency(recommendedPrice)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = EzcarGreen
                )
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedTextField(
                    value = priceText,
                    onValueChange = { priceText = it },
                    label = { Text("Asking Price") },
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
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun getExpenseTypeLabel(type: ExpenseCategoryType): String {
    return when (type) {
        ExpenseCategoryType.HOLDING_COST -> "Operational"
        ExpenseCategoryType.IMPROVEMENT -> "Improvements"
        ExpenseCategoryType.OPERATIONAL -> "Holding Cost"
    }
}
