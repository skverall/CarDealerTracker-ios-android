import Foundation
import CoreData

extension Client {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Client> {
        return NSFetchRequest<Client>(entityName: "Client")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var phone: String?
    @NSManaged public var email: String?
    @NSManaged public var notes: String?
    @NSManaged public var requestDetails: String?
    @NSManaged public var preferredDate: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var status: String?
    @NSManaged public var interactions: NSSet?
    @NSManaged public var reminders: NSSet?
    @NSManaged public var vehicle: Vehicle?

    public var sortedInteractions: [ClientInteraction] {
        let set = interactions as? Set<ClientInteraction> ?? []
        return set.sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }

    public var sortedReminders: [ClientReminder] {
        let set = reminders as? Set<ClientReminder> ?? []
        return set.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    public var nextReminder: ClientReminder? {
        sortedReminders.first(where: { !$0.isCompleted })
    }

    public var lastInteraction: ClientInteraction? {
        sortedInteractions.first
    }
}

extension Client: Identifiable {
}
