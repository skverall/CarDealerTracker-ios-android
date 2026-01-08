import Foundation
import CoreData


extension User {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<User> {
        return NSFetchRequest<User>(entityName: "User")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var expenses: NSSet?
    @NSManaged public var expenseTemplates: NSSet?

}

// MARK: Generated accessors for expenses
extension User {

    @objc(addExpensesObject:)
    @NSManaged public func addToExpenses(_ value: Expense)

    @objc(removeExpensesObject:)
    @NSManaged public func removeFromExpenses(_ value: Expense)

    @objc(addExpenses:)
    @NSManaged public func addToExpenses(_ values: NSSet)

    @objc(removeExpenses:)
    @NSManaged public func removeFromExpenses(_ values: NSSet)

}

// MARK: Generated accessors for expenseTemplates
extension User {

    @objc(addExpenseTemplatesObject:)
    @NSManaged public func addToExpenseTemplates(_ value: ExpenseTemplate)

    @objc(removeExpenseTemplatesObject:)
    @NSManaged public func removeFromExpenseTemplates(_ value: ExpenseTemplate)

    @objc(addExpenseTemplates:)
    @NSManaged public func addToExpenseTemplates(_ values: NSSet)

    @objc(removeExpenseTemplates:)
    @NSManaged public func removeFromExpenseTemplates(_ values: NSSet)

}

extension User : Identifiable {

}
