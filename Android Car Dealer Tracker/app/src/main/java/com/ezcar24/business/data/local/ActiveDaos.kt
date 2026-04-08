package com.ezcar24.business.data.local

import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow

abstract class ActiveDaoSupport(
    protected val provider: ActiveDatabaseProvider
) {
    protected fun currentDatabase(): AppDatabase = provider.currentDatabase()

    protected fun <T> flow(block: (AppDatabase) -> Flow<T>): Flow<T> {
        return provider.flowForActiveDatabase(block)
    }
}

@Singleton
class ActiveVehicleDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), VehicleDao {
    override suspend fun upsert(entity: Vehicle) = currentDatabase().vehicleDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Vehicle>) = currentDatabase().vehicleDao().upsertAll(entities)

    override suspend fun delete(entity: Vehicle) = currentDatabase().vehicleDao().delete(entity)

    override fun getAllActive(): Flow<List<Vehicle>> = flow { it.vehicleDao().getAllActive() }

    override suspend fun getAllActiveWithFinancials(): List<VehicleWithFinancials> {
        return currentDatabase().vehicleDao().getAllActiveWithFinancials()
    }

    override fun getAllActiveWithFinancialsFlow(): Flow<List<VehicleWithFinancials>> {
        return flow { it.vehicleDao().getAllActiveWithFinancialsFlow() }
    }

    override suspend fun getByStatus(status: String): List<Vehicle> = currentDatabase().vehicleDao().getByStatus(status)

    override suspend fun getAllIncludingDeleted(): List<Vehicle> = currentDatabase().vehicleDao().getAllIncludingDeleted()

    override suspend fun getById(id: UUID): Vehicle? = currentDatabase().vehicleDao().getById(id)

    override suspend fun searchActive(query: String): List<Vehicle> = currentDatabase().vehicleDao().searchActive(query)

    override suspend fun count(): Int = currentDatabase().vehicleDao().count()
}

@Singleton
class ActiveExpenseDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), ExpenseDao {
    override suspend fun upsert(entity: Expense) = currentDatabase().expenseDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Expense>) = currentDatabase().expenseDao().upsertAll(entities)

    override suspend fun delete(entity: Expense) = currentDatabase().expenseDao().delete(entity)

    override fun getByVehicleId(vehicleId: UUID): Flow<List<Expense>> = flow { it.expenseDao().getByVehicleId(vehicleId) }

    override suspend fun getExpensesForVehicleSync(vehicleId: UUID): List<Expense> {
        return currentDatabase().expenseDao().getExpensesForVehicleSync(vehicleId)
    }

    override suspend fun getById(id: UUID): Expense? = currentDatabase().expenseDao().getById(id)

    override fun getAll(): Flow<List<Expense>> = flow { it.expenseDao().getAll() }

    override suspend fun count(): Int = currentDatabase().expenseDao().count()

    override suspend fun getAllIncludingDeleted(): List<Expense> = currentDatabase().expenseDao().getAllIncludingDeleted()

    override suspend fun getExpensesSince(since: Date): List<Expense> = currentDatabase().expenseDao().getExpensesSince(since)

    override suspend fun searchActive(query: String): List<Expense> = currentDatabase().expenseDao().searchActive(query)

    override suspend fun updateUserId(oldId: UUID, newId: UUID) = currentDatabase().expenseDao().updateUserId(oldId, newId)

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) = currentDatabase().expenseDao().updateAccountId(oldId, newId)
}

@Singleton
class ActiveClientDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), ClientDao {
    override suspend fun upsert(entity: Client) = currentDatabase().clientDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Client>) = currentDatabase().clientDao().upsertAll(entities)

    override suspend fun delete(entity: Client) = currentDatabase().clientDao().delete(entity)

    override fun getAllActive(): Flow<List<Client>> = flow { it.clientDao().getAllActive() }

    override suspend fun getByVehicleId(vehicleId: UUID): Client? = currentDatabase().clientDao().getByVehicleId(vehicleId)

    override suspend fun getAllIncludingDeleted(): List<Client> = currentDatabase().clientDao().getAllIncludingDeleted()

    override suspend fun getById(id: UUID): Client? = currentDatabase().clientDao().getById(id)

    override suspend fun countAll(): Int = currentDatabase().clientDao().countAll()

    override suspend fun searchActive(query: String): List<Client> = currentDatabase().clientDao().searchActive(query)
}

@Singleton
class ActiveUserDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), UserDao {
    override suspend fun upsert(entity: User) = currentDatabase().userDao().upsert(entity)

    override suspend fun upsertAll(entities: List<User>) = currentDatabase().userDao().upsertAll(entities)

    override suspend fun delete(entity: User) = currentDatabase().userDao().delete(entity)

    override suspend fun getById(id: UUID): User? = currentDatabase().userDao().getById(id)

    override fun getAllActive(): Flow<List<User>> = flow { it.userDao().getAllActive() }

    override suspend fun count(): Int = currentDatabase().userDao().count()

    override suspend fun getAllIncludingDeleted(): List<User> = currentDatabase().userDao().getAllIncludingDeleted()
}

@Singleton
class ActiveFinancialAccountDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), FinancialAccountDao {
    override suspend fun upsert(entity: FinancialAccount) = currentDatabase().financialAccountDao().upsert(entity)

    override suspend fun upsertAll(entities: List<FinancialAccount>) = currentDatabase().financialAccountDao().upsertAll(entities)

    override suspend fun delete(entity: FinancialAccount) = currentDatabase().financialAccountDao().delete(entity)

    override fun getAll(): Flow<List<FinancialAccount>> = flow { it.financialAccountDao().getAll() }

    override suspend fun getAllIncludingDeleted(): List<FinancialAccount> {
        return currentDatabase().financialAccountDao().getAllIncludingDeleted()
    }

    override suspend fun getById(id: UUID): FinancialAccount? = currentDatabase().financialAccountDao().getById(id)

    override suspend fun countAll(): Int = currentDatabase().financialAccountDao().countAll()
}

@Singleton
class ActiveSyncQueueDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), SyncQueueDao {
    override suspend fun upsert(entity: SyncQueueItem) = currentDatabase().syncQueueDao().upsert(entity)

    override suspend fun upsertAll(entities: List<SyncQueueItem>) = currentDatabase().syncQueueDao().upsertAll(entities)

    override suspend fun delete(entity: SyncQueueItem) = currentDatabase().syncQueueDao().delete(entity)

    override suspend fun getAll(): List<SyncQueueItem> = currentDatabase().syncQueueDao().getAll()

    override suspend fun deleteById(id: UUID) = currentDatabase().syncQueueDao().deleteById(id)
}

@Singleton
class ActiveSaleDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), SaleDao {
    override suspend fun upsert(entity: Sale) = currentDatabase().saleDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Sale>) = currentDatabase().saleDao().upsertAll(entities)

    override suspend fun delete(entity: Sale) = currentDatabase().saleDao().delete(entity)

    override suspend fun getById(id: UUID): Sale? = currentDatabase().saleDao().getById(id)

    override suspend fun getByVehicleId(vehicleId: UUID): Sale? = currentDatabase().saleDao().getByVehicleId(vehicleId)

    override fun getAll(): Flow<List<Sale>> = flow { it.saleDao().getAll() }

    override suspend fun count(): Int = currentDatabase().saleDao().count()

    override suspend fun getAllIncludingDeleted(): List<Sale> = currentDatabase().saleDao().getAllIncludingDeleted()

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) = currentDatabase().saleDao().updateAccountId(oldId, newId)
}

@Singleton
class ActiveDebtDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), DebtDao {
    override suspend fun upsert(entity: Debt) = currentDatabase().debtDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Debt>) = currentDatabase().debtDao().upsertAll(entities)

    override suspend fun delete(entity: Debt) = currentDatabase().debtDao().delete(entity)

    override suspend fun getById(id: UUID): Debt? = currentDatabase().debtDao().getById(id)

    override fun getAllFlow(): Flow<List<Debt>> = flow { it.debtDao().getAllFlow() }

    override suspend fun getAllIncludingDeleted(): List<Debt> = currentDatabase().debtDao().getAllIncludingDeleted()

    override suspend fun count(): Int = currentDatabase().debtDao().count()

    override suspend fun getUpcomingDebts(now: Date): List<Debt> = currentDatabase().debtDao().getUpcomingDebts(now)
}

@Singleton
class ActiveDebtPaymentDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), DebtPaymentDao {
    override suspend fun upsert(entity: DebtPayment) = currentDatabase().debtPaymentDao().upsert(entity)

    override suspend fun upsertAll(entities: List<DebtPayment>) = currentDatabase().debtPaymentDao().upsertAll(entities)

    override suspend fun delete(entity: DebtPayment) = currentDatabase().debtPaymentDao().delete(entity)

    override suspend fun getById(id: UUID): DebtPayment? = currentDatabase().debtPaymentDao().getById(id)

    override suspend fun getAllIncludingDeleted(): List<DebtPayment> {
        return currentDatabase().debtPaymentDao().getAllIncludingDeleted()
    }

    override suspend fun count(): Int = currentDatabase().debtPaymentDao().count()

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) {
        currentDatabase().debtPaymentDao().updateAccountId(oldId, newId)
    }
}

@Singleton
class ActiveAccountTransactionDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), AccountTransactionDao {
    override suspend fun upsert(entity: AccountTransaction) = currentDatabase().accountTransactionDao().upsert(entity)

    override suspend fun upsertAll(entities: List<AccountTransaction>) {
        currentDatabase().accountTransactionDao().upsertAll(entities)
    }

    override suspend fun delete(entity: AccountTransaction) = currentDatabase().accountTransactionDao().delete(entity)

    override suspend fun getById(id: UUID): AccountTransaction? = currentDatabase().accountTransactionDao().getById(id)

    override suspend fun getAllIncludingDeleted(): List<AccountTransaction> {
        return currentDatabase().accountTransactionDao().getAllIncludingDeleted()
    }

    override suspend fun count(): Int = currentDatabase().accountTransactionDao().count()

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) {
        currentDatabase().accountTransactionDao().updateAccountId(oldId, newId)
    }
}

@Singleton
class ActiveExpenseTemplateDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), ExpenseTemplateDao {
    override suspend fun upsert(entity: ExpenseTemplate) = currentDatabase().expenseTemplateDao().upsert(entity)

    override suspend fun upsertAll(entities: List<ExpenseTemplate>) {
        currentDatabase().expenseTemplateDao().upsertAll(entities)
    }

    override suspend fun delete(entity: ExpenseTemplate) = currentDatabase().expenseTemplateDao().delete(entity)

    override suspend fun getById(id: UUID): ExpenseTemplate? = currentDatabase().expenseTemplateDao().getById(id)

    override suspend fun getAllIncludingDeleted(): List<ExpenseTemplate> {
        return currentDatabase().expenseTemplateDao().getAllIncludingDeleted()
    }

    override suspend fun count(): Int = currentDatabase().expenseTemplateDao().count()

    override suspend fun updateUserId(oldId: UUID, newId: UUID) {
        currentDatabase().expenseTemplateDao().updateUserId(oldId, newId)
    }

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) {
        currentDatabase().expenseTemplateDao().updateAccountId(oldId, newId)
    }
}

@Singleton
class ActivePartDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), PartDao {
    override suspend fun upsert(entity: Part) = currentDatabase().partDao().upsert(entity)

    override suspend fun upsertAll(entities: List<Part>) = currentDatabase().partDao().upsertAll(entities)

    override suspend fun delete(entity: Part) = currentDatabase().partDao().delete(entity)

    override fun getAllActive(): Flow<List<Part>> = flow { it.partDao().getAllActive() }

    override suspend fun getAllActiveList(): List<Part> = currentDatabase().partDao().getAllActiveList()

    override suspend fun getAllIncludingDeleted(): List<Part> = currentDatabase().partDao().getAllIncludingDeleted()

    override suspend fun getById(id: UUID): Part? = currentDatabase().partDao().getById(id)

    override suspend fun count(): Int = currentDatabase().partDao().count()
}

@Singleton
class ActivePartBatchDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), PartBatchDao {
    override suspend fun upsert(entity: PartBatch) = currentDatabase().partBatchDao().upsert(entity)

    override suspend fun upsertAll(entities: List<PartBatch>) = currentDatabase().partBatchDao().upsertAll(entities)

    override suspend fun delete(entity: PartBatch) = currentDatabase().partBatchDao().delete(entity)

    override fun getAllActive(): Flow<List<PartBatch>> = flow { it.partBatchDao().getAllActive() }

    override suspend fun getAllActiveList(): List<PartBatch> = currentDatabase().partBatchDao().getAllActiveList()

    override fun getByPartId(partId: UUID): Flow<List<PartBatch>> = flow { it.partBatchDao().getByPartId(partId) }

    override suspend fun getAllIncludingDeleted(): List<PartBatch> = currentDatabase().partBatchDao().getAllIncludingDeleted()

    override suspend fun getById(id: UUID): PartBatch? = currentDatabase().partBatchDao().getById(id)

    override suspend fun count(): Int = currentDatabase().partBatchDao().count()

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) = currentDatabase().partBatchDao().updateAccountId(oldId, newId)
}

@Singleton
class ActivePartSaleDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), PartSaleDao {
    override suspend fun upsert(entity: PartSale) = currentDatabase().partSaleDao().upsert(entity)

    override suspend fun upsertAll(entities: List<PartSale>) = currentDatabase().partSaleDao().upsertAll(entities)

    override suspend fun delete(entity: PartSale) = currentDatabase().partSaleDao().delete(entity)

    override fun getAllActive(): Flow<List<PartSale>> = flow { it.partSaleDao().getAllActive() }

    override suspend fun getAllIncludingDeleted(): List<PartSale> = currentDatabase().partSaleDao().getAllIncludingDeleted()

    override suspend fun getById(id: UUID): PartSale? = currentDatabase().partSaleDao().getById(id)

    override suspend fun count(): Int = currentDatabase().partSaleDao().count()

    override suspend fun updateAccountId(oldId: UUID, newId: UUID) = currentDatabase().partSaleDao().updateAccountId(oldId, newId)
}

@Singleton
class ActivePartSaleLineItemDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), PartSaleLineItemDao {
    override suspend fun upsert(entity: PartSaleLineItem) = currentDatabase().partSaleLineItemDao().upsert(entity)

    override suspend fun upsertAll(entities: List<PartSaleLineItem>) {
        currentDatabase().partSaleLineItemDao().upsertAll(entities)
    }

    override suspend fun delete(entity: PartSaleLineItem) = currentDatabase().partSaleLineItemDao().delete(entity)

    override fun getAllActive(): Flow<List<PartSaleLineItem>> = flow { it.partSaleLineItemDao().getAllActive() }

    override suspend fun getBySaleId(saleId: UUID): List<PartSaleLineItem> {
        return currentDatabase().partSaleLineItemDao().getBySaleId(saleId)
    }

    override suspend fun getAllIncludingDeleted(): List<PartSaleLineItem> {
        return currentDatabase().partSaleLineItemDao().getAllIncludingDeleted()
    }

    override suspend fun getById(id: UUID): PartSaleLineItem? = currentDatabase().partSaleLineItemDao().getById(id)

    override suspend fun count(): Int = currentDatabase().partSaleLineItemDao().count()
}

@Singleton
class ActiveClientInteractionDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), ClientInteractionDao {
    override suspend fun upsert(entity: ClientInteraction) = currentDatabase().clientInteractionDao().upsert(entity)

    override suspend fun upsertAll(entities: List<ClientInteraction>) {
        currentDatabase().clientInteractionDao().upsertAll(entities)
    }

    override suspend fun delete(entity: ClientInteraction) = currentDatabase().clientInteractionDao().delete(entity)

    override suspend fun getByClient(clientId: UUID): List<ClientInteraction> {
        return currentDatabase().clientInteractionDao().getByClient(clientId)
    }

    override suspend fun getById(id: UUID): ClientInteraction? = currentDatabase().clientInteractionDao().getById(id)

    override suspend fun getAllIncludingDeleted(): List<ClientInteraction> {
        return currentDatabase().clientInteractionDao().getAllIncludingDeleted()
    }

    override suspend fun deleteByClient(clientId: UUID) = currentDatabase().clientInteractionDao().deleteByClient(clientId)
}

@Singleton
class ActiveClientReminderDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), ClientReminderDao {
    override suspend fun upsert(entity: ClientReminder) = currentDatabase().clientReminderDao().upsert(entity)

    override suspend fun upsertAll(entities: List<ClientReminder>) {
        currentDatabase().clientReminderDao().upsertAll(entities)
    }

    override suspend fun delete(entity: ClientReminder) = currentDatabase().clientReminderDao().delete(entity)

    override suspend fun getByClient(clientId: UUID): List<ClientReminder> {
        return currentDatabase().clientReminderDao().getByClient(clientId)
    }

    override suspend fun deleteByClient(clientId: UUID) = currentDatabase().clientReminderDao().deleteByClient(clientId)

    override suspend fun getUpcomingReminders(now: Date): List<ClientReminder> {
        return currentDatabase().clientReminderDao().getUpcomingReminders(now)
    }
}

@Singleton
class ActiveHoldingCostSettingsDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), HoldingCostSettingsDao {
    override suspend fun upsert(entity: HoldingCostSettings) = currentDatabase().holdingCostSettingsDao().upsert(entity)

    override suspend fun upsertAll(entities: List<HoldingCostSettings>) {
        currentDatabase().holdingCostSettingsDao().upsertAll(entities)
    }

    override suspend fun delete(entity: HoldingCostSettings) = currentDatabase().holdingCostSettingsDao().delete(entity)

    override suspend fun getById(id: UUID): HoldingCostSettings? = currentDatabase().holdingCostSettingsDao().getById(id)

    override suspend fun getByDealerId(dealerId: UUID): HoldingCostSettings? {
        return currentDatabase().holdingCostSettingsDao().getByDealerId(dealerId)
    }

    override fun getByDealerIdFlow(dealerId: UUID): Flow<HoldingCostSettings?> {
        return flow { it.holdingCostSettingsDao().getByDealerIdFlow(dealerId) }
    }

    override fun getSettings(): Flow<HoldingCostSettings?> = flow { it.holdingCostSettingsDao().getSettings() }

    override suspend fun getAllIncludingDeleted(): List<HoldingCostSettings> {
        return currentDatabase().holdingCostSettingsDao().getAllIncludingDeleted()
    }
}

@Singleton
class ActiveVehicleInventoryStatsDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), VehicleInventoryStatsDao {
    override suspend fun upsert(entity: VehicleInventoryStats) = currentDatabase().vehicleInventoryStatsDao().upsert(entity)

    override suspend fun upsertAll(entities: List<VehicleInventoryStats>) {
        currentDatabase().vehicleInventoryStatsDao().upsertAll(entities)
    }

    override suspend fun delete(entity: VehicleInventoryStats) = currentDatabase().vehicleInventoryStatsDao().delete(entity)

    override suspend fun getByVehicleId(vehicleId: UUID): VehicleInventoryStats? {
        return currentDatabase().vehicleInventoryStatsDao().getByVehicleId(vehicleId)
    }

    override fun getByVehicleIdFlow(vehicleId: UUID): Flow<VehicleInventoryStats?> {
        return flow { it.vehicleInventoryStatsDao().getByVehicleIdFlow(vehicleId) }
    }

    override suspend fun getAllIncludingDeleted(): List<VehicleInventoryStats> {
        return currentDatabase().vehicleInventoryStatsDao().getAllIncludingDeleted()
    }

    override fun getAllFlow(): Flow<List<VehicleInventoryStats>> = flow { it.vehicleInventoryStatsDao().getAllFlow() }

    override suspend fun deleteByVehicleId(vehicleId: UUID) = currentDatabase().vehicleInventoryStatsDao().deleteByVehicleId(vehicleId)
}

@Singleton
class ActiveInventoryAlertDao @Inject constructor(
    provider: ActiveDatabaseProvider
) : ActiveDaoSupport(provider), InventoryAlertDao {
    override suspend fun upsert(entity: InventoryAlert) = currentDatabase().inventoryAlertDao().upsert(entity)

    override suspend fun upsertAll(entities: List<InventoryAlert>) {
        currentDatabase().inventoryAlertDao().upsertAll(entities)
    }

    override suspend fun delete(entity: InventoryAlert) = currentDatabase().inventoryAlertDao().delete(entity)

    override suspend fun getByVehicleId(vehicleId: UUID): List<InventoryAlert> {
        return currentDatabase().inventoryAlertDao().getByVehicleId(vehicleId)
    }

    override fun getByVehicleIdFlow(vehicleId: UUID): Flow<List<InventoryAlert>> {
        return flow { it.inventoryAlertDao().getByVehicleIdFlow(vehicleId) }
    }

    override fun getUnreadAlerts(): Flow<List<InventoryAlert>> = flow { it.inventoryAlertDao().getUnreadAlerts() }

    override fun getAllAlerts(): Flow<List<InventoryAlert>> = flow { it.inventoryAlertDao().getAllAlerts() }

    override suspend fun getAllIncludingDeleted(): List<InventoryAlert> {
        return currentDatabase().inventoryAlertDao().getAllIncludingDeleted()
    }

    override suspend fun markAsRead(id: UUID) = currentDatabase().inventoryAlertDao().markAsRead(id)

    override suspend fun dismiss(id: UUID, dismissedAt: Date) = currentDatabase().inventoryAlertDao().dismiss(id, dismissedAt)

    override suspend fun deleteByVehicleId(vehicleId: UUID) = currentDatabase().inventoryAlertDao().deleteByVehicleId(vehicleId)
}
