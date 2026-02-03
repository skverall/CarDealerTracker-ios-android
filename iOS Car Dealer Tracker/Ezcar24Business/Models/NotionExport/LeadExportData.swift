import Foundation

struct LeadExportData {
    let id: UUID
    let name: String
    let phone: String?
    let email: String?
    let leadStage: String
    let leadSource: String?
    let leadScore: Int
    let priority: String
    let estimatedValue: Decimal?
    let daysSinceCreated: Int
    let daysSinceLastContact: Int?
    let interactionCount: Int
    let nextFollowUpAt: Date?
    let notes: String?
}

extension LeadExportData {
    init(from client: Client) {
        self.id = client.id ?? UUID()
        self.name = client.name ?? "Unknown"
        self.phone = client.phone
        self.email = client.email
        self.leadStage = client.leadStage ?? "new"
        self.leadSource = client.leadSource
        self.leadScore = Int(client.leadScore)
        self.priority = Self.calculatePriorityLabel(score: Int(client.priority))
        self.estimatedValue = client.estimatedValue?.decimalValue
        
        let createdAt = client.leadCreatedAt ?? client.createdAt ?? Date()
        self.daysSinceCreated = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        
        if let lastContact = client.lastContactAt {
            self.daysSinceLastContact = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day
        } else {
            self.daysSinceLastContact = nil
        }
        
        let interactions = client.interactions?.allObjects as? [ClientInteraction] ?? []
        self.interactionCount = interactions.count
        
        self.nextFollowUpAt = client.nextFollowUpAt
        self.notes = client.notes
    }
    
    private static func calculatePriorityLabel(score: Int) -> String {
        switch score {
        case 0...1:
            return "Low"
        case 2...3:
            return "Medium"
        case 4...5:
            return "High"
        default:
            return "Unknown"
        }
    }
}