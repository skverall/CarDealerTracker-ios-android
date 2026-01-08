import Foundation
import Supabase

enum PermissionKey: String, Codable {
    case viewFinancials = "view_financials"
    case viewExpenses = "view_expenses"
    case viewInventory = "view_inventory"
    case createSale = "create_sale"
    case manageTeam = "manage_team"
    case viewLeads = "view_leads"
}

@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()
    
    @Published private(set) var permissions: [String: Bool] = [:]
    
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://haordpdxyyreliyzmire.supabase.co")!,
        supabaseKey: "PLACEHOLDER_KEY_managed_by_config" // Actually usually injected or config
        // In this project SupabaseConfig.plist is used or CloudSyncManager has the client.
        // We should probably inject the client or use a shared one.
        // For now, I'll expose a setup method or use a shared accessor if available.
    )
    
    // In Ezcar24Business, usually CloudSyncManager has the client.
    // Or there is a SupabaseManager. 
    // I see SupabaseModels, but not Manager in file list explicitly? 
    // CloudSyncManager.init takes a client.
    // I will let PermissionService be initialized with a client or fetched via Dependency Injection.
    // For simplicity I'll add a 'configure' method.
    
    private var supabase: SupabaseClient?
    
    func configure(client: SupabaseClient) {
        self.supabase = client
    }
    
    func fetchPermissions(dealerId: UUID) async {
        guard let supabase = supabase else { return }
        
        do {
            let result: [String: Bool] = try await supabase
                .rpc("get_my_permissions", params: ["_org_id": dealerId.uuidString])
                .execute()
                .value
            
            self.permissions = result
            print("PermissionService: Loaded permissions: \(result)")
        } catch {
            print("PermissionService: Failed to fetch permissions: \(error)")
            // Default to RESTRICTIVE if fail? Or Permissive for Owner?
            // "Secure by Default" -> False.
        }
    }
    
    func can(_ key: PermissionKey) -> Bool {
        return permissions[key.rawValue] ?? false
    }
    
    // Helper for 'owner' bypass? No, cache should reflect owner=true from DB RPC.
}
