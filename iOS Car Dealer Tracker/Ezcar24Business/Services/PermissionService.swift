import Foundation
import Supabase

enum PermissionKey: String, Codable {
    case viewFinancials = "view_financials"
    case viewExpenses = "view_expenses"
    case viewInventory = "view_inventory"
    case createSale = "create_sale"
    case manageTeam = "manage_team"
    case viewLeads = "view_leads"
    case viewVehicleCost = "view_vehicle_cost"
    case viewVehicleProfit = "view_vehicle_profit"
    case deleteRecords = "delete_records"
}

@MainActor
final class PermissionService: ObservableObject {
    static let shared = PermissionService()
    
    @Published private(set) var permissions: [String: Bool] = [:]
    @Published private(set) var didLoad = false
    
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
        self.permissions = [:]
        self.didLoad = false
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
        self.didLoad = true
    }
    
    func can(_ key: PermissionKey) -> Bool {
        return permissions[key.rawValue] ?? false
    }

    private func permissionValue(for key: PermissionKey) -> Bool? {
        if permissions.keys.contains(key.rawValue) {
            return permissions[key.rawValue] ?? false
        }
        return nil
    }

    func canViewVehicleCost() -> Bool {
        if let value = permissionValue(for: .viewVehicleCost) {
            return value
        }
        return can(.viewFinancials)
    }

    func canViewVehicleProfit() -> Bool {
        if let value = permissionValue(for: .viewVehicleProfit) {
            return value
        }
        return can(.viewFinancials)
    }
    
    // Helper for 'owner' bypass? No, cache should reflect owner=true from DB RPC.
}

struct PermissionDefinition: Identifiable {
    let key: PermissionKey
    let titleKey: String
    let detailKey: String
    let systemImage: String

    var id: String { key.rawValue }
}

struct PermissionGroup: Identifiable {
    let id = UUID()
    let primary: PermissionDefinition
    let detailTitleKey: String?
    let detailItems: [PermissionDefinition]
}

enum PermissionCatalog {
    static let roles = ["admin", "sales", "viewer"]

    static let groups: [PermissionGroup] = [
        PermissionGroup(
            primary: PermissionDefinition(
                key: .viewInventory,
                titleKey: "permission_view_inventory_title",
                detailKey: "permission_view_inventory_detail",
                systemImage: "car.fill"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .createSale,
                titleKey: "permission_create_sale_title",
                detailKey: "permission_create_sale_detail",
                systemImage: "checkmark.seal.fill"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .viewLeads,
                titleKey: "permission_view_leads_title",
                detailKey: "permission_view_leads_detail",
                systemImage: "person.crop.circle.badge.magnifyingglass"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .viewExpenses,
                titleKey: "permission_view_expenses_title",
                detailKey: "permission_view_expenses_detail",
                systemImage: "creditcard.fill"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .manageTeam,
                titleKey: "permission_manage_team_title",
                detailKey: "permission_manage_team_detail",
                systemImage: "person.3.fill"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .deleteRecords,
                titleKey: "permission_delete_records_title",
                detailKey: "permission_delete_records_detail",
                systemImage: "trash.fill"
            ),
            detailTitleKey: nil,
            detailItems: []
        )
    ]

    static let items: [PermissionDefinition] = groups.flatMap { [$0.primary] + $0.detailItems }

    static func defaultPermissions(for role: String) -> [String: Bool] {
        switch role {
        case "owner":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: true,
                PermissionKey.viewLeads.rawValue: true,
                PermissionKey.viewExpenses.rawValue: true,
                PermissionKey.manageTeam.rawValue: true,
                PermissionKey.deleteRecords.rawValue: true
            ]
        case "admin":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: true,
                PermissionKey.viewLeads.rawValue: true,
                PermissionKey.viewExpenses.rawValue: true,
                PermissionKey.manageTeam.rawValue: true,
                PermissionKey.deleteRecords.rawValue: true
            ]
        case "sales":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: true,
                PermissionKey.viewLeads.rawValue: true,
                PermissionKey.viewExpenses.rawValue: true,
                PermissionKey.manageTeam.rawValue: false,
                PermissionKey.deleteRecords.rawValue: false
            ]
        case "viewer":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: false,
                PermissionKey.viewLeads.rawValue: false,
                PermissionKey.viewExpenses.rawValue: false,
                PermissionKey.manageTeam.rawValue: false,
                PermissionKey.deleteRecords.rawValue: false
            ]
        default:
            return [:]
        }
    }

    static func resolvedPermissions(_ input: [String: Bool]?, role: String) -> [String: Bool] {
        var result = defaultPermissions(for: role)
        guard let input else { return result }
        for (key, value) in input {
            result[key] = value
        }
        return result
    }

    static func applyDefaults(to permissions: inout [String: Bool], role: String) {
        let defaults = defaultPermissions(for: role)
        for item in items {
            permissions[item.key.rawValue] = defaults[item.key.rawValue] ?? false
        }
    }

    static func isCustomPermissions(_ permissions: [String: Bool]?, role: String) -> Bool {
        let resolved = resolvedPermissions(permissions, role: role)
        let defaults = defaultPermissions(for: role)
        for item in items {
            let key = item.key.rawValue
            if resolved[key] != defaults[key] {
                return true
            }
        }
        return false
    }

    @MainActor
    static func enabledPermissionTitles(from permissions: [String: Bool]?, role: String) -> [String] {
        let resolved = resolvedPermissions(permissions, role: role)
        return items.compactMap { item in
            resolved[item.key.rawValue] == true ? item.titleKey.localizedString : nil
        }
    }

    @MainActor
    static func roleSummary(for role: String) -> String {
        let defaults = defaultPermissions(for: role)
        let enabledTitles = items.compactMap { item -> String? in
            defaults[item.key.rawValue] == true ? item.titleKey.localizedString : nil
        }

        if enabledTitles.isEmpty {
            return "permission_role_no_access".localizedString
        }

        let summaryFormat = "permission_role_preset_summary".localizedString
        return String(format: summaryFormat, locale: Locale.current, enabledTitles.joined(separator: ", "))
    }

    @MainActor
    static func permissionSummary(for permissions: [String: Bool]?, role: String, maxItems: Int = 3) -> String {
        let enabled = enabledPermissionTitles(from: permissions, role: role)
        if enabled.isEmpty {
            return "permission_access_none".localizedString
        }
        let displayed = enabled.prefix(maxItems)
        let baseFormat = "permission_access_summary".localizedString
        var summary = String(format: baseFormat, locale: Locale.current, displayed.joined(separator: ", "))
        if enabled.count > maxItems {
            let extraFormat = "permission_access_summary_extra".localizedString
            summary = String(
                format: extraFormat,
                locale: Locale.current,
                displayed.joined(separator: ", "),
                enabled.count - maxItems
            )
        }
        return summary
    }
}
