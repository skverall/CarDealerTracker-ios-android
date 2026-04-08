package com.ezcar24.business.di

import android.content.Context
import android.content.SharedPreferences
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
    private const val SUPABASE_URL = "https://haordpdxyyreliyzmire.supabase.co"
    private const val SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhhb3JkcGR4eXlyZWxpeXptaXJlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwNzIxNTAsImV4cCI6MjA3MDY0ODE1MH0.3cc_tkF4So5g0JbbPLEiKlZ_3JyaqW6u_cxV6rxKFQg"

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
    fun provideSyncQueueManager(
        syncQueueDao: com.ezcar24.business.data.local.SyncQueueDao
    ): com.ezcar24.business.data.sync.SyncQueueManager {
        return com.ezcar24.business.data.sync.SyncQueueManagerImpl(syncQueueDao)
    }

    @Provides
    @Singleton
    fun provideWorkManagerConfiguration(
        @ApplicationContext context: Context
    ): androidx.work.Configuration {
        return androidx.work.Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()
    }
}
