import Foundation
import CoreData

extension VehicleInventoryStats {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VehicleInventoryStats> {
        return NSFetchRequest<VehicleInventoryStats>(entityName: "VehicleInventoryStats")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var vehicleId: UUID?
    @NSManaged public var daysInInventory: Int32
    @NSManaged public var agingBucket: String?
    @NSManaged public var totalCost: NSDecimalNumber?
    @NSManaged public var holdingCostAccumulated: NSDecimalNumber?
    @NSManaged public var roiPercent: NSDecimalNumber?
    @NSManaged public var profitEstimate: NSDecimalNumber?
    @NSManaged public var lastCalculatedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
}

extension VehicleInventoryStats: Identifiable {
}
