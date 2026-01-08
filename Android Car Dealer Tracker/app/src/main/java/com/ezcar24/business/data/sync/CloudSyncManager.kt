package com.ezcar24.business.data.sync

import android.content.SharedPreferences
import android.util.Log
import androidx.room.withTransaction
import com.ezcar24.business.data.images.ImageStore
import com.ezcar24.business.data.local.*
import com.ezcar24.business.util.DateUtils
import com.ezcar24.business.util.toUUID
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import java.math.BigDecimal
import java.util.Date
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Singleton
class CloudSyncManager @Inject constructor(
    private val client: SupabaseClient,
    private val db: AppDatabase,
    private val syncQueueManager: SyncQueueManager,
    private val syncPrefs: SharedPreferences,
    private val imageStore: ImageStore
) {
    private val tag = "CloudSyncManager"
    private val json = Json { ignoreUnknownKeys = true }
    private val syncScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile
    var isSyncing = false
        private set

    var lastSyncAt: Date? = null
        private set
    
    // Public sync state for UI observation
    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()
    
    // Queue count for UI display
    private val _queueCount = MutableStateFlow(0)
    val queueCount: StateFlow<Int> = _queueCount.asStateFlow()

    private var lastSyncTimestamp: Date?
        get() {
            val stored = syncPrefs.getLong(KEY_LAST_SYNC, 0L)
            return if (stored == 0L) null else Date(stored)
        }
        set(value) {
            syncPrefs.edit().putLong(KEY_LAST_SYNC, value?.time ?: 0L).apply()
        }

    suspend fun syncAfterLogin(dealerId: UUID) = withContext(Dispatchers.IO) {
        if (isSyncing) return@withContext
        isSyncing = true
        try {
            Log.i(tag, "syncAfterLogin start dealerId=$dealerId lastSync=$lastSyncTimestamp")
            processOfflineQueue(dealerId)

            val pendingDeletes = pendingDeleteIds(dealerId)
            var effectiveSince = lastSyncTimestamp

            val localClientCount = db.clientDao().countAll()
            if (localClientCount == 0) {
                effectiveSince = null
            }

            val snapshot = fetchRemoteChanges(dealerId, effectiveSince)
            val filteredSnapshot = filterSnapshot(snapshot, pendingDeletes)
            Log.i(tag, "syncAfterLogin fetched ${snapshotSummary(snapshot)} pendingDeletes=${pendingDeletes.mapValues { it.value.size }}")

            val localAccountCount = db.financialAccountDao().countAll()
            val accountsForMerge = if (localAccountCount == 0) {
                ensureDefaultAccounts(dealerId, filteredSnapshot.accounts)
            } else {
                filteredSnapshot.accounts
            }

            val snapshotForMerge = filteredSnapshot.copy(accounts = accountsForMerge)
            mergeRemoteChanges(snapshotForMerge, dealerId)

            pushLocalChanges(dealerId, pendingDeletes[SyncEntityType.VEHICLE] ?: emptySet())

            lastSyncTimestamp = Date()
            lastSyncAt = lastSyncTimestamp

            syncScope.launch {
                downloadVehicleImages(dealerId, filteredSnapshot.vehicles)
            }

            processOfflineQueue(dealerId)
            Log.i(tag, "syncAfterLogin finished dealerId=$dealerId lastSyncAt=$lastSyncAt")
        } catch (e: Exception) {
            if (e is CancellationException) return@withContext
            Log.e(tag, "syncAfterLogin failed: ${e.message}", e)
            logSyncError(rpc = "syncAfterLogin", dealerId = dealerId, error = e)
        } finally {
            isSyncing = false
        }
    }

    suspend fun manualSync(dealerId: UUID, force: Boolean = false) = withContext(Dispatchers.IO) {
        if (isSyncing) return@withContext
        isSyncing = true
        _syncState.value = SyncState.Syncing

        val syncStartedAt = Date()
        val since = if (force) null else lastSyncTimestamp
        val queueItems = syncQueueManager.getAllItems().filter { it.dealerId == dealerId }
        val protectedIds = collectProtectedIds(queueItems)
        _queueCount.value = queueItems.size

        try {
            Log.i(tag, "manualSync start dealerId=$dealerId since=$since force=$force")
            processOfflineQueue(dealerId)

            val snapshot = fetchRemoteChanges(dealerId, since)
            if (!snapshotHasChanges(snapshot)) {
                Log.i(tag, "manualSync no changes dealerId=$dealerId")
                lastSyncTimestamp = Date()
                lastSyncAt = lastSyncTimestamp
                _syncState.value = SyncState.Success
                // Auto-dismiss success state
                launch {
                    delay(2000)
                    if (_syncState.value == SyncState.Success) {
                        _syncState.value = SyncState.Idle
                    }
                }
                return@withContext
            }

            val cleanupContext = if (force) {
                MissingCleanupContext(
                    syncStartedAt = syncStartedAt,
                    remoteIds = buildRemoteIdMap(snapshot),
                    protectedIds = protectedIds
                )
            } else {
                null
            }

            mergeRemoteChanges(snapshot, dealerId, cleanupContext)

            lastSyncTimestamp = Date()
            lastSyncAt = lastSyncTimestamp
            _queueCount.value = 0
            _syncState.value = SyncState.Success

            syncScope.launch {
                downloadVehicleImages(dealerId, snapshot.vehicles)
            }
            
            // Auto-dismiss success state
            launch {
                delay(2000)
                if (_syncState.value == SyncState.Success) {
                    _syncState.value = SyncState.Idle
                }
            }
            Log.i(tag, "manualSync finished dealerId=$dealerId lastSyncAt=$lastSyncAt")
        } catch (e: Exception) {
            if (e is CancellationException) {
                _syncState.value = SyncState.Idle
                return@withContext
            }
            Log.e(tag, "manualSync failed: ${e.message}", e)
            logSyncError(rpc = "manualSync", dealerId = dealerId, error = e)
            _syncState.value = SyncState.Failure(e.message)
            // Auto-dismiss failure state
            launch {
                delay(3000)
                if (_syncState.value is SyncState.Failure) {
                    _syncState.value = SyncState.Idle
                }
            }
        } finally {
            isSyncing = false
        }
    }

    suspend fun fullSync(dealerId: UUID) {
        syncAfterLogin(dealerId)
    }

    suspend fun runDiagnostics(dealerId: UUID): SyncDiagnosticsReport = withContext(Dispatchers.IO) {
        val queueItems = syncQueueManager.getAllItems().filter { it.dealerId == dealerId }
        val queueSummary = summarizeQueue(queueItems)

        val localCounts: Map<SyncEntityType, Int> = mapOf(
            SyncEntityType.VEHICLE to db.vehicleDao().count(),
            SyncEntityType.EXPENSE to db.expenseDao().count(),
            SyncEntityType.SALE to db.saleDao().count(),
            SyncEntityType.DEBT to db.debtDao().getAllIncludingDeleted().count { it.deletedAt == null },
            SyncEntityType.DEBT_PAYMENT to db.debtPaymentDao().getAllIncludingDeleted().count { it.deletedAt == null },
            SyncEntityType.CLIENT to db.clientDao().countAll(),
            SyncEntityType.USER to db.userDao().count(),
            SyncEntityType.ACCOUNT to db.financialAccountDao().countAll(),
            SyncEntityType.ACCOUNT_TRANSACTION to db.accountTransactionDao().getAllIncludingDeleted().count { it.deletedAt == null },
            SyncEntityType.TEMPLATE to db.expenseTemplateDao().getAllIncludingDeleted().count { it.deletedAt == null }
        )

        var remoteCounts: Map<SyncEntityType, Int>? = null
        var remoteFetchError: String? = null
        try {
            val snapshot = fetchRemoteChanges(dealerId, null)
            remoteCounts = mapOf(
                SyncEntityType.VEHICLE to snapshot.vehicles.count { it.deletedAt == null },
                SyncEntityType.EXPENSE to snapshot.expenses.count { it.deletedAt == null },
                SyncEntityType.SALE to snapshot.sales.count { it.deletedAt == null },
                SyncEntityType.DEBT to snapshot.debts.count { it.deletedAt == null },
                SyncEntityType.DEBT_PAYMENT to snapshot.debtPayments.count { it.deletedAt == null },
                SyncEntityType.CLIENT to snapshot.clients.count { it.deletedAt == null },
                SyncEntityType.USER to snapshot.users.count { it.deletedAt == null },
                SyncEntityType.ACCOUNT to snapshot.accounts.count { it.deletedAt == null },
                SyncEntityType.ACCOUNT_TRANSACTION to snapshot.accountTransactions.count { it.deletedAt == null },
                SyncEntityType.TEMPLATE to snapshot.templates.count { it.deletedAt == null }
            )
        } catch (e: Exception) {
            remoteFetchError = e.message
        }

        val entityCounts = SyncEntityType.entries.map { entity ->
            SyncEntityCount(
                entity = entity,
                localCount = localCounts[entity] ?: 0,
                remoteCount = remoteCounts?.get(entity)
            )
        }

        SyncDiagnosticsReport(
            generatedAt = Date(),
            lastSyncAt = lastSyncAt,
            isSyncing = isSyncing,
            offlineQueueCount = queueItems.count(),
            offlineQueueSummary = queueSummary,
            entityCounts = entityCounts,
            remoteFetchError = remoteFetchError
        )
    }

    private suspend fun fetchRemoteChanges(dealerId: UUID, since: Date?): RemoteSnapshot {
        val driftMillis = 5 * 60 * 1000L
        val effectiveSince = since?.let { Date(it.time - driftMillis) }
        val sinceString = effectiveSince?.let { DateUtils.formatDateAndTime(it) } ?: "1970-01-01T00:00:00Z"
        val params = buildJsonObject {
            put("dealer_id", dealerId.toString())
            put("since", sinceString)
        }

        return try {
            val result = client.postgrest.rpc("get_changes", params)
            val snapshot: RemoteSnapshot = json.decodeFromString(result.data)
            Log.i(tag, "get_changes dealerId=$dealerId since=$sinceString rawSize=${result.data.length} ${snapshotSummary(snapshot)}")
            snapshot
        } catch (e: Exception) {
            logSyncError(rpc = "get_changes", dealerId = dealerId, error = e)
            throw e
        }
    }

    private inline fun <reified T> payloadParams(payload: List<T>): JsonObject {
        val payloadJson = json.encodeToString(payload)
        val payloadElement = json.decodeFromString(JsonElement.serializer(), payloadJson)
        return buildJsonObject {
            put("payload", payloadElement)
        }
    }

    private fun deleteParams(id: UUID, dealerId: UUID): JsonObject {
        return buildJsonObject {
            put("p_id", id.toString())
            put("p_dealer_id", dealerId.toString())
        }
    }

    private fun deleteParams(id: String, dealerId: UUID): JsonObject {
        return buildJsonObject {
            put("p_id", id)
            put("p_dealer_id", dealerId.toString())
        }
    }

    private fun snapshotHasChanges(snapshot: RemoteSnapshot): Boolean {
        return snapshot.vehicles.isNotEmpty() ||
            snapshot.expenses.isNotEmpty() ||
            snapshot.sales.isNotEmpty() ||
            snapshot.debts.isNotEmpty() ||
            snapshot.debtPayments.isNotEmpty() ||
            snapshot.clients.isNotEmpty() ||
            snapshot.users.isNotEmpty() ||
            snapshot.accounts.isNotEmpty() ||
            snapshot.accountTransactions.isNotEmpty() ||
            snapshot.templates.isNotEmpty()
    }

    private fun snapshotSummary(snapshot: RemoteSnapshot): String {
        return "counts vehicles=${snapshot.vehicles.size} expenses=${snapshot.expenses.size} sales=${snapshot.sales.size} " +
            "debts=${snapshot.debts.size} debtPayments=${snapshot.debtPayments.size} clients=${snapshot.clients.size} " +
            "users=${snapshot.users.size} accounts=${snapshot.accounts.size} accountTransactions=${snapshot.accountTransactions.size} " +
            "templates=${snapshot.templates.size}"
    }

    private fun buildRemoteIdMap(snapshot: RemoteSnapshot): Map<SyncEntityType, Set<UUID>> {
        return mapOf(
            SyncEntityType.VEHICLE to snapshot.vehicles.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.EXPENSE to snapshot.expenses.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.SALE to snapshot.sales.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.DEBT to snapshot.debts.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.DEBT_PAYMENT to snapshot.debtPayments.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.CLIENT to snapshot.clients.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.USER to snapshot.users.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.ACCOUNT to snapshot.accounts.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.ACCOUNT_TRANSACTION to snapshot.accountTransactions.mapNotNull { it.id.toUUID() }.toSet(),
            SyncEntityType.TEMPLATE to snapshot.templates.mapNotNull { it.id.toUUID() }.toSet()
        )
    }

    private fun imagePath(dealerId: UUID, vehicleId: UUID): String {
        val dealerPart = dealerId.toString().lowercase(Locale.US)
        val vehiclePart = vehicleId.toString().lowercase(Locale.US)
        return "$dealerPart/vehicles/$vehiclePart.jpg"
    }

    suspend fun uploadVehicleImage(vehicleId: UUID, dealerId: UUID, imageData: ByteArray) = withContext(Dispatchers.IO) {
        val path = imagePath(dealerId, vehicleId)
        try {
            client.storage
                .from("vehicle-images")
                .upload(path, imageData) {
                    upsert = true
                    contentType = ContentType.Image.JPEG
                }
        } catch (e: Exception) {
            Log.e(tag, "uploadVehicleImage failed: ${e.message}", e)
        }
    }

    suspend fun deleteVehicleImage(vehicleId: UUID, dealerId: UUID) = withContext(Dispatchers.IO) {
        val path = imagePath(dealerId, vehicleId)
        try {
            client.storage
                .from("vehicle-images")
                .delete(listOf(path))
        } catch (e: Exception) {
            Log.e(tag, "deleteVehicleImage failed: ${e.message}", e)
        }
    }

    private suspend fun downloadVehicleImages(dealerId: UUID, vehicles: List<RemoteVehicle>) {
        for (vehicle in vehicles) {
            val vehicleId = vehicle.id.toUUID() ?: continue
            val path = imagePath(dealerId, vehicleId)
            try {
                val data = client.storage
                    .from("vehicle-images")
                    .downloadAuthenticated(path)
                imageStore.saveImage(vehicleId, data)
            } catch (e: Exception) {
                Log.d(tag, "No image for vehicle $vehicleId at $path")
            }
        }
    }

    private suspend fun processOfflineQueue(dealerId: UUID) {
        val items = syncQueueManager.getAllItems()
        if (items.isEmpty()) return

        for (item in items) {
            if (item.dealerId != dealerId) continue
            val entityType = SyncEntityType.fromRaw(item.entityType) ?: continue
            val operation = SyncOperationType.fromRaw(item.operation) ?: continue

            try {
                when (operation) {
                    SyncOperationType.UPSERT -> processUpsert(entityType, item.payload)
                    SyncOperationType.DELETE -> processDelete(entityType, item.payload, item.dealerId)
                }
                syncQueueManager.remove(item.id)
            } catch (e: Exception) {
                val rpcName = when (operation) {
                    SyncOperationType.UPSERT -> syncRpcName(entityType)
                    SyncOperationType.DELETE -> deleteRpcName(entityType)
                }
                val payloadId = when (operation) {
                    SyncOperationType.DELETE -> parseDeleteId(entityType, item.payload)
                    SyncOperationType.UPSERT -> parseUpsertId(entityType, item.payload)
                }
                Log.e(tag, "Failed to process offline item ${item.id}: ${e.message}", e)
                logSyncError(
                    rpc = rpcName,
                    dealerId = dealerId,
                    entityType = entityType,
                    payloadId = payloadId,
                    extraContext = mapOf(
                        "offline_queue_item_id" to item.id.toString(),
                        "operation" to operation.rawValue
                    ),
                    error = e
                )
            }
        }
    }

    private fun syncRpcName(entityType: SyncEntityType): String {
        return when (entityType) {
            SyncEntityType.VEHICLE -> "sync_vehicles"
            SyncEntityType.EXPENSE -> "sync_expenses"
            SyncEntityType.SALE -> "sync_sales"
            SyncEntityType.CLIENT -> "sync_clients"
            SyncEntityType.USER -> "sync_users"
            SyncEntityType.ACCOUNT -> "sync_accounts"
            SyncEntityType.ACCOUNT_TRANSACTION -> "sync_account_transactions"
            SyncEntityType.TEMPLATE -> "sync_templates"
            SyncEntityType.DEBT -> "sync_debts"
            SyncEntityType.DEBT_PAYMENT -> "sync_debt_payments"
        }
    }

    private fun deleteRpcName(entityType: SyncEntityType): String {
        return when (entityType) {
            SyncEntityType.VEHICLE -> "delete_crm_vehicles"
            SyncEntityType.EXPENSE -> "delete_crm_expenses"
            SyncEntityType.SALE -> "delete_crm_sales"
            SyncEntityType.CLIENT -> "delete_crm_dealer_clients"
            SyncEntityType.USER -> "delete_crm_dealer_users"
            SyncEntityType.ACCOUNT -> "delete_crm_financial_accounts"
            SyncEntityType.ACCOUNT_TRANSACTION -> "delete_crm_account_transactions"
            SyncEntityType.TEMPLATE -> "delete_crm_expense_templates"
            SyncEntityType.DEBT -> "delete_crm_debts"
            SyncEntityType.DEBT_PAYMENT -> "delete_crm_debt_payments"
        }
    }

    private suspend fun processUpsert(entityType: SyncEntityType, payload: String) {
        when (entityType) {
            SyncEntityType.VEHICLE -> {
                val remote = json.decodeFromString(RemoteVehicle.serializer(), payload)
                client.postgrest.rpc("sync_vehicles", payloadParams(listOf(remote)))
            }
            SyncEntityType.EXPENSE -> {
                val remote = json.decodeFromString(RemoteExpense.serializer(), payload)
                client.postgrest.rpc("sync_expenses", payloadParams(listOf(remote)))
            }
            SyncEntityType.SALE -> {
                val remote = json.decodeFromString(RemoteSale.serializer(), payload)
                client.postgrest.rpc("sync_sales", payloadParams(listOf(remote)))
            }
            SyncEntityType.CLIENT -> {
                val remote = json.decodeFromString(RemoteClient.serializer(), payload)
                client.postgrest.rpc("sync_clients", payloadParams(listOf(remote)))
            }
            SyncEntityType.USER -> {
                val remote = json.decodeFromString(RemoteDealerUser.serializer(), payload)
                client.postgrest.rpc("sync_users", payloadParams(listOf(remote)))
            }
            SyncEntityType.ACCOUNT -> {
                val remote = json.decodeFromString(RemoteFinancialAccount.serializer(), payload)
                client.postgrest.rpc("sync_accounts", payloadParams(listOf(remote)))
            }
            SyncEntityType.ACCOUNT_TRANSACTION -> {
                val remote = json.decodeFromString(RemoteAccountTransaction.serializer(), payload)
                client.postgrest.rpc("sync_account_transactions", payloadParams(listOf(remote)))
            }
            SyncEntityType.TEMPLATE -> {
                val remote = json.decodeFromString(RemoteExpenseTemplate.serializer(), payload)
                client.postgrest.rpc("sync_templates", payloadParams(listOf(remote)))
            }
            SyncEntityType.DEBT -> {
                val remote = json.decodeFromString(RemoteDebt.serializer(), payload)
                client.postgrest.rpc("sync_debts", payloadParams(listOf(remote)))
            }
            SyncEntityType.DEBT_PAYMENT -> {
                val remote = json.decodeFromString(RemoteDebtPayment.serializer(), payload)
                client.postgrest.rpc("sync_debt_payments", payloadParams(listOf(remote)))
            }
        }
    }

    private suspend fun processDelete(entityType: SyncEntityType, payload: String, dealerId: UUID) {
        val id = parseDeleteId(entityType, payload) ?: return
        deleteEntityById(entityType, id, dealerId)
    }

    private suspend fun deleteEntityById(entityType: SyncEntityType, id: UUID, dealerId: UUID) {
        when (entityType) {
            SyncEntityType.VEHICLE -> db.vehicleDao().getById(id)?.let { deleteVehicle(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.EXPENSE -> db.expenseDao().getById(id)?.let { deleteExpense(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.SALE -> db.saleDao().getById(id)?.let { deleteSale(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.CLIENT -> db.clientDao().getById(id)?.let { deleteClient(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.USER -> db.userDao().getById(id)?.let { deleteUser(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.ACCOUNT -> db.financialAccountDao().getById(id)?.let { deleteFinancialAccount(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.ACCOUNT_TRANSACTION -> db.accountTransactionDao().getById(id)?.let { deleteAccountTransaction(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.TEMPLATE -> db.expenseTemplateDao().getById(id)?.let { deleteTemplate(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.DEBT -> db.debtDao().getById(id)?.let { deleteDebt(it) } ?: performDeleteRpc(entityType, id, dealerId)
            SyncEntityType.DEBT_PAYMENT -> db.debtPaymentDao().getById(id)?.let { deleteDebtPayment(it) } ?: performDeleteRpc(entityType, id, dealerId)
        }
    }

    private suspend fun performDeleteRpc(entityType: SyncEntityType, id: UUID, dealerId: UUID) {
        val rpcName = deleteRpcName(entityType)
        client.postgrest.rpc(rpcName, deleteParams(id, dealerId))
    }

    private suspend fun enqueueDelete(entityType: SyncEntityType, id: UUID, dealerId: UUID) {
        val payload = id.toString()
        val item = SyncQueueItem(
            id = UUID.randomUUID(),
            entityType = entityType.rawValue,
            operation = SyncOperationType.DELETE.rawValue,
            payload = payload,
            dealerId = dealerId,
            createdAt = Date()
        )
        syncQueueManager.enqueue(item)
    }

    private suspend fun pendingDeleteIds(dealerId: UUID): Map<SyncEntityType, Set<UUID>> {
        val items = syncQueueManager.getAllItems()
        val ids = mutableMapOf<SyncEntityType, MutableSet<UUID>>()

        for (item in items) {
            if (item.dealerId != dealerId) continue
            if (item.operation != SyncOperationType.DELETE.rawValue) continue
            val entityType = SyncEntityType.fromRaw(item.entityType) ?: continue
            val id = parseDeleteId(entityType, item.payload) ?: continue
            ids.getOrPut(entityType) { mutableSetOf() }.add(id)
        }

        return ids.mapValues { it.value.toSet() }
    }

    private fun collectProtectedIds(queueItems: List<SyncQueueItem>): Map<SyncEntityType, Set<UUID>> {
        val ids = mutableMapOf<SyncEntityType, MutableSet<UUID>>()

        for (item in queueItems) {
            val entityType = SyncEntityType.fromRaw(item.entityType) ?: continue
            val operation = SyncOperationType.fromRaw(item.operation) ?: continue
            val id = when (operation) {
                SyncOperationType.DELETE -> parseDeleteId(entityType, item.payload)
                SyncOperationType.UPSERT -> parseUpsertId(entityType, item.payload)
            } ?: continue

            ids.getOrPut(entityType) { mutableSetOf() }.add(id)
        }

        return ids.mapValues { it.value.toSet() }
    }

    private fun parseUuidPayload(payload: String): UUID? {
        val trimmed = payload.trim()
        val cleaned = if (trimmed.startsWith("\"") && trimmed.endsWith("\"") && trimmed.length > 1) {
            trimmed.substring(1, trimmed.length - 1)
        } else {
            trimmed
        }
        return runCatching { UUID.fromString(cleaned) }.getOrNull()
    }

    private fun parseDeleteId(entityType: SyncEntityType, payload: String): UUID? {
        return parseUuidPayload(payload) ?: parseUpsertId(entityType, payload)
    }

    private fun parseUpsertId(entityType: SyncEntityType, payload: String): UUID? {
        return try {
            when (entityType) {
                SyncEntityType.VEHICLE -> json.decodeFromString(RemoteVehicle.serializer(), payload).id.toUUID()
                SyncEntityType.EXPENSE -> json.decodeFromString(RemoteExpense.serializer(), payload).id.toUUID()
                SyncEntityType.SALE -> json.decodeFromString(RemoteSale.serializer(), payload).id.toUUID()
                SyncEntityType.CLIENT -> json.decodeFromString(RemoteClient.serializer(), payload).id.toUUID()
                SyncEntityType.USER -> json.decodeFromString(RemoteDealerUser.serializer(), payload).id.toUUID()
                SyncEntityType.ACCOUNT -> json.decodeFromString(RemoteFinancialAccount.serializer(), payload).id.toUUID()
                SyncEntityType.ACCOUNT_TRANSACTION -> json.decodeFromString(RemoteAccountTransaction.serializer(), payload).id.toUUID()
                SyncEntityType.TEMPLATE -> json.decodeFromString(RemoteExpenseTemplate.serializer(), payload).id.toUUID()
                SyncEntityType.DEBT -> json.decodeFromString(RemoteDebt.serializer(), payload).id.toUUID()
                SyncEntityType.DEBT_PAYMENT -> json.decodeFromString(RemoteDebtPayment.serializer(), payload).id.toUUID()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun filterSnapshot(
        snapshot: RemoteSnapshot,
        skippingIds: Map<SyncEntityType, Set<UUID>>
    ): RemoteSnapshot {
        if (skippingIds.isEmpty()) return snapshot

        val vehicleIds = skippingIds[SyncEntityType.VEHICLE] ?: emptySet()
        val expenseIds = skippingIds[SyncEntityType.EXPENSE] ?: emptySet()
        val saleIds = skippingIds[SyncEntityType.SALE] ?: emptySet()
        val debtIds = skippingIds[SyncEntityType.DEBT] ?: emptySet()
        val debtPaymentIds = skippingIds[SyncEntityType.DEBT_PAYMENT] ?: emptySet()
        val clientIds = skippingIds[SyncEntityType.CLIENT] ?: emptySet()
        val userIds = skippingIds[SyncEntityType.USER] ?: emptySet()
        val accountIds = skippingIds[SyncEntityType.ACCOUNT] ?: emptySet()
        val accountTransactionIds = skippingIds[SyncEntityType.ACCOUNT_TRANSACTION] ?: emptySet()
        val templateIds = skippingIds[SyncEntityType.TEMPLATE] ?: emptySet()

        val filteredVehicles = snapshot.vehicles.filter { v ->
            val id = v.id.toUUID()
            id == null || !vehicleIds.contains(id)
        }

        val filteredExpenses = snapshot.expenses.filter { e ->
            val id = e.id.toUUID()
            if (id != null && expenseIds.contains(id)) return@filter false
            val vId = e.vehicleId?.toUUID()
            if (vId != null && vehicleIds.contains(vId)) return@filter false
            true
        }

        val filteredSales = snapshot.sales.filter { s ->
            val id = s.id.toUUID()
            if (id != null && saleIds.contains(id)) return@filter false
            val vId = s.vehicleId.toUUID()
            if (vId != null && vehicleIds.contains(vId)) return@filter false
            true
        }

        val filteredClients = snapshot.clients.filter { c ->
            val id = c.id.toUUID()
            if (id != null && clientIds.contains(id)) return@filter false
            val vId = c.vehicleId?.toUUID()
            if (vId != null && vehicleIds.contains(vId)) return@filter false
            true
        }

        val filteredDebts = snapshot.debts.filter { d ->
            val id = d.id.toUUID()
            id == null || !debtIds.contains(id)
        }

        val filteredDebtPayments = snapshot.debtPayments.filter { p ->
            val id = p.id.toUUID()
            if (id != null && debtPaymentIds.contains(id)) return@filter false
            val dId = p.debtId.toUUID()
            if (dId != null && debtIds.contains(dId)) return@filter false
            true
        }

        val filteredUsers = snapshot.users.filter { u ->
            val id = u.id.toUUID()
            id == null || !userIds.contains(id)
        }

        val filteredAccounts = snapshot.accounts.filter { a ->
            val id = a.id.toUUID()
            id == null || !accountIds.contains(id)
        }

        val filteredAccountTransactions = snapshot.accountTransactions.filter { t ->
            val id = t.id.toUUID()
            if (id != null && accountTransactionIds.contains(id)) return@filter false
            val aId = t.accountId.toUUID()
            if (aId != null && accountIds.contains(aId)) return@filter false
            true
        }

        val filteredTemplates = snapshot.templates.filter { t ->
            val id = t.id.toUUID()
            id == null || !templateIds.contains(id)
        }

        return RemoteSnapshot(
            users = filteredUsers,
            accounts = filteredAccounts,
            accountTransactions = filteredAccountTransactions,
            vehicles = filteredVehicles,
            templates = filteredTemplates,
            expenses = filteredExpenses,
            sales = filteredSales,
            debts = filteredDebts,
            debtPayments = filteredDebtPayments,
            clients = filteredClients
        )
    }

    private suspend fun ensureDefaultAccounts(
        dealerId: UUID,
        existingAccounts: List<RemoteFinancialAccount>
    ): List<RemoteFinancialAccount> {
        val hasCash = existingAccounts.any { it.accountType.lowercase(Locale.US) == "cash" }
        val hasBank = existingAccounts.any { it.accountType.lowercase(Locale.US) == "bank" }

        if (hasCash && hasBank) {
            return existingAccounts.filter { it.deletedAt == null }
        }

        val now = Date()
        val newAccounts = buildList {
            if (!hasCash) {
                add(
                    RemoteFinancialAccount(
                        id = UUID.randomUUID().toString(),
                        dealerId = dealerId.toString(),
                        accountType = "Cash",
                        balance = BigDecimal.ZERO,
                        updatedAt = DateUtils.formatDateAndTime(now),
                        deletedAt = null
                    )
                )
            }
            if (!hasBank) {
                add(
                    RemoteFinancialAccount(
                        id = UUID.randomUUID().toString(),
                        dealerId = dealerId.toString(),
                        accountType = "Bank",
                        balance = BigDecimal.ZERO,
                        updatedAt = DateUtils.formatDateAndTime(now),
                        deletedAt = null
                    )
                )
            }
        }

        if (newAccounts.isNotEmpty()) {
            try {
                client.postgrest.rpc("sync_accounts", payloadParams(newAccounts))
            } catch (e: Exception) {
                Log.e(tag, "ensureDefaultAccounts failed: ${e.message}", e)
            }
        }

        return existingAccounts.filter { it.deletedAt == null } + newAccounts
    }

    private suspend fun mergeRemoteChanges(
        snapshot: RemoteSnapshot,
        dealerId: UUID,
        missingCleanup: MissingCleanupContext? = null
    ) {
        db.withTransaction {
            mergeUsers(snapshot.users)
            mergeAccounts(snapshot.accounts)
            mergeVehicles(snapshot.vehicles)
            mergeClients(snapshot.clients)
            mergeTemplates(snapshot.templates)
            mergeExpenses(snapshot.expenses)
            mergeSales(snapshot.sales)
            mergeDebts(snapshot.debts)
            mergeDebtPayments(snapshot.debtPayments)
            mergeAccountTransactions(snapshot.accountTransactions)

            if (missingCleanup != null) {
                applyMissingCleanup(missingCleanup)
            }
        }
    }

    private suspend fun mergeUsers(remoteUsers: List<RemoteDealerUser>) {
        if (remoteUsers.isEmpty()) return
        val existingUsers = db.userDao().getAllIncludingDeleted()
        val usersById = existingUsers.associateBy { it.id }
        val usersByName = existingUsers.groupBy { it.name.lowercase(Locale.US) }

        for (remote in remoteUsers) {
            val remoteId = remote.id.toUUID() ?: continue
            var local = usersById[remoteId]
            if (local == null) {
                val duplicates = usersByName[remote.name.lowercase(Locale.US)].orEmpty()
                if (duplicates.isNotEmpty()) {
                    duplicates.forEach { dup ->
                        db.expenseDao().updateUserId(dup.id, remoteId)
                        db.expenseTemplateDao().updateUserId(dup.id, remoteId)
                        db.userDao().delete(dup)
                    }
                }
            }

            if (remote.deletedAt != null) {
                if (local != null) db.userDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && local.updatedAt >= remoteUpdated) continue

            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: remoteUpdated
            val newUser = User(
                id = remoteId,
                name = remote.name,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null
            )
            db.userDao().upsert(newUser)
        }
    }

    private suspend fun mergeAccounts(remoteAccounts: List<RemoteFinancialAccount>) {
        if (remoteAccounts.isEmpty()) return
        val localAccounts = db.financialAccountDao().getAllIncludingDeleted()
        val accountsById = localAccounts.associateBy { it.id }
        val accountsByType = localAccounts.groupBy { it.accountType.trim().lowercase(Locale.US) }

        for (remote in remoteAccounts) {
            val remoteId = remote.id.toUUID() ?: continue
            var local = accountsById[remoteId]
            var localCandidate = local
            if (localCandidate == null) {
                val duplicates = accountsByType[remote.accountType.trim().lowercase(Locale.US)].orEmpty()
                if (duplicates.isNotEmpty()) {
                    val best = duplicates.sortedWith { a, b ->
                        val aHasBalance = a.balance.abs() > BigDecimal.ZERO
                        val bHasBalance = b.balance.abs() > BigDecimal.ZERO
                        when {
                            aHasBalance != bHasBalance -> if (aHasBalance) -1 else 1
                            else -> b.updatedAt.compareTo(a.updatedAt)
                        }
                    }.first()
                    duplicates.forEach { dup ->
                        if (dup.id != remoteId) {
                            migrateAccountId(dup.id, remoteId)
                        }
                        db.financialAccountDao().delete(dup)
                    }
                    localCandidate = best
                }
            }

            if (remote.deletedAt != null) {
                if (local != null) db.financialAccountDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (localCandidate != null && localCandidate.updatedAt >= remoteUpdated) {
                if (localCandidate.id != remoteId) {
                    val migrated = localCandidate.copy(id = remoteId)
                    db.financialAccountDao().upsert(migrated)
                }
                continue
            }

            val newAccount = FinancialAccount(
                id = remoteId,
                accountType = remote.accountType,
                balance = remote.balance,
                updatedAt = remoteUpdated,
                deletedAt = null
            )
            db.financialAccountDao().upsert(newAccount)
        }
    }

    private suspend fun migrateAccountId(oldId: UUID, newId: UUID) {
        if (oldId == newId) return
        db.expenseDao().updateAccountId(oldId, newId)
        db.saleDao().updateAccountId(oldId, newId)
        db.debtPaymentDao().updateAccountId(oldId, newId)
        db.accountTransactionDao().updateAccountId(oldId, newId)
        db.expenseTemplateDao().updateAccountId(oldId, newId)
    }

    private suspend fun mergeVehicles(remoteVehicles: List<RemoteVehicle>) {
        if (remoteVehicles.isEmpty()) return
        val existing = db.vehicleDao().getAllIncludingDeleted().associateBy { it.id }

        for (remote in remoteVehicles) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.vehicleDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val purchaseDate = DateUtils.parseRemoteDateOnly(remote.purchaseDate)
                ?: DateUtils.parseDateAndTime(remote.createdAt)
                ?: Date()
            val saleDate = remote.saleDate?.let {
                DateUtils.parseDateAndTime(it) ?: DateUtils.parseDateOnly(it)
            }
            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: purchaseDate

            val newVehicle = Vehicle(
                id = remoteId,
                vin = remote.vin,
                make = remote.make,
                model = remote.model,
                year = remote.year,
                purchasePrice = remote.purchasePrice,
                purchaseDate = purchaseDate,
                status = remote.status,
                notes = remote.notes,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null,
                saleDate = saleDate,
                buyerName = local?.buyerName,
                buyerPhone = local?.buyerPhone,
                paymentMethod = local?.paymentMethod,
                salePrice = remote.salePrice,
                askingPrice = remote.askingPrice,
                reportURL = remote.reportUrl,
                photoUrl = remote.photoUrl
            )
            db.vehicleDao().upsert(newVehicle)
        }
    }

    private suspend fun mergeClients(remoteClients: List<RemoteClient>) {
        if (remoteClients.isEmpty()) return
        val existing = db.clientDao().getAllIncludingDeleted().associateBy { it.id }
        val vehicleIds = db.vehicleDao().getAllIncludingDeleted().map { it.id }.toSet()

        for (remote in remoteClients) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.clientDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: remoteUpdated
            val preferredDate = remote.preferredDate?.let {
                DateUtils.parseDateAndTime(it) ?: DateUtils.parseRemoteDateOnly(it)
            }
            val vehicleId = remote.vehicleId?.toUUID()?.takeIf { it in vehicleIds }

            val newClient = Client(
                id = remoteId,
                name = remote.name,
                phone = remote.phone,
                email = remote.email,
                notes = remote.notes,
                requestDetails = remote.requestDetails,
                preferredDate = preferredDate,
                status = remote.status,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null,
                vehicleId = vehicleId
            )
            db.clientDao().upsert(newClient)
        }
    }

    private suspend fun mergeTemplates(remoteTemplates: List<RemoteExpenseTemplate>) {
        if (remoteTemplates.isEmpty()) return
        val existing = db.expenseTemplateDao().getAllIncludingDeleted().associateBy { it.id }

        for (remote in remoteTemplates) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.expenseTemplateDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val newTemplate = ExpenseTemplate(
                id = remoteId,
                name = remote.name,
                category = remote.category,
                defaultDescription = remote.defaultDescription,
                defaultAmount = remote.defaultAmount,
                updatedAt = remoteUpdated,
                deletedAt = null,
                vehicleId = null,
                userId = null,
                accountId = null
            )
            db.expenseTemplateDao().upsert(newTemplate)
        }
    }

    private suspend fun mergeExpenses(remoteExpenses: List<RemoteExpense>) {
        if (remoteExpenses.isEmpty()) return
        val existing = db.expenseDao().getAllIncludingDeleted().associateBy { it.id }
        val vehicleIds = db.vehicleDao().getAllIncludingDeleted().map { it.id }.toSet()
        val userIds = db.userDao().getAllIncludingDeleted().map { it.id }.toSet()
        val accountIds = db.financialAccountDao().getAllIncludingDeleted().map { it.id }.toSet()

        for (remote in remoteExpenses) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.expenseDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val expenseDate = DateUtils.parseRemoteDateOnly(remote.date)
                ?: DateUtils.parseDateAndTime(remote.createdAt)
                ?: Date()
            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: expenseDate
            val vehicleId = remote.vehicleId?.toUUID()?.takeIf { it in vehicleIds }
            val userId = remote.userId?.toUUID()?.takeIf { it in userIds }
            val accountId = remote.accountId?.toUUID()?.takeIf { it in accountIds }

            val newExpense = Expense(
                id = remoteId,
                amount = remote.amount,
                date = expenseDate,
                expenseDescription = remote.expenseDescription,
                category = remote.category,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null,
                vehicleId = vehicleId,
                userId = userId,
                accountId = accountId
            )
            db.expenseDao().upsert(newExpense)
        }
    }

    private suspend fun mergeSales(remoteSales: List<RemoteSale>) {
        if (remoteSales.isEmpty()) return
        val existing = db.saleDao().getAllIncludingDeleted().associateBy { it.id }
        val vehicleIds = db.vehicleDao().getAllIncludingDeleted().map { it.id }.toSet()
        val accountIds = db.financialAccountDao().getAllIncludingDeleted().map { it.id }.toSet()

        for (remote in remoteSales) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.saleDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val saleDate = DateUtils.parseDateAndTime(remote.date)
                ?: DateUtils.parseDateOnly(remote.date)
                ?: DateUtils.parseDateAndTime(remote.createdAt)
                ?: Date()
            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: saleDate
            val vehicleId = remote.vehicleId.toUUID()?.takeIf { it in vehicleIds }
            val accountId = remote.accountId?.toUUID()?.takeIf { it in accountIds }

            val newSale = Sale(
                id = remoteId,
                amount = remote.amount,
                date = saleDate,
                buyerName = remote.buyerName,
                buyerPhone = remote.buyerPhone,
                paymentMethod = remote.paymentMethod,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null,
                vehicleId = vehicleId,
                accountId = accountId
            )
            db.saleDao().upsert(newSale)
        }
    }

    private suspend fun mergeDebts(remoteDebts: List<RemoteDebt>) {
        if (remoteDebts.isEmpty()) return
        val existing = db.debtDao().getAllIncludingDeleted().associateBy { it.id }

        for (remote in remoteDebts) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.debtDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: remoteUpdated
            val dueDate = remote.dueDate?.let { DateUtils.parseRemoteDateOnly(it) }

            val newDebt = Debt(
                id = remoteId,
                counterpartyName = remote.counterpartyName,
                counterpartyPhone = remote.counterpartyPhone,
                direction = remote.direction,
                amount = remote.amount,
                notes = remote.notes,
                dueDate = dueDate,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null
            )
            db.debtDao().upsert(newDebt)
        }
    }

    private suspend fun mergeDebtPayments(remotePayments: List<RemoteDebtPayment>) {
        if (remotePayments.isEmpty()) return
        val existing = db.debtPaymentDao().getAllIncludingDeleted().associateBy { it.id }
        val debtIds = db.debtDao().getAllIncludingDeleted().map { it.id }.toSet()
        val accountIds = db.financialAccountDao().getAllIncludingDeleted().map { it.id }.toSet()

        for (remote in remotePayments) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.debtPaymentDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val paymentDate = DateUtils.parseDateAndTime(remote.date)
                ?: DateUtils.parseRemoteDateOnly(remote.date)
                ?: DateUtils.parseDateAndTime(remote.createdAt)
                ?: Date()
            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: paymentDate
            val debtId = remote.debtId.toUUID()?.takeIf { it in debtIds }
            val accountId = remote.accountId?.toUUID()?.takeIf { it in accountIds }

            val newPayment = DebtPayment(
                id = remoteId,
                amount = remote.amount,
                date = paymentDate,
                note = remote.note,
                paymentMethod = remote.paymentMethod,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null,
                debtId = debtId,
                accountId = accountId
            )
            db.debtPaymentDao().upsert(newPayment)
        }
    }

    private suspend fun mergeAccountTransactions(remoteTxs: List<RemoteAccountTransaction>) {
        if (remoteTxs.isEmpty()) return
        val existing = db.accountTransactionDao().getAllIncludingDeleted().associateBy { it.id }
        val accountIds = db.financialAccountDao().getAllIncludingDeleted().map { it.id }.toSet()

        for (remote in remoteTxs) {
            val remoteId = remote.id.toUUID() ?: continue
            val local = existing[remoteId]

            if (remote.deletedAt != null) {
                if (local != null) db.accountTransactionDao().delete(local)
                continue
            }

            val remoteUpdated = DateUtils.parseDateAndTime(remote.updatedAt) ?: Date()
            if (local != null && (local.updatedAt ?: Date(0)) >= remoteUpdated) continue

            val txDate = DateUtils.parseDateAndTime(remote.date)
                ?: DateUtils.parseRemoteDateOnly(remote.date)
                ?: DateUtils.parseDateAndTime(remote.createdAt)
                ?: Date()
            val createdAt = DateUtils.parseDateAndTime(remote.createdAt) ?: txDate
            val accountId = remote.accountId.toUUID()?.takeIf { it in accountIds }

            val newTx = AccountTransaction(
                id = remoteId,
                accountId = accountId,
                transactionType = remote.transactionType,
                amount = remote.amount,
                date = txDate,
                note = remote.note,
                createdAt = createdAt,
                updatedAt = remoteUpdated,
                deletedAt = null
            )
            db.accountTransactionDao().upsert(newTx)
        }
    }

    private suspend fun applyMissingCleanup(cleanup: MissingCleanupContext) {
        fun shouldDelete(id: UUID, updatedAt: Date?, createdAt: Date): Boolean {
            if (updatedAt != null && updatedAt > cleanup.syncStartedAt) return false
            if (updatedAt == null && createdAt > cleanup.syncStartedAt) return false
            return true
        }

        val protectedVehicles = cleanup.protectedIds[SyncEntityType.VEHICLE].orEmpty()
        db.vehicleDao().getAllIncludingDeleted().forEach { vehicle ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.VEHICLE].orEmpty()
            if (!remoteIds.contains(vehicle.id) && !protectedVehicles.contains(vehicle.id)) {
                if (shouldDelete(vehicle.id, vehicle.updatedAt, vehicle.createdAt)) {
                    db.vehicleDao().delete(vehicle)
                }
            }
        }

        val protectedExpenses = cleanup.protectedIds[SyncEntityType.EXPENSE].orEmpty()
        db.expenseDao().getAllIncludingDeleted().forEach { expense ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.EXPENSE].orEmpty()
            if (!remoteIds.contains(expense.id) && !protectedExpenses.contains(expense.id)) {
                val createdAt = expense.createdAt
                if (shouldDelete(expense.id, expense.updatedAt, createdAt)) {
                    db.expenseDao().delete(expense)
                }
            }
        }

        val protectedSales = cleanup.protectedIds[SyncEntityType.SALE].orEmpty()
        db.saleDao().getAllIncludingDeleted().forEach { sale ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.SALE].orEmpty()
            if (!remoteIds.contains(sale.id) && !protectedSales.contains(sale.id)) {
                val createdAt = sale.createdAt ?: Date(0)
                if (shouldDelete(sale.id, sale.updatedAt, createdAt)) {
                    db.saleDao().delete(sale)
                }
            }
        }

        val protectedAccountTx = cleanup.protectedIds[SyncEntityType.ACCOUNT_TRANSACTION].orEmpty()
        db.accountTransactionDao().getAllIncludingDeleted().forEach { tx ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.ACCOUNT_TRANSACTION].orEmpty()
            if (!remoteIds.contains(tx.id) && !protectedAccountTx.contains(tx.id)) {
                if (shouldDelete(tx.id, tx.updatedAt, tx.createdAt)) {
                    db.accountTransactionDao().delete(tx)
                }
            }
        }

        val protectedDebts = cleanup.protectedIds[SyncEntityType.DEBT].orEmpty()
        db.debtDao().getAllIncludingDeleted().forEach { debt ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.DEBT].orEmpty()
            if (!remoteIds.contains(debt.id) && !protectedDebts.contains(debt.id)) {
                if (shouldDelete(debt.id, debt.updatedAt, debt.createdAt)) {
                    db.debtDao().delete(debt)
                }
            }
        }

        val protectedDebtPayments = cleanup.protectedIds[SyncEntityType.DEBT_PAYMENT].orEmpty()
        db.debtPaymentDao().getAllIncludingDeleted().forEach { payment ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.DEBT_PAYMENT].orEmpty()
            if (!remoteIds.contains(payment.id) && !protectedDebtPayments.contains(payment.id)) {
                if (shouldDelete(payment.id, payment.updatedAt, payment.createdAt)) {
                    db.debtPaymentDao().delete(payment)
                }
            }
        }

        val protectedClients = cleanup.protectedIds[SyncEntityType.CLIENT].orEmpty()
        db.clientDao().getAllIncludingDeleted().forEach { client ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.CLIENT].orEmpty()
            if (!remoteIds.contains(client.id) && !protectedClients.contains(client.id)) {
                if (shouldDelete(client.id, client.updatedAt, client.createdAt)) {
                    db.clientDao().delete(client)
                }
            }
        }

        val protectedUsers = cleanup.protectedIds[SyncEntityType.USER].orEmpty()
        db.userDao().getAllIncludingDeleted().forEach { user ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.USER].orEmpty()
            if (!remoteIds.contains(user.id) && !protectedUsers.contains(user.id)) {
                if (shouldDelete(user.id, user.updatedAt, user.createdAt)) {
                    db.userDao().delete(user)
                }
            }
        }

        val protectedAccounts = cleanup.protectedIds[SyncEntityType.ACCOUNT].orEmpty()
        db.financialAccountDao().getAllIncludingDeleted().forEach { account ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.ACCOUNT].orEmpty()
            if (!remoteIds.contains(account.id) && !protectedAccounts.contains(account.id)) {
                if (shouldDelete(account.id, account.updatedAt, account.updatedAt)) {
                    db.financialAccountDao().delete(account)
                }
            }
        }

        val protectedTemplates = cleanup.protectedIds[SyncEntityType.TEMPLATE].orEmpty()
        db.expenseTemplateDao().getAllIncludingDeleted().forEach { template ->
            val remoteIds = cleanup.remoteIds[SyncEntityType.TEMPLATE].orEmpty()
            if (!remoteIds.contains(template.id) && !protectedTemplates.contains(template.id)) {
                val createdAt = template.updatedAt ?: Date(0)
                if (shouldDelete(template.id, template.updatedAt, createdAt)) {
                    db.expenseTemplateDao().delete(template)
                }
            }
        }
    }

    private suspend fun pushLocalChanges(
        dealerId: UUID,
        skippingVehicleIds: Set<UUID> = emptySet()
    ) {
        val users = db.userDao().getAllIncludingDeleted()
        val accounts = db.financialAccountDao().getAllIncludingDeleted()
        val accountTransactions = db.accountTransactionDao().getAllIncludingDeleted()
        val vehicles = db.vehicleDao().getAllIncludingDeleted().filter { !skippingVehicleIds.contains(it.id) }
        val expenses = db.expenseDao().getAllIncludingDeleted().filter { expense ->
            val vId = expense.vehicleId
            vId == null || !skippingVehicleIds.contains(vId)
        }
        val sales = db.saleDao().getAllIncludingDeleted().filter { sale ->
            val vId = sale.vehicleId
            vId == null || !skippingVehicleIds.contains(vId)
        }
        val debts = db.debtDao().getAllIncludingDeleted()
        val debtPayments = db.debtPaymentDao().getAllIncludingDeleted()
        val clients = db.clientDao().getAllIncludingDeleted().filter { client ->
            val vId = client.vehicleId
            vId == null || !skippingVehicleIds.contains(vId)
        }
        val templates = db.expenseTemplateDao().getAllIncludingDeleted()

        val remoteUsers = users.map { it.toRemote(dealerId.toString()) }

        val accountsByType = mutableMapOf<String, FinancialAccount>()
        for (account in accounts) {
            val key = account.accountType.trim().lowercase(Locale.US)
            val existing = accountsByType[key]
            if (existing == null) {
                accountsByType[key] = account
            } else {
                val existingBalance = existing.balance.abs()
                val newBalance = account.balance.abs()
                val shouldReplace = newBalance > existingBalance ||
                    (newBalance == existingBalance && account.updatedAt.after(existing.updatedAt))
                if (shouldReplace) {
                    accountsByType[key] = account
                }
            }
        }

        val remoteAccounts = accountsByType.values.map { it.toRemote(dealerId.toString()) }
        val remoteAccountTransactions = accountTransactions.mapNotNull { it.toRemote(dealerId.toString()) }
        val remoteVehicles = vehicles.map { it.toRemote(dealerId.toString()) }
        val remoteExpenses = expenses.map { it.toRemote(dealerId.toString()) }
        val remoteSales = sales.mapNotNull { it.toRemote(dealerId.toString()) }
        val remoteDebts = debts.map { it.toRemote(dealerId.toString()) }
        val remoteDebtPayments = debtPayments.mapNotNull { it.toRemote(dealerId.toString()) }
        val remoteClients = clients.map { it.toRemote(dealerId.toString()) }
        val remoteTemplates = templates.map { it.toRemote(dealerId.toString()) }

        if (remoteUsers.isNotEmpty()) {
            client.postgrest.rpc("sync_users", payloadParams(remoteUsers))
        }
        if (remoteAccounts.isNotEmpty()) {
            client.postgrest.rpc("sync_accounts", payloadParams(remoteAccounts))
        }
        if (remoteAccountTransactions.isNotEmpty()) {
            client.postgrest.rpc("sync_account_transactions", payloadParams(remoteAccountTransactions))
        }
        if (remoteVehicles.isNotEmpty()) {
            client.postgrest.rpc("sync_vehicles", payloadParams(remoteVehicles))
        }
        if (remoteExpenses.isNotEmpty()) {
            client.postgrest.rpc("sync_expenses", payloadParams(remoteExpenses))
        }
        if (remoteSales.isNotEmpty()) {
            client.postgrest.rpc("sync_sales", payloadParams(remoteSales))
        }
        if (remoteDebts.isNotEmpty()) {
            client.postgrest.rpc("sync_debts", payloadParams(remoteDebts))
        }
        if (remoteDebtPayments.isNotEmpty()) {
            client.postgrest.rpc("sync_debt_payments", payloadParams(remoteDebtPayments))
        }
        if (remoteClients.isNotEmpty()) {
            client.postgrest.rpc("sync_clients", payloadParams(remoteClients))
        }
        if (remoteTemplates.isNotEmpty()) {
            client.postgrest.rpc("sync_templates", payloadParams(remoteTemplates))
        }
    }

    private fun summarizeQueue(items: List<SyncQueueItem>): List<SyncQueueSummaryItem> {
        val grouped = items.mapNotNull { item ->
            val entityType = SyncEntityType.fromRaw(item.entityType) ?: return@mapNotNull null
            val operation = SyncOperationType.fromRaw(item.operation) ?: return@mapNotNull null
            SyncQueueGroupKey(entityType, operation)
        }.groupingBy { it }.eachCount()

        return grouped.map { (key, count) ->
            SyncQueueSummaryItem(
                entity = key.entity,
                operation = key.operation,
                count = count
            )
        }.sortedWith { a, b ->
            if (a.entity.sortOrder == b.entity.sortOrder) {
                a.operation.sortOrder - b.operation.sortOrder
            } else {
                a.entity.sortOrder - b.entity.sortOrder
            }
        }
    }

    private suspend fun logSyncError(
        rpc: String,
        dealerId: UUID?,
        entityType: SyncEntityType? = null,
        payloadId: UUID? = null,
        extraContext: Map<String, String> = emptyMap(),
        error: Throwable
    ) {
        if (error is CancellationException) return

        val context = mutableMapOf(
            "component" to "CloudSyncManager",
            "rpc" to rpc,
            "error" to (error.message ?: "unknown"),
            "error_type" to error::class.java.simpleName
        )

        if (dealerId != null) {
            context["dealer_id"] = dealerId.toString()
        }
        if (entityType != null) {
            context["entity_type"] = entityType.rawValue
        }
        if (payloadId != null) {
            context["payload_id"] = payloadId.toString()
        }
        for ((key, value) in extraContext) {
            context[key] = value
        }

        val row = ApplicationLogInsert(
            level = "error",
            message = "Sync error: $rpc",
            context = context,
            userId = dealerId?.toString()
        )

        try {
            client.postgrest
                .from("application_logs")
                .insert(row)
        } catch (logError: Exception) {
            Log.e(tag, "logSyncError failed: ${logError.message}", logError)
        }
    }

    private fun getCurrentDealerId(): UUID = CloudSyncEnvironment.currentDealerId
        ?: throw IllegalStateException("Dealer ID not set")

    suspend fun upsertClient(clientRecord: Client) {
        db.clientDao().upsert(clientRecord)
        val dealerId = getCurrentDealerId()
        val remote = clientRecord.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_clients", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_clients",
                dealerId = dealerId,
                entityType = SyncEntityType.CLIENT,
                payloadId = clientRecord.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.CLIENT, remote, dealerId)
        }
    }

    suspend fun deleteClient(clientRecord: Client) {
        val deleted = clientRecord.copy(deletedAt = Date(), updatedAt = Date())
        db.clientDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_clients", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_clients",
                dealerId = dealerId,
                entityType = SyncEntityType.CLIENT,
                payloadId = clientRecord.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.CLIENT, remote, dealerId)
        }
    }



    suspend fun upsertSale(sale: Sale) {
        db.saleDao().upsert(sale)
        val dealerId = getCurrentDealerId()
        val remote = sale.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_sales", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_sales",
                dealerId = dealerId,
                entityType = SyncEntityType.SALE,
                payloadId = sale.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.SALE, remote, dealerId)
        }
    }

    suspend fun deleteSale(sale: Sale) {
        val deleted = sale.copy(deletedAt = Date(), updatedAt = Date())
        db.saleDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_sales", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_sales",
                dealerId = dealerId,
                entityType = SyncEntityType.SALE,
                payloadId = sale.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.SALE, remote, dealerId)
        }
    }

    suspend fun upsertVehicle(vehicle: Vehicle) {
        db.vehicleDao().upsert(vehicle)
        val dealerId = getCurrentDealerId()
        val remote = vehicle.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_vehicles", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_vehicles",
                dealerId = dealerId,
                entityType = SyncEntityType.VEHICLE,
                payloadId = vehicle.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.VEHICLE, remote, dealerId)
        }
    }

    suspend fun deleteVehicle(vehicle: Vehicle) {
        val deleted = vehicle.copy(deletedAt = Date(), updatedAt = Date())
        db.vehicleDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_vehicles", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_vehicles",
                dealerId = dealerId,
                entityType = SyncEntityType.VEHICLE,
                payloadId = vehicle.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.VEHICLE, remote, dealerId)
        }
    }

    suspend fun upsertFinancialAccount(account: FinancialAccount) {
        db.financialAccountDao().upsert(account)
        val dealerId = getCurrentDealerId()
        val remote = account.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_accounts", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_accounts",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT,
                payloadId = account.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.ACCOUNT, remote, dealerId)
        }
    }

    suspend fun deleteFinancialAccount(account: FinancialAccount) {
        val deleted = account.copy(deletedAt = Date(), updatedAt = Date())
        db.financialAccountDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_accounts", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_accounts",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT,
                payloadId = account.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.ACCOUNT, remote, dealerId)
        }
    }

    suspend fun upsertExpense(expense: Expense) {
        db.expenseDao().upsert(expense)
        val dealerId = getCurrentDealerId()
        val remote = expense.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_expenses", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_expenses",
                dealerId = dealerId,
                entityType = SyncEntityType.EXPENSE,
                payloadId = expense.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.EXPENSE, remote, dealerId)
        }
    }

    suspend fun deleteExpense(expense: Expense) {
        val deleted = expense.copy(deletedAt = Date(), updatedAt = Date())
        db.expenseDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_expenses", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_expenses",
                dealerId = dealerId,
                entityType = SyncEntityType.EXPENSE,
                payloadId = expense.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.EXPENSE, remote, dealerId)
        }
    }

    suspend fun upsertDebt(debt: Debt) {
        db.debtDao().upsert(debt)
        val dealerId = getCurrentDealerId()
        val remote = debt.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_debts", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_debts",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT,
                payloadId = debt.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.DEBT, remote, dealerId)
        }
    }

    suspend fun deleteDebt(debt: Debt) {
        val deleted = debt.copy(deletedAt = Date(), updatedAt = Date())
        db.debtDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_debts", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_debts",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT,
                payloadId = debt.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.DEBT, remote, dealerId)
        }
    }

    suspend fun upsertDebtPayment(payment: DebtPayment) {
        db.debtPaymentDao().upsert(payment)
        val dealerId = getCurrentDealerId()
        val remote = payment.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_debt_payments", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_debt_payments",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT_PAYMENT,
                payloadId = payment.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.DEBT_PAYMENT, remote, dealerId)
        }
    }

    suspend fun deleteDebtPayment(payment: DebtPayment) {
        val deleted = payment.copy(deletedAt = Date(), updatedAt = Date())
        db.debtPaymentDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_debt_payments", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_debt_payments",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT_PAYMENT,
                payloadId = payment.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.DEBT_PAYMENT, remote, dealerId)
        }
    }

    suspend fun upsertUser(user: User) {
        db.userDao().upsert(user)
        val dealerId = getCurrentDealerId()
        val remote = user.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_users", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_users",
                dealerId = dealerId,
                entityType = SyncEntityType.USER,
                payloadId = user.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.USER, remote, dealerId)
        }
    }

    suspend fun deleteUser(user: User) {
        val deleted = user.copy(deletedAt = Date(), updatedAt = Date())
        db.userDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_users", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_users",
                dealerId = dealerId,
                entityType = SyncEntityType.USER,
                payloadId = user.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.USER, remote, dealerId)
        }
    }

    suspend fun upsertAccountTransaction(transaction: AccountTransaction) {
        db.accountTransactionDao().upsert(transaction)
        val dealerId = getCurrentDealerId()
        val remote = transaction.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_account_transactions", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_account_transactions",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT_TRANSACTION,
                payloadId = transaction.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.ACCOUNT_TRANSACTION, remote, dealerId)
        }
    }

    suspend fun deleteAccountTransaction(transaction: AccountTransaction) {
        val deleted = transaction.copy(deletedAt = Date(), updatedAt = Date())
        db.accountTransactionDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString()) ?: return
        try {
            client.postgrest.rpc("sync_account_transactions", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_account_transactions",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT_TRANSACTION,
                payloadId = transaction.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.ACCOUNT_TRANSACTION, remote, dealerId)
        }
    }

    suspend fun upsertTemplate(template: ExpenseTemplate) {
        db.expenseTemplateDao().upsert(template)
        val dealerId = getCurrentDealerId()
        val remote = template.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_templates", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_templates",
                dealerId = dealerId,
                entityType = SyncEntityType.TEMPLATE,
                payloadId = template.id,
                error = e
            )
            enqueueUpsert(SyncEntityType.TEMPLATE, remote, dealerId)
        }
    }

    suspend fun deleteTemplate(template: ExpenseTemplate) {
        val deleted = template.copy(deletedAt = Date(), updatedAt = Date())
        db.expenseTemplateDao().upsert(deleted)
        val dealerId = getCurrentDealerId()
        val remote = deleted.toRemote(dealerId.toString())
        try {
            client.postgrest.rpc("sync_templates", payloadParams(listOf(remote)))
            processOfflineQueue(dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "sync_templates",
                dealerId = dealerId,
                entityType = SyncEntityType.TEMPLATE,
                payloadId = template.id,
                extraContext = mapOf("operation" to "delete"),
                error = e
            )
            enqueueUpsert(SyncEntityType.TEMPLATE, remote, dealerId)
        }
    }

    private suspend inline fun <reified T : Any> enqueueUpsert(
        entityType: SyncEntityType,
        remote: T,
        dealerId: UUID
    ) {
        val payload = json.encodeToString(remote)
        val item = SyncQueueItem(
            id = UUID.randomUUID(),
            entityType = entityType.rawValue,
            operation = SyncOperationType.UPSERT.rawValue,
            payload = payload,
            dealerId = dealerId,
            createdAt = Date()
        )
        syncQueueManager.enqueue(item)
    }

    suspend fun deleteSale(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.SALE, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_sales",
                dealerId = dealerId,
                entityType = SyncEntityType.SALE,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.SALE, id, dealerId)
        }
    }

    suspend fun deleteExpense(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.EXPENSE, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_expenses",
                dealerId = dealerId,
                entityType = SyncEntityType.EXPENSE,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.EXPENSE, id, dealerId)
        }
    }

    suspend fun deleteVehicle(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.VEHICLE, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_vehicles",
                dealerId = dealerId,
                entityType = SyncEntityType.VEHICLE,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.VEHICLE, id, dealerId)
        }
    }

    suspend fun deleteClient(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.CLIENT, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_dealer_clients",
                dealerId = dealerId,
                entityType = SyncEntityType.CLIENT,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.CLIENT, id, dealerId)
        }
    }

    suspend fun deleteDebt(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.DEBT, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_debts",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.DEBT, id, dealerId)
        }
    }

    suspend fun deleteDebtPayment(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.DEBT_PAYMENT, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_debt_payments",
                dealerId = dealerId,
                entityType = SyncEntityType.DEBT_PAYMENT,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.DEBT_PAYMENT, id, dealerId)
        }
    }

    suspend fun deleteUser(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.USER, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_dealer_users",
                dealerId = dealerId,
                entityType = SyncEntityType.USER,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.USER, id, dealerId)
        }
    }

    suspend fun deleteFinancialAccount(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.ACCOUNT, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_financial_accounts",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.ACCOUNT, id, dealerId)
        }
    }

    suspend fun deleteAccountTransaction(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.ACCOUNT_TRANSACTION, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_account_transactions",
                dealerId = dealerId,
                entityType = SyncEntityType.ACCOUNT_TRANSACTION,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.ACCOUNT_TRANSACTION, id, dealerId)
        }
    }

    suspend fun deleteTemplate(id: UUID, dealerId: UUID) {
        try {
            performDeleteRpc(SyncEntityType.TEMPLATE, id, dealerId)
        } catch (e: Exception) {
            logSyncError(
                rpc = "delete_crm_expense_templates",
                dealerId = dealerId,
                entityType = SyncEntityType.TEMPLATE,
                payloadId = id,
                error = e
            )
            enqueueDelete(SyncEntityType.TEMPLATE, id, dealerId)
        }
    }

    suspend fun deduplicateData(dealerId: UUID) = withContext(Dispatchers.IO) {
        val vehiclesResult = client.postgrest
            .from("crm_vehicles")
            .select { filter { eq("dealer_id", dealerId.toString()) } }
        val vehicles = json.decodeFromString<List<RemoteVehicle>>(vehiclesResult.data)

        val vehiclesByVin = vehicles.groupBy { it.vin }
        vehiclesByVin.forEach { (_, group) ->
            if (group.size <= 1) return@forEach
            val sorted = group.sortedByDescending { DateUtils.parseDateAndTime(it.createdAt) ?: Date(0) }
            sorted.drop(1).forEach { vehicle ->
                try {
                    client.postgrest.rpc(
                        "delete_crm_vehicles",
                        deleteParams(vehicle.id, dealerId)
                    )
                } catch (e: Exception) {
                    Log.e(tag, "Failed to delete duplicate vehicle ${vehicle.id}: ${e.message}", e)
                }
            }
        }

        val clientsResult = client.postgrest
            .from("crm_dealer_clients")
            .select { filter { eq("dealer_id", dealerId.toString()) } }
        val clients = json.decodeFromString<List<RemoteClient>>(clientsResult.data)

        val clientsByPhone = clients.groupBy { it.phone ?: "" }
        clientsByPhone.forEach { (_, group) ->
            if (group.size <= 1) return@forEach
            val sorted = group.sortedByDescending { DateUtils.parseDateAndTime(it.createdAt) ?: Date(0) }
            sorted.drop(1).forEach { remoteClient ->
                try {
                    client.postgrest.rpc(
                        "delete_crm_dealer_clients",
                        deleteParams(remoteClient.id, dealerId)
                    )
                } catch (e: Exception) {
                    Log.e(tag, "Failed to delete duplicate client ${remoteClient.id}: ${e.message}", e)
                }
            }
        }

        val accountsResult = client.postgrest
            .from("crm_financial_accounts")
            .select { filter { eq("dealer_id", dealerId.toString()) } }
        val accounts = json.decodeFromString<List<RemoteFinancialAccount>>(accountsResult.data)

        val accountsByType = accounts.groupBy { it.accountType.trim().lowercase(Locale.US) }
        accountsByType.forEach { (type, group) ->
            if (type.isEmpty() || group.size <= 1) return@forEach
            val sorted = group.sortedWith { a, b ->
                val aHasBalance = a.balance.abs() > BigDecimal.ZERO
                val bHasBalance = b.balance.abs() > BigDecimal.ZERO
                when {
                    aHasBalance != bHasBalance -> if (aHasBalance) -1 else 1
                    else -> {
                        val aUpdated = DateUtils.parseDateAndTime(a.updatedAt) ?: Date(0)
                        val bUpdated = DateUtils.parseDateAndTime(b.updatedAt) ?: Date(0)
                        bUpdated.compareTo(aUpdated)
                    }
                }
            }
            sorted.drop(1).forEach { account ->
                try {
                    client.postgrest.rpc(
                        "delete_crm_financial_accounts",
                        deleteParams(account.id, dealerId)
                    )
                } catch (e: Exception) {
                    Log.e(tag, "Failed to delete duplicate account ${account.id}: ${e.message}", e)
                }
            }
        }

        val usersResult = client.postgrest
            .from("crm_dealer_users")
            .select { filter { eq("dealer_id", dealerId.toString()) } }
        val users = json.decodeFromString<List<RemoteDealerUser>>(usersResult.data)

        val usersByName = users.groupBy { it.name.trim().lowercase(Locale.US) }
        usersByName.forEach { (name, group) ->
            if (name.isEmpty() || group.size <= 1) return@forEach
            val sorted = group.sortedByDescending { DateUtils.parseDateAndTime(it.createdAt) ?: Date(0) }
            sorted.drop(1).forEach { user ->
                try {
                    client.postgrest.rpc(
                        "delete_crm_dealer_users",
                        deleteParams(user.id, dealerId)
                    )
                } catch (e: Exception) {
                    Log.e(tag, "Failed to delete duplicate user ${user.id}: ${e.message}", e)
                }
            }
        }

        val snapshot = fetchRemoteChanges(dealerId, null)
        mergeRemoteChanges(snapshot, dealerId)
    }

    suspend fun deleteAllRemoteData(dealerId: UUID) = withContext(Dispatchers.IO) {
        client.postgrest.from("crm_expenses").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_debt_payments").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_sales").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_debts").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_dealer_clients").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_vehicles").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_expense_templates").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_account_transactions").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_financial_accounts").delete { filter { eq("dealer_id", dealerId.toString()) } }
        client.postgrest.from("crm_dealer_users").delete { filter { eq("dealer_id", dealerId.toString()) } }
    }

    companion object {
        private const val KEY_LAST_SYNC = "lastSyncTimestamp"
    }

    @Serializable
    private data class ApplicationLogInsert(
        val level: String,
        val message: String,
        val context: Map<String, String>?,
        @SerialName("user_id") val userId: String?
    )

    private data class MissingCleanupContext(
        val syncStartedAt: Date,
        val remoteIds: Map<SyncEntityType, Set<UUID>>,
        val protectedIds: Map<SyncEntityType, Set<UUID>>
    )
}

enum class SyncOperationType(val rawValue: String, val displayName: String, val sortOrder: Int) {
    UPSERT("upsert", "Upsert", 0),
    DELETE("delete", "Delete", 1);

    companion object {
        fun fromRaw(value: String): SyncOperationType? {
            return values().firstOrNull { it.rawValue == value }
        }
    }
}

enum class SyncEntityType(val rawValue: String, val displayName: String, val sortOrder: Int) {
    VEHICLE("vehicle", "Vehicles", 0),
    EXPENSE("expense", "Expenses", 1),
    SALE("sale", "Sales", 2),
    DEBT("debt", "Debts", 3),
    DEBT_PAYMENT("debtPayment", "Debt Payments", 4),
    CLIENT("client", "Clients", 5),
    USER("user", "Users", 6),
    ACCOUNT("account", "Accounts", 7),
    ACCOUNT_TRANSACTION("accountTransaction", "Account Transactions", 8),
    TEMPLATE("template", "Expense Templates", 9);

    companion object {
        fun fromRaw(value: String): SyncEntityType? {
            return when (value) {
                "vehicle" -> VEHICLE
                "expense" -> EXPENSE
                "sale" -> SALE
                "debt" -> DEBT
                "debtPayment" -> DEBT_PAYMENT
                "client" -> CLIENT
                "user" -> USER
                "account" -> ACCOUNT
                "financialAccount" -> ACCOUNT
                "accountTransaction" -> ACCOUNT_TRANSACTION
                "template" -> TEMPLATE
                "expenseTemplate" -> TEMPLATE
                else -> null
            }
        }
    }
}

data class SyncQueueSummaryItem(
    val entity: SyncEntityType,
    val operation: SyncOperationType,
    val count: Int
)

data class SyncEntityCount(
    val entity: SyncEntityType,
    val localCount: Int,
    val remoteCount: Int?
)

data class SyncDiagnosticsReport(
    val generatedAt: Date,
    val lastSyncAt: Date?,
    val isSyncing: Boolean,
    val offlineQueueCount: Int,
    val offlineQueueSummary: List<SyncQueueSummaryItem>,
    val entityCounts: List<SyncEntityCount>,
    val remoteFetchError: String?
)

private data class SyncQueueGroupKey(
    val entity: SyncEntityType,
    val operation: SyncOperationType
)

fun User.toRemote(dealerId: String) = RemoteDealerUser(
    id = id.toString(),
    dealerId = dealerId,
    name = name,
    createdAt = DateUtils.formatDateAndTime(createdAt),
    updatedAt = DateUtils.formatDateAndTime(updatedAt),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)

fun Client.toRemote(dealerId: String) = RemoteClient(
    id = id.toString(),
    dealerId = dealerId,
    name = name,
    phone = phone,
    email = email,
    notes = notes,
    requestDetails = requestDetails,
    preferredDate = preferredDate?.let { DateUtils.formatDateAndTime(it) },
    status = status ?: "new",
    vehicleId = vehicleId?.toString(),
    createdAt = DateUtils.formatDateAndTime(createdAt),
    updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)

fun Sale.toRemote(dealerId: String): RemoteSale? {
    val vehicleId = vehicleId ?: return null
    val dateValue = date ?: Date()
    return RemoteSale(
        id = id.toString(),
        dealerId = dealerId,
        vehicleId = vehicleId.toString(),
        amount = amount ?: BigDecimal.ZERO,
        salePrice = amount ?: BigDecimal.ZERO,
        profit = null,
        date = DateUtils.formatDateAndTime(dateValue),
        buyerName = buyerName,
        buyerPhone = buyerPhone,
        paymentMethod = paymentMethod,
        accountId = accountId?.toString(),
        notes = null,
        createdAt = DateUtils.formatDateAndTime(Date()),
        updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
        deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
    )
}

fun Vehicle.toRemote(dealerId: String) = RemoteVehicle(
    id = id.toString(),
    dealerId = dealerId,
    vin = vin,
    make = make,
    model = model,
    year = year,
    purchasePrice = purchasePrice,
    purchaseDate = DateUtils.formatDateOnly(purchaseDate),
    status = status,
    notes = notes,
    createdAt = DateUtils.formatDateAndTime(createdAt),
    updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) },
    salePrice = salePrice,
    saleDate = saleDate?.let { DateUtils.formatDateAndTime(it) },
    askingPrice = askingPrice,
    reportUrl = reportURL,
    photoUrl = photoUrl
)

fun FinancialAccount.toRemote(dealerId: String) = RemoteFinancialAccount(
    id = id.toString(),
    dealerId = dealerId,
    accountType = accountType,
    balance = balance,
    updatedAt = DateUtils.formatDateAndTime(updatedAt),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)

fun Expense.toRemote(dealerId: String) = RemoteExpense(
    id = id.toString(),
    dealerId = dealerId,
    amount = amount,
    date = DateUtils.formatDateOnly(date),
    expenseDescription = expenseDescription,
    category = category,
    vehicleId = vehicleId?.toString(),
    userId = userId?.toString(),
    accountId = accountId?.toString(),
    createdAt = DateUtils.formatDateAndTime(createdAt),
    updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)

fun Debt.toRemote(dealerId: String) = RemoteDebt(
    id = id.toString(),
    dealerId = dealerId,
    counterpartyName = counterpartyName,
    counterpartyPhone = counterpartyPhone,
    direction = direction,
    amount = amount,
    notes = notes,
    dueDate = dueDate?.let { DateUtils.formatDateOnly(it) },
    createdAt = DateUtils.formatDateAndTime(createdAt),
    updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)

fun DebtPayment.toRemote(dealerId: String): RemoteDebtPayment? {
    val debtId = debtId ?: return null
    val dateValue = date
    return RemoteDebtPayment(
        id = id.toString(),
        dealerId = dealerId,
        debtId = debtId.toString(),
        amount = amount,
        date = DateUtils.formatDateAndTime(dateValue),
        note = note,
        paymentMethod = paymentMethod,
        accountId = accountId?.toString(),
        createdAt = DateUtils.formatDateAndTime(createdAt),
        updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
        deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
    )
}

fun AccountTransaction.toRemote(dealerId: String): RemoteAccountTransaction? {
    val accountId = accountId ?: return null
    val dateValue = date
    return RemoteAccountTransaction(
        id = id.toString(),
        dealerId = dealerId,
        accountId = accountId.toString(),
        transactionType = transactionType,
        amount = amount,
        date = DateUtils.formatDateAndTime(dateValue),
        note = note,
        createdAt = DateUtils.formatDateAndTime(createdAt),
        updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
        deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
    )
}

fun ExpenseTemplate.toRemote(dealerId: String) = RemoteExpenseTemplate(
    id = id.toString(),
    dealerId = dealerId,
    name = name,
    category = category ?: "",
    defaultDescription = defaultDescription,
    defaultAmount = defaultAmount,
    updatedAt = updatedAt?.let { DateUtils.formatDateAndTime(it) } ?: DateUtils.formatDateAndTime(Date()),
    deletedAt = deletedAt?.let { DateUtils.formatDateAndTime(it) }
)
