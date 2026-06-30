package com.ezcar24.business

import com.ezcar24.business.util.vehiclePurchaseAccountBalanceDeltas
import java.math.BigDecimal
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VehiclePurchaseAccountBalanceTest {
    @Test
    fun newVehicleDeductsPurchasePriceFromTargetAccount() {
        val accountId = UUID.fromString("00000000-0000-0000-0000-000000000001")

        val deltas = vehiclePurchaseAccountBalanceDeltas(
            isNewVehicle = true,
            previousAccountId = null,
            previousPurchasePrice = BigDecimal.ZERO,
            targetAccountId = accountId,
            newPurchasePrice = BigDecimal("12500")
        )

        assertEquals(BigDecimal("-12500"), deltas[accountId])
    }

    @Test
    fun editSamePurchaseAccountAppliesOnlyPriceDelta() {
        val accountId = UUID.fromString("00000000-0000-0000-0000-000000000001")

        val deltas = vehiclePurchaseAccountBalanceDeltas(
            isNewVehicle = false,
            previousAccountId = accountId,
            previousPurchasePrice = BigDecimal("10000"),
            targetAccountId = accountId,
            newPurchasePrice = BigDecimal("12000")
        )

        assertEquals(BigDecimal("-2000"), deltas[accountId])
    }

    @Test
    fun editChangedPurchaseAccountRestoresPreviousAndDeductsTarget() {
        val previousAccountId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val targetAccountId = UUID.fromString("00000000-0000-0000-0000-000000000002")

        val deltas = vehiclePurchaseAccountBalanceDeltas(
            isNewVehicle = false,
            previousAccountId = previousAccountId,
            previousPurchasePrice = BigDecimal("10000"),
            targetAccountId = targetAccountId,
            newPurchasePrice = BigDecimal("12000")
        )

        assertEquals(BigDecimal("10000"), deltas[previousAccountId])
        assertEquals(BigDecimal("-12000"), deltas[targetAccountId])
    }

    @Test
    fun legacyExistingVehicleWithoutPurchaseAccountIsNotRebalanced() {
        val targetAccountId = UUID.fromString("00000000-0000-0000-0000-000000000002")

        val deltas = vehiclePurchaseAccountBalanceDeltas(
            isNewVehicle = false,
            previousAccountId = null,
            previousPurchasePrice = BigDecimal("10000"),
            targetAccountId = targetAccountId,
            newPurchasePrice = BigDecimal("12000")
        )

        assertTrue(deltas.isEmpty())
    }
}
