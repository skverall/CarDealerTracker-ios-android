import Foundation
import CoreData

extension ClientReminder {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClientReminder> {
        NSFetchRequest<ClientReminder>(entityName: "ClientReminder")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var notes: String?
    @NSManaged public var dueDate: Date?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var client: Client?
}

extension ClientReminder: Identifiable { }
