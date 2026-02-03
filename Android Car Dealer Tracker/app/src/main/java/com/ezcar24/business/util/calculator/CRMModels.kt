package com.ezcar24.business.util.calculator

import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import java.math.BigDecimal

/**
 * Data class representing funnel metrics for lead tracking
 */
data class FunnelMetrics(
    val countsPerStage: Map<LeadStage, Int>,
    val conversionRates: Map<Pair<LeadStage, LeadStage>, Double>,
    val averageTimePerStage: Map<LeadStage, Int>,
    val totalLeads: Int,
    val wonLeads: Int,
    val lostLeads: Int,
    val activeLeads: Int,
    val overallConversionRate: Double
)

/**
 * Data class representing daily activity summary for CRM
 */
data class DailyActivitySummary(
    val callsCount: Int,
    val meetingsCount: Int,
    val messagesCount: Int,
    val newLeadsCount: Int,
    val followUpsCount: Int,
    val totalInteractions: Int,
    val date: java.util.Date
)

/**
 * Data class representing lead source performance metrics
 */
data class SourcePerformance(
    val source: LeadSource,
    val leadCount: Int,
    val convertedCount: Int,
    val conversionRate: Double,
    val totalValue: BigDecimal,
    val averageLeadValue: BigDecimal
)

/**
 * Data class representing lead score breakdown
 */
data class LeadScoreBreakdown(
    val totalScore: Int,
    val interactionScore: Int,
    val recencyScore: Int,
    val engagementScore: Int,
    val valueScore: Int
)

/**
 * Data class representing stage transition info
 */
data class StageTransition(
    val fromStage: LeadStage,
    val toStage: LeadStage,
    val daysInStage: Int,
    val transitionedAt: java.util.Date?
)

/**
 * Data class representing pipeline summary
 */
data class PipelineSummary(
    val totalPipelineValue: BigDecimal,
    val weightedPipelineValue: BigDecimal,
    val leadsByStage: Map<LeadStage, List<LeadSummary>>,
    val averageDealSize: BigDecimal,
    val expectedRevenue: BigDecimal
)

/**
 * Data class representing a lead summary for pipeline view
 */
data class LeadSummary(
    val clientId: java.util.UUID,
    val clientName: String,
    val currentStage: LeadStage,
    val estimatedValue: BigDecimal?,
    val probability: Double,
    val daysInCurrentStage: Int,
    val lastContactAt: java.util.Date?,
    val nextFollowUpAt: java.util.Date?
)
