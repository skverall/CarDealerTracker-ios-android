package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientDao
import com.ezcar24.business.data.local.ClientInteraction
import com.ezcar24.business.data.local.ClientInteractionDao
import com.ezcar24.business.data.local.LeadSource
import com.ezcar24.business.data.local.LeadStage
import com.ezcar24.business.util.calculator.DailyActivitySummary
import com.ezcar24.business.util.calculator.FunnelMetrics
import com.ezcar24.business.util.calculator.LeadFunnelCalculator
import com.ezcar24.business.util.calculator.SourcePerformance
import java.util.Date
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map

data class ClientWithInteractions(
    val client: Client,
    val interactions: List<ClientInteraction>
)

data class ClientFunnelSummary(
    val client: Client,
    val interactions: List<ClientInteraction>,
    val leadScore: Int,
    val daysInCurrentStage: Int,
    val daysSinceLastContact: Int,
    val closeProbability: Double
)

@Singleton
class ClientRepository @Inject constructor(
    private val clientDao: ClientDao,
    private val interactionDao: ClientInteractionDao
) {

    fun getAllActiveClients(): Flow<List<Client>> {
        return clientDao.getAllActive()
    }

    fun getClientsByLeadStage(stage: LeadStage): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            clients.filter { it.leadStage == stage }
        }
    }

    fun getClientsByLeadSource(source: LeadSource): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            clients.filter { it.leadSource == source }
        }
    }

    fun getClientsWithInteractions(): Flow<List<ClientWithInteractions>> {
        return combine(
            clientDao.getAllActive(),
            flow {
                val clients = clientDao.getAllActive().first()
                val allInteractions = mutableListOf<ClientInteraction>()
                clients.forEach { client ->
                    allInteractions.addAll(interactionDao.getByClient(client.id))
                }
                emit(allInteractions)
            }
        ) { clients, _ ->
            clients.map { client ->
                val interactions = interactionDao.getByClient(client.id)
                ClientWithInteractions(client, interactions)
            }
        }
    }

    suspend fun getClientWithInteractions(clientId: UUID): ClientWithInteractions? {
        val client = clientDao.getById(clientId) ?: return null
        val interactions = interactionDao.getByClient(clientId)
        return ClientWithInteractions(client, interactions)
    }

    fun getClientWithInteractionsFlow(clientId: UUID): Flow<ClientWithInteractions?> {
        return flow {
            val client = clientDao.getById(clientId)
            if (client != null) {
                val interactions = interactionDao.getByClient(clientId)
                emit(ClientWithInteractions(client, interactions))
            } else {
                emit(null)
            }
        }
    }

    fun getActiveLeads(): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            clients.filter {
                it.leadStage != LeadStage.closed_won && it.leadStage != LeadStage.closed_lost
            }
        }
    }

    fun getClosedWonLeads(): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            clients.filter { it.leadStage == LeadStage.closed_won }
        }
    }

    fun getClosedLostLeads(): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            clients.filter { it.leadStage == LeadStage.closed_lost }
        }
    }

    fun getLeadsNeedingFollowUp(daysThreshold: Int = 3): Flow<List<Client>> {
        return clientDao.getAllActive().map { clients ->
            val now = Date()
            clients.filter { client ->
                val nextFollowUp = client.nextFollowUpAt
                if (nextFollowUp != null) {
                    val diffMillis = nextFollowUp.time - now.time
                    val diffDays = (diffMillis / (1000 * 60 * 60 * 24)).toInt()
                    diffDays <= daysThreshold
                } else {
                    val lastContact = client.lastContactAt
                    if (lastContact != null) {
                        val daysSinceContact = ((now.time - lastContact.time) / (1000 * 60 * 60 * 24)).toInt()
                        daysSinceContact >= daysThreshold
                    } else {
                        true
                    }
                }
            }
        }
    }

    fun getFunnelMetricsFlow(): Flow<FunnelMetrics> {
        return clientDao.getAllActive().map { clients ->
            LeadFunnelCalculator.calculateFunnelMetrics(clients)
        }
    }

    suspend fun calculateFunnelMetrics(): FunnelMetrics {
        val clients = clientDao.getAllActive().first()
        return LeadFunnelCalculator.calculateFunnelMetrics(clients)
    }

    fun getDailyActivitySummaryFlow(date: Date = Date()): Flow<DailyActivitySummary> {
        return flow {
            val allInteractions = mutableListOf<ClientInteraction>()
            val clients = clientDao.getAllActive().first()
            clients.forEach { client ->
                allInteractions.addAll(interactionDao.getByClient(client.id))
            }
            emit(LeadFunnelCalculator.getDailyActivitySummary(allInteractions, date))
        }
    }

    suspend fun getDailyActivitySummary(date: Date = Date()): DailyActivitySummary {
        val allInteractions = mutableListOf<ClientInteraction>()
        val clients = clientDao.getAllActive().first()
        clients.forEach { client ->
            allInteractions.addAll(interactionDao.getByClient(client.id))
        }
        return LeadFunnelCalculator.getDailyActivitySummary(allInteractions, date)
    }

    fun getLeadSourcePerformanceFlow(): Flow<Map<LeadSource, SourcePerformance>> {
        return clientDao.getAllActive().map { clients ->
            LeadFunnelCalculator.calculateLeadSourcePerformance(clients)
        }
    }

    suspend fun calculateLeadSourcePerformance(): Map<LeadSource, SourcePerformance> {
        val clients = clientDao.getAllActive().first()
        return LeadFunnelCalculator.calculateLeadSourcePerformance(clients)
    }

    fun getClientFunnelSummaryFlow(clientId: UUID): Flow<ClientFunnelSummary?> {
        return getClientWithInteractionsFlow(clientId).map { clientWithInteractions ->
            clientWithInteractions?.let { cwi ->
                ClientFunnelSummary(
                    client = cwi.client,
                    interactions = cwi.interactions,
                    leadScore = LeadFunnelCalculator.calculateLeadScore(cwi.client, cwi.interactions),
                    daysInCurrentStage = calculateDaysInCurrentStage(cwi.client, cwi.interactions),
                    daysSinceLastContact = LeadFunnelCalculator.calculateDaysSinceLastContact(
                        cwi.client,
                        cwi.interactions
                    ),
                    closeProbability = LeadFunnelCalculator.calculateCloseProbability(cwi.client)
                )
            }
        }
    }

    fun getPipelineValueFlow(): Flow<java.math.BigDecimal> {
        return getActiveLeads().map { clients ->
            LeadFunnelCalculator.calculatePipelineValue(clients)
        }
    }

    fun getWeightedPipelineValueFlow(): Flow<java.math.BigDecimal> {
        return getActiveLeads().map { clients ->
            LeadFunnelCalculator.calculateWeightedPipelineValue(clients)
        }
    }

    suspend fun getClientsByStage(stage: LeadStage): List<Client> {
        return clientDao.getAllActive().first().filter { it.leadStage == stage }
    }

    suspend fun getClientsBySource(source: LeadSource): List<Client> {
        return clientDao.getAllActive().first().filter { it.leadSource == source }
    }

    suspend fun searchClients(query: String): List<Client> {
        return clientDao.searchActive("%${query.lowercase()}%")
    }

    suspend fun getClientById(clientId: UUID): Client? {
        return clientDao.getById(clientId)
    }

    private fun calculateDaysInCurrentStage(client: Client, interactions: List<ClientInteraction>): Int {
        val timeInStage = LeadFunnelCalculator.calculateTimeInStage(client, interactions)
        return timeInStage[client.leadStage] ?: 0
    }
}
