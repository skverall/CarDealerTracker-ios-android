package com.ezcar24.business.di

import com.ezcar24.business.data.local.AccountTransactionDao
import com.ezcar24.business.data.local.ActiveAccountTransactionDao
import com.ezcar24.business.data.local.ActiveClientDao
import com.ezcar24.business.data.local.ActiveClientInteractionDao
import com.ezcar24.business.data.local.ActiveClientReminderDao
import com.ezcar24.business.data.local.ActiveDebtDao
import com.ezcar24.business.data.local.ActiveDebtPaymentDao
import com.ezcar24.business.data.local.ActiveExpenseDao
import com.ezcar24.business.data.local.ActiveExpenseTemplateDao
import com.ezcar24.business.data.local.ActiveFinancialAccountDao
import com.ezcar24.business.data.local.ActiveHoldingCostSettingsDao
import com.ezcar24.business.data.local.ActiveInventoryAlertDao
import com.ezcar24.business.data.local.ActivePartBatchDao
import com.ezcar24.business.data.local.ActivePartDao
import com.ezcar24.business.data.local.ActivePartSaleDao
import com.ezcar24.business.data.local.ActivePartSaleLineItemDao
import com.ezcar24.business.data.local.ActiveSaleDao
import com.ezcar24.business.data.local.ActiveSyncQueueDao
import com.ezcar24.business.data.local.ActiveUserDao
import com.ezcar24.business.data.local.ActiveVehicleDao
import com.ezcar24.business.data.local.ActiveVehicleInventoryStatsDao
import com.ezcar24.business.data.local.ClientDao
import com.ezcar24.business.data.local.ClientInteractionDao
import com.ezcar24.business.data.local.ClientReminderDao
import com.ezcar24.business.data.local.DebtDao
import com.ezcar24.business.data.local.DebtPaymentDao
import com.ezcar24.business.data.local.ExpenseDao
import com.ezcar24.business.data.local.ExpenseTemplateDao
import com.ezcar24.business.data.local.FinancialAccountDao
import com.ezcar24.business.data.local.HoldingCostSettingsDao
import com.ezcar24.business.data.local.InventoryAlertDao
import com.ezcar24.business.data.local.PartBatchDao
import com.ezcar24.business.data.local.PartDao
import com.ezcar24.business.data.local.PartSaleDao
import com.ezcar24.business.data.local.PartSaleLineItemDao
import com.ezcar24.business.data.local.SaleDao
import com.ezcar24.business.data.local.SyncQueueDao
import com.ezcar24.business.data.local.UserDao
import com.ezcar24.business.data.local.VehicleDao
import com.ezcar24.business.data.local.VehicleInventoryStatsDao
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class DatabaseRoutingModule {
    @Binds
    @Singleton
    abstract fun bindVehicleDao(dao: ActiveVehicleDao): VehicleDao

    @Binds
    @Singleton
    abstract fun bindExpenseDao(dao: ActiveExpenseDao): ExpenseDao

    @Binds
    @Singleton
    abstract fun bindClientDao(dao: ActiveClientDao): ClientDao

    @Binds
    @Singleton
    abstract fun bindUserDao(dao: ActiveUserDao): UserDao

    @Binds
    @Singleton
    abstract fun bindFinancialAccountDao(dao: ActiveFinancialAccountDao): FinancialAccountDao

    @Binds
    @Singleton
    abstract fun bindSyncQueueDao(dao: ActiveSyncQueueDao): SyncQueueDao

    @Binds
    @Singleton
    abstract fun bindSaleDao(dao: ActiveSaleDao): SaleDao

    @Binds
    @Singleton
    abstract fun bindDebtDao(dao: ActiveDebtDao): DebtDao

    @Binds
    @Singleton
    abstract fun bindDebtPaymentDao(dao: ActiveDebtPaymentDao): DebtPaymentDao

    @Binds
    @Singleton
    abstract fun bindAccountTransactionDao(dao: ActiveAccountTransactionDao): AccountTransactionDao

    @Binds
    @Singleton
    abstract fun bindExpenseTemplateDao(dao: ActiveExpenseTemplateDao): ExpenseTemplateDao

    @Binds
    @Singleton
    abstract fun bindClientInteractionDao(dao: ActiveClientInteractionDao): ClientInteractionDao

    @Binds
    @Singleton
    abstract fun bindClientReminderDao(dao: ActiveClientReminderDao): ClientReminderDao

    @Binds
    @Singleton
    abstract fun bindPartDao(dao: ActivePartDao): PartDao

    @Binds
    @Singleton
    abstract fun bindPartBatchDao(dao: ActivePartBatchDao): PartBatchDao

    @Binds
    @Singleton
    abstract fun bindPartSaleDao(dao: ActivePartSaleDao): PartSaleDao

    @Binds
    @Singleton
    abstract fun bindPartSaleLineItemDao(dao: ActivePartSaleLineItemDao): PartSaleLineItemDao

    @Binds
    @Singleton
    abstract fun bindHoldingCostSettingsDao(dao: ActiveHoldingCostSettingsDao): HoldingCostSettingsDao

    @Binds
    @Singleton
    abstract fun bindVehicleInventoryStatsDao(dao: ActiveVehicleInventoryStatsDao): VehicleInventoryStatsDao

    @Binds
    @Singleton
    abstract fun bindInventoryAlertDao(dao: ActiveInventoryAlertDao): InventoryAlertDao
}
