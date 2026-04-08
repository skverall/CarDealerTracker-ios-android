package com.ezcar24.business.util

import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

enum class UserFacingErrorContext {
    LOAD_ACCOUNT,
    RUN_SYNC,
    SWITCH_BUSINESS,
    CREATE_BUSINESS,
    ACCEPT_TEAM_INVITE,
    SIGN_OUT,
    LOAD_TEAM,
    INVITE_TEAM_MEMBER,
    UPDATE_TEAM_ACCESS,
    REMOVE_TEAM_MEMBER,
    SAVE_CLIENT,
    SAVE_CLIENT_INTERACTION,
    DELETE_CLIENT_INTERACTION,
    SAVE_CLIENT_REMINDER,
    UPDATE_CLIENT_REMINDER,
    DELETE_CLIENT_REMINDER,
    UPDATE_CLIENT
}

object UserFacingErrorMapper {

    fun map(error: Throwable, context: UserFacingErrorContext): String {
        return map(error.messageBlob(), context)
    }

    fun map(message: String?, context: UserFacingErrorContext): String {
        val trimmed = message?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return fallback(context)
        }

        val normalized = trimmed.lowercase()

        return when {
            normalized.contains("unable to resolve host") ||
                normalized.contains("no address associated with hostname") ||
                normalized.contains("unknownhostexception") ->
                "No internet connection. Check your network and try again."

            normalized.contains("failed to connect") ||
                normalized.contains("network is unreachable") ||
                normalized.contains("connection refused") ||
                normalized.contains("timeout") ||
                normalized.contains("timed out") ||
                normalized.contains("software caused connection abort") ||
                normalized.contains("unable to receive data") ||
                normalized.contains("sockettimeoutexception") ||
                normalized.contains("connectexception") ||
                normalized.contains("sslexception") ->
                "Unable to reach the server right now. Try again in a moment."

            normalized.contains("please sign in") ||
                normalized.contains("jwt") ||
                normalized.contains("session missing") ||
                normalized.contains("invalid refresh token") ||
                normalized.contains("access token") ->
                "Please sign in again and try again."

            context.isTeamContext() &&
                (
                    normalized.contains("permission denied") ||
                        normalized.contains("row-level security") ||
                        normalized.contains("not allowed") ||
                        normalized.contains("forbidden")
                    ) ->
                "You do not have permission to manage team members."

            context == UserFacingErrorContext.ACCEPT_TEAM_INVITE &&
                (
                    normalized.contains("invalid") ||
                        normalized.contains("expired") ||
                        normalized.contains("revoked") ||
                        normalized.contains("mismatch")
                    ) ->
                "This invite is no longer valid. Ask for a new invite."

            context == UserFacingErrorContext.INVITE_TEAM_MEMBER &&
                (
                    normalized.contains("account already exists") ||
                        normalized.contains("already registered") ||
                        normalized.contains("user already registered") ||
                        normalized.contains("member already exists")
                    ) ->
                "Account already exists. Ask the member to sign in or reset their password."

            context == UserFacingErrorContext.CREATE_BUSINESS &&
                (
                    normalized.contains("already exists") ||
                        normalized.contains("duplicate key value") ||
                        normalized.contains("unique constraint")
                    ) ->
                "A business with this name already exists."

            normalized.contains("not found") ||
                normalized.contains("no rows") ||
                normalized.contains("does not exist") ->
                "This item is no longer available. Refresh and try again."

            looksTechnical(normalized) ->
                fallback(context)

            else -> trimmed
        }
    }

    private fun fallback(context: UserFacingErrorContext): String {
        return when (context) {
            UserFacingErrorContext.LOAD_ACCOUNT ->
                "We couldn't load your account right now. Please try again."

            UserFacingErrorContext.RUN_SYNC ->
                "Unable to sync right now. Check your network and try again."

            UserFacingErrorContext.SWITCH_BUSINESS ->
                "We couldn't switch businesses right now. Please try again."

            UserFacingErrorContext.CREATE_BUSINESS ->
                "We couldn't create the business right now. Please try again."

            UserFacingErrorContext.ACCEPT_TEAM_INVITE ->
                "We couldn't apply that invite right now. Please try again."

            UserFacingErrorContext.SIGN_OUT ->
                "We couldn't sign you out right now. Please try again."

            UserFacingErrorContext.LOAD_TEAM ->
                "We couldn't load the team right now. Please try again."

            UserFacingErrorContext.INVITE_TEAM_MEMBER ->
                "We couldn't send the invite right now. Please try again."

            UserFacingErrorContext.UPDATE_TEAM_ACCESS ->
                "We couldn't update access right now. Please try again."

            UserFacingErrorContext.REMOVE_TEAM_MEMBER ->
                "We couldn't remove this team member right now. Please try again."

            UserFacingErrorContext.SAVE_CLIENT ->
                "We couldn't save this client right now. Please try again."

            UserFacingErrorContext.SAVE_CLIENT_INTERACTION ->
                "We couldn't save this interaction right now. Please try again."

            UserFacingErrorContext.DELETE_CLIENT_INTERACTION ->
                "We couldn't delete this interaction right now. Please try again."

            UserFacingErrorContext.SAVE_CLIENT_REMINDER ->
                "We couldn't save this reminder right now. Please try again."

            UserFacingErrorContext.UPDATE_CLIENT_REMINDER ->
                "We couldn't update this reminder right now. Please try again."

            UserFacingErrorContext.DELETE_CLIENT_REMINDER ->
                "We couldn't delete this reminder right now. Please try again."

            UserFacingErrorContext.UPDATE_CLIENT ->
                "We couldn't update this client right now. Please try again."
        }
    }

    private fun looksTechnical(message: String): Boolean {
        return message.contains("supabase.co") ||
            message.contains("/auth/v1/") ||
            message.contains("/functions/v1/") ||
            message.contains("/rest/v1/") ||
            message.contains("http request to") ||
            message.contains("exception") ||
            message.contains("duplicate key value") ||
            message.contains("violates unique constraint") ||
            message.contains("row-level security") ||
            message.contains("<!doctype") ||
            message.contains("{\"")
    }

    private fun UserFacingErrorContext.isTeamContext(): Boolean {
        return this == UserFacingErrorContext.LOAD_TEAM ||
            this == UserFacingErrorContext.INVITE_TEAM_MEMBER ||
            this == UserFacingErrorContext.UPDATE_TEAM_ACCESS ||
            this == UserFacingErrorContext.REMOVE_TEAM_MEMBER
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

    if (this.hasCause<UnknownHostException>()) {
        messages += "unknownhostexception"
    }
    if (this.hasCause<ConnectException>()) {
        messages += "connectexception"
    }
    if (this.hasCause<SocketTimeoutException>()) {
        messages += "sockettimeoutexception"
    }
    if (this.hasCause<SSLException>()) {
        messages += "sslexception"
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
