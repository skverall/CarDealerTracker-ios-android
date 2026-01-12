import Foundation
import CoreData
import Combine

@MainActor
final class PartsInventoryViewModel: ObservableObject {
    @Published var parts: [Part] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: String? = nil {
        didSet { fetchParts() }
    }
    @Published var showLowStockOnly: Bool = false {
        didSet { fetchParts() }
    }

    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext) {
        self.context = context
        fetchParts()
        observeContextChanges()

        $searchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.fetchParts()
            }
            .store(in: &cancellables)
    }

    func fetchParts() {
        let request: NSFetchRequest<Part> = Part.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Part.name, ascending: true)]

        var predicates: [NSPredicate] = [NSPredicate(format: "deletedAt == nil")]
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "name CONTAINS[cd] %@", search),
                NSPredicate(format: "category CONTAINS[cd] %@", search)
            ])
            predicates.append(searchPredicate)
        }
        
        if let category = selectedCategory {
            predicates.append(NSPredicate(format: "category == %@", category))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        do {
            var results = try context.fetch(request)
            if showLowStockOnly {
                results = results.filter { $0.quantityOnHand <= 2 }
            }
            parts = results
        } catch {
            print("PartsInventoryViewModel fetchParts error: \(error)")
        }
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                if Self.shouldRefresh(userInfo: info) {
                    self.fetchParts()
                }
            }
            .store(in: &cancellables)
    }

    private static func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0 is Part || $0 is PartBatch || $0 is PartSaleLineItem }) {
                return true
            }
        }
        return false
    }

    // MARK: - Analytics & Helpers
    
    var totalValue: Decimal {
        parts.reduce(0) { $0 + $1.inventoryValue }
    }
    
    var activeItemCount: Int {
        parts.count
    }
    
    var lowStockCount: Int {
        parts.filter { $0.quantityOnHand <= 2 }.count
    }

    /// Fetches all unique categories from the database (ignoring current filters)
    /// to populate the filter menu.
    func getAllCategories() -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Part")
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = ["category"]
        request.predicate = NSPredicate(format: "deletedAt == nil AND category != nil AND category != ''")
        request.sortDescriptors = [NSSortDescriptor(key: "category", ascending: true)]

        do {
            let results = try context.fetch(request)
            return results.compactMap { $0["category"] as? String }
        } catch {
            return []
        }
    }
}
