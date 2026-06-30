package com.ezcar24.business.util

import java.util.Locale

object VehicleStatus {
    const val RESERVED = "reserved"
    const val OWNED_LEGACY = "owned"
    const val ON_SALE = "on_sale"
    const val AVAILABLE_LEGACY = "available"
    const val IN_TRANSIT = "in_transit"
    const val UNDER_SERVICE = "under_service"
    const val SOLD = "sold"
}

fun normalizeVehicleStatus(status: String?): String {
    val normalized = status?.trim()?.lowercase(Locale.US).orEmpty()
    return when (normalized) {
        VehicleStatus.OWNED_LEGACY -> VehicleStatus.RESERVED
        else -> normalized
    }
}

fun isVehicleOnSaleStatus(status: String?): Boolean {
    return when (status?.trim()?.lowercase(Locale.US)) {
        VehicleStatus.ON_SALE, VehicleStatus.AVAILABLE_LEGACY -> true
        else -> false
    }
}

fun isVehicleReservedGroupStatus(status: String?): Boolean {
    return when (status?.trim()?.lowercase(Locale.US)) {
        VehicleStatus.RESERVED,
        VehicleStatus.OWNED_LEGACY,
        VehicleStatus.UNDER_SERVICE -> true
        else -> false
    }
}

fun vehicleStatusLabelSource(status: String?): String {
    return when (status?.trim()?.lowercase(Locale.US)) {
        VehicleStatus.RESERVED, VehicleStatus.OWNED_LEGACY -> "Reserved"
        VehicleStatus.ON_SALE, VehicleStatus.AVAILABLE_LEGACY -> "On Sale"
        VehicleStatus.IN_TRANSIT -> "In Transit"
        VehicleStatus.UNDER_SERVICE -> "Under Service"
        VehicleStatus.SOLD -> "Sold"
        else -> "On Sale"
    }
}
