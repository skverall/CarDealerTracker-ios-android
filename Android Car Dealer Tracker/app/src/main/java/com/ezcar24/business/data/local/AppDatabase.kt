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

    @Query("UPDATE expenses SET userId = :newId WHERE userId = :oldId")
    suspend fun updateUserId(oldId: UUID, newId: UUID)

    @Query("UPDATE expenses SET accountId = :newId WHERE accountId = :oldId")
    suspend fun updateAccountId(oldId: UUID, newId: UUID)
}

@Dao
interface ClientDao : BaseDao<Client> {
    @Query("SELECT * FROM clients WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    fun getAllActive(): Flow<List<Client>>
    
    @Query("SELECT * FROM clients")
    suspend fun getAllIncludingDeleted(): List<Client>

    @Query("SELECT * FROM clients WHERE id = :id")
    suspend fun getById(id: UUID): Client?

    @Query("SELECT COUNT(*) FROM clients")
    suspend fun countAll(): Int
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
interface ClientInteractionDao : BaseDao<ClientInteraction> {
    @Query("SELECT * FROM client_interactions WHERE clientId = :clientId ORDER BY occurredAt DESC")
    suspend fun getByClient(clientId: UUID): List<ClientInteraction>

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

@Database(
    entities = [
        User::class, Vehicle::class, Expense::class, Sale::class, 
        Client::class, ClientInteraction::class, ClientReminder::class,
        FinancialAccount::class, AccountTransaction::class,
        Debt::class, DebtPayment::class, ExpenseTemplate::class,
        SyncQueueItem::class
    ],
    version = 2,
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
    
    companion object {
        val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE vehicles ADD COLUMN photoUrl TEXT")
            }
        }
    }
}
