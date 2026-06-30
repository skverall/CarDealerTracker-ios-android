package com.ezcar24.business

import com.ezcar24.business.ui.dashboard.DashboardTimeRange
import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DashboardTimeRangeTest {
    @Test
    fun weekStartsSixDaysBeforeTodayLikeIos() {
        val start = DashboardTimeRange.ONE_WEEK.getStartDate()!!
        val cal = Calendar.getInstance()
        cal.time = start
        cal.add(Calendar.DAY_OF_YEAR, 6)

        assertEquals(startOfTodayMillis(), cal.timeInMillis)
    }

    @Test
    fun monthFilterStartsThirtyDaysBeforeTodayLikeIos() {
        val start = DashboardTimeRange.ONE_MONTH.getStartDate()!!
        val cal = Calendar.getInstance()
        cal.time = start
        cal.add(Calendar.DAY_OF_YEAR, 30)

        assertEquals(startOfTodayMillis(), cal.timeInMillis)
    }

    @Test
    fun allTimeHasNoLowerBoundLikeIos() {
        assertNull(DashboardTimeRange.ALL_TIME.getStartDate())
        assertNull(DashboardTimeRange.ALL_TIME.getEndDate())
    }

    private fun startOfTodayMillis(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }
}
