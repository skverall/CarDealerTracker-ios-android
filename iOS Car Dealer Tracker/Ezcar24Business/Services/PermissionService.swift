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
    @Published private(set) var currentRole: String = ""
    @Published private(set) var didLoad = false

    private var supabase: SupabaseClient?
    private var activeDealerId: UUID?
    private let permissionsCacheKeyPrefix = "permissions_cache_v1"
    private let roleCacheKeyPrefix = "role_cache_v1"
    
    func configure(client: SupabaseClient, dealerId: UUID? = nil) {
        self.supabase = client
        if let dealerId {
            setActiveDealerId(dealerId)
        }
    }

    func setActiveDealerId(_ dealerId: UUID?) {
        activeDealerId = dealerId
        guard let dealerId, let userId = currentUserId() else {
            resetSession()
            return
        }
        let cachedPermissions = loadCachedPermissions(userId: userId, dealerId: dealerId)
        let cachedRole = loadCachedRole(userId: userId, dealerId: dealerId)
        if applyCachedState(permissions: cachedPermissions, role: cachedRole) {
            return
        }
        permissions = [:]
        currentRole = ""
        didLoad = false
    }

    func resetSession() {
        activeDealerId = nil
        permissions = [:]
        currentRole = ""
        didLoad = false
    }
    
    func fetchPermissions(dealerId: UUID) async {
        guard let supabase = supabase else { return }
        loadCachedStateIfAvailable(dealerId: dealerId)
        
        do {
            let result: [String: Bool] = try await supabase
                .rpc("get_my_permissions", params: ["_org_id": dealerId.uuidString])
                .execute()
                .value
            
            self.permissions = result
            cachePermissions(result, dealerId: dealerId)
            print("PermissionService: Loaded permissions: \(result)")
        } catch {
            print("PermissionService: Failed to fetch permissions: \(error)")
            // Default to RESTRICTIVE if fail? Or Permissive for Owner?
            // "Secure by Default" -> False.
        }
        
        // Fetch role
        do {
            let roleResult: String = try await supabase
                .rpc("get_my_role", params: ["_org_id": dealerId.uuidString])
                .execute()
                .value
            
            self.currentRole = roleResult
            cacheRole(roleResult, dealerId: dealerId)
            print("PermissionService: Loaded role: \(roleResult)")
        } catch {
            print("PermissionService: Failed to fetch role: \(error)")
            self.currentRole = ""
        }

        applyResolvedPermissionsIfPossible()
        
        self.didLoad = true
    }
    
    func can(_ key: PermissionKey) -> Bool {
        if let value = permissionValue(for: key) {
            return value
        }
        if !currentRole.isEmpty {
            return PermissionCatalog.defaultPermissions(for: currentRole)[key.rawValue] ?? false
        }
        return false
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

    private func currentUserId() -> UUID? {
        supabase?.auth.currentSession?.user.id ?? supabase?.auth.currentUser?.id
    }

    private func cacheKey(prefix: String, userId: UUID, dealerId: UUID) -> String {
        "\(prefix)_\(userId.uuidString.lowercased())_\(dealerId.uuidString.lowercased())"
    }

    private func loadCachedPermissions(userId: UUID, dealerId: UUID) -> [String: Bool]? {
        let key = cacheKey(prefix: permissionsCacheKeyPrefix, userId: userId, dealerId: dealerId)
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        var result: [String: Bool] = [:]
        for (k, v) in raw {
            if let boolValue = v as? Bool {
                result[k] = boolValue
            } else if let number = v as? NSNumber {
                result[k] = number.boolValue
            }
        }
        return result.isEmpty ? nil : result
    }

    private func loadCachedRole(userId: UUID, dealerId: UUID) -> String? {
        let key = cacheKey(prefix: roleCacheKeyPrefix, userId: userId, dealerId: dealerId)
        return UserDefaults.standard.string(forKey: key)
    }

    private func cachePermissions(_ permissions: [String: Bool], dealerId: UUID) {
        guard let userId = currentUserId() else { return }
        let key = cacheKey(prefix: permissionsCacheKeyPrefix, userId: userId, dealerId: dealerId)
        UserDefaults.standard.set(permissions, forKey: key)
    }

    private func cacheRole(_ role: String, dealerId: UUID) {
        guard let userId = currentUserId() else { return }
        let key = cacheKey(prefix: roleCacheKeyPrefix, userId: userId, dealerId: dealerId)
        UserDefaults.standard.set(role, forKey: key)
    }

    private func loadCachedStateIfAvailable(dealerId: UUID) {
        guard let userId = currentUserId() else { return }
        let cachedPermissions = loadCachedPermissions(userId: userId, dealerId: dealerId)
        let cachedRole = loadCachedRole(userId: userId, dealerId: dealerId)
        _ = applyCachedState(permissions: cachedPermissions, role: cachedRole)
    }

    private func applyCachedState(permissions cachedPermissions: [String: Bool]?, role cachedRole: String?) -> Bool {
        guard cachedPermissions != nil || cachedRole != nil else { return false }
        if let role = cachedRole, !role.isEmpty {
            currentRole = role
            let resolved = PermissionCatalog.resolvedPermissions(cachedPermissions, role: role)
            if !resolved.isEmpty {
                permissions = resolved
            } else if let cachedPermissions {
                permissions = cachedPermissions
            }
        } else if let cachedPermissions {
            permissions = cachedPermissions
        }
        didLoad = true
        return true
    }

    private func applyResolvedPermissionsIfPossible() {
        guard !currentRole.isEmpty else { return }
        let resolved = PermissionCatalog.resolvedPermissions(permissions, role: currentRole)
        if !resolved.isEmpty {
            permissions = resolved
        }
    }
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
                systemImage: "person.text.rectangle"
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
                key: .viewVehicleCost,
                titleKey: "permission_view_vehicle_cost_title",
                detailKey: "permission_view_vehicle_cost_detail",
                systemImage: "dollarsign.circle"
            ),
            detailTitleKey: nil,
            detailItems: []
        ),
        PermissionGroup(
            primary: PermissionDefinition(
                key: .viewVehicleProfit,
                titleKey: "permission_view_vehicle_profit_title",
                detailKey: "permission_view_vehicle_profit_detail",
                systemImage: "chart.line.uptrend.xyaxis"
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
                PermissionKey.viewVehicleCost.rawValue: true,
                PermissionKey.viewVehicleProfit.rawValue: true,
                PermissionKey.manageTeam.rawValue: true,
                PermissionKey.deleteRecords.rawValue: true
            ]
        case "admin":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: true,
                PermissionKey.viewLeads.rawValue: true,
                PermissionKey.viewExpenses.rawValue: true,
                PermissionKey.viewVehicleCost.rawValue: true,
                PermissionKey.viewVehicleProfit.rawValue: true,
                PermissionKey.manageTeam.rawValue: true,
                PermissionKey.deleteRecords.rawValue: true
            ]
        case "sales":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: true,
                PermissionKey.viewLeads.rawValue: true,
                PermissionKey.viewExpenses.rawValue: true,
                PermissionKey.viewVehicleCost.rawValue: false,
                PermissionKey.viewVehicleProfit.rawValue: false,
                PermissionKey.manageTeam.rawValue: false,
                PermissionKey.deleteRecords.rawValue: false
            ]
        case "viewer":
            return [
                PermissionKey.viewInventory.rawValue: true,
                PermissionKey.createSale.rawValue: false,
                PermissionKey.viewLeads.rawValue: false,
                PermissionKey.viewExpenses.rawValue: false,
                PermissionKey.viewVehicleCost.rawValue: false,
                PermissionKey.viewVehicleProfit.rawValue: false,
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
