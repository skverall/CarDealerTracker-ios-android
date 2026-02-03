import Foundation
import CoreData

extension InventoryAlert {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InventoryAlert> {
        return NSFetchRequest<InventoryAlert>(entityName: "InventoryAlert")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var vehicleId: UUID?
    @NSManaged public var alertType: String?
    @NSManaged public var severity: String?
    @NSManaged public var message: String?
    @NSManaged public var isRead: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var dismissedAt: Date?
}

extension InventoryAlert: Identifiable {
}
