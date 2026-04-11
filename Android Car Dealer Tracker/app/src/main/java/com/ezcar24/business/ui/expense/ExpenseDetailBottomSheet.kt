package com.ezcar24.business.ui.expense

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.Today
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.unit.dp
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseCategoryType
import com.ezcar24.business.ui.theme.EzcarBackgroundLight
import com.ezcar24.business.ui.theme.EzcarNavy
import com.ezcar24.business.util.expenseDisplayDateTime
import com.ezcar24.business.util.rememberRegionSettingsManager
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseDetailBottomSheet(
    expense: Expense,
    vehicleTitle: String?,
    onDismiss: () -> Unit,
    onSaveComment: (Expense, String) -> Unit,
    onViewReceipt: (Expense) -> Unit = {},
    onReplaceReceipt: (Expense, ExpenseReceiptDraft, (Expense) -> Unit) -> Unit = { _, _, _ -> },
    onRemoveReceipt: (Expense, (Expense) -> Unit) -> Unit = { _, _ -> }
) {
    val regionSettingsManager = rememberRegionSettingsManager()
    val context = LocalContext.current
    var currentExpense by remember(expense.id) { mutableStateOf(expense) }
    var commentDraft by remember(expense.id, expense.expenseDescription) {
        mutableStateOf(expense.expenseDescription.orEmpty())
    }
    var showReceiptActionsSheet by remember(currentExpense.id) { mutableStateOf(false) }
    val openReceiptPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            val draft = readExpenseReceipt(context, uri)
            if (draft != null) {
                onReplaceReceipt(currentExpense, draft) { updatedExpense ->
                    currentExpense = updatedExpense
                    Toast.makeText(context, "Receipt updated", Toast.LENGTH_SHORT).show()
                }
            } else {
                Toast.makeText(context, "Could not attach receipt", Toast.LENGTH_SHORT).show()
            }
        }
    }
    val takePhotoLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicturePreview()
    ) { bitmap ->
        if (bitmap != null) {
            onReplaceReceipt(currentExpense, bitmap.toExpenseReceipt()) { updatedExpense ->
                currentExpense = updatedExpense
                Toast.makeText(context, "Receipt updated", Toast.LENGTH_SHORT).show()
            }
        }
    }

    val title = remember(currentExpense.category, currentExpense.expenseDescription) {
        currentExpense.expenseDescription
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: expenseCategoryTitle(currentExpense.category)
    }
    val dateLabel = remember(currentExpense.date, currentExpense.createdAt) {
        SimpleDateFormat("MMM dd, yyyy • HH:mm", Locale.getDefault())
            .format(expenseDisplayDateTime(currentExpense))
    }
    val receiptPath = currentExpense.receiptPath

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.fillMaxHeight(0.9f),
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = EzcarBackgroundLight,
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Expense Details",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close"
                    )
                }
            }

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Column(modifier = Modifier.padding(horizontal = 20.dp)) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = regionSettingsManager.formatCurrency(currentExpense.amount),
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                            color = EzcarNavy
                        )
                    }
                }

                item {
                    Card(
                        modifier = Modifier
                            .padding(horizontal = 20.dp)
                            .fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color.White),
                        shape = RoundedCornerShape(18.dp)
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            ExpenseMetaRow(
                                icon = Icons.Default.Tag,
                                label = "Category",
                                value = expenseCategoryTitle(currentExpense.category)
                            )
                            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                            ExpenseMetaRow(
                                icon = Icons.Default.DirectionsCar,
                                label = "Vehicle",
                                value = vehicleTitle?.takeIf { it.isNotBlank() } ?: "No vehicle linked"
                            )
                            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                            ExpenseMetaRow(
                                icon = Icons.Default.Today,
                                label = "Date",
                                value = dateLabel
                            )
                            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                            ExpenseMetaRow(
                                icon = Icons.Default.WorkspacePremium,
                                label = "Expense Type",
                                value = expenseTypeLabel(currentExpense.expenseType)
                            )
                            if (!receiptPath.isNullOrBlank()) {
                                HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                                ExpenseMetaRow(
                                    icon = Icons.Default.Description,
                                    label = "Receipt",
                                    value = receiptPath.substringAfterLast('/')
                                )
                            }
                        }
                    }
                }

                if (!receiptPath.isNullOrBlank()) {
                    item {
                        Column(modifier = Modifier.padding(horizontal = 20.dp)) {
                            OutlinedButton(
                                onClick = { onViewReceipt(currentExpense) },
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(16.dp)
                            ) {
                                Text("View Receipt")
                            }
                        }
                    }
                }

                item {
                    Column(modifier = Modifier.padding(horizontal = 20.dp)) {
                        OutlinedButton(
                            onClick = { showReceiptActionsSheet = true },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Text(
                                if (receiptPath.isNullOrBlank()) {
                                    "Attach Receipt"
                                } else {
                                    "Manage Receipt"
                                }
                            )
                        }
                    }
                }

                item {
                    Column(modifier = Modifier.padding(horizontal = 20.dp)) {
                        Text(
                            text = "Comment",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedTextField(
                            value = commentDraft,
                            onValueChange = { commentDraft = it },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = {
                                Text("Add a note (what was this expense for?)")
                            },
                            minLines = 4,
                            maxLines = 6,
                            shape = RoundedCornerShape(16.dp)
                        )
                    }
                }
            }

            HorizontalDivider()

            Button(
                onClick = {
                    onSaveComment(currentExpense, commentDraft)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = EzcarNavy,
                    contentColor = Color.White
                )
            ) {
                Text(
                    text = "Save Comment",
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }
        }

        if (showReceiptActionsSheet) {
            ModalBottomSheet(
                onDismissRequest = { showReceiptActionsSheet = false },
                containerColor = Color.White
            ) {
                ReceiptActionSheet(
                    hasReceipt = !receiptPath.isNullOrBlank(),
                    receiptLabel = receiptPath?.substringAfterLast('/'),
                    onDismiss = { showReceiptActionsSheet = false },
                    onTakePhoto = {
                        showReceiptActionsSheet = false
                        takePhotoLauncher.launch(null)
                    },
                    onChooseFile = {
                        showReceiptActionsSheet = false
                        openReceiptPickerLauncher.launch(arrayOf("image/*", "application/pdf"))
                    },
                    onRemove = {
                        showReceiptActionsSheet = false
                        onRemoveReceipt(currentExpense) { updatedExpense ->
                            currentExpense = updatedExpense
                            Toast.makeText(context, "Receipt removed", Toast.LENGTH_SHORT).show()
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun ExpenseMetaRow(
    icon: ImageVector,
    label: String,
    value: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = EzcarNavy
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = androidx.compose.ui.graphics.Color.Gray
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge
            )
        }
    }
}

private fun readExpenseReceipt(context: android.content.Context, uri: android.net.Uri): ExpenseReceiptDraft? {
    return readExpenseReceiptDraft(context, uri)
}

private fun android.graphics.Bitmap.toExpenseReceipt(): ExpenseReceiptDraft {
    return toExpenseReceiptDraft()
}

internal fun expenseCategoryTitle(category: String): String {
    return when (category.trim().lowercase(Locale.US)) {
        "vehicle" -> "Vehicle"
        "personal" -> "Personal"
        "employee" -> "Employee"
        "office", "bills" -> "Bills"
        "marketing" -> "Marketing"
        else -> category.replaceFirstChar { it.titlecase(Locale.US) }
    }
}

internal fun expenseTypeLabel(type: ExpenseCategoryType): String {
    return when (type) {
        ExpenseCategoryType.HOLDING_COST -> "Holding Cost"
        ExpenseCategoryType.IMPROVEMENT -> "Improvement"
        ExpenseCategoryType.OPERATIONAL -> "Operational"
    }
}
