import Foundation
import CoreData

extension ClientInteraction {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClientInteraction> {
        NSFetchRequest<ClientInteraction>(entityName: "ClientInteraction")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var detail: String?
    @NSManaged public var occurredAt: Date?
    @NSManaged public var stage: String?
    @NSManaged public var value: NSDecimalNumber?
    @NSManaged public var client: Client?
}

extension ClientInteraction: Identifiable { }
