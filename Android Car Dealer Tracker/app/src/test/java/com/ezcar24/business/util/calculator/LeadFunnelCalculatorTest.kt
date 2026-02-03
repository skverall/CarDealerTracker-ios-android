package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.util.Calendar
import java.util.Date
import java.util.UUID

class LeadFunnelCalculatorTest {

    private fun createClient(
        leadStage: LeadStage = LeadStage.new,
        leadSource: LeadSource? = LeadSource.website,
        estimatedValue: BigDecimal? = BigDecimal("25000"),
        leadCreatedAt: Date = Date(),
        lastContactAt: Date? = null
    ): Client {
        return Client(
            id = UUID.randomUUID(),
            name = "Test Client",
            phone = "+1234567890",
            email = "test@example.com",
            notes = null,
            requestDetails = null,
            preferredDate = null,
            status = "active",
            createdAt = leadCreatedAt,
            updatedAt = null,
            deletedAt = null,
            vehicleId = null,
            leadStage = leadStage,
            leadSource = leadSource,
            assignedUserId = null,
            estimatedValue = estimatedValue,
            priority = 0,
            leadCreatedAt = leadCreatedAt,
            lastContactAt = lastContactAt,
            nextFollowUpAt = null
        )
    }

    private fun createInteraction(
        clientId: UUID,
        occurredAt: Date = Date(),
        interactionType: String? = "call",
        outcome: String? = null,
        stage: String? = "new",
        isFollowUpRequired: Boolean = false
    ): ClientInteraction {
        return ClientInteraction(
            id = UUID.randomUUID(),
            title = "Test Interaction",
            detail = "Test detail",
            occurredAt = occurredAt,
            stage = stage,
            value = null,
            clientId = clientId,
            interactionType = interactionType,
            outcome = outcome,
            durationMinutes = null,
            isFollowUpRequired = isFollowUpRequired
        )
    }

    private fun dateDaysAgo(days: Int): Date {
        val calendar = Calendar.getInstance()
        calendar.add(Calendar.DAY_OF_YEAR, -days)
        return calendar.time
    }

    @Test
    fun `calculateLeadScore returns score between 0 and 100`() {
        val client = createClient()
        val interactions = listOf(
            createInteraction(client.id, occurredAt = dateDaysAgo(1), interactionType = "call"),
            createInteraction(client.id, occurredAt = dateDaysAgo(2), interactionType = "meeting")
        )

        val score = LeadFunnelCalculator.calculateLeadScore(client, interactions)

        assertTrue("Score should be >= 0", score >= 0)
        assertTrue("Score should be <= 100", score <= 100)
    }

    @Test
    fun `calculateLeadScore increases with more interactions`() {
        val client = createClient()
        val fewInteractions = listOf(createInteraction(client.id))
        val manyInteractions = List(5) { createInteraction(client.id) }

        val fewScore = LeadFunnelCalculator.calculateLeadScore(client, fewInteractions)
        val manyScore = LeadFunnelCalculator.calculateLeadScore(client, manyInteractions)

        assertTrue("More interactions should yield higher score", manyScore >= fewScore)
    }

    @Test
    fun `calculateLeadScore increases with recent contact`() {
        val client = createClient(lastContactAt = dateDaysAgo(1))
        val oldClient = createClient(lastContactAt = dateDaysAgo(30))
        val interactions = emptyList<ClientInteraction>()

        val recentScore = LeadFunnelCalculator.calculateLeadScore(client, interactions)
        val oldScore = LeadFunnelCalculator.calculateLeadScore(oldClient, interactions)

        assertTrue("Recent contact should yield higher score", recentScore >= oldScore)
    }

    @Test
    fun `calculateLeadScore increases with higher estimated value`() {
        val lowValueClient = createClient(estimatedValue = BigDecimal("5000"))
        val highValueClient = createClient(estimatedValue = BigDecimal("100000"))
        val interactions = emptyList<ClientInteraction>()

        val lowScore = LeadFunnelCalculator.calculateLeadScore(lowValueClient, interactions)
        val highScore = LeadFunnelCalculator.calculateLeadScore(highValueClient, interactions)

        assertTrue("Higher value should yield higher score", highScore >= lowScore)
    }

    @Test
    fun `calculateTimeInStage returns correct days for single stage`() {
        val client = createClient(leadStage = LeadStage.new, leadCreatedAt = dateDaysAgo(10))
        val interactions = emptyList<ClientInteraction>()

        val timeInStage = LeadFunnelCalculator.calculateTimeInStage(client, interactions)

        assertTrue("Should have time for new stage", timeInStage.containsKey(LeadStage.new))
        assertTrue("Days in new stage should be >= 10", (timeInStage[LeadStage.new] ?: 0) >= 10)
    }

    @Test
    fun `calculateConversionRate returns 0 when no clients in fromStage`() {
        val clients = emptyList<Client>()

        val rate = LeadFunnelCalculator.calculateConversionRate(LeadStage.new, LeadStage.contacted, clients)

        assertEquals(0.0, rate, 0.01)
    }

    @Test
    fun `calculateConversionRate returns correct rate`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.contacted),
            createClient(leadStage = LeadStage.contacted),
            createClient(leadStage = LeadStage.new)
        )

        val rate = LeadFunnelCalculator.calculateConversionRate(LeadStage.new, LeadStage.contacted, clients)

        assertEquals(66.67, rate, 0.01)
    }

    @Test
    fun `calculateFunnelMetrics returns correct counts per stage`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.new),
            createClient(leadStage = LeadStage.new),
            createClient(leadStage = LeadStage.contacted),
            createClient(leadStage = LeadStage.closed_won),
            createClient(leadStage = LeadStage.closed_lost)
        )

        val metrics = LeadFunnelCalculator.calculateFunnelMetrics(clients)

        assertEquals(2, metrics.countsPerStage[LeadStage.new] ?: 0)
        assertEquals(1, metrics.countsPerStage[LeadStage.contacted] ?: 0)
        assertEquals(1, metrics.countsPerStage[LeadStage.closed_won] ?: 0)
        assertEquals(1, metrics.countsPerStage[LeadStage.closed_lost] ?: 0)
    }

    @Test
    fun `calculateFunnelMetrics returns correct totals`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.new),
            createClient(leadStage = LeadStage.contacted),
            createClient(leadStage = LeadStage.closed_won),
            createClient(leadStage = LeadStage.closed_lost)
        )

        val metrics = LeadFunnelCalculator.calculateFunnelMetrics(clients)

        assertEquals(4, metrics.totalLeads)
        assertEquals(1, metrics.wonLeads)
        assertEquals(1, metrics.lostLeads)
        assertEquals(2, metrics.activeLeads)
    }

    @Test
    fun `calculateFunnelMetrics returns overall conversion rate`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.new),
            createClient(leadStage = LeadStage.contacted),
            createClient(leadStage = LeadStage.closed_won),
            createClient(leadStage = LeadStage.closed_lost)
        )

        val metrics = LeadFunnelCalculator.calculateFunnelMetrics(clients)

        assertEquals(25.0, metrics.overallConversionRate, 0.01)
    }

    @Test
    fun `calculatePipelineValue sums estimated values of active leads`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.new, estimatedValue = BigDecimal("10000")),
            createClient(leadStage = LeadStage.negotiation, estimatedValue = BigDecimal("20000")),
            createClient(leadStage = LeadStage.closed_won, estimatedValue = BigDecimal("30000")),
            createClient(leadStage = LeadStage.closed_lost, estimatedValue = BigDecimal("40000"))
        )

        val pipelineValue = LeadFunnelCalculator.calculatePipelineValue(clients)

        assertEquals(BigDecimal("30000.00"), pipelineValue)
    }

    @Test
    fun `calculatePipelineValue returns zero when no active leads`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.closed_won, estimatedValue = BigDecimal("10000")),
            createClient(leadStage = LeadStage.closed_lost, estimatedValue = BigDecimal("20000"))
        )

        val pipelineValue = LeadFunnelCalculator.calculatePipelineValue(clients)

        assertEquals(BigDecimal.ZERO, pipelineValue)
    }

    @Test
    fun `getDailyActivitySummary returns correct counts`() {
        val today = Date()
        val clientId = UUID.randomUUID()
        val interactions = listOf(
            createInteraction(clientId, occurredAt = today, interactionType = "call"),
            createInteraction(clientId, occurredAt = today, interactionType = "call"),
            createInteraction(clientId, occurredAt = today, interactionType = "meeting"),
            createInteraction(clientId, occurredAt = today, interactionType = "email"),
            createInteraction(clientId, occurredAt = today, interactionType = "call", isFollowUpRequired = true)
        )

        val summary = LeadFunnelCalculator.getDailyActivitySummary(interactions, today)

        assertEquals(2, summary.callsCount)
        assertEquals(1, summary.meetingsCount)
        assertEquals(1, summary.messagesCount)
        assertEquals(1, summary.followUpsCount)
        assertEquals(5, summary.totalInteractions)
    }

    @Test
    fun `getDailyActivitySummary filters by date`() {
        val today = Date()
        val yesterday = dateDaysAgo(1)
        val clientId = UUID.randomUUID()
        val interactions = listOf(
            createInteraction(clientId, occurredAt = today, interactionType = "call"),
            createInteraction(clientId, occurredAt = yesterday, interactionType = "call")
        )

        val summary = LeadFunnelCalculator.getDailyActivitySummary(interactions, today)

        assertEquals(1, summary.totalInteractions)
        assertEquals(1, summary.callsCount)
    }

    @Test
    fun `calculateLeadSourcePerformance returns metrics per source`() {
        val clients = listOf(
            createClient(leadSource = LeadSource.website, leadStage = LeadStage.closed_won, estimatedValue = BigDecimal("20000")),
            createClient(leadSource = LeadSource.website, leadStage = LeadStage.new, estimatedValue = BigDecimal("15000")),
            createClient(leadSource = LeadSource.referral, leadStage = LeadStage.closed_won, estimatedValue = BigDecimal("30000")),
            createClient(leadSource = LeadSource.facebook, leadStage = LeadStage.new, estimatedValue = BigDecimal("10000"))
        )

        val performance = LeadFunnelCalculator.calculateLeadSourcePerformance(clients)

        assertEquals(2, performance[LeadSource.website]?.leadCount)
        assertEquals(1, performance[LeadSource.website]?.convertedCount)
        assertEquals(50.0, performance[LeadSource.website]?.conversionRate ?: 0.0, 0.01)
        assertEquals(BigDecimal("35000.00"), performance[LeadSource.website]?.totalValue)

        assertEquals(1, performance[LeadSource.referral]?.leadCount)
        assertEquals(100.0, performance[LeadSource.referral]?.conversionRate ?: 0.0, 0.01)

        assertEquals(1, performance[LeadSource.facebook]?.leadCount)
        assertEquals(0.0, performance[LeadSource.facebook]?.conversionRate ?: 0.0, 0.01)
    }

    @Test
    fun `calculateWeightedPipelineValue applies stage probabilities`() {
        val clients = listOf(
            createClient(leadStage = LeadStage.new, estimatedValue = BigDecimal("10000")),
            createClient(leadStage = LeadStage.qualified, estimatedValue = BigDecimal("20000")),
            createClient(leadStage = LeadStage.offer, estimatedValue = BigDecimal("40000"))
        )

        val weightedValue = LeadFunnelCalculator.calculateWeightedPipelineValue(clients)

        assertTrue("Weighted value should be less than total", weightedValue < BigDecimal("70000"))
        assertTrue("Weighted value should be greater than zero", weightedValue > BigDecimal.ZERO)
    }

    @Test
    fun `calculateCloseProbability returns correct probability per stage`() {
        val newClient = createClient(leadStage = LeadStage.new)
        val negotiationClient = createClient(leadStage = LeadStage.negotiation)
        val wonClient = createClient(leadStage = LeadStage.closed_won)
        val lostClient = createClient(leadStage = LeadStage.closed_lost)

        assertEquals(0.10, LeadFunnelCalculator.calculateCloseProbability(newClient), 0.01)
        assertEquals(0.60, LeadFunnelCalculator.calculateCloseProbability(negotiationClient), 0.01)
        assertEquals(1.0, LeadFunnelCalculator.calculateCloseProbability(wonClient), 0.01)
        assertEquals(0.0, LeadFunnelCalculator.calculateCloseProbability(lostClient), 0.01)
    }

    @Test
    fun `calculateDaysSinceLastContact returns correct days`() {
        val client = createClient(lastContactAt = dateDaysAgo(5))
        val interactions = emptyList<ClientInteraction>()

        val days = LeadFunnelCalculator.calculateDaysSinceLastContact(client, interactions)

        assertTrue("Days since last contact should be >= 5", days >= 5)
    }

    @Test
    fun `calculateDaysSinceLastContact uses interaction date when lastContactAt is null`() {
        val client = createClient(lastContactAt = null, leadCreatedAt = dateDaysAgo(10))
        val interactions = listOf(
            createInteraction(client.id, occurredAt = dateDaysAgo(3))
        )

        val days = LeadFunnelCalculator.calculateDaysSinceLastContact(client, interactions)

        assertTrue("Days should be based on interaction", days >= 3)
    }

    @Test
    fun `calculateFunnelMetrics excludes deleted clients`() {
        val activeClient = createClient(leadStage = LeadStage.new)
        val deletedClient = createClient(leadStage = LeadStage.new).copy(deletedAt = Date())

        val clients = listOf(activeClient, deletedClient)
        val metrics = LeadFunnelCalculator.calculateFunnelMetrics(clients)

        assertEquals(1, metrics.totalLeads)
    }

    @Test
    fun `calculateLeadSourcePerformance excludes deleted clients`() {
        val activeClient = createClient(leadSource = LeadSource.website, leadStage = LeadStage.new)
        val deletedClient = createClient(leadSource = LeadSource.website, leadStage = LeadStage.new).copy(deletedAt = Date())

        val clients = listOf(activeClient, deletedClient)
        val performance = LeadFunnelCalculator.calculateLeadSourcePerformance(clients)

        assertEquals(1, performance[LeadSource.website]?.leadCount)
    }
}
