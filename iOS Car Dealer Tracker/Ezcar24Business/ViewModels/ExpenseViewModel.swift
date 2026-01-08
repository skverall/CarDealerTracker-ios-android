//
//  ExpenseViewModel.swift
//  Ezcar24Business
//
//  ViewModel for expense tracking
//

import Foundation
import CoreData
import Combine

class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var selectedCategory: String = "all"
    @Published var selectedVehicle: Vehicle? = nil
    @Published var selectedUser: User? = nil
    @Published var vehicles: [Vehicle] = []
    @Published var users: [User] = []
    @Published var accounts: [FinancialAccount] = []
    @Published var templates: [ExpenseTemplate] = []

    @Published var startDate: Date? = nil
    @Published var endDate: Date? = nil
    @Published var searchQuery: String = ""

    enum SortOption {
        case dateDesc, dateAsc, amountDesc, amountAsc
    }
    @Published var sortOption: SortOption = .dateDesc
    private var cancellables = Set<AnyCancellable>()

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        observeContextChanges()
        fetchFilters()
        fetchExpenses()
    }

    func fetchExpenses() {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        // Sorting
        switch sortOption {
        case .dateDesc:    request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.date, ascending: false)]
        case .dateAsc:     request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.date, ascending: true)]
        case .amountDesc:  request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.amount, ascending: false)]
        case .amountAsc:   request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.amount, ascending: true)]
        }

        var predicates: [NSPredicate] = []
        if selectedCategory != "all" {
            predicates.append(NSPredicate(format: "category == %@", selectedCategory))
        }
        if let v = selectedVehicle {
            predicates.append(NSPredicate(format: "vehicle == %@", v))
        }
        if let u = selectedUser {
            predicates.append(NSPredicate(format: "user == %@", u))
        }
        if let sd = startDate {
            predicates.append(NSPredicate(format: "date >= %@", sd as NSDate))
        }
        if let ed = endDate {
            predicates.append(NSPredicate(format: "date < %@", ed as NSDate))
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            predicates.append(NSPredicate(format: "expenseDescription CONTAINS[cd] %@", q))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        do {
            expenses = try context.fetch(request)
        } catch {
            print("Error fetching expenses: \(error)")
        }
    }

    func fetchFilters() {
        do {
            let vReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
            vReq.sortDescriptors = [NSSortDescriptor(key: "make", ascending: true)]
            vehicles = try context.fetch(vReq)
        } catch {
            print("Error fetching vehicles: \(error)")
        }

        do {
            let uReq: NSFetchRequest<User> = User.fetchRequest()
            uReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            users = try context.fetch(uReq)
        } catch {
            print("Error fetching users: \(error)")
        }

        do {
            let aReq: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()
            aReq.sortDescriptors = [NSSortDescriptor(key: "accountType", ascending: true)]
            accounts = try context.fetch(aReq)
        } catch {
            print("Error fetching accounts: \(error)")
        }

        fetchTemplates()
    }

    func refreshFiltersIfNeeded() {
        if vehicles.isEmpty || users.isEmpty || accounts.isEmpty {
            fetchFilters()
        } else if templates.isEmpty {
            fetchTemplates()
        }
    }
    func csvStringForCurrentExpenses() -> String {
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var csv = "Date,Description,Category,Amount,Vehicle,User,Account\n"
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        for e in expenses {
            let dateStr = e.date.map { df.string(from: $0) } ?? ""
            let desc = e.expenseDescription ?? ""
            let cat = e.category ?? ""
            let amt = (e.amount?.decimalValue ?? 0).asCurrencyFallback()
            let vehicle = [e.vehicle?.make, e.vehicle?.model].compactMap { $0 }.joined(separator: " ")
            let user = e.user?.name ?? ""
            let account = e.account?.accountType ?? ""
            csv += [q(dateStr), q(desc), q(cat), q(amt), q(vehicle), q(user), q(account)].joined(separator: ",") + "\n"
        }
        return csv
    }


    @discardableResult
    func addExpense(
        amount: Decimal,
        date: Date,
        description: String,
        category: String,
        vehicle: Vehicle?,
        user: User?,
        account: FinancialAccount?,
        shouldRefresh: Bool = true
    ) throws -> Expense {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.amount = NSDecimalNumber(decimal: amount)
        expense.date = date
        expense.expenseDescription = description
        expense.category = category
        expense.vehicle = vehicle
        expense.user = user
        expense.account = account
        expense.createdAt = Date()
        expense.updatedAt = expense.createdAt

        // Update Account Balance
        if let account = account {
            let currentBalance = account.balance?.decimalValue ?? 0
            account.balance = NSDecimalNumber(decimal: currentBalance - amount)
            account.updatedAt = Date()
        }

        try saveContext()
        if shouldRefresh {
            fetchExpenses()
        }
        return expense
    }

    func deleteExpense(_ expense: Expense) throws -> UUID? {
        let id = expense.id
        let objID = expense.objectID
        // Ensure we operate on the right queue and object instance
        var capturedError: Error?
        context.performAndWait {
            if let existing = try? context.existingObject(with: objID) as? Expense {
                // Restore Balance
                if let account = existing.account, let amount = existing.amount {
                    let currentBalance = account.balance?.decimalValue ?? 0
                    account.balance = NSDecimalNumber(decimal: currentBalance + amount.decimalValue)
                    account.updatedAt = Date()
                }
                
                context.delete(existing)
                do {
                    try context.save()
                    // Clear registered faults to avoid showing stale objects
                    // context.refreshAllObjects() // Removed to prevent UI glitches during swipe to delete
                } catch {
                    context.rollback()
                    capturedError = error
                }
            }
        }
        if let error = capturedError {
            throw error
        }
        // Refresh the published list
        fetchExpenses()
        return id
    }

    func totalExpenses() -> Decimal {
        expenses.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
    }

    private func saveContext() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateExpense(_ expense: Expense, amount: Decimal, date: Date, description: String, category: String, vehicle: Vehicle?, user: User?, account: FinancialAccount?) throws {
        // Revert old balance
        if let oldAccount = expense.account, let oldAmount = expense.amount {
            let oldBalance = oldAccount.balance?.decimalValue ?? 0
            oldAccount.balance = NSDecimalNumber(decimal: oldBalance + oldAmount.decimalValue)
            oldAccount.updatedAt = Date()
        }

        expense.amount = NSDecimalNumber(decimal: amount)
        expense.date = date
        expense.expenseDescription = description
        expense.category = category
        expense.vehicle = vehicle
        expense.user = user
        expense.account = account
        expense.updatedAt = Date()

        // Apply new balance
        if let newAccount = account {
            let newBalance = newAccount.balance?.decimalValue ?? 0
            newAccount.balance = NSDecimalNumber(decimal: newBalance - amount)
            newAccount.updatedAt = Date()
        }

        try saveContext()
        fetchExpenses()
    }
    // MARK: - Templates
    func fetchTemplates() {
        do {
            let tReq: NSFetchRequest<ExpenseTemplate> = ExpenseTemplate.fetchRequest()
            tReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            templates = try context.fetch(tReq)
        } catch {
            print("Error fetching templates: \(error)")
        }
    }

    func saveTemplate(name: String, category: String, vehicle: Vehicle?, user: User?, account: FinancialAccount?, defaultAmount: Decimal?, defaultDescription: String?) throws {
        let t = ExpenseTemplate(context: context)
        t.id = UUID()
        t.name = name
        t.category = category
        t.vehicle = vehicle
        t.user = user
        t.account = account
        if let da = defaultAmount { t.defaultAmount = NSDecimalNumber(decimal: da) }
        if let dd = defaultDescription, !dd.isEmpty { t.defaultDescription = dd }
        t.updatedAt = Date()
        t.deletedAt = nil
        do {
            try context.save()
            fetchTemplates()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - CSV Import
    func importCSV(from url: URL) {
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let rows = raw.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            guard rows.count > 1 else { return }
            // Expect header: Date,Description,Category,Amount,Vehicle,User
            let dataRows = rows.dropFirst()
            for line in dataRows {
                let cols = parseCSVLine(String(line))
                guard cols.count >= 6 else { continue }
                let dateStr = cols[0]
                let desc = cols[1]
                let cat = cols[2]
                let amtStr = cols[3]
                let vehicleStr = cols[4]
                let userStr = cols[5]

                guard let amount = parseAmount(amtStr) else { continue }
                let date = parseDate(dateStr) ?? Date()

                // Match vehicle by "Make Model"
                let vehicle = vehicles.first { v in
                    let name = [v.make, v.model].compactMap { $0 }.joined(separator: " ")
                    return name.caseInsensitiveCompare(vehicleStr) == .orderedSame
                }
                // Match user by name
                let user = users.first { u in
                    (u.name ?? "").caseInsensitiveCompare(userStr) == .orderedSame
                }

                do {
                    try addExpense(
                        amount: amount,
                        date: date,
                        description: desc,
                        category: cat,
                        vehicle: vehicle,
                        user: user,
                        account: nil,
                        shouldRefresh: false
                    )
                } catch {
                    print("Failed to import expense: \(error)")
                }
            }
            fetchExpenses()
        } catch {
            print("Failed to import CSV: \(error)")
        }
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefreshFilters(userInfo: info) {
                    self.fetchFilters()
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefreshFilters(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSDeletedObjectsKey, NSUpdatedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { obj in
                obj is Vehicle || obj is User || obj is FinancialAccount
            }) {
                return true
            }
        }
        return false
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" { // quote
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == "," && !inQuotes {
                result.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(c)
            }
            i += 1
        }
        result.append(current)
        return result
    }

    private func parseAmount(_ s: String) -> Decimal? {
        let filtered = s.filter { ("0"..."9").contains($0) || $0 == "." || $0 == "-" }
        return Decimal(string: filtered)
    }

    private func parseDate(_ s: String) -> Date? {
        // Try short date+time (as exported)
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        if let d = df.date(from: s) { return d }
        // Try just date
        df.timeStyle = .none
        if let d = df.date(from: s) { return d }
        // Try ISO
        let iso = ISO8601DateFormatter()
        return iso.date(from: s)
    }

}
