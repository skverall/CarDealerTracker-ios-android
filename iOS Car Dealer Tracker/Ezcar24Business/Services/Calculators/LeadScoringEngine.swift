import Foundation

class LeadScoringEngine {
    
    private static let maxLeadScore = 100
    
    static func calculateLeadScore(
        client: Client,
        interactions: [ClientInteraction]
    ) -> Int {
        let interactionScore = calculateInteractionScore(interactions: interactions)
        let recencyScore = calculateRecencyScore(lastContactAt: client.lastContactAt)
        let engagementScore = calculateEngagementScore(client: client, interactions: interactions)
        let valueScore = calculateValueScore(estimatedValue: client.estimatedValue?.decimalValue)
        
        let totalScore = interactionScore + recencyScore + engagementScore + valueScore
        return max(0, min(maxLeadScore, totalScore))
    }
    
    static func calculateRecencyScore(lastContactAt: Date?) -> Int {
        guard let lastContact = lastContactAt else {
            return 0
        }
        
        let daysSinceLastContact = Int(Date().timeIntervalSince(lastContact) / 86400)
        
        switch daysSinceLastContact {
        case 0...1:
            return 20
        case 2...7:
            return 15
        case 8...30:
            return 10
        default:
            return 0
        }
    }
    
    static func calculateEngagementScore(
        client: Client,
        interactions: [ClientInteraction]
    ) -> Int {
        var score = 0
        
        if !(client.phone?.isEmpty ?? true) {
            score += 10
        }
        if !(client.email?.isEmpty ?? true) {
            score += 5
        }
        
        let interactionPoints = min(interactions.count * 5, 30)
        score += interactionPoints
        
        let hasVehicleAssociation = client.vehicle != nil
        if hasVehicleAssociation {
            score += 10
        }
        
        return score
    }
    
    static func calculateValueScore(estimatedValue: Decimal?) -> Int {
        guard let value = estimatedValue, value > 0 else {
            return 10
        }
        
        if value >= 100_000 {
            return 25
        } else if value >= 50_000 {
            return 20
        } else if value >= 20_000 {
            return 15
        } else {
            return 10
        }
    }
    
    private static func calculateInteractionScore(interactions: [ClientInteraction]) -> Int {
        let baseScore = min(interactions.count * 5, 30)
        
        let positiveOutcomes = interactions.filter { interaction in
            guard let outcome = interaction.outcome?.lowercased() else { return false }
            return outcome.contains("positive") || outcome.contains("successful")
        }.count
        
        return min(baseScore + (positiveOutcomes * 10), 40)
    }
}
