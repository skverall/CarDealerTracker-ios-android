package com.ezcar24.business.data.repository

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import com.ezcar24.business.util.PermissionAccessState
import com.ezcar24.business.util.TeamPermissionCatalog

private const val PERMISSION_PREFS = "ezcar24_permissions"
private const val PERMISSION_CACHE_PREFIX = "permissions_cache_v1"
private const val ROLE_CACHE_PREFIX = "role_cache_v1"

@Singleton
class PermissionRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient
) {
    private val prefs = context.getSharedPreferences(PERMISSION_PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val lastFetchAtByDealerId = mutableMapOf<UUID, Date>()
    private val minimumFetchIntervalMs = 15_000L
    private val _state = MutableStateFlow(PermissionAccessState())

    val state = _state.asStateFlow()

    suspend fun activate(organization: OrganizationMembership?, force: Boolean = false) {
        if (organization == null) {
            reset()
            return
        }

        val dealerId = organization.organizationId
        val cachedPermissions = loadCachedPermissions(dealerId)
        val cachedRole = loadCachedRole(dealerId)
        val initialRole = cachedRole ?: organization.role
        val initialPermissions = cachedPermissions.orEmpty()
        _state.value = PermissionAccessState(
            dealerId = dealerId,
            permissions = initialPermissions,
            role = initialRole,
            didLoad = initialPermissions.isNotEmpty() || initialRole.isNotBlank(),
            isLoading = initialPermissions.isEmpty()
        )

        if (!force && !shouldFetch(dealerId)) {
            _state.value = _state.value.copy(isLoading = false)
            return
        }

        fetchRemoteAccess(dealerId, organization.role)
    }

    suspend fun refresh() {
        val current = _state.value
        val dealerId = current.dealerId ?: return
        fetchRemoteAccess(dealerId, current.role)
    }

    fun reset() {
        _state.value = PermissionAccessState()
        lastFetchAtByDealerId.clear()
    }

    private fun shouldFetch(dealerId: UUID): Boolean {
        val lastFetchAt = lastFetchAtByDealerId[dealerId] ?: return true
        return Date().time - lastFetchAt.time >= minimumFetchIntervalMs
    }

    private suspend fun fetchRemoteAccess(dealerId: UUID, fallbackRole: String) = withContext(Dispatchers.IO) {
        _state.value = _state.value.copy(isLoading = true)
        val permissions = runCatching { fetchPermissions(dealerId) }.getOrNull()
        val role = runCatching { fetchRole(dealerId) }.getOrNull() ?: fallbackRole

        if (permissions != null) {
            cachePermissions(dealerId, permissions)
        }
        if (role.isNotBlank()) {
            cacheRole(dealerId, role)
        }

        val resolved = if (role.isNotBlank()) {
            TeamPermissionCatalog.resolvedPermissions(permissions, role)
        } else {
            permissions.orEmpty()
        }

        _state.value = PermissionAccessState(
            dealerId = dealerId,
            permissions = resolved,
            role = role,
            didLoad = resolved.isNotEmpty() || role.isNotBlank(),
            isLoading = false
        )
        lastFetchAtByDealerId[dealerId] = Date()
    }

    private suspend fun fetchPermissions(dealerId: UUID): Map<String, Boolean> {
        val params = buildJsonObject {
            put("_org_id", dealerId.toString())
        }
        val result = client.postgrest.rpc("get_my_permissions", params)
        return json.decodeFromString(result.data)
    }

    private suspend fun fetchRole(dealerId: UUID): String {
        val params = buildJsonObject {
            put("_org_id", dealerId.toString())
        }
        val result = client.postgrest.rpc("get_my_role", params)
        return json.decodeFromString(result.data)
    }

    private fun loadCachedPermissions(dealerId: UUID): Map<String, Boolean>? {
        val raw = prefs.getString(cacheKey(PERMISSION_CACHE_PREFIX, dealerId), null) ?: return null
        return runCatching { json.decodeFromString<Map<String, Boolean>>(raw) }.getOrNull()
    }

    private fun loadCachedRole(dealerId: UUID): String? {
        return prefs.getString(cacheKey(ROLE_CACHE_PREFIX, dealerId), null)
    }

    private fun cachePermissions(dealerId: UUID, permissions: Map<String, Boolean>) {
        prefs.edit()
            .putString(cacheKey(PERMISSION_CACHE_PREFIX, dealerId), json.encodeToString(permissions))
            .apply()
    }

    private fun cacheRole(dealerId: UUID, role: String) {
        prefs.edit()
            .putString(cacheKey(ROLE_CACHE_PREFIX, dealerId), role)
            .apply()
    }

    private fun cacheKey(prefix: String, dealerId: UUID): String {
        return "${prefix}_${dealerId.toString().lowercase()}"
    }
}
