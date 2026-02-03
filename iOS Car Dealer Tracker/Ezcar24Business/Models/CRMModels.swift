import Foundation

struct FunnelMetrics {
    let countsPerStage: [LeadStage: Int]
    let conversionRates: [LeadStage: Double]
    let totalLeads: Int
    let wonLeads: Int
    let lostLeads: Int
    let activeLeads: Int
    let overallConversionRate: Double
}

struct SourcePerformance {
    let source: LeadSource
    let leadCount: Int
    let convertedCount: Int
    let conversionRate: Double
    let totalValue: Decimal
}

struct PipelineSummary {
    let totalPipelineValue: Decimal
    let weightedPipelineValue: Decimal
    let averageDealSize: Decimal
    let expectedRevenue: Decimal
}

struct DailyActivitySummary {
    let callsCount: Int
    let meetingsCount: Int
    let messagesCount: Int
    let newLeadsCount: Int
    let followUpsCount: Int
    let totalInteractions: Int
    let date: Date
}

struct LeadScoreBreakdown {
    let totalScore: Int
    let interactionScore: Int
    let recencyScore: Int
    let engagementScore: Int
    let valueScore: Int
}

struct StageTransition {
    let fromStage: LeadStage
    let toStage: LeadStage
    let daysInStage: Int
    let transitionedAt: Date?
}

struct LeadSummary {
    let clientId: UUID
    let clientName: String
    let currentStage: LeadStage
    let estimatedValue: Decimal?
    let probability: Double
    let daysInCurrentStage: Int
    let lastContactAt: Date?
    let nextFollowUpAt: Date?
}
