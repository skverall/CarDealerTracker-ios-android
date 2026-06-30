package com.ezcar24.business.util

import java.math.BigDecimal
import java.util.UUID

fun vehiclePurchaseAccountBalanceDeltas(
    isNewVehicle: Boolean,
    previousAccountId: UUID?,
    previousPurchasePrice: BigDecimal,
    targetAccountId: UUID?,
    newPurchasePrice: BigDecimal
): Map<UUID, BigDecimal> {
    val deltas = linkedMapOf<UUID, BigDecimal>()

    fun addDelta(accountId: UUID?, delta: BigDecimal) {
        if (accountId == null || delta.compareTo(BigDecimal.ZERO) == 0) return
        deltas[accountId] = deltas[accountId]?.add(delta) ?: delta
    }

    if (isNewVehicle) {
        addDelta(targetAccountId, newPurchasePrice.negate())
    } else if (previousAccountId == null) {
        return emptyMap()
    } else if (previousAccountId == targetAccountId) {
        addDelta(targetAccountId, previousPurchasePrice.subtract(newPurchasePrice))
    } else {
        addDelta(previousAccountId, previousPurchasePrice)
        addDelta(targetAccountId, newPurchasePrice.negate())
    }

    return deltas
}
