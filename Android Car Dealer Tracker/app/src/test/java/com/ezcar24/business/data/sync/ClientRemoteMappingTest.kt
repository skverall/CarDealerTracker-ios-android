package com.ezcar24.business.data.sync

import java.math.BigDecimal
import java.util.Date
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.util.DateUtils

class ClientRemoteMappingTest {
    @Test
    fun `client remote payload includes crm lead fields`() {
        val assignedUserId = UUID.randomUUID()
        val createdAt = Date(1_700_000_000_000)
        val updatedAt = Date(1_700_086_400_000)
        val leadCreatedAt = Date(1_699_913_600_000)
        val lastContactAt = Date(1_700_172_800_000)
        val nextFollowUpAt = Date(1_700_259_200_000)
        val client = Client(
            id = UUID.randomUUID(),
            name = "Client",
            phone = "+15550000000",
            email = "client@example.com",
            notes = "Notes",
            requestDetails = "Looking for SUV",
            preferredDate = nextFollowUpAt,
            status = "new",
            createdAt = createdAt,
            updatedAt = updatedAt,
            deletedAt = null,
            vehicleId = UUID.randomUUID(),
            leadStage = LeadStage.qualified,
            leadSource = LeadSource.website,
            assignedUserId = assignedUserId,
            estimatedValue = BigDecimal("42000.00"),
            priority = 4,
            leadCreatedAt = leadCreatedAt,
            lastContactAt = lastContactAt,
            nextFollowUpAt = nextFollowUpAt
        )

        val remote = client.toRemote(UUID.randomUUID().toString())

        assertEquals("qualified", remote.leadStage)
        assertEquals("website", remote.leadSource)
        assertEquals(assignedUserId.toString(), remote.assignedUserId)
        assertBigDecimalEquals(BigDecimal("42000.00"), remote.estimatedValue)
        assertEquals(4, remote.priority)
        assertEquals(leadCreatedAt, DateUtils.parseDateAndTime(remote.leadCreatedAt!!))
        assertEquals(lastContactAt, DateUtils.parseDateAndTime(remote.lastContactAt!!))
        assertEquals(nextFollowUpAt, DateUtils.parseDateAndTime(remote.nextFollowUpAt!!))
    }

    @Test
    fun `remote crm enum parsing is safe for old or unexpected backend values`() {
        assertEquals(LeadStage.new, remoteLeadStage(null))
        assertEquals(LeadStage.new, remoteLeadStage("not_a_stage"))
        assertEquals(LeadStage.closed_won, remoteLeadStage("closed_won"))
        assertNull(remoteLeadSource(null))
        assertNull(remoteLeadSource("not_a_source"))
        assertEquals(LeadSource.referral, remoteLeadSource("referral"))
    }

    private fun assertBigDecimalEquals(expected: BigDecimal, actual: BigDecimal?) {
        requireNotNull(actual)
        assertEquals(0, expected.compareTo(actual))
    }
}
