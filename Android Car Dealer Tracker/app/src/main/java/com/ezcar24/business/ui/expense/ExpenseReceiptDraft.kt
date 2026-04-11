package com.ezcar24.business.ui.expense

data class ExpenseReceiptDraft(
    val bytes: ByteArray,
    val fileName: String,
    val contentType: String,
    val fileExtension: String
)
