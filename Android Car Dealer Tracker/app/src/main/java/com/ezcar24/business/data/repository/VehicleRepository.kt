package com.ezcar24.business.data.repository

import com.ezcar24.business.data.local.Vehicle
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleWithFinancials
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow

@Singleton
class VehicleRepository @Inject constructor(
    private val vehicleDao: VehicleDao
) {
    fun getActiveVehicles(): Flow<List<Vehicle>> {
        return vehicleDao.getAllActive()
    }
    
    fun getVehiclesWithFinancials(): Flow<List<VehicleWithFinancials>> {
        return vehicleDao.getAllActiveWithFinancialsFlow()
    }
}
