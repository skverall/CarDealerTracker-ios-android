package com.ezcar24.business.data.sync

/**
 * Represents the current state of synchronization.
 */
sealed class SyncState {
    /** No sync is currently happening */
    object Idle : SyncState()
    
    /** Sync is in progress */
    object Syncing : SyncState()
    
    /** Sync completed successfully */
    object Success : SyncState()
    
    /** Sync failed with an error */
    data class Failure(val message: String?) : SyncState()
}
