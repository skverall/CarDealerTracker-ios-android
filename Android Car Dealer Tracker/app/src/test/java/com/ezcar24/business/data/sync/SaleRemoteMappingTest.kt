package com.ezcar24.business.data.sync

import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

import com.ezcar24.business.data.local.Sale
import com.ezcar24.business.data.repository.DealDeskJurisdictionType
import com.ezcar24.business.data.repository.DealDeskLine
import com.ezcar24.business.data.repository.DealDeskLineCalculationType
import com.ezcar24.business.data.repository.DealDeskPaymentPlan
import com.ezcar24.business.data.repository.DealDeskSnapshot
import com.ezcar24.business.data.repository.DealDeskTotals
import com.ezcar24.business.data.repository.toJsonString
import com.ezcar24.business.util.DateUtils

class SaleRemoteMappingTest {
    @Test
    fun `sale remote payload includes iOS deal desk columns`() {
        val createdAt = Date(1_700_000_000_000)
        val updatedAt = Date(1_700_086_400_000)
        val snapshot = DealDeskSnapshot(
            templateCode = "usa",
            templateVersion = 3,
            jurisdictionType = DealDeskJurisdictionType.STATE,
            jurisdictionCode = "CA",
            taxLines = listOf(
                DealDeskLine(
                    lineCode = "sales_tax",
                    title = "Sales tax",
                    calculationType = DealDeskLineCalculationType.PERCENT_OF_SALE_PRICE,
                    value = BigDecimal("7.25")
                )
            ),
            feeLines = emptyList(),
            paymentPlan = DealDeskPaymentPlan(
                methodCode = "finance",
                downPayment = BigDecimal("4000.00"),
                aprPercent = BigDecimal("6.50"),
                termMonths = 48
            ),
            totals = DealDeskTotals(
                salePrice = BigDecimal("18000.00"),
                taxTotal = BigDecimal("1305.00"),
                feeTotal = BigDecimal("250.00"),
                outTheDoorTotal = BigDecimal("19555.00"),
                cashReceivedNow = BigDecimal("4000.00"),
                amountFinanced = BigDecimal("15555.00"),
                monthlyPaymentEstimate = BigDecimal("368.42")
            )
        )
        val sale = Sale(
            id = UUID.randomUUID(),
            amount = BigDecimal("18000.00"),
            date = Date(1_700_172_800_000),
            buyerName = "Buyer",
            buyerPhone = "+15550000000",
            paymentMethod = "Finance",
            createdAt = createdAt,
            updatedAt = updatedAt,
            deletedAt = null,
            vehicleId = UUID.randomUUID(),
            accountId = UUID.randomUUID(),
            dealDeskPayload = snapshot.toJsonString(),
            dealDeskTemplateCode = snapshot.templateCode,
            dealDeskTemplateVersion = snapshot.templateVersion
        )

        val remote = requireNotNull(sale.toRemote(UUID.randomUUID().toString()))

        assertEquals("state", remote.jurisdictionType)
        assertEquals("CA", remote.jurisdictionCode)
        assertBigDecimalEquals(BigDecimal("19555.00"), remote.outTheDoorTotal)
        assertBigDecimalEquals(BigDecimal("4000.00"), remote.cashReceivedNow)
        assertBigDecimalEquals(BigDecimal("15555.00"), remote.amountFinanced)
        assertBigDecimalEquals(BigDecimal("368.42"), remote.monthlyPaymentEstimate)
        assertEquals(createdAt, DateUtils.parseDateAndTime(remote.createdAt))
        assertEquals(updatedAt, DateUtils.parseDateAndTime(remote.updatedAt))
    }

    private fun assertBigDecimalEquals(expected: BigDecimal, actual: BigDecimal?) {
        requireNotNull(actual)
        assertEquals(0, expected.compareTo(actual))
    }
}
