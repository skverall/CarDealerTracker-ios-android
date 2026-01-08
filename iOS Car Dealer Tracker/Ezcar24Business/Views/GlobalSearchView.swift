import SwiftUI
import CoreData

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var searchText = ""
    @State private var vehicleResults: [Vehicle] = []
    @State private var clientResults: [Client] = []
    @State private var expenseResults: [Expense] = []
    
    var body: some View {
        NavigationStack {
            List {
                if !vehicleResults.isEmpty {
                    Section("Vehicles") {
                        ForEach(vehicleResults) { vehicle in
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                }
                
                if !clientResults.isEmpty {
                    Section("Clients") {
                        ForEach(clientResults) { client in
                            ClientRow(client: client)
                        }
                    }
                }
                
                if !expenseResults.isEmpty {
                    Section("Expenses") {
                        ForEach(expenseResults) { expense in
                            RecentExpenseRow(expense: expense)
                        }
                    }
                }
                
                if !searchText.isEmpty && vehicleResults.isEmpty && clientResults.isEmpty && expenseResults.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .searchable(text: $searchText, prompt: Text("search_placeholder_text".localizedString))
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .navigationTitle("search".localizedString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("done".localizedString) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            vehicleResults = []
            clientResults = []
            expenseResults = []
            return
        }
        
        let lowerQuery = query.lowercased()
        
        // Search Vehicles
        let vehicleReq: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        vehicleReq.predicate = NSPredicate(format: "make CONTAINS[cd] %@ OR model CONTAINS[cd] %@ OR vin CONTAINS[cd] %@", query, query, query)
        vehicleReq.fetchLimit = 5
        
        // Search Clients
        let clientReq: NSFetchRequest<Client> = Client.fetchRequest()
        clientReq.predicate = NSPredicate(format: "firstName CONTAINS[cd] %@ OR lastName CONTAINS[cd] %@ OR phone CONTAINS[cd] %@", query, query, query)
        clientReq.fetchLimit = 5
        
        // Search Expenses
        let expenseReq: NSFetchRequest<Expense> = Expense.fetchRequest()
        expenseReq.predicate = NSPredicate(format: "expenseDescription CONTAINS[cd] %@ OR category CONTAINS[cd] %@", query, query)
        expenseReq.fetchLimit = 5
        
        do {
            vehicleResults = try viewContext.fetch(vehicleReq)
            clientResults = try viewContext.fetch(clientReq)
            expenseResults = try viewContext.fetch(expenseReq)
        } catch {
            print("Search failed: \(error)")
        }
    }
}

// Minimal row components for results if main ones aren't reusable easily
// I'll assume VehicleRow and ClientRow might exist or I can make simple ones.
// RecentExpenseRow is available from DashboardComponents.

private struct VehicleRow: View {
    let vehicle: Vehicle
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                .font(.headline)
            Text(vehicle.vin ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct ClientRow: View {
    let client: Client
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(client.firstName ?? "") \(client.lastName ?? "")")
                .font(.headline)
            Text(client.phone ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
