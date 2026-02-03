package com.ezcar24.business.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ezcar24.business.data.local.Client
import com.ezcar24.business.data.local.ClientDao
import com.ezcar24.business.data.local.Expense
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleDao
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

data class GlobalSearchUiState(
    val query: String = "",
    val vehicleResults: List<Vehicle> = emptyList(),
    val clientResults: List<Client> = emptyList(),
    val expenseResults: List<Expense> = emptyList()
)

@HiltViewModel
class GlobalSearchViewModel @Inject constructor(
    private val vehicleDao: VehicleDao,
    private val clientDao: ClientDao,
    private val expenseDao: ExpenseDao
) : ViewModel() {

    private val _uiState = MutableStateFlow(GlobalSearchUiState())
    val uiState = _uiState.asStateFlow()

    private var searchJob: Job? = null

    fun onQueryChanged(query: String) {
        _uiState.update { it.copy(query = query) }
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(250)
            val trimmed = query.trim()
            if (trimmed.isEmpty()) {
                _uiState.update {
                    it.copy(vehicleResults = emptyList(), clientResults = emptyList(), expenseResults = emptyList())
                }
                return@launch
            }

            val wildcard = "%${trimmed.lowercase(Locale.US)}%"
            val vehicles = withContext(Dispatchers.IO) { vehicleDao.searchActive(wildcard) }
            val clients = withContext(Dispatchers.IO) { clientDao.searchActive(wildcard) }
            val expenses = withContext(Dispatchers.IO) { expenseDao.searchActive(wildcard) }
            _uiState.update { it.copy(vehicleResults = vehicles, clientResults = clients, expenseResults = expenses) }
        }
    }
}
