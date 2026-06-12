package com.ezcar24.business.util

import java.util.UUID

enum class PermissionKey(val rawValue: String) {
    VIEW_FINANCIALS("view_financials"),
    VIEW_EXPENSES("view_expenses"),
    VIEW_INVENTORY("view_inventory"),
    CREATE_SALE("create_sale"),
    VIEW_PARTS_INVENTORY("view_parts_inventory"),
    MANAGE_PARTS_INVENTORY("manage_parts_inventory"),
    CREATE_PART_SALE("create_part_sale"),
    MANAGE_TEAM("manage_team"),
    VIEW_LEADS("view_leads"),
    VIEW_VEHICLE_COST("view_vehicle_cost"),
    VIEW_VEHICLE_PROFIT("view_vehicle_profit"),
    VIEW_PART_COST("view_part_cost"),
    VIEW_PART_PROFIT("view_part_profit"),
    DELETE_RECORDS("delete_records")
}

data class PermissionAccessState(
    val dealerId: UUID? = null,
    val permissions: Map<String, Boolean> = emptyMap(),
    val role: String = "",
    val didLoad: Boolean = false,
    val isLoading: Boolean = false
) {
    fun can(key: PermissionKey): Boolean {
        permissions[key.rawValue]?.let { return it }
        if (role.isNotBlank()) {
            return TeamPermissionCatalog.defaultPermissions(role)[key.rawValue] == true
        }
        return false
    }

    fun canAny(keys: Collection<PermissionKey>): Boolean {
        return keys.any(::can)
    }

    fun canViewVehicleCost(): Boolean {
        permissions[PermissionKey.VIEW_VEHICLE_COST.rawValue]?.let { return it }
        return can(PermissionKey.VIEW_FINANCIALS)
    }

    fun canViewVehicleProfit(): Boolean {
        permissions[PermissionKey.VIEW_VEHICLE_PROFIT.rawValue]?.let { return it }
        return can(PermissionKey.VIEW_FINANCIALS)
    }

    fun canViewPartCost(): Boolean {
        permissions[PermissionKey.VIEW_PART_COST.rawValue]?.let { return it }
        return can(PermissionKey.VIEW_FINANCIALS)
    }

    fun canViewPartProfit(): Boolean {
        permissions[PermissionKey.VIEW_PART_PROFIT.rawValue]?.let { return it }
        return can(PermissionKey.VIEW_FINANCIALS)
    }
}
