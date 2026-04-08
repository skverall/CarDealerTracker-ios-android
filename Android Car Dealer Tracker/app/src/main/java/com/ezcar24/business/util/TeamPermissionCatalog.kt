package com.ezcar24.business.util

object TeamPermissionCatalog {
    val roles = listOf("owner", "admin", "sales", "viewer")

    val permissions = listOf(
        PermissionOption(
            key = "view_inventory",
            title = "View Inventory",
            detail = "Browse vehicles and stock visibility."
        ),
        PermissionOption(
            key = "create_sale",
            title = "Create Sale",
            detail = "Record vehicle sales and close deals."
        ),
        PermissionOption(
            key = "view_parts_inventory",
            title = "View Parts Inventory",
            detail = "Browse parts catalog and stock levels."
        ),
        PermissionOption(
            key = "manage_parts_inventory",
            title = "Manage Parts Inventory",
            detail = "Add, edit, and remove parts from inventory."
        ),
        PermissionOption(
            key = "create_part_sale",
            title = "Create Part Sale",
            detail = "Sell parts and record part sales."
        ),
        PermissionOption(
            key = "view_leads",
            title = "View Leads",
            detail = "Open CRM, leads and follow-up lists."
        ),
        PermissionOption(
            key = "view_expenses",
            title = "View Expenses",
            detail = "See expense history and spend data."
        ),
        PermissionOption(
            key = "view_vehicle_cost",
            title = "View Vehicle Cost",
            detail = "Access cost data for each vehicle."
        ),
        PermissionOption(
            key = "view_vehicle_profit",
            title = "View Vehicle Profit",
            detail = "Access deal profit and margin data."
        ),
        PermissionOption(
            key = "view_part_cost",
            title = "View Part Cost",
            detail = "Access cost data for parts."
        ),
        PermissionOption(
            key = "view_part_profit",
            title = "View Part Profit",
            detail = "Access part sale profit and margin data."
        ),
        PermissionOption(
            key = "manage_team",
            title = "Manage Team",
            detail = "Invite members and edit their access."
        ),
        PermissionOption(
            key = "delete_records",
            title = "Delete Records",
            detail = "Remove vehicles, users and other records."
        ),
        PermissionOption(
            key = "view_financials",
            title = "View Financials",
            detail = "Access financial accounts and overall financial data."
        )
    )

    fun defaultPermissions(role: String): Map<String, Boolean> {
        return when (role) {
            "owner" -> mapOf(
                "view_inventory" to true,
                "create_sale" to true,
                "view_parts_inventory" to true,
                "manage_parts_inventory" to true,
                "create_part_sale" to true,
                "view_leads" to true,
                "view_expenses" to true,
                "view_vehicle_cost" to true,
                "view_vehicle_profit" to true,
                "view_part_cost" to true,
                "view_part_profit" to true,
                "view_financials" to true,
                "manage_team" to true,
                "delete_records" to true
            )

            "admin" -> mapOf(
                "view_inventory" to true,
                "create_sale" to true,
                "view_parts_inventory" to true,
                "manage_parts_inventory" to true,
                "create_part_sale" to true,
                "view_leads" to true,
                "view_expenses" to true,
                "view_vehicle_cost" to true,
                "view_vehicle_profit" to true,
                "view_part_cost" to true,
                "view_part_profit" to true,
                "view_financials" to true,
                "manage_team" to true,
                "delete_records" to true
            )

            "sales" -> mapOf(
                "view_inventory" to true,
                "create_sale" to true,
                "view_parts_inventory" to true,
                "manage_parts_inventory" to false,
                "create_part_sale" to true,
                "view_leads" to true,
                "view_expenses" to true,
                "view_vehicle_cost" to false,
                "view_vehicle_profit" to false,
                "view_part_cost" to false,
                "view_part_profit" to false,
                "view_financials" to false,
                "manage_team" to false,
                "delete_records" to false
            )

            else -> mapOf(
                "view_inventory" to true,
                "create_sale" to false,
                "view_parts_inventory" to true,
                "manage_parts_inventory" to false,
                "create_part_sale" to false,
                "view_leads" to false,
                "view_expenses" to false,
                "view_vehicle_cost" to false,
                "view_vehicle_profit" to false,
                "view_part_cost" to false,
                "view_part_profit" to false,
                "view_financials" to false,
                "manage_team" to false,
                "delete_records" to false
            )
        }
    }

    fun resolvedPermissions(input: Map<String, Boolean>?, role: String): Map<String, Boolean> {
        val defaults = defaultPermissions(role).toMutableMap()
        input.orEmpty().forEach { (key, value) ->
            if (defaults.containsKey(key)) {
                defaults[key] = value
            }
        }
        return defaults
    }

    fun roleSummary(role: String): String {
        return when (role) {
            "owner" -> "Full owner access across the business."
            "admin" -> "Full access to operations, analytics and team management."
            "sales" -> "Deal-focused access with inventory and leads, but no team administration."
            "viewer" -> "Read-only visibility with restricted sales and finance actions."
            else -> "Custom access profile."
        }
    }

    fun isCustomPermissions(input: Map<String, Boolean>?, role: String): Boolean {
        return resolvedPermissions(input, role) != defaultPermissions(role)
    }

    fun permissionSummary(input: Map<String, Boolean>?, role: String): String {
        val resolved = resolvedPermissions(input, role)
        val enabled = permissions.filter { resolved[it.key] == true }.map { it.title }
        if (enabled.isEmpty()) {
            return "No access granted."
        }
        return enabled.joinToString(separator = ", ")
    }
}

data class PermissionOption(
    val key: String,
    val title: String,
    val detail: String
)
