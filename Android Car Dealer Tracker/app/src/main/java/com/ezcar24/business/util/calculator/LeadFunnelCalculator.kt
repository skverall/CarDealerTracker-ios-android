package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Date
import java.util.concurrent.TimeUnit

object LeadFunnelCalculator {

    private const val MAX_LEAD_SCORE = 100
    private const val INTERACTION_SCALE = 4
    private const val DISPLAY_SCALE = 2

    /**
     * Calculates a lead score (0-100) based on client interactions and attributes
     */
    fun calculateLeadScore(client: Client, interactions: List<ClientInteraction>): Int {
        val interactionScore = calculateInteractionScore(interactions)
        val recencyScore = calculateRecencyScore(client, interactions)
        val engagementScore = calculateEngagementScore(interactions)
        val valueScore = calculateValueScore(client)

        val totalScore = interactionScore + recencyScore + engagementScore + valueScore
        return totalScore.coerceIn(0, MAX_LEAD_SCORE)
    }

    /**
     * Calculates time spent in each stage for a client
     */
    fun calculateTimeInStage(
        client: Client,
        interactions: List<ClientInteraction>
    ): Map<LeadStage, Int> {
        val sortedInteractions = interactions.sortedBy { it.occurredAt }
        val timeInStage = mutableMapOf<LeadStage, Int>()

        if (sortedInteractions.isEmpty()) {
            val daysSinceCreated = calculateDaysBetween(client.leadCreatedAt ?: client.createdAt, Date())
            timeInStage[client.leadStage] = daysSinceCreated
            return timeInStage
        }

        var currentStage: LeadStage? = null
        var stageStartDate: Date? = null

        for (interaction in sortedInteractions) {
            val interactionStage = try {
                interaction.stage?.let { LeadStage.valueOf(it) }
            } catch (e: IllegalArgumentException) {
                null
            }

            if (interactionStage != null && interactionStage != currentStage) {
                if (currentStage != null && stageStartDate != null) {
                    val daysInStage = calculateDaysBetween(stageStartDate, interaction.occurredAt)
                    timeInStage[currentStage] = (timeInStage[currentStage] ?: 0) + daysInStage
                }
                currentStage = interactionStage
                stageStartDate = interaction.occurredAt
            }
        }

        if (currentStage != null && stageStartDate != null) {
            val daysInCurrentStage = calculateDaysBetween(stageStartDate, Date())
            timeInStage[currentStage] = (timeInStage[currentStage] ?: 0) + daysInCurrentStage
        }

        return timeInStage
    }

    /**
     * Calculates conversion rate from one stage to another
     */
    fun calculateConversionRate(
        fromStage: LeadStage,
        toStage: LeadStage,
        clients: List<Client>
    ): Double {
        val clientsInFromStage = clients.filter { it.leadStage == fromStage || hasReachedStage(it, toStage, clients) }
        if (clientsInFromStage.isEmpty()) {
            return 0.0
        }

        val clientsReachedToStage = clients.filter { hasReachedStage(it, toStage, clients) }
        return (clientsReachedToStage.size.toDouble() / clientsInFromStage.size * 100)
            .coerceIn(0.0, 100.0)
    }

    /**
     * Calculates comprehensive funnel metrics
     */
    fun calculateFunnelMetrics(clients: List<Client>): FunnelMetrics {
        val activeClients = clients.filter { it.deletedAt == null }
        val countsPerStage = activeClients.groupingBy { it.leadStage }.eachCount()

        val conversionRates = mutableMapOf<Pair<LeadStage, LeadStage>, Double>()
        val stageProgression = listOf(
            LeadStage.new to LeadStage.contacted,
            LeadStage.contacted to LeadStage.qualified,
            LeadStage.qualified to LeadStage.negotiation,
            LeadStage.negotiation to LeadStage.offer,
            LeadStage.offer to LeadStage.closed_won
        )

        stageProgression.forEach { (from, to) ->
            conversionRates[from to to] = calculateConversionRate(from, to, activeClients)
        }

        val averageTimePerStage = mutableMapOf<LeadStage, Int>()
        LeadStage.values().forEach { stage ->
            val clientsInStage = activeClients.filter { it.leadStage == stage }
            if (clientsInStage.isNotEmpty()) {
                val avgDays = clientsInStage.map { client ->
                    calculateDaysBetween(client.leadCreatedAt ?: client.createdAt, Date())
                }.average().toInt()
                averageTimePerStage[stage] = avgDays
            }
        }

        val wonLeads = countsPerStage[LeadStage.closed_won] ?: 0
        val lostLeads = countsPerStage[LeadStage.closed_lost] ?: 0
        val activeLeads = activeClients.size - wonLeads - lostLeads

        val overallConversionRate = if (activeClients.isNotEmpty()) {
            (wonLeads.toDouble() / activeClients.size * 100)
        } else {
            0.0
        }

        return FunnelMetrics(
            countsPerStage = countsPerStage,
            conversionRates = conversionRates,
            averageTimePerStage = averageTimePerStage,
            totalLeads = activeClients.size,
            wonLeads = wonLeads,
            lostLeads = lostLeads,
            activeLeads = activeLeads,
            overallConversionRate = overallConversionRate
        )
    }

    /**
     * Calculates total pipeline value from client estimated values
     */
    fun calculatePipelineValue(clients: List<Client>): BigDecimal {
        return clients
            .filter { it.deletedAt == null }
            .filter { it.leadStage != LeadStage.closed_won && it.leadStage != LeadStage.closed_lost }
            .map { it.estimatedValue ?: BigDecimal.ZERO }
            .fold(BigDecimal.ZERO) { acc, value -> acc.add(value) }
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    /**
     * Gets daily activity summary for a specific date
     */
    fun getDailyActivitySummary(
        interactions: List<ClientInteraction>,
        date: Date
    ): DailyActivitySummary {
        val calendar = java.util.Calendar.getInstance()
        calendar.time = date
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        val startOfDay = calendar.time

        calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
        val endOfDay = calendar.time

        val dayInteractions = interactions.filter {
            it.occurredAt >= startOfDay && it.occurredAt < endOfDay
        }

        val callsCount = dayInteractions.count {
            it.interactionType?.lowercase()?.contains("call") == true
        }
        val meetingsCount = dayInteractions.count {
            it.interactionType?.lowercase()?.contains("meeting") == true
        }
        val messagesCount = dayInteractions.count {
            it.interactionType?.lowercase()?.contains("message") == true ||
            it.interactionType?.lowercase()?.contains("email") == true
        }
        val followUpsCount = dayInteractions.count { it.isFollowUpRequired }

        return DailyActivitySummary(
            callsCount = callsCount,
            meetingsCount = meetingsCount,
            messagesCount = messagesCount,
            newLeadsCount = 0,
            followUpsCount = followUpsCount,
            totalInteractions = dayInteractions.size,
            date = date
        )
    }

    /**
     * Calculates performance metrics for each lead source
     */
    fun calculateLeadSourcePerformance(
        clients: List<Client>
    ): Map<LeadSource, SourcePerformance> {
        val clientsBySource = clients
            .filter { it.deletedAt == null && it.leadSource != null }
            .groupBy { it.leadSource!! }

        return clientsBySource.map { (source, sourceClients) ->
            val leadCount = sourceClients.size
            val convertedCount = sourceClients.count {
                it.leadStage == LeadStage.closed_won
            }
            val conversionRate = if (leadCount > 0) {
                (convertedCount.toDouble() / leadCount * 100)
            } else {
                0.0
            }
            val totalValue = sourceClients
                .map { it.estimatedValue ?: BigDecimal.ZERO }
                .fold(BigDecimal.ZERO) { acc, value -> acc.add(value) }
            val averageLeadValue = if (leadCount > 0) {
                totalValue.divide(BigDecimal(leadCount), DISPLAY_SCALE, RoundingMode.HALF_UP)
            } else {
                BigDecimal.ZERO
            }

            source to SourcePerformance(
                source = source,
                leadCount = leadCount,
                convertedCount = convertedCount,
                conversionRate = conversionRate,
                totalValue = totalValue,
                averageLeadValue = averageLeadValue
            )
        }.toMap()
    }

    /**
     * Calculates weighted pipeline value based on stage probabilities
     */
    fun calculateWeightedPipelineValue(clients: List<Client>): BigDecimal {
        val stageProbabilities = mapOf(
            LeadStage.new to 0.10,
            LeadStage.contacted to 0.25,
            LeadStage.qualified to 0.40,
            LeadStage.negotiation to 0.60,
            LeadStage.offer to 0.75,
            LeadStage.test_drive to 0.85,
            LeadStage.closed_won to 1.0,
            LeadStage.closed_lost to 0.0
        )

        return clients
            .filter { it.deletedAt == null }
            .filter { it.leadStage != LeadStage.closed_won && it.leadStage != LeadStage.closed_lost }
            .map { client ->
                val probability = stageProbabilities[client.leadStage] ?: 0.0
                (client.estimatedValue ?: BigDecimal.ZERO)
                    .multiply(BigDecimal(probability))
            }
            .fold(BigDecimal.ZERO) { acc, value -> acc.add(value) }
            .setScale(DISPLAY_SCALE, RoundingMode.HALF_UP)
    }

    /**
     * Calculates the probability of closing for a specific client based on their stage
     */
    fun calculateCloseProbability(client: Client): Double {
        val stageProbabilities = mapOf(
            LeadStage.new to 0.10,
            LeadStage.contacted to 0.25,
            LeadStage.qualified to 0.40,
            LeadStage.negotiation to 0.60,
            LeadStage.offer to 0.75,
            LeadStage.test_drive to 0.85,
            LeadStage.closed_won to 1.0,
            LeadStage.closed_lost to 0.0
        )
        return stageProbabilities[client.leadStage] ?: 0.0
    }

    /**
     * Calculates days since last contact
     */
    fun calculateDaysSinceLastContact(client: Client, interactions: List<ClientInteraction>): Int {
        val lastInteraction = interactions.maxByOrNull { it.occurredAt }
        val lastContactDate = client.lastContactAt ?: lastInteraction?.occurredAt
        return lastContactDate?.let {
            calculateDaysBetween(it, Date())
        } ?: calculateDaysBetween(client.createdAt, Date())
    }

    // Private helper methods

    private fun calculateInteractionScore(interactions: List<ClientInteraction>): Int {
        val baseScore = interactions.size * 5
        val positiveOutcomes = interactions.count {
            it.outcome?.lowercase()?.contains("positive") == true ||
            it.outcome?.lowercase()?.contains("successful") == true
        }
        return (baseScore + (positiveOutcomes * 10)).coerceAtMost(40)
    }

    private fun calculateRecencyScore(client: Client, interactions: List<ClientInteraction>): Int {
        val daysSinceLastContact = calculateDaysSinceLastContact(client, interactions)
        return when {
            daysSinceLastContact <= 1 -> 25
            daysSinceLastContact <= 3 -> 20
            daysSinceLastContact <= 7 -> 15
            daysSinceLastContact <= 14 -> 10
            daysSinceLastContact <= 30 -> 5
            else -> 0
        }
    }

    private fun calculateEngagementScore(interactions: List<ClientInteraction>): Int {
        val uniqueTypes = interactions.mapNotNull { it.interactionType }.distinct().size
        val hasMeetings = interactions.any {
            it.interactionType?.lowercase()?.contains("meeting") == true
        }
        val hasTestDrive = interactions.any {
            it.interactionType?.lowercase()?.contains("test") == true
        }

        var score = uniqueTypes * 5
        if (hasMeetings) score += 10
        if (hasTestDrive) score += 15

        return score.coerceAtMost(25)
    }

    private fun calculateValueScore(client: Client): Int {
        val estimatedValue = client.estimatedValue ?: return 0
        return when {
            estimatedValue >= BigDecimal("100000") -> 10
            estimatedValue >= BigDecimal("50000") -> 8
            estimatedValue >= BigDecimal("25000") -> 6
            estimatedValue >= BigDecimal("10000") -> 4
            estimatedValue > BigDecimal.ZERO -> 2
            else -> 0
        }
    }

    private fun calculateDaysBetween(startDate: Date, endDate: Date): Int {
        val diffInMillis = endDate.time - startDate.time
        return maxOf(0, TimeUnit.MILLISECONDS.toDays(diffInMillis).toInt())
    }

    private fun hasReachedStage(client: Client, targetStage: LeadStage, allClients: List<Client>): Boolean {
        val stageOrder = LeadStage.values()
        val clientStageIndex = stageOrder.indexOf(client.leadStage)
        val targetStageIndex = stageOrder.indexOf(targetStage)
        return clientStageIndex >= targetStageIndex
    }
}
