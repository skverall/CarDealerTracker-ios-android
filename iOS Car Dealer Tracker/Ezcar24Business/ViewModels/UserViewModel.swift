//
//  UserViewModel.swift
//  Ezcar24Business
//
//  ViewModel for user management
//

import Foundation
import CoreData
import Combine

class UserViewModel: ObservableObject {
    @Published var users: [User] = []
    
    private let context: NSManagedObjectContext
    
    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    init(context: NSManagedObjectContext) {
        self.context = context
        fetchUsers()
    }
    
    func fetchUsers() {
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \User.name, ascending: true)]

        do {
            users = try context.fetch(request)
        } catch {
            print("Error fetching users: \(error)")
        }
    }

    @discardableResult
    func addUser(name: String) -> User {
        let normalizedName = normalize(name)
        if let existing = users.first(where: { normalize($0.name ?? "") == normalizedName }) {
            existing.updatedAt = Date()
            saveContext()
            fetchUsers()
            return existing
        }
        
        let user = User(context: context)
        user.id = UUID()
        user.name = name
        user.createdAt = Date()
        user.updatedAt = Date()

        saveContext()
        fetchUsers()
        return user
    }

    @discardableResult
    func deleteUser(_ user: User) -> UUID? {
        let id = user.id
        context.delete(user)
        saveContext()
        fetchUsers()
        return id
    }

    func expenseCount(for user: User) -> Int {
        return (user.expenses as? Set<Expense>)?.count ?? 0
    }
    
    func totalExpenses(for user: User) -> Decimal {
        return (user.expenses as? Set<Expense>)?.reduce(0) { $0 + ($1.amount as Decimal? ?? 0) } ?? 0
    }
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
