package com.ezcar24.business.data.sync

import java.util.UUID
import java.util.Locale

object CloudSyncEnvironment {
    var currentDealerId: UUID? = null
    
    private const val SUPABASE_URL = "https://haordpdxyyreliyzmire.supabase.co"
    private const val BUCKET_NAME = "vehicle-images"
    
    /**
     * Generate public URL for a vehicle image in Supabase Storage.
     */
    fun vehicleImageUrl(vehicleId: UUID, dealerId: UUID? = currentDealerId): String? {
        val dealer = dealerId ?: return null
        val dealerPart = dealer.toString().lowercase(Locale.US)
        val vehiclePart = vehicleId.toString().lowercase(Locale.US)
        return "$SUPABASE_URL/storage/v1/object/public/$BUCKET_NAME/$dealerPart/vehicles/$vehiclePart.jpg"
    }
}
