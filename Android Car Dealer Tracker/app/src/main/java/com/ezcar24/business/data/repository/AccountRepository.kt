package com.ezcar24.business.data.repository

import android.content.Context
import android.util.Log
import com.ezcar24.business.data.images.ImageStore
import com.ezcar24.business.data.local.ActiveDatabaseProvider
import com.ezcar24.business.data.sync.CloudSyncEnvironment
import com.ezcar24.business.data.sync.CloudSyncManager
import com.ezcar24.business.util.TeamPermissionCatalog
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val ACCOUNT_PREFS = "ezcar24_account"
private const val ACTIVE_ORGANIZATION_KEY_PREFIX = "activeOrganization"
private const val SUPABASE_URL = "https://haordpdxyyreliyzmire.supabase.co"
private const val ACCOUNT_TAG = "AccountRepository"

data class OrganizationMembership(
    val organizationId: UUID,
    val organizationName: String,
    val role: String,
    val status: String
)

data class ReferralStats(
    val totalRewards: Int,
    val lastRewardedAt: Date?,
    val bonusAccessUntil: Date?,
    val totalMonths: Int
)

data class TeamMemberAccess(
    val id: UUID,
    val role: String,
    val status: String,
    val email: String?,
    val inviteToken: String?,
    val permissions: Map<String, Boolean>
) {
    val isInvited: Boolean
        get() = status.equals("invited", ignoreCase = true)

    val canEditRole: Boolean
        get() = !role.equals("owner", ignoreCase = true)
}

data class TeamInviteResult(
    val inviteCode: String?,
    val inviteUrl: String?,
    val generatedPassword: String?,
    val existingUser: Boolean,
    val message: String?
)

@Serializable
private data class OrganizationMembershipDto(
    @SerialName("organization_id") val organizationId: String,
    @SerialName("organization_name") val organizationName: String,
    val role: String,
    val status: String
)

@Serializable
private data class ReferralStatsDto(
    @SerialName("total_rewards") val totalRewards: Int? = null,
    @SerialName("last_rewarded_at") val lastRewardedAt: String? = null,
    @SerialName("bonus_access_until") val bonusAccessUntil: String? = null,
    @SerialName("total_months") val totalMonths: Int? = null
)

@Serializable
private data class TeamMemberAccessDto(
    @SerialName("user_id") val userId: String,
    val role: String,
    val status: String,
    @SerialName("member_email") val memberEmail: String? = null,
    @SerialName("invite_token") val inviteToken: String? = null,
    val permissions: Map<String, Boolean> = emptyMap()
)

@Serializable
private data class TeamInviteRequest(
    val email: String,
    val role: String,
    val language: String,
    val permissions: Map<String, Boolean>,
    @SerialName("create_account") val createAccount: Boolean,
    @SerialName("organization_id") val organizationId: String
)

@Serializable
private data class TeamInviteResultDto(
    val success: Boolean = false,
    @SerialName("generated_password") val generatedPassword: String? = null,
    @SerialName("existing_user") val existingUser: Boolean? = null,
    @SerialName("invite_code") val inviteCode: String? = null,
    @SerialName("invite_url") val inviteUrl: String? = null,
    val message: String? = null
)

@Serializable
private data class AccountFunctionErrorPayload(
    val error: String? = null
)

@Singleton
class AccountRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
    private val databaseProvider: ActiveDatabaseProvider,
    private val imageStore: ImageStore,
    private val cloudSyncManager: CloudSyncManager
) {
    private val prefs = context.getSharedPreferences(ACCOUNT_PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val _organizations = MutableStateFlow<List<OrganizationMembership>>(emptyList())
    private val _activeOrganization = MutableStateFlow<OrganizationMembership?>(null)

    val organizations = _organizations.asStateFlow()
    val activeOrganization = _activeOrganization.asStateFlow()

    suspend fun bootstrapActiveOrganization(): UUID? = withContext(Dispatchers.IO) {
        val user = client.auth.currentUserOrNull() ?: return@withContext clearAndReturnNull()
        val userId = runCatching { UUID.fromString(user.id) }.getOrNull() ?: return@withContext clearAndReturnNull()
        ensurePersonalOrganization()
        val organizations = fetchOrganizationsFromServer()
        val active = resolveActiveOrganization(userId, organizations)
        _organizations.value = organizations
        _activeOrganization.value = active
        CloudSyncEnvironment.currentDealerId = active?.organizationId
        active?.organizationId
    }

    suspend fun refreshOrganizations(): List<OrganizationMembership> = withContext(Dispatchers.IO) {
        val user = client.auth.currentUserOrNull() ?: return@withContext clearAndReturnEmpty()
        val userId = runCatching { UUID.fromString(user.id) }.getOrNull() ?: return@withContext clearAndReturnEmpty()
        ensurePersonalOrganization()
        val organizations = fetchOrganizationsFromServer()
        val active = resolveActiveOrganization(userId, organizations)
        _organizations.value = organizations
        _activeOrganization.value = active
        CloudSyncEnvironment.currentDealerId = active?.organizationId
        organizations
    }

    suspend fun createOrganization(name: String): OrganizationMembership = withContext(Dispatchers.IO) {
        val normalizedName = name.trim()
        require(normalizedName.isNotEmpty()) { "Business name is required." }

        val params = buildJsonObject {
            put("_name", normalizedName)
        }
        val result = client.postgrest.rpc("create_organization", params)
        val organizationId = UUID.fromString(json.decodeFromString<String>(result.data))
        val organizations = refreshOrganizations()
        val created = organizations.firstOrNull { it.organizationId == organizationId }
            ?: OrganizationMembership(
                organizationId = organizationId,
                organizationName = normalizedName,
                role = "owner",
                status = "active"
            )
        switchOrganization(organizationId, forceSync = true)
        created
    }

    suspend fun switchOrganization(organizationId: UUID, forceSync: Boolean): OrganizationMembership? = withContext(Dispatchers.IO) {
        val user = client.auth.currentUserOrNull() ?: return@withContext null
        val userId = runCatching { UUID.fromString(user.id) }.getOrNull() ?: return@withContext null
        val organizations = if (_organizations.value.isEmpty()) refreshOrganizations() else _organizations.value
        val active = organizations.firstOrNull { it.organizationId == organizationId } ?: return@withContext null
        persistActiveOrganizationId(userId, organizationId)
        _activeOrganization.value = active
        CloudSyncEnvironment.currentDealerId = organizationId
        if (forceSync) {
            cloudSyncManager.refreshLastSyncForCurrentOrg()
            cloudSyncManager.syncAfterLogin(organizationId)
        }
        active
    }

    suspend fun getDealerReferralCode(dealerId: UUID): String? = withContext(Dispatchers.IO) {
        runCatching {
            val params = buildJsonObject {
                put("p_dealer_id", dealerId.toString())
            }
            val result = client.postgrest.rpc("get_or_create_dealer_referral_code", params)
            json.decodeFromString<String>(result.data)
        }.getOrNull()
    }

    suspend fun getReferralStats(): ReferralStats? = withContext(Dispatchers.IO) {
        runCatching {
            val result = client.postgrest.rpc("get_referral_stats")
            val stats = json.decodeFromString<List<ReferralStatsDto>>(result.data).firstOrNull()
            stats?.toModel()
        }.getOrNull()
    }

    suspend fun fetchTeamMembers(organizationId: UUID?): List<TeamMemberAccess> = withContext(Dispatchers.IO) {
        val result = if (organizationId == null) {
            client.postgrest.rpc("get_team_members_secure")
        } else {
            val params = buildJsonObject {
                put("_org_id", organizationId.toString())
            }
            client.postgrest.rpc("get_team_members_secure", params)
        }
        json.decodeFromString<List<TeamMemberAccessDto>>(result.data)
            .mapNotNull { it.toModel() }
            .sortedWith(
                compareBy<TeamMemberAccess> { it.isInvited }
                    .thenBy { it.role != "owner" }
                    .thenBy { it.email.orEmpty().lowercase(Locale.US) }
            )
    }

    suspend fun inviteMember(
        email: String,
        role: String,
        organizationId: UUID,
        createAccount: Boolean,
        permissions: Map<String, Boolean>
    ): TeamInviteResult = withContext(Dispatchers.IO) {
        val accessToken = client.auth.currentAccessTokenOrNull()
            ?: throw IllegalStateException("Please sign in to invite team members.")
        val request = TeamInviteRequest(
            email = email.trim(),
            role = role.lowercase(Locale.US),
            language = Locale.getDefault().language.ifBlank { "en" },
            permissions = TeamPermissionCatalog.resolvedPermissions(permissions, role),
            createAccount = createAccount,
            organizationId = organizationId.toString()
        )
        val connection = (URL("$SUPABASE_URL/functions/v1/invite_member").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doInput = true
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("Content-Type", "application/json")
        }

        try {
            connection.outputStream.bufferedWriter().use { writer ->
                writer.write(json.encodeToString(request))
            }

            val statusCode = connection.responseCode
            val body = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode !in 200..299) {
                throw IllegalStateException(parseFunctionError(body))
            }

            val payload = json.decodeFromString<TeamInviteResultDto>(body)
            TeamInviteResult(
                inviteCode = payload.inviteCode,
                inviteUrl = payload.inviteUrl,
                generatedPassword = payload.generatedPassword,
                existingUser = payload.existingUser == true,
                message = payload.message
            )
        } finally {
            connection.disconnect()
        }
    }

    suspend fun updateMemberRole(
        organizationId: UUID,
        memberId: UUID,
        role: String,
        permissions: Map<String, Boolean>
    ) = withContext(Dispatchers.IO) {
        val params = buildJsonObject {
            put("_org_id", organizationId.toString())
            put("_member_id", memberId.toString())
            put("_role", role.lowercase(Locale.US))
            put("_permissions", permissionsJson(role, permissions))
        }
        client.postgrest.rpc("update_team_member_access", params)
    }

    suspend fun updateInviteRole(
        organizationId: UUID,
        inviteId: UUID,
        role: String,
        permissions: Map<String, Boolean>
    ) = withContext(Dispatchers.IO) {
        val params = buildJsonObject {
            put("_org_id", organizationId.toString())
            put("_invite_id", inviteId.toString())
            put("_role", role.lowercase(Locale.US))
            put("_permissions", permissionsJson(role, permissions))
        }
        client.postgrest.rpc("update_team_invite_access", params)
    }

    suspend fun removeMember(
        organizationId: UUID,
        memberId: UUID
    ) = withContext(Dispatchers.IO) {
        client.postgrest.from("dealer_team_members").delete {
            filter {
                eq("organization_id", organizationId.toString())
                eq("user_id", memberId.toString())
            }
        }
    }

    suspend fun cancelInvite(
        organizationId: UUID,
        inviteId: UUID
    ) = withContext(Dispatchers.IO) {
        client.postgrest.from("team_invitations").delete {
            filter {
                eq("organization_id", organizationId.toString())
                eq("id", inviteId.toString())
            }
        }
    }

    fun clearSessionState() {
        _organizations.value = emptyList()
        _activeOrganization.value = null
        CloudSyncEnvironment.currentDealerId = null
    }

    suspend fun clearLocalData() = withContext(Dispatchers.IO) {
        databaseProvider.clearAllStores()
        imageStore.clearAll()
        cloudSyncManager.clearAllSyncState()
    }

    private suspend fun ensurePersonalOrganization() {
        runCatching {
            client.postgrest.rpc("ensure_personal_organization")
        }.onFailure {
            Log.w(ACCOUNT_TAG, "ensurePersonalOrganization failed", it)
        }
    }

    private suspend fun fetchOrganizationsFromServer(): List<OrganizationMembership> {
        val result = client.postgrest.rpc("get_my_organizations")
        return json.decodeFromString<List<OrganizationMembershipDto>>(result.data)
            .mapNotNull { dto ->
                runCatching {
                    OrganizationMembership(
                        organizationId = UUID.fromString(dto.organizationId),
                        organizationName = dto.organizationName,
                        role = dto.role,
                        status = dto.status
                    )
                }.getOrNull()
            }
    }

    private fun resolveActiveOrganization(
        userId: UUID,
        organizations: List<OrganizationMembership>
    ): OrganizationMembership? {
        if (organizations.isEmpty()) {
            persistActiveOrganizationId(userId, null)
            return null
        }

        val stored = restoreActiveOrganizationId(userId)
        if (stored != null) {
            organizations.firstOrNull { it.organizationId == stored }?.let { return it }
        }

        organizations.firstOrNull { it.organizationId == userId }?.let {
            persistActiveOrganizationId(userId, it.organizationId)
            return it
        }

        return organizations.firstOrNull()?.also {
            persistActiveOrganizationId(userId, it.organizationId)
        }
    }

    private fun permissionsJson(role: String, permissions: Map<String, Boolean>): JsonObject {
        return JsonObject(
            TeamPermissionCatalog.resolvedPermissions(permissions, role).mapValues { JsonPrimitive(it.value) }
        )
    }

    private fun parseFunctionError(body: String): String {
        return runCatching {
            json.decodeFromString<AccountFunctionErrorPayload>(body).error?.trim()
        }.getOrNull().takeUnless { it.isNullOrEmpty() } ?: body.ifBlank { "Unexpected error" }
    }

    private fun persistActiveOrganizationId(userId: UUID, organizationId: UUID?) {
        val key = activeOrganizationKey(userId)
        prefs.edit().apply {
            if (organizationId == null) {
                remove(key)
            } else {
                putString(key, organizationId.toString())
            }
        }.apply()
    }

    private fun restoreActiveOrganizationId(userId: UUID): UUID? {
        val raw = prefs.getString(activeOrganizationKey(userId), null) ?: return null
        return runCatching { UUID.fromString(raw) }.getOrNull()
    }

    private fun activeOrganizationKey(userId: UUID): String {
        return "${ACTIVE_ORGANIZATION_KEY_PREFIX}_$userId"
    }

    private fun clearAndReturnNull(): UUID? {
        clearSessionState()
        return null
    }

    private fun clearAndReturnEmpty(): List<OrganizationMembership> {
        clearSessionState()
        return emptyList()
    }

    private fun ReferralStatsDto.toModel(): ReferralStats {
        return ReferralStats(
            totalRewards = totalRewards ?: 0,
            lastRewardedAt = lastRewardedAt.toDateOrNull(),
            bonusAccessUntil = bonusAccessUntil.toDateOrNull(),
            totalMonths = totalMonths ?: 0
        )
    }

    private fun TeamMemberAccessDto.toModel(): TeamMemberAccess? {
        val uuid = runCatching { UUID.fromString(userId) }.getOrNull() ?: return null
        return TeamMemberAccess(
            id = uuid,
            role = role,
            status = status,
            email = memberEmail,
            inviteToken = inviteToken,
            permissions = permissions
        )
    }
}

private fun String?.toDateOrNull(): Date? {
    val value = this?.trim().orEmpty()
    if (value.isEmpty()) return null
    return runCatching { Date.from(Instant.parse(value)) }.getOrNull()
}
