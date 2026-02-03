import Foundation
import CoreData

extension HoldingCostSettings {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HoldingCostSettings> {
        return NSFetchRequest<HoldingCostSettings>(entityName: "HoldingCostSettings")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var dealerId: UUID?
    @NSManaged public var annualRatePercent: NSDecimalNumber?
    @NSManaged public var dailyRatePercent: NSDecimalNumber?
    @NSManaged public var isEnabled: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
}

extension HoldingCostSettings: Identifiable {
}
