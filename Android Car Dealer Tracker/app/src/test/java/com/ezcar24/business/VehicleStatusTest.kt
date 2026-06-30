package com.ezcar24.business

import com.ezcar24.business.util.VehicleStatus
import com.ezcar24.business.util.isVehicleOnSaleStatus
import com.ezcar24.business.util.isVehicleReservedGroupStatus
import com.ezcar24.business.util.normalizeVehicleStatus
import com.ezcar24.business.util.vehicleStatusLabelSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VehicleStatusTest {
    @Test
    fun normalizesLegacyOwnedToReserved() {
        assertEquals(VehicleStatus.RESERVED, normalizeVehicleStatus("owned"))
        assertEquals(VehicleStatus.RESERVED, normalizeVehicleStatus(" reserved "))
    }

    @Test
    fun groupsIosAndLegacyStatusesForFilters() {
        assertTrue(isVehicleReservedGroupStatus("reserved"))
        assertTrue(isVehicleReservedGroupStatus("owned"))
        assertTrue(isVehicleReservedGroupStatus("under_service"))
        assertFalse(isVehicleReservedGroupStatus("on_sale"))

        assertTrue(isVehicleOnSaleStatus("on_sale"))
        assertTrue(isVehicleOnSaleStatus("available"))
        assertFalse(isVehicleOnSaleStatus("reserved"))
    }

    @Test
    fun usesIosVisibleLabelsForLegacyStatuses() {
        assertEquals("Reserved", vehicleStatusLabelSource("owned"))
        assertEquals("On Sale", vehicleStatusLabelSource("available"))
        assertEquals("Under Service", vehicleStatusLabelSource("under_service"))
    }
}
