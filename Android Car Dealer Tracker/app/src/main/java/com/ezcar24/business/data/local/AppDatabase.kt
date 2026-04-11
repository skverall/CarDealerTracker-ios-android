package com.ezcar24.business.data.local

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.Update
import java.util.UUID
import java.util.Date
import java.math.BigDecimal
import kotlinx.coroutines.flow.Flow

data class VehicleWithFinancials(
    @Embedded val vehicle: Vehicle,
    val totalExpenseCost: BigDecimal?,
    val expenseCount: Int
)

data class VehicleWithExpenses(
    @Embedded val vehicle: Vehicle,
    val expenses: List<Expense>
)

@Dao
interface BaseDao<T> {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: T)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<T>)

    @Delete
    suspend fun delete(entity: T)
}

@Dao
interface VehicleDao : BaseDao<Vehicle> {
    @Query("SELECT * FROM vehicles WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    fun getAllActive(): Flow<List<Vehicle>>

    @Query("""
        SELECT v.*, SUM(e.amount) as totalExpenseCost, COUNT(e.id) as expenseCount 
        FROM vehicles v 
        LEFT JOIN expenses e ON v.id = e.vehicleId AND e.deletedAt IS NULL 
        WHERE v.deletedAt IS NULL 
        GROUP BY v.id 
        ORDER BY v.createdAt DESC
    """)
    suspend fun getAllActiveWithFinancials(): List<VehicleWithFinancials>
    
    @Query("""
        SELECT v.*, SUM(e.amount) as totalExpenseCost, COUNT(e.id) as expenseCount 
        FROM vehicles v 
        LEFT JOIN expenses e ON v.id = e.vehicleId AND e.deletedAt IS NULL 
        WHERE v.deletedAt IS NULL 
        GROUP BY v.id 
        ORDER BY v.createdAt DESC
    """)
    fun getAllActiveWithFinancialsFlow(): Flow<List<VehicleWithFinancials>>

    @Query("SELECT * FROM vehicles WHERE status = :status AND deletedAt IS NULL ORDER BY createdAt DESC")
    suspend fun getByStatus(status: String): List<Vehicle>

    @Query("SELECT * FROM vehicles")
    suspend fun getAllIncludingDeleted(): List<Vehicle>

    @Query("SELECT * FROM vehicles WHERE id = :id")
    suspend fun getById(id: UUID): Vehicle?

    @Query(
        """
        SELECT * FROM vehicles
        WHERE deletedAt IS NULL AND (
            LOWER(vin) LIKE :query OR
            LOWER(make) LIKE :query OR
            LOWER(model) LIKE :query OR
            CAST(year AS TEXT) LIKE :query
        )
        ORDER BY createdAt DESC
        """
    )
    suspend fun searchActive(query: String): List<Vehicle>

    @Query("SELECT COUNT(*) FROM vehicles WHERE deletedAt IS NULL")
    suspend fun count(): Int
}

@Dao
interface ExpenseDao : BaseDao<Expense> {
    @Query("SELECT * FROM expenses WHERE vehicleId = :vehicleId AND deletedAt IS NULL ORDER BY date DESC")
    fun getByVehicleId(vehicleId: UUID): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE vehicleId = :vehicleId AND deletedAt IS NULL ORDER BY date DESC")
    suspend fun getExpensesForVehicleSync(vehicleId: UUID): List<Expense>
    
    @Query("SELECT * FROM expenses WHERE id = :id")
    suspend fun getById(id: UUID): Expense?

    @Query("SELECT * FROM expenses WHERE deletedAt IS NULL ORDER BY date DESC")
    fun getAll(): Flow<List<Expense>>
    
    @Query("SELECT COUNT(*) FROM expenses WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("SELECT * FROM expenses")
    suspend fun getAllIncludingDeleted(): List<Expense>

    @Query("SELECT * FROM expenses WHERE date >= :since AND deletedAt IS NULL ORDER BY date DESC")
    suspend fun getExpensesSince(since: Date): List<Expense>

    @Query(
        """
        SELECT * FROM expenses
        WHERE deletedAt IS NULL AND (
            LOWER(expenseDescription) LIKE :query OR
            LOWER(category) LIKE :query
        )
        ORDER BY date DESC
        """
    )
    suspend fun searchActive(query: String): List<Expense>

    @Query("UPDATE expenses SET userId = :newId WHERE userId = :oldId")
    suspend fun updateUserId(oldId: UUID, newId: UUID)

    @Query("UPDATE expenses SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface ClientDao : BaseDao<Client> {
    @Query("SELECT * FROM clients WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    fun getAllActive(): Flow<List<Client>>

    @Query("SELECT * FROM clients WHERE vehicleId = :vehicleId AND deletedAt IS NULL ORDER BY createdAt DESC LIMIT 1")
    suspend fun getByVehicleId(vehicleId: UUID): Client?
    
    @Query("SELECT * FROM clients")
    suspend fun getAllIncludingDeleted(): List<Client>

    @Query("SELECT * FROM clients WHERE id = :id")
    suspend fun getById(id: UUID): Client?

    @Query("SELECT COUNT(*) FROM clients")
    suspend fun countAll(): Int

    @Query(
        """
        SELECT * FROM clients
        WHERE deletedAt IS NULL AND (
            LOWER(name) LIKE :query OR
            LOWER(phone) LIKE :query OR
            LOWER(email) LIKE :query OR
            LOWER(notes) LIKE :query
        )
        ORDER BY createdAt DESC
        """
    )
    suspend fun searchActive(query: String): List<Client>
}

@Dao
interface UserDao : BaseDao<User> {
    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun getById(id: UUID): User?

    @Query("SELECT * FROM users WHERE deletedAt IS NULL ORDER BY name ASC")
    fun getAllActive(): Flow<List<User>>
    
    @Query("SELECT COUNT(*) FROM users WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("SELECT * FROM users")
    suspend fun getAllIncludingDeleted(): List<User>
}

@Dao
interface FinancialAccountDao : BaseDao<FinancialAccount> {
    @Query("SELECT * FROM financial_accounts WHERE deletedAt IS NULL")
    fun getAll(): Flow<List<FinancialAccount>>

    @Query("SELECT * FROM financial_accounts")
    suspend fun getAllIncludingDeleted(): List<FinancialAccount>
    
    @Query("SELECT * FROM financial_accounts WHERE id = :id")
    suspend fun getById(id: UUID): FinancialAccount?

    @Query("SELECT COUNT(*) FROM financial_accounts")
    suspend fun countAll(): Int
}

@Dao
interface SyncQueueDao : BaseDao<SyncQueueItem> {
    @Query("SELECT * FROM sync_queue ORDER BY createdAt ASC")
    suspend fun getAll(): List<SyncQueueItem>

    @Query("DELETE FROM sync_queue WHERE id = :id")
    suspend fun deleteById(id: UUID)
}

@Dao
interface SaleDao : BaseDao<Sale> {
    @Query("SELECT * FROM sales WHERE id = :id")
    suspend fun getById(id: UUID): Sale?

    @Query("SELECT * FROM sales WHERE vehicleId = :vehicleId AND deletedAt IS NULL ORDER BY createdAt DESC LIMIT 1")
    suspend fun getByVehicleId(vehicleId: UUID): Sale?

    @Query("SELECT * FROM sales WHERE deletedAt IS NULL")
    fun getAll(): Flow<List<Sale>>
    
    @Query("SELECT COUNT(*) FROM sales WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("SELECT * FROM sales")
    suspend fun getAllIncludingDeleted(): List<Sale>

    @Query("UPDATE sales SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface DebtDao : BaseDao<Debt> {
    @Query("SELECT * FROM debts WHERE id = :id")
    suspend fun getById(id: UUID): Debt?

    @Query("SELECT * FROM debts")
    fun getAllFlow(): Flow<List<Debt>>

    @Query("SELECT * FROM debts")
    suspend fun getAllIncludingDeleted(): List<Debt>
    
    @Query("SELECT COUNT(*) FROM debts WHERE deletedAt IS NULL")
    suspend fun count(): Int
    
    @Query("SELECT * FROM debts WHERE dueDate IS NOT NULL AND dueDate > :now AND deletedAt IS NULL")
    suspend fun getUpcomingDebts(now: Date): List<Debt>
}

@Dao
interface DebtPaymentDao : BaseDao<DebtPayment> {
    @Query("SELECT * FROM debt_payments WHERE id = :id")
    suspend fun getById(id: UUID): DebtPayment?

    @Query("SELECT * FROM debt_payments")
    suspend fun getAllIncludingDeleted(): List<DebtPayment>
    
    @Query("SELECT COUNT(*) FROM debt_payments WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("UPDATE debt_payments SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface AccountTransactionDao : BaseDao<AccountTransaction> {
    @Query("SELECT * FROM account_transactions WHERE id = :id")
    suspend fun getById(id: UUID): AccountTransaction?

    @Query("SELECT * FROM account_transactions")
    suspend fun getAllIncludingDeleted(): List<AccountTransaction>
    
    @Query("SELECT COUNT(*) FROM account_transactions WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("UPDATE account_transactions SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface ExpenseTemplateDao : BaseDao<ExpenseTemplate> {
    @Query("SELECT * FROM expense_templates WHERE deletedAt IS NULL ORDER BY name ASC")
    fun getAllActive(): Flow<List<ExpenseTemplate>>

    @Query("SELECT * FROM expense_templates WHERE id = :id")
    suspend fun getById(id: UUID): ExpenseTemplate?

    @Query("SELECT * FROM expense_templates")
    suspend fun getAllIncludingDeleted(): List<ExpenseTemplate>
    
    @Query("SELECT COUNT(*) FROM expense_templates WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("UPDATE expense_templates SET userId = :newId WHERE userId = :oldId")
    suspend fun updateUserId(oldId: UUID, newId: UUID)

    @Query("UPDATE expense_templates SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface PartDao : BaseDao<Part> {
    @Query("SELECT * FROM parts WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    fun getAllActive(): Flow<List<Part>>

    @Query("SELECT * FROM parts WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    suspend fun getAllActiveList(): List<Part>

    @Query("SELECT * FROM parts")
    suspend fun getAllIncludingDeleted(): List<Part>

    @Query("SELECT * FROM parts WHERE id = :id")
    suspend fun getById(id: UUID): Part?

    @Query("SELECT COUNT(*) FROM parts WHERE deletedAt IS NULL")
    suspend fun count(): Int
}

@Dao
interface PartBatchDao : BaseDao<PartBatch> {
    @Query("SELECT * FROM part_batches WHERE deletedAt IS NULL ORDER BY purchaseDate DESC")
    fun getAllActive(): Flow<List<PartBatch>>

    @Query("SELECT * FROM part_batches WHERE deletedAt IS NULL ORDER BY purchaseDate DESC")
    suspend fun getAllActiveList(): List<PartBatch>

    @Query("SELECT * FROM part_batches WHERE partId = :partId AND deletedAt IS NULL ORDER BY purchaseDate DESC")
    fun getByPartId(partId: UUID): Flow<List<PartBatch>>

    @Query("SELECT * FROM part_batches")
    suspend fun getAllIncludingDeleted(): List<PartBatch>

    @Query("SELECT * FROM part_batches WHERE id = :id")
    suspend fun getById(id: UUID): PartBatch?

    @Query("SELECT COUNT(*) FROM part_batches WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("UPDATE part_batches SET purchaseAccountId = :newId WHERE purchaseAccountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface PartSaleDao : BaseDao<PartSale> {
    @Query("SELECT * FROM part_sales WHERE deletedAt IS NULL ORDER BY date DESC")
    fun getAllActive(): Flow<List<PartSale>>

    @Query("SELECT * FROM part_sales")
    suspend fun getAllIncludingDeleted(): List<PartSale>

    @Query("SELECT * FROM part_sales WHERE id = :id")
    suspend fun getById(id: UUID): PartSale?

    @Query("SELECT COUNT(*) FROM part_sales WHERE deletedAt IS NULL")
    suspend fun count(): Int

    @Query("UPDATE part_sales SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface PartSaleLineItemDao : BaseDao<PartSaleLineItem> {
    @Query("SELECT * FROM part_sale_line_items WHERE deletedAt IS NULL")
    fun getAllActive(): Flow<List<PartSaleLineItem>>

    @Query("SELECT * FROM part_sale_line_items WHERE saleId = :saleId AND deletedAt IS NULL")
    suspend fun getBySaleId(saleId: UUID): List<PartSaleLineItem>

    @Query("SELECT * FROM part_sale_line_items")
    suspend fun getAllIncludingDeleted(): List<PartSaleLineItem>

    @Query("SELECT * FROM part_sale_line_items WHERE id = :id")
    suspend fun getById(id: UUID): PartSaleLineItem?

    @Query("SELECT COUNT(*) FROM part_sale_line_items WHERE deletedAt IS NULL")
    suspend fun count(): Int
}

@Dao
interface ClientInteractionDao : BaseDao<ClientInteraction> {
    @Query("SELECT * FROM client_interactions WHERE clientId = :clientId AND deletedAt IS NULL ORDER BY occurredAt DESC")
    suspend fun getByClient(clientId: UUID): List<ClientInteraction>

    @Query("SELECT * FROM client_interactions WHERE id = :id")
    suspend fun getById(id: UUID): ClientInteraction?

    @Query("SELECT * FROM client_interactions")
    suspend fun getAllIncludingDeleted(): List<ClientInteraction>

    @Query("DELETE FROM client_interactions WHERE clientId = :clientId")
    suspend fun deleteByClient(clientId: UUID)
}

@Dao
interface ClientReminderDao : BaseDao<ClientReminder> {
    @Query("SELECT * FROM client_reminders WHERE clientId = :clientId ORDER BY dueDate ASC")
    suspend fun getByClient(clientId: UUID): List<ClientReminder>

    @Query("DELETE FROM client_reminders WHERE clientId = :clientId")
    suspend fun deleteByClient(clientId: UUID)
    
    @Query("SELECT * FROM client_reminders WHERE isCompleted = 0 AND dueDate > :now")
    suspend fun getUpcomingReminders(now: Date): List<ClientReminder>
}

@Dao
interface HoldingCostSettingsDao : BaseDao<HoldingCostSettings> {
    @Query("SELECT * FROM holding_cost_settings WHERE id = :id LIMIT 1")
    suspend fun getById(id: UUID): HoldingCostSettings?

    @Query("SELECT * FROM holding_cost_settings WHERE dealerId = :dealerId LIMIT 1")
    suspend fun getByDealerId(dealerId: UUID): HoldingCostSettings?

    @Query("SELECT * FROM holding_cost_settings WHERE dealerId = :dealerId LIMIT 1")
    fun getByDealerIdFlow(dealerId: UUID): Flow<HoldingCostSettings?>

    @Query("SELECT * FROM holding_cost_settings LIMIT 1")
    fun getSettings(): Flow<HoldingCostSettings?>

    @Query("SELECT * FROM holding_cost_settings")
    suspend fun getAllIncludingDeleted(): List<HoldingCostSettings>
}

@Dao
interface VehicleInventoryStatsDao : BaseDao<VehicleInventoryStats> {
    @Query("SELECT * FROM vehicle_inventory_stats WHERE vehicleId = :vehicleId")
    suspend fun getByVehicleId(vehicleId: UUID): VehicleInventoryStats?

    @Query("SELECT * FROM vehicle_inventory_stats WHERE vehicleId = :vehicleId")
    fun getByVehicleIdFlow(vehicleId: UUID): Flow<VehicleInventoryStats?>

    @Query("SELECT * FROM vehicle_inventory_stats")
    suspend fun getAllIncludingDeleted(): List<VehicleInventoryStats>

    @Query("SELECT * FROM vehicle_inventory_stats")
    fun getAllFlow(): Flow<List<VehicleInventoryStats>>

    @Query("DELETE FROM vehicle_inventory_stats WHERE vehicleId = :vehicleId")
    suspend fun deleteByVehicleId(vehicleId: UUID)
}

@Dao
interface InventoryAlertDao : BaseDao<InventoryAlert> {
    @Query("SELECT * FROM inventory_alerts WHERE vehicleId = :vehicleId ORDER BY createdAt DESC")
    suspend fun getByVehicleId(vehicleId: UUID): List<InventoryAlert>

    @Query("SELECT * FROM inventory_alerts WHERE vehicleId = :vehicleId ORDER BY createdAt DESC")
    fun getByVehicleIdFlow(vehicleId: UUID): Flow<List<InventoryAlert>>

    @Query("SELECT * FROM inventory_alerts WHERE isRead = 0 ORDER BY createdAt DESC")
    fun getUnreadAlerts(): Flow<List<InventoryAlert>>

    @Query("SELECT * FROM inventory_alerts ORDER BY createdAt DESC")
    fun getAllAlerts(): Flow<List<InventoryAlert>>

    @Query("SELECT * FROM inventory_alerts")
    suspend fun getAllIncludingDeleted(): List<InventoryAlert>

    @Query("UPDATE inventory_alerts SET isRead = 1 WHERE id = :id")
    suspend fun markAsRead(id: UUID)

    @Query("UPDATE inventory_alerts SET dismissedAt = :dismissedAt WHERE id = :id")
    suspend fun dismiss(id: UUID, dismissedAt: Date)

    @Query("DELETE FROM inventory_alerts WHERE vehicleId = :vehicleId")
    suspend fun deleteByVehicleId(vehicleId: UUID)
}

@Database(
    entities = [
        User::class, Vehicle::class, Expense::class, Sale::class, 
        Client::class, ClientInteraction::class, ClientReminder::class,
        FinancialAccount::class, AccountTransaction::class,
        Debt::class, DebtPayment::class, ExpenseTemplate::class,
        Part::class, PartBatch::class, PartSale::class, PartSaleLineItem::class,
        SyncQueueItem::class, HoldingCostSettings::class,
        VehicleInventoryStats::class, InventoryAlert::class
    ],
    version = 8,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun vehicleDao(): VehicleDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun clientDao(): ClientDao
    abstract fun userDao(): UserDao
    abstract fun financialAccountDao(): FinancialAccountDao
    abstract fun syncQueueDao(): SyncQueueDao
    abstract fun saleDao(): SaleDao
    abstract fun debtDao(): DebtDao
    abstract fun debtPaymentDao(): DebtPaymentDao
    abstract fun accountTransactionDao(): AccountTransactionDao
    abstract fun expenseTemplateDao(): ExpenseTemplateDao
    abstract fun clientInteractionDao(): ClientInteractionDao
    abstract fun clientReminderDao(): ClientReminderDao
    abstract fun partDao(): PartDao
    abstract fun partBatchDao(): PartBatchDao
    abstract fun partSaleDao(): PartSaleDao
    abstract fun partSaleLineItemDao(): PartSaleLineItemDao
    abstract fun holdingCostSettingsDao(): HoldingCostSettingsDao
    abstract fun vehicleInventoryStatsDao(): VehicleInventoryStatsDao
    abstract fun inventoryAlertDao(): InventoryAlertDao
    
    companion object {
        val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE vehicles ADD COLUMN photoUrl TEXT")
            }
        }

        val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `parts` (
                        `id` TEXT NOT NULL,
                        `name` TEXT NOT NULL,
                        `code` TEXT,
                        `category` TEXT,
                        `notes` TEXT,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        `deletedAt` INTEGER,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `part_batches` (
                        `id` TEXT NOT NULL,
                        `partId` TEXT NOT NULL,
                        `batchLabel` TEXT,
                        `quantityReceived` TEXT NOT NULL,
                        `quantityRemaining` TEXT NOT NULL,
                        `unitCost` TEXT NOT NULL,
                        `purchaseDate` INTEGER NOT NULL,
                        `purchaseAccountId` TEXT,
                        `notes` TEXT,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        `deletedAt` INTEGER,
                        PRIMARY KEY(`id`),
                        FOREIGN KEY(`partId`) REFERENCES `parts`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE,
                        FOREIGN KEY(`purchaseAccountId`) REFERENCES `financial_accounts`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_batches_partId` ON `part_batches` (`partId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_batches_purchaseAccountId` ON `part_batches` (`purchaseAccountId`)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `part_sales` (
                        `id` TEXT NOT NULL,
                        `amount` TEXT NOT NULL,
                        `date` INTEGER NOT NULL,
                        `buyerName` TEXT,
                        `buyerPhone` TEXT,
                        `paymentMethod` TEXT,
                        `accountId` TEXT,
                        `notes` TEXT,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        `deletedAt` INTEGER,
                        PRIMARY KEY(`id`),
                        FOREIGN KEY(`accountId`) REFERENCES `financial_accounts`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_sales_accountId` ON `part_sales` (`accountId`)")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `part_sale_line_items` (
                        `id` TEXT NOT NULL,
                        `saleId` TEXT NOT NULL,
                        `partId` TEXT NOT NULL,
                        `batchId` TEXT NOT NULL,
                        `quantity` TEXT NOT NULL,
                        `unitPrice` TEXT NOT NULL,
                        `unitCost` TEXT NOT NULL,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        `deletedAt` INTEGER,
                        PRIMARY KEY(`id`),
                        FOREIGN KEY(`saleId`) REFERENCES `part_sales`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE,
                        FOREIGN KEY(`partId`) REFERENCES `parts`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE,
                        FOREIGN KEY(`batchId`) REFERENCES `part_batches`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_sale_line_items_saleId` ON `part_sale_line_items` (`saleId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_sale_line_items_partId` ON `part_sale_line_items` (`partId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_part_sale_line_items_batchId` ON `part_sale_line_items` (`batchId`)")
            }
        }

        val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE expenses ADD COLUMN expenseType TEXT NOT NULL DEFAULT 'HOLDING_COST'")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `holding_cost_settings` (
                        `id` TEXT NOT NULL,
                        `dealerId` TEXT NOT NULL,
                        `annualRatePercent` TEXT NOT NULL,
                        `dailyRatePercent` TEXT NOT NULL,
                        `isEnabled` INTEGER NOT NULL,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_holding_cost_settings_dealerId` ON `holding_cost_settings` (`dealerId`)")
            }
        }

        val MIGRATION_4_5 = object : androidx.room.migration.Migration(4, 5) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                // Add new columns to clients table for CRM/Lead Funnel
                db.execSQL("ALTER TABLE clients ADD COLUMN leadStage TEXT NOT NULL DEFAULT 'new'")
                db.execSQL("ALTER TABLE clients ADD COLUMN leadSource TEXT")
                db.execSQL("ALTER TABLE clients ADD COLUMN assignedUserId TEXT")
                db.execSQL("ALTER TABLE clients ADD COLUMN estimatedValue TEXT")
                db.execSQL("ALTER TABLE clients ADD COLUMN priority INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE clients ADD COLUMN leadCreatedAt INTEGER")
                db.execSQL("ALTER TABLE clients ADD COLUMN lastContactAt INTEGER")
                db.execSQL("ALTER TABLE clients ADD COLUMN nextFollowUpAt INTEGER")
                
                // Create new indexes for clients table
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_clients_leadStage` ON `clients` (`leadStage`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_clients_assignedUserId` ON `clients` (`assignedUserId`)")
                
                // Add new columns to client_interactions table
                db.execSQL("ALTER TABLE client_interactions ADD COLUMN interactionType TEXT")
                db.execSQL("ALTER TABLE client_interactions ADD COLUMN outcome TEXT")
                db.execSQL("ALTER TABLE client_interactions ADD COLUMN durationMinutes INTEGER")
                db.execSQL("ALTER TABLE client_interactions ADD COLUMN isFollowUpRequired INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_5_6 = object : androidx.room.migration.Migration(5, 6) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                // Create vehicle_inventory_stats table
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `vehicle_inventory_stats` (
                        `id` TEXT NOT NULL,
                        `vehicleId` TEXT NOT NULL,
                        `daysInInventory` INTEGER NOT NULL,
                        `agingBucket` TEXT NOT NULL,
                        `totalCost` TEXT NOT NULL,
                        `holdingCostAccumulated` TEXT NOT NULL,
                        `roiPercent` TEXT,
                        `profitEstimate` TEXT,
                        `lastCalculatedAt` INTEGER NOT NULL,
                        `createdAt` INTEGER NOT NULL,
                        `updatedAt` INTEGER,
                        PRIMARY KEY(`id`),
                        FOREIGN KEY(`vehicleId`) REFERENCES `vehicles`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_vehicle_inventory_stats_vehicleId` ON `vehicle_inventory_stats` (`vehicleId`)")
                
                // Create inventory_alerts table
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `inventory_alerts` (
                        `id` TEXT NOT NULL,
                        `vehicleId` TEXT NOT NULL,
                        `alertType` TEXT NOT NULL,
                        `severity` TEXT NOT NULL,
                        `message` TEXT NOT NULL,
                        `isRead` INTEGER NOT NULL,
                        `createdAt` INTEGER NOT NULL,
                        `dismissedAt` INTEGER,
                        PRIMARY KEY(`id`),
                        FOREIGN KEY(`vehicleId`) REFERENCES `vehicles`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_inventory_alerts_vehicleId` ON `inventory_alerts` (`vehicleId`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_inventory_alerts_alertType` ON `inventory_alerts` (`alertType`)")
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_inventory_alerts_isRead` ON `inventory_alerts` (`isRead`)")
            }
        }

        val MIGRATION_6_7 = object : androidx.room.migration.Migration(6, 7) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE vehicles ADD COLUMN mileage INTEGER NOT NULL DEFAULT 0")
            }
        }

        val MIGRATION_7_8 = object : androidx.room.migration.Migration(7, 8) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE expenses ADD COLUMN receiptPath TEXT")
            }
        }
    }
}
