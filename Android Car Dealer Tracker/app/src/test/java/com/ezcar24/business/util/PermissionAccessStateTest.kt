package com.ezcar24.business.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionAccessStateTest {
    @Test
    fun `explicit permission overrides role default`() {
        val state = PermissionAccessState(
            role = "admin",
            permissions = mapOf(PermissionKey.VIEW_EXPENSES.rawValue to false)
        )

        assertFalse(state.can(PermissionKey.VIEW_EXPENSES))
    }

    @Test
    fun `role default is used when explicit permission is missing`() {
        val state = PermissionAccessState(role = "sales")

        assertTrue(state.can(PermissionKey.VIEW_INVENTORY))
        assertFalse(state.can(PermissionKey.VIEW_FINANCIALS))
    }

    @Test
    fun `can any allows iOS sales tab behavior`() {
        val state = PermissionAccessState(
            role = "viewer",
            permissions = mapOf(
                PermissionKey.CREATE_SALE.rawValue to false,
                PermissionKey.VIEW_FINANCIALS.rawValue to true
            )
        )

        assertTrue(
            state.canAny(
                listOf(PermissionKey.CREATE_SALE, PermissionKey.VIEW_FINANCIALS)
            )
        )
    }
}
