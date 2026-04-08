package com.ezcar24.business.ui.auth

import org.junit.Assert.assertEquals
import org.junit.Test
import java.net.UnknownHostException

class AuthErrorMapperTest {

    @Test
    fun `map returns no internet message for unknown host failures`() {
        val error = IllegalStateException(
            "HTTP request to https://haordpdxyyreliyzmire.supabase.co/auth/v1/token failed",
            UnknownHostException("Unable to resolve host haordpdxyyreliyzmire.supabase.co")
        )

        val message = AuthErrorMapper.map(error, AuthFailureContext.SIGN_IN)

        assertEquals(
            "No internet connection. Check your network and try again.",
            message
        )
    }

    @Test
    fun `map returns invalid credentials message for sign in auth errors`() {
        val error = IllegalStateException("Invalid login credentials")

        val message = AuthErrorMapper.map(error, AuthFailureContext.SIGN_IN)

        assertEquals("Invalid email or password.", message)
    }

    @Test
    fun `map returns already registered message for duplicate sign up`() {
        val error = IllegalStateException("User already registered")

        val message = AuthErrorMapper.map(error, AuthFailureContext.SIGN_UP)

        assertEquals(
            "This email is already registered. Sign in or reset your password.",
            message
        )
    }

    @Test
    fun `map returns expired recovery message for reset completion failures`() {
        val error = IllegalStateException("Auth recovery session missing")

        val message = AuthErrorMapper.map(error, AuthFailureContext.PASSWORD_RESET_COMPLETE)

        assertEquals("Your password reset link has expired. Request a new one.", message)
    }

    @Test
    fun `map hides raw supabase request details behind a generic message`() {
        val error = IllegalStateException(
            "HTTP request to https://haordpdxyyreliyzmire.supabase.co/auth/v1/token?grant_type=password failed"
        )

        val message = AuthErrorMapper.map(error, AuthFailureContext.SIGN_UP)

        assertEquals(
            "We couldn't create your account right now. Please try again.",
            message
        )
    }

    @Test
    fun `map returns password change fallback for generic password update failures`() {
        val error = IllegalStateException("Unexpected upstream failure")

        val message = AuthErrorMapper.map(error, AuthFailureContext.PASSWORD_CHANGE)

        assertEquals(
            "We couldn't update your password right now. Please try again.",
            message
        )
    }
}
