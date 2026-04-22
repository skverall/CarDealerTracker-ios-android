package com.ezcar24.business.util

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.util.Calendar
import java.util.Date
import java.util.TimeZone

class DateUtilsTest {
    private lateinit var originalTimeZone: TimeZone

    @Before
    fun setUp() {
        originalTimeZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(originalTimeZone)
    }

    @Test
    fun `parseRemoteExpenseDate normalizes legacy migrated timestamp to local midnight`() {
        val createdAt = Date.from(Instant.parse("2026-03-28T15:02:36Z"))

        val parsedDate = DateUtils.parseRemoteExpenseDate(
            "2026-03-28T15:02:36.000Z",
            createdAt
        )!!

        val calendar = Calendar.getInstance()
        calendar.time = parsedDate

        assertEquals(2026, calendar.get(Calendar.YEAR))
        assertEquals(Calendar.MARCH, calendar.get(Calendar.MONTH))
        assertEquals(28, calendar.get(Calendar.DAY_OF_MONTH))
        assertEquals(0, calendar.get(Calendar.HOUR_OF_DAY))
        assertEquals(0, calendar.get(Calendar.MINUTE))
        assertEquals(0, calendar.get(Calendar.SECOND))
    }

    @Test
    fun `parseRemoteExpenseDate keeps real post migration timestamp`() {
        val createdAt = Date.from(Instant.parse("2026-04-21T18:07:42Z"))
        val parsedDate = DateUtils.parseRemoteExpenseDate(
            "2026-04-21T18:07:42.000Z",
            createdAt
        )

        assertEquals(createdAt.time, parsedDate!!.time)
    }

    @Test
    fun `parseRemoteExpenseDate treats utc midnight timestamp as floating day`() {
        val createdAt = Date.from(Instant.parse("2026-04-21T18:07:42Z"))
        val parsedDate = DateUtils.parseRemoteExpenseDate(
            "2026-04-21T00:00:00.000Z",
            createdAt
        )!!

        val calendar = Calendar.getInstance()
        calendar.time = parsedDate

        assertEquals(2026, calendar.get(Calendar.YEAR))
        assertEquals(Calendar.APRIL, calendar.get(Calendar.MONTH))
        assertEquals(21, calendar.get(Calendar.DAY_OF_MONTH))
        assertEquals(0, calendar.get(Calendar.HOUR_OF_DAY))
    }

    @Test
    fun `encodeRemoteExpenseDate always returns timestamp format`() {
        val midnight = Calendar.getInstance().apply {
            clear()
            set(2026, Calendar.APRIL, 22, 0, 0, 0)
        }.time

        val encoded = DateUtils.encodeRemoteExpenseDate(midnight)

        assertTrue(encoded.contains("T"))
    }

    @Test
    fun `encodeRemoteCalendarDate omits timestamp`() {
        val midnight = Calendar.getInstance().apply {
            clear()
            set(2026, Calendar.APRIL, 22, 0, 0, 0)
        }.time

        val encoded = DateUtils.encodeRemoteCalendarDate(midnight)

        assertTrue(!encoded.contains("T"))
        assertEquals(10, encoded.length)
    }
}
