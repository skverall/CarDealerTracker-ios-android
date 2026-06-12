package com.ezcar24.business.util

object SubscriptionAccess {
    const val FREE_VEHICLE_LIMIT = 3

    fun shouldGateVehicleCreation(
        isProAccessActive: Boolean,
        isCheckingStatus: Boolean,
        vehicleCount: Int
    ): Boolean {
        return !isProAccessActive &&
            !isCheckingStatus &&
            vehicleCount >= FREE_VEHICLE_LIMIT
    }
}
