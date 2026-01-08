import Foundation
import CoreData

extension Vehicle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Vehicle> {
        return NSFetchRequest<Vehicle>(entityName: "Vehicle")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var vin: String?
    @NSManaged public var make: String?
    @NSManaged public var model: String?
    @NSManaged public var year: Int32
    @NSManaged public var purchasePrice: NSDecimalNumber?
    @NSManaged public var purchaseDate: Date?
    @NSManaged public var status: String?
    @NSManaged public var notes: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var saleDate: Date?
    @NSManaged public var buyerName: String?
    @NSManaged public var buyerPhone: String?
    @NSManaged public var paymentMethod: String?
    @NSManaged public var salePrice: NSDecimalNumber?
    
    // New Feature Fields
    @NSManaged public var askingPrice: NSDecimalNumber?
    @NSManaged public var reportURL: String?
    
    @NSManaged public var expenses: NSSet?
    @NSManaged public var clients: NSSet?
    @NSManaged public var expenseTemplates: NSSet?
    @NSManaged public var sales: NSSet?

}

extension Vehicle : Identifiable {

}
