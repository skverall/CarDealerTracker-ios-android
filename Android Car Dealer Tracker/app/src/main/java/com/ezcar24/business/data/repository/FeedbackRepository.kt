package com.ezcar24.business.data.repository

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import java.time.Instant
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

data class AppFeedbackRequest(
    val id: UUID,
    val title: String,
    val details: String?,
    val status: String,
    val voteCount: Int,
    val hasVoted: Boolean,
    val isMine: Boolean,
    val canDelete: Boolean,
    val canAdmin: Boolean,
    val completedAt: Date?,
    val createdAt: Date
)

data class AppFeedbackVoteResult(
    val voted: Boolean,
    val voteCount: Int
)

data class AppFeedbackStatusResult(
    val id: UUID,
    val status: String,
    val completedAt: Date?
)

@Singleton
class FeedbackRepository @Inject constructor(
    private val client: SupabaseClient
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchRequests(limit: Int = 100): List<AppFeedbackRequest> = withContext(Dispatchers.IO) {
        requireSignedIn()
        val params = buildJsonObject {
            put("p_limit", limit.coerceIn(1, 100))
        }
        val result = client.postgrest.rpc("get_app_feedback_requests", params)
        json.decodeFromString<List<AppFeedbackRequestDto>>(result.data)
            .map { it.toModel() }
    }

    suspend fun createRequest(
        title: String,
        details: String?,
        platform: String,
        language: String?
    ) = withContext(Dispatchers.IO) {
        requireSignedIn()
        val trimmedDetails = details?.trim().orEmpty()
        val trimmedLanguage = language?.trim().orEmpty()
        val params = buildJsonObject {
            put("p_title", title.trim())
            if (trimmedDetails.isEmpty()) {
                put("p_details", JsonNull)
            } else {
                put("p_details", trimmedDetails)
            }
            put("p_platform", platform)
            if (trimmedLanguage.isEmpty()) {
                put("p_language", JsonNull)
            } else {
                put("p_language", trimmedLanguage)
            }
        }
        client.postgrest.rpc("create_app_feedback_request", params)
    }

    suspend fun toggleVote(requestId: UUID): AppFeedbackVoteResult? = withContext(Dispatchers.IO) {
        requireSignedIn()
        val params = buildJsonObject {
            put("p_request_id", requestId.toString())
        }
        val result = client.postgrest.rpc("toggle_app_feedback_vote", params)
        json.decodeFromString<List<AppFeedbackVoteResultDto>>(result.data)
            .firstOrNull()
            ?.toModel()
    }

    suspend fun deleteRequest(requestId: UUID) = withContext(Dispatchers.IO) {
        requireSignedIn()
        val params = buildJsonObject {
            put("p_request_id", requestId.toString())
        }
        client.postgrest.rpc("delete_app_feedback_request", params)
    }

    suspend fun setStatus(requestId: UUID, status: String): AppFeedbackStatusResult? = withContext(Dispatchers.IO) {
        requireSignedIn()
        val params = buildJsonObject {
            put("p_request_id", requestId.toString())
            put("p_status", status)
        }
        val result = client.postgrest.rpc("set_app_feedback_status", params)
        json.decodeFromString<List<AppFeedbackStatusResultDto>>(result.data)
            .firstOrNull()
            ?.toModel()
    }

    private fun requireSignedIn() {
        check(client.auth.currentUserOrNull() != null) {
            "Please sign in to share ideas and vote."
        }
    }
}

@Serializable
private data class AppFeedbackRequestDto(
    val id: String,
    val title: String,
    val details: String? = null,
    val status: String = "open",
    @SerialName("vote_count") val voteCount: Int = 0,
    @SerialName("has_voted") val hasVoted: Boolean = false,
    @SerialName("is_mine") val isMine: Boolean = false,
    @SerialName("can_delete") val canDelete: Boolean = false,
    @SerialName("can_admin") val canAdmin: Boolean = false,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("created_at") val createdAt: String
) {
    fun toModel(): AppFeedbackRequest {
        return AppFeedbackRequest(
            id = UUID.fromString(id),
            title = title,
            details = details,
            status = status,
            voteCount = voteCount,
            hasVoted = hasVoted,
            isMine = isMine,
            canDelete = canDelete,
            canAdmin = canAdmin,
            completedAt = completedAt?.let { Date.from(Instant.parse(it)) },
            createdAt = Date.from(Instant.parse(createdAt))
        )
    }
}

@Serializable
private data class AppFeedbackVoteResultDto(
    val voted: Boolean,
    @SerialName("vote_count") val voteCount: Int
) {
    fun toModel() = AppFeedbackVoteResult(
        voted = voted,
        voteCount = voteCount
    )
}

@Serializable
private data class AppFeedbackStatusResultDto(
    val id: String,
    val status: String,
    @SerialName("completed_at") val completedAt: String? = null
) {
    fun toModel() = AppFeedbackStatusResult(
        id = UUID.fromString(id),
        status = status,
        completedAt = completedAt?.let { Date.from(Instant.parse(it)) }
    )
}
