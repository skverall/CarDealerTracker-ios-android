package com.ezcar24.business.data.sync

import com.ezcar24.business.data.local.SyncQueueDao
import com.ezcar24.business.data.local.SyncQueueItem
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

interface SyncQueueManager {
    suspend fun enqueue(item: SyncQueueItem)
    suspend fun getAllItems(): List<SyncQueueItem>
    suspend fun remove(id: UUID)
    suspend fun clear()
}

@Singleton
class SyncQueueManagerImpl @Inject constructor(
    private val syncQueueDao: SyncQueueDao
) : SyncQueueManager {

    override suspend fun enqueue(item: SyncQueueItem) {
        syncQueueDao.upsert(item)
    }

    override suspend fun getAllItems(): List<SyncQueueItem> {
        return syncQueueDao.getAll()
    }

    override suspend fun remove(id: UUID) {
        syncQueueDao.deleteById(id)
    }
    
    override suspend fun clear() {
        // Not implemented in Dao yet, but loop delete or new query
        // For now, rarely used
    }
}
