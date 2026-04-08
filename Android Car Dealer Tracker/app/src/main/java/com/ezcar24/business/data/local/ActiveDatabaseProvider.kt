package com.ezcar24.business.data.local

import android.content.Context
import androidx.room.Room
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest

@Singleton
class ActiveDatabaseProvider @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val lock = Any()
    private val databases = LinkedHashMap<String, AppDatabase>()

    val activeDealerIdFlow = CloudSyncEnvironment.currentDealerIdFlow

    fun currentDatabase(): AppDatabase = databaseFor(CloudSyncEnvironment.currentDealerId)

    fun databaseFor(dealerId: UUID?): AppDatabase {
        val key = storeKey(dealerId)
        synchronized(lock) {
            return databases.getOrPut(key) {
                Room.databaseBuilder(
                    context,
                    AppDatabase::class.java,
                    databaseName(key)
                )
                    .fallbackToDestructiveMigration()
                    .addMigrations(
                        AppDatabase.MIGRATION_1_2,
                        AppDatabase.MIGRATION_2_3,
                        AppDatabase.MIGRATION_3_4,
                        AppDatabase.MIGRATION_4_5,
                        AppDatabase.MIGRATION_5_6,
                        AppDatabase.MIGRATION_6_7
                    )
                    .build()
            }
        }
    }

    fun <T> flowForActiveDatabase(block: (AppDatabase) -> Flow<T>): Flow<T> {
        return activeDealerIdFlow.flatMapLatest { dealerId ->
            block(databaseFor(dealerId))
        }
    }

    private fun storeKey(dealerId: UUID?): String {
        return dealerId?.toString()?.lowercase(Locale.US) ?: GUEST_STORE_KEY
    }

    private fun databaseName(storeKey: String): String {
        return "${DATABASE_PREFIX}$storeKey.db"
    }

    fun clearAllStores() {
        val openDatabases = synchronized(lock) {
            val snapshot = databases.values.toList()
            databases.clear()
            snapshot
        }
        openDatabases.forEach { it.close() }
        context.databaseList()
            .filter { it.startsWith(DATABASE_PREFIX) }
            .forEach { context.deleteDatabase(it) }
    }

    private companion object {
        private const val DATABASE_PREFIX = "ezcar24_business_"
        private const val GUEST_STORE_KEY = "guest"
    }
}
