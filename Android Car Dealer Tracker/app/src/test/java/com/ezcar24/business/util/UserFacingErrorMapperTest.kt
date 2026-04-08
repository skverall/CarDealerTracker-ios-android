package com.ezcar24.business.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.net.UnknownHostException

class UserFacingErrorMapperTest {

    @Test
    fun `map returns no internet message for network failures`() {
        val error = IllegalStateException(
            "HTTP request to https://haordpdxyyreliyzmire.supabase.co/functions/v1/invite_member failed",
            UnknownHostException("Unable to resolve host haordpdxyyreliyzmire.supabase.co")
        )

        val message = UserFacingErrorMapper.map(error, UserFacingErrorContext.LOAD_ACCOUNT)

        assertEquals(
            "No internet connection. Check your network and try again.",
            message
        )
    }

    @Test
    fun `map returns duplicate business name message`() {
        val message = UserFacingErrorMapper.map(
            "duplicate key value violates unique constraint \"organizations_name_key\"",
            UserFacingErrorContext.CREATE_BUSINESS
        )

        assertEquals("A business with this name already exists.", message)
    }

    @Test
    fun `map returns existing account message for team invites`() {
        val message = UserFacingErrorMapper.map(
            "User already registered",
            UserFacingErrorContext.INVITE_TEAM_MEMBER
        )

        assertEquals(
            "Account already exists. Ask the member to sign in or reset their password.",
            message
        )
    }

    @Test
    fun `map returns invalid invite message for expired invites`() {
        val message = UserFacingErrorMapper.map(
            "Invite code expired",
            UserFacingErrorContext.ACCEPT_TEAM_INVITE
        )

        assertEquals("This invite is no longer valid. Ask for a new invite.", message)
    }

    @Test
    fun `map returns permission denied message for team management`() {
        val message = UserFacingErrorMapper.map(
            "permission denied for table dealer_team_members",
            UserFacingErrorContext.UPDATE_TEAM_ACCESS
        )

        assertEquals("You do not have permission to manage team members.", message)
    }

    @Test
    fun `map hides raw backend details for client updates`() {
        val message = UserFacingErrorMapper.map(
            "HTTP request to https://haordpdxyyreliyzmire.supabase.co/rest/v1/clients failed",
            UserFacingErrorContext.UPDATE_CLIENT
        )

        assertEquals(
            "We couldn't update this client right now. Please try again.",
            message
        )
    }
}
