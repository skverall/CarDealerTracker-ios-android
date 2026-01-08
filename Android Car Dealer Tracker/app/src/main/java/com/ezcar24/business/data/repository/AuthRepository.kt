package com.ezcar24.business.data.repository

import android.net.Uri
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val client: SupabaseClient
) {
    val sessionStatus = client.auth.sessionStatus

    suspend fun awaitInitialization() {
        client.auth.awaitInitialization()
    }

    suspend fun login(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signUp(email: String, password: String) {
        client.auth.signUpWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun resetPassword(email: String) {
        client.auth.resetPasswordForEmail(
            email = email,
            redirectUrl = "ezcar24business://reset-password"
        )
    }

    suspend fun updatePassword(newPassword: String) {
        client.auth.updateUser {
            password = newPassword
        }
    }

    suspend fun handleDeepLink(uri: Uri): Boolean {
        val uriString = uri.toString()
        // Check if this is a password recovery deep-link
        return uriString.contains("type=recovery") || 
               uriString.contains("reset-password")
    }

    suspend fun signOut() {
        client.auth.signOut()
    }
    
    fun getCurrentUser() = client.auth.currentUserOrNull()

    suspend fun getDealerId(): String? {
        val user = client.auth.currentUserOrNull() ?: return null
        return user.id
    }
}
