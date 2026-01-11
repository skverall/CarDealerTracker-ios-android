//
//  PersistenceController.swift
//  Ezcar24Business
//
//  Core Data stack and sample data management
//

import CoreData
import Foundation

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    private static let managedObjectModel: NSManagedObjectModel = {
        guard let modelURL = Bundle.main.url(forResource: "Ezcar24Business", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model.")
        }
        return model
    }()
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.viewContext
        
        // Create sample data for previews
        result.createSampleData(in: viewContext)
        
        return result
    }()
    
    @Published private(set) var activeStoreKey: String
    private var containers: [String: NSPersistentContainer] = [:]

    var container: NSPersistentContainer {
        guard let container = containers[activeStoreKey] else {
            let created = makeContainer(storeKey: activeStoreKey, inMemory: activeStoreKey == Self.guestStoreKey)
            containers[activeStoreKey] = created
            return created
        }
        return container
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    static let guestStoreKey = "guest"
    
    init(inMemory: Bool = false) {
        let initialKey = inMemory ? Self.guestStoreKey : Self.guestStoreKey
        activeStoreKey = initialKey
        containers[initialKey] = makeContainer(storeKey: initialKey, inMemory: inMemory || initialKey == Self.guestStoreKey)
    }

    func setActiveStore(organizationId: UUID?) {
        let key = organizationId?.uuidString ?? Self.guestStoreKey
        guard key != activeStoreKey else { return }
        activeStoreKey = key
        if containers[key] == nil {
            containers[key] = makeContainer(storeKey: key, inMemory: key == Self.guestStoreKey)
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    private func makeContainer(storeKey: String, inMemory: Bool) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Ezcar24Business", managedObjectModel: Self.managedObjectModel)
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true

        if inMemory {
            description?.url = URL(fileURLWithPath: "/dev/null")
        } else if let description {
            description.url = storeURL(for: storeKey)
        }

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                #if DEBUG
                print("Core Data failed to load: \(error.localizedDescription)")
                print("Attempting to delete and recreate the store...")

                do {
                    if let storeURL = storeDescription.url {
                        try container.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)

                        container.loadPersistentStores { (_, error) in
                            if let error = error as NSError? {
                                fatalError("Unresolved error after reset \(error), \(error.userInfo)")
                            }
                        }
                    }
                } catch {
                    fatalError("Failed to destroy persistent store: \(error)")
                }
                #else
                print("Unresolved error \(error), \(error.userInfo)")
                #endif
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private func storeURL(for key: String) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base
            .appendingPathComponent("Ezcar24Business", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("Ezcar24Business.sqlite")
    }
    
    func createSampleData(in context: NSManagedObjectContext) {
        // Create sample users
        let ivan = User(context: context)
        ivan.id = UUID()
        ivan.name = "Ivan"
        ivan.createdAt = Date()
        ivan.setValue(Date(), forKey: "updatedAt")

        let vanya = User(context: context)
        vanya.id = UUID()
        vanya.name = "Vanya"
        vanya.createdAt = Date()
        vanya.setValue(Date(), forKey: "updatedAt")

        let ahmed = User(context: context)
        ahmed.id = UUID()
        ahmed.name = "Ahmed"
        ahmed.createdAt = Date()
        ahmed.setValue(Date(), forKey: "updatedAt")
        
        // Create financial accounts
        // Check if accounts already exist to avoid duplicates
        let fetchRequest: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
        if let count = try? context.count(for: fetchRequest), count > 0 {
            // Accounts already exist, skip seeding
            return
        }
        
        let cashAccount = FinancialAccount(context: context)
        cashAccount.id = UUID()
        cashAccount.accountType = "cash"
        cashAccount.balance = NSDecimalNumber(value: 45000.0)
        cashAccount.updatedAt = Date()
        
        let bankAccount = FinancialAccount(context: context)
        bankAccount.id = UUID()
        bankAccount.accountType = "bank"
        bankAccount.balance = NSDecimalNumber(value: 125000.0)
        bankAccount.updatedAt = Date()
        
        // Create sample vehicles
        let vehicle1 = Vehicle(context: context)
        vehicle1.id = UUID()
        vehicle1.vin = "1HGBH41JXMN109186"
        vehicle1.make = "Toyota"
        vehicle1.model = "Land Cruiser"
        vehicle1.year = 2022
        vehicle1.purchasePrice = NSDecimalNumber(value: 185000.0)
        vehicle1.purchaseDate = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        vehicle1.status = "owned"
        vehicle1.notes = "Excellent condition, full service history"
        vehicle1.createdAt = Date()
        
        let vehicle2 = Vehicle(context: context)
        vehicle2.id = UUID()
        vehicle2.vin = "WBADT43452G123456"
        vehicle2.make = "BMW"
        vehicle2.model = "X5"
        vehicle2.year = 2021
        vehicle2.purchasePrice = NSDecimalNumber(value: 145000.0)
        vehicle2.purchaseDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        vehicle2.status = "available"
        vehicle2.notes = "Minor scratches, needs detailing"
        vehicle2.createdAt = Date()
        
        let vehicle3 = Vehicle(context: context)
        vehicle3.id = UUID()
        vehicle3.vin = "5UXWX7C5XBA123789"
        vehicle3.make = "Mercedes-Benz"
        vehicle3.model = "GLE 450"
        vehicle3.year = 2023
        vehicle3.purchasePrice = NSDecimalNumber(value: 225000.0)
        vehicle3.purchaseDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        vehicle3.status = "in_transit"
        vehicle3.notes = "Arriving from Dubai next week"
        vehicle3.createdAt = Date()
        
        let vehicle4 = Vehicle(context: context)
        vehicle4.id = UUID()
        vehicle4.vin = "JN1AZ4EH8FM123456"
        vehicle4.make = "Nissan"
        vehicle4.model = "Patrol"
        vehicle4.year = 2022
        vehicle4.purchasePrice = NSDecimalNumber(value: 165000.0)
        vehicle4.purchaseDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        vehicle4.status = "under_service"
        vehicle4.notes = "Engine service in progress"
        vehicle4.createdAt = Date()
        
        // Create sample expenses for vehicles
        let expense1 = Expense(context: context)
        expense1.id = UUID()
        expense1.amount = NSDecimalNumber(value: 3500.0)
        expense1.date = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        expense1.expenseDescription = "Full service and oil change"
        expense1.category = "vehicle"
        expense1.vehicle = vehicle1
        expense1.user = ivan
        expense1.createdAt = Date()
        
        let expense2 = Expense(context: context)
        expense2.id = UUID()
        expense2.amount = NSDecimalNumber(value: 1200.0)
        expense2.date = Calendar.current.date(byAdding: .day, value: -38, to: Date())!
        expense2.expenseDescription = "New tires - all four"
        expense2.category = "vehicle"
        expense2.vehicle = vehicle1
        expense2.user = ivan
        expense2.createdAt = Date()
        
        let expense3 = Expense(context: context)
        expense3.id = UUID()
        expense3.amount = NSDecimalNumber(value: 2800.0)
        expense3.date = Calendar.current.date(byAdding: .day, value: -25, to: Date())!
        expense3.expenseDescription = "Paint correction and ceramic coating"
        expense3.category = "vehicle"
        expense3.vehicle = vehicle2
        expense3.user = vanya
        expense3.createdAt = Date()
        
        let expense4 = Expense(context: context)
        expense4.id = UUID()
        expense4.amount = NSDecimalNumber(value: 850.0)
        expense4.date = Calendar.current.date(byAdding: .day, value: -22, to: Date())!
        expense4.expenseDescription = "Interior detailing"
        expense4.category = "vehicle"
        expense4.vehicle = vehicle2
        expense4.user = vanya
        expense4.createdAt = Date()
        
        let expense5 = Expense(context: context)
        expense5.id = UUID()
        expense5.amount = NSDecimalNumber(value: 4500.0)
        expense5.date = Calendar.current.date(byAdding: .day, value: -18, to: Date())!
        expense5.expenseDescription = "Brake system overhaul"
        expense5.category = "vehicle"
        expense5.vehicle = vehicle4
        expense5.user = ahmed
        expense5.createdAt = Date()
        
        // Create personal expenses
        let expense6 = Expense(context: context)
        expense6.id = UUID()
        expense6.amount = NSDecimalNumber(value: 8500.0)
        expense6.date = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        expense6.expenseDescription = "Office rent - monthly"
        expense6.category = "personal"
        expense6.user = ivan
        expense6.createdAt = Date()
        
        let expense7 = Expense(context: context)
        expense7.id = UUID()
        expense7.amount = NSDecimalNumber(value: 1200.0)
        expense7.date = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        expense7.expenseDescription = "Utilities and internet"
        expense7.category = "personal"
        expense7.user = ivan
        expense7.createdAt = Date()
        
        // Create employee expenses
        let expense8 = Expense(context: context)
        expense8.id = UUID()
        expense8.amount = NSDecimalNumber(value: 12000.0)
        expense8.date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        expense8.expenseDescription = "Monthly salary - Mechanic"
        expense8.category = "employee"
        expense8.user = ahmed
        expense8.createdAt = Date()
        
        let expense9 = Expense(context: context)
        expense9.id = UUID()
        expense9.amount = NSDecimalNumber(value: 15000.0)
        expense9.date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        expense9.expenseDescription = "Monthly salary - Sales Manager"
        expense9.category = "employee"
        expense9.user = vanya
        expense9.createdAt = Date()
        
        // Save context
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func save() {
        let context = viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    func deleteAllData() {
        // Remove all persistent stores from disk to fully isolate accounts/orgs
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storesDir = base
            .appendingPathComponent("Ezcar24Business", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
        if fm.fileExists(atPath: storesDir.path) {
            try? fm.removeItem(at: storesDir)
        }

        containers.removeAll()
        activeStoreKey = Self.guestStoreKey
        containers[activeStoreKey] = makeContainer(storeKey: activeStoreKey, inMemory: true)
    }
}
