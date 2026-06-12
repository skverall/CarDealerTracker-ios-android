package com.ezcar24.business.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionAccessTest {
    @Test
    fun `free users are gated at the vehicle limit`() {
        assertFalse(
            SubscriptionAccess.shouldGateVehicleCreation(
                isProAccessActive = false,
                isCheckingStatus = false,
                vehicleCount = 2
            )
        )

        assertTrue(
            SubscriptionAccess.shouldGateVehicleCreation(
                isProAccessActive = false,
                isCheckingStatus = false,
                vehicleCount = 3
            )
        )
    }

    @Test
    fun `pro users and status checks are not gated`() {
        assertFalse(
            SubscriptionAccess.shouldGateVehicleCreation(
                isProAccessActive = true,
                isCheckingStatus = false,
                vehicleCount = 20
            )
        )

        assertFalse(
            SubscriptionAccess.shouldGateVehicleCreation(
                isProAccessActive = false,
                isCheckingStatus = true,
                vehicleCount = 20
            )
        )
    }
}
