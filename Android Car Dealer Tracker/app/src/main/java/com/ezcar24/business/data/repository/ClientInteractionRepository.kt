package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.ClientInteractionDao
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

@Singleton
class ClientInteractionRepository @Inject constructor(
    private val interactionDao: ClientInteractionDao
) {

    suspend fun createInteraction(interaction: ClientInteraction) {
        interactionDao.upsert(interaction)
    }

    suspend fun updateInteraction(interaction: ClientInteraction) {
        interactionDao.upsert(interaction)
    }

    suspend fun deleteInteraction(interaction: ClientInteraction) {
        interactionDao.delete(interaction)
    }

    suspend fun getInteractionById(interactionId: UUID): ClientInteraction? {
        return interactionDao.getById(interactionId)
    }

    suspend fun getInteractionsByClient(clientId: UUID): List<ClientInteraction> {
        return interactionDao.getByClient(clientId)
    }

    fun getInteractionsByClientFlow(clientId: UUID): Flow<List<ClientInteraction>> {
        return flow {
            emit(interactionDao.getByClient(clientId))
        }
    }

    suspend fun getInteractionsByDateRange(
        clientId: UUID,
        startDate: Date,
        endDate: Date
    ): List<ClientInteraction> {
        return interactionDao.getByClient(clientId).filter {
            it.occurredAt >= startDate && it.occurredAt <= endDate
        }
    }

    suspend fun getInteractionsByType(clientId: UUID, interactionType: String): List<ClientInteraction> {
        return interactionDao.getByClient(clientId).filter {
            it.interactionType?.equals(interactionType, ignoreCase = true) == true
        }
    }

    suspend fun getInteractionsByOutcome(clientId: UUID, outcome: String): List<ClientInteraction> {
        return interactionDao.getByClient(clientId).filter {
            it.outcome?.equals(outcome, ignoreCase = true) == true
        }
    }

    suspend fun getRecentInteractions(clientId: UUID, limit: Int = 10): List<ClientInteraction> {
        return interactionDao.getByClient(clientId)
            .sortedByDescending { it.occurredAt }
            .take(limit)
    }

    suspend fun getInteractionsRequiringFollowUp(clientId: UUID): List<ClientInteraction> {
        return interactionDao.getByClient(clientId).filter { it.isFollowUpRequired }
    }

    suspend fun getAllInteractionsForClients(clientIds: List<UUID>): List<ClientInteraction> {
        val allInteractions = mutableListOf<ClientInteraction>()
        clientIds.forEach { clientId ->
            allInteractions.addAll(interactionDao.getByClient(clientId))
        }
        return allInteractions
    }

    suspend fun getInteractionsByDate(date: Date): List<ClientInteraction> {
        val calendar = java.util.Calendar.getInstance()
        calendar.time = date
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        val startOfDay = calendar.time

        calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
        val endOfDay = calendar.time

        return getAllInteractions().filter {
            it.occurredAt >= startOfDay && it.occurredAt < endOfDay
        }
    }

    suspend fun getInteractionsCountByClient(clientId: UUID): Int {
        return interactionDao.getByClient(clientId).size
    }

    suspend fun getLastInteraction(clientId: UUID): ClientInteraction? {
        return interactionDao.getByClient(clientId).maxByOrNull { it.occurredAt }
    }

    suspend fun getInteractionsByStage(clientId: UUID, stage: String): List<ClientInteraction> {
        return interactionDao.getByClient(clientId).filter {
            it.stage?.equals(stage, ignoreCase = true) == true
        }
    }

    suspend fun deleteAllInteractionsForClient(clientId: UUID) {
        interactionDao.deleteByClient(clientId)
    }

    private suspend fun getAllInteractions(): List<ClientInteraction> {
        return interactionDao.getAllIncludingDeleted()
            .filter { it.deletedAt == null }
    }
}
