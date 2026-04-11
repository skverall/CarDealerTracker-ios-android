package com.ezcar24.business.util

import com.ezcar24.business.data.local.Expense
import java.util.Calendar
import java.util.Date

fun expenseDisplayDateTime(expense: Expense): Date {
    val expenseDate = expense.date
    val expenseCalendar = Calendar.getInstance().apply { time = expenseDate }
    val hasExplicitTime =
        expenseCalendar.get(Calendar.HOUR_OF_DAY) != 0 ||
            expenseCalendar.get(Calendar.MINUTE) != 0 ||
            expenseCalendar.get(Calendar.SECOND) != 0 ||
            expenseCalendar.get(Calendar.MILLISECOND) != 0

    if (hasExplicitTime) {
        return expenseDate
    }

    val timeSource = expense.createdAt

    val dateCalendar = Calendar.getInstance().apply { time = expenseDate }
    val timeCalendar = Calendar.getInstance().apply { time = timeSource }

    return Calendar.getInstance().apply {
        clear()
        set(
            dateCalendar.get(Calendar.YEAR),
            dateCalendar.get(Calendar.MONTH),
            dateCalendar.get(Calendar.DAY_OF_MONTH),
            timeCalendar.get(Calendar.HOUR_OF_DAY),
            timeCalendar.get(Calendar.MINUTE),
            timeCalendar.get(Calendar.SECOND)
        )
        set(Calendar.MILLISECOND, timeCalendar.get(Calendar.MILLISECOND))
    }.time
}
