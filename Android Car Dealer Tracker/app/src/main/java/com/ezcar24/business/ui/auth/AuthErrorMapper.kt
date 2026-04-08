package com.ezcar24.business.ui.auth

import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

enum class AuthFailureContext {
    SIGN_IN,
    SIGN_UP,
    PASSWORD_RESET_REQUEST,
    PASSWORD_RESET_COMPLETE,
    PASSWORD_CHANGE
}

object AuthErrorMapper {

    fun map(error: Throwable, context: AuthFailureContext): String {
        val messageBlob = error.messageBlob()

        return when {
            error.hasCause<UnknownHostException>() ||
                messageBlob.contains("unable to resolve host") ||
                messageBlob.contains("no address associated with hostname") ->
                "No internet connection. Check your network and try again."

            error.hasCause<ConnectException>() ||
                error.hasCause<SocketTimeoutException>() ||
                error.hasCause<SSLException>() ||
                messageBlob.contains("failed to connect") ||
                messageBlob.contains("network is unreachable") ||
                messageBlob.contains("connection refused") ||
                messageBlob.contains("timeout") ||
                messageBlob.contains("timed out") ||
                messageBlob.contains("software caused connection abort") ||
                messageBlob.contains("unable to receive data") ->
                "Unable to reach the server right now. Try again in a moment."

            messageBlob.contains("invalid login credentials") ||
                messageBlob.contains("invalid credentials") ||
                messageBlob.contains("invalid grant") ||
                messageBlob.contains("email or password is incorrect") ->
                "Invalid email or password."

            messageBlob.contains("email not confirmed") ||
                messageBlob.contains("confirm your email") ->
                "Please confirm your email before signing in."

            messageBlob.contains("user already registered") ||
                messageBlob.contains("already registered") ||
                messageBlob.contains("account already exists") ->
                "This email is already registered. Sign in or reset your password."

            messageBlob.contains("invalid email") ||
                messageBlob.contains("email format") ||
                messageBlob.contains("email_address_invalid") ->
                "Enter a valid email address."

            messageBlob.contains("password should be at least") ||
                messageBlob.contains("weak password") ||
                messageBlob.contains("password is too short") ->
                "Password must be at least 6 characters long."

            messageBlob.contains("signup is disabled") ||
                messageBlob.contains("signups not allowed") ||
                messageBlob.contains("sign-up disabled") ->
                "New account creation is unavailable right now. Try again later."

            messageBlob.contains("too many requests") ||
                messageBlob.contains("rate limit") ||
                messageBlob.contains("over request rate limit") ||
                messageBlob.contains("for security purposes") ->
                "Too many attempts. Please wait a moment and try again."

            context == AuthFailureContext.PASSWORD_RESET_COMPLETE &&
                (
                    messageBlob.contains("recovery session") ||
                        messageBlob.contains("session missing") ||
                        messageBlob.contains("refresh token not found") ||
                        messageBlob.contains("flow state")
                    ) ->
                "Your password reset link has expired. Request a new one."

            messageBlob.contains("supabase.co") ||
                messageBlob.contains("/auth/v1/") ||
                messageBlob.contains("http request to") ->
                fallback(context)

            else -> fallback(context)
        }
    }

    private fun fallback(context: AuthFailureContext): String {
        return when (context) {
            AuthFailureContext.SIGN_IN ->
                "We couldn't sign you in right now. Please try again."

            AuthFailureContext.SIGN_UP ->
                "We couldn't create your account right now. Please try again."

            AuthFailureContext.PASSWORD_RESET_REQUEST ->
                "We couldn't send the reset email right now. Please try again."

            AuthFailureContext.PASSWORD_RESET_COMPLETE ->
                "We couldn't update your password right now. Please try again."

            AuthFailureContext.PASSWORD_CHANGE ->
                "We couldn't update your password right now. Please try again."
        }
    }
}

private fun Throwable.messageBlob(): String {
    val messages = mutableListOf<String>()
    var current: Throwable? = this

    while (current != null) {
        current.message?.takeIf { it.isNotBlank() }?.let(messages::add)
        current.localizedMessage
            ?.takeIf { it.isNotBlank() && it != current.message }
            ?.let(messages::add)
        current = current.cause
    }

    return messages.joinToString(" | ").lowercase()
}

private inline fun <reified T : Throwable> Throwable.hasCause(): Boolean {
    var current: Throwable? = this
    while (current != null) {
        if (current is T) {
            return true
        }
        current = current.cause
    }
    return false
}
