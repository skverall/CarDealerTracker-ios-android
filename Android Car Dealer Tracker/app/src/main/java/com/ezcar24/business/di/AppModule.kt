package com.ezcar24.business.di

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import com.ezcar24.business.data.local.AppDatabase
import com.ezcar24.business.data.local.ClientDao
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.UserDao
import com.ezcar24.business.data.local.VehicleDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import com.russhwolf.settings.SharedPreferencesSettings
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.SettingsSessionManager
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.serializer.JacksonSerializer
import io.github.jan.supabase.storage.Storage
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    // Ideally move to BuildConfig
    private const val SUPABASE_URL = "https://ltjjzamyclmjaavxmyug.supabase.co"
    private const val SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx0amp6YW15Y2xtamFhdnhteXVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc4OTUxNTMsImV4cCI6MjA4MzQ3MTE1M30.HX0yFl47XKMdVo5OD5tYuvyCvw5uS4pCutpql1Jmzo0"

    @Provides
    @Singleton
    fun provideSupabaseClient(@ApplicationContext context: Context): SupabaseClient {
        val settings = SharedPreferencesSettings.Factory(context).create("ezcar24_supabase")
        val sessionManager = SettingsSessionManager(settings = settings, key = "auth_session")

        return createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_KEY
        ) {
            install(Auth) {
                this.sessionManager = sessionManager
                autoLoadFromStorage = true
                autoSaveToStorage = true
                enableLifecycleCallbacks = true
            }
            install(Postgrest)
            install(Storage)
            // defaultSerializer = JacksonSerializer() // Or KotlinX
        }
    }

    @Provides
    @Singleton
    fun provideSyncPreferences(@ApplicationContext context: Context): SharedPreferences {
        return context.getSharedPreferences("ezcar24_sync", Context.MODE_PRIVATE)
    }

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "ezcar24_business.db"
        )
        .fallbackToDestructiveMigration() // For development speed
        .addMigrations(AppDatabase.MIGRATION_1_2)
        .build()
    }

    @Provides
    @Singleton
    fun provideVehicleDao(db: AppDatabase): VehicleDao = db.vehicleDao()

    @Provides
    @Singleton
    fun provideExpenseDao(db: AppDatabase): ExpenseDao = db.expenseDao()

    @Provides
    @Singleton
    fun provideClientDao(db: AppDatabase): ClientDao = db.clientDao()

    @Provides
    @Singleton
    fun provideUserDao(db: AppDatabase): UserDao = db.userDao()

    @Provides
    @Singleton
    fun provideFinancialAccountDao(db: AppDatabase): FinancialAccountDao = db.financialAccountDao()

    @Provides
    @Singleton
    fun provideSyncQueueDao(db: AppDatabase): com.ezcar24.business.data.local.SyncQueueDao = db.syncQueueDao()

    @Provides
    @Singleton
    fun provideSyncQueueManager(
        syncQueueDao: com.ezcar24.business.data.local.SyncQueueDao
    ): com.ezcar24.business.data.sync.SyncQueueManager {
        return com.ezcar24.business.data.sync.SyncQueueManagerImpl(syncQueueDao)
    }

    @Provides
    @Singleton
    fun provideSaleDao(db: AppDatabase): com.ezcar24.business.data.local.SaleDao = db.saleDao()

    @Provides
    @Singleton
    fun provideDebtDao(db: AppDatabase): com.ezcar24.business.data.local.DebtDao = db.debtDao()

    @Provides
    @Singleton
    fun provideDebtPaymentDao(db: AppDatabase): com.ezcar24.business.data.local.DebtPaymentDao = db.debtPaymentDao()

    @Provides
    @Singleton
    fun provideAccountTransactionDao(db: AppDatabase): com.ezcar24.business.data.local.AccountTransactionDao = db.accountTransactionDao()

    @Provides
    @Singleton
    fun provideExpenseTemplateDao(db: AppDatabase): com.ezcar24.business.data.local.ExpenseTemplateDao = db.expenseTemplateDao()

    @Provides
    @Singleton
    fun provideClientInteractionDao(db: AppDatabase): com.ezcar24.business.data.local.ClientInteractionDao = db.clientInteractionDao()

    @Provides
    @Singleton
    fun provideClientReminderDao(db: AppDatabase): com.ezcar24.business.data.local.ClientReminderDao = db.clientReminderDao()
}
