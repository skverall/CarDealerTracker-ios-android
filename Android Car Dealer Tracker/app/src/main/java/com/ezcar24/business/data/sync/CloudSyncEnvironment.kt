package com.ezcar24.business.data.sync

import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object CloudSyncEnvironment {
    private val _currentDealerId = MutableStateFlow<UUID?>(null)

    var currentDealerId: UUID?
        get() = _currentDealerId.value
        set(value) {
            _currentDealerId.value = value
        }

    val currentDealerIdFlow: StateFlow<UUID?> = _currentDealerId.asStateFlow()
    
    const val SUPABASE_URL = "https://haordpdxyyreliyzmire.supabase.co"
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

    fun vehiclePhotoUrl(storagePath: String): String {
        return "$SUPABASE_URL/storage/v1/object/public/$BUCKET_NAME/$storagePath"
    }
}
