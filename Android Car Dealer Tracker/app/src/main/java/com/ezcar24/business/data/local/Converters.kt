package com.ezcar24.business.data.local

import androidx.room.TypeConverter
import java.math.BigDecimal
import java.util.Date
import java.util.UUID

class Converters {
    @TypeConverter
    fun fromTimestamp(value: Long?): Date? {
        return value?.let { Date(it) }
    }

    @TypeConverter
    fun dateToTimestamp(date: Date?): Long? {
        return date?.time
    }

    @TypeConverter
    fun fromUUID(uuid: String?): UUID? {
        return uuid?.let { UUID.fromString(it) }
    }

    @TypeConverter
    fun uuidToString(uuid: UUID?): String? {
        return uuid?.toString()
    }

    @TypeConverter
    fun fromBigDecimal(value: String?): BigDecimal? {
        return value?.let { BigDecimal(it) }
    }

    @TypeConverter
    fun bigDecimalToString(value: BigDecimal?): String? {
        return value?.toPlainString()
    }

    @TypeConverter
    fun fromExpenseCategoryType(value: String?): ExpenseCategoryType? {
        return value?.let { ExpenseCategoryType.valueOf(it) }
    }

    @TypeConverter
    fun expenseCategoryTypeToString(type: ExpenseCategoryType?): String? {
        return type?.name
    }

    @TypeConverter
    fun fromLeadStage(value: String?): LeadStage? {
        return value?.let { LeadStage.valueOf(it) }
    }

    @TypeConverter
    fun leadStageToString(stage: LeadStage?): String? {
        return stage?.name
    }

    @TypeConverter
    fun fromLeadSource(value: String?): LeadSource? {
        return value?.let { LeadSource.valueOf(it) }
    }

    @TypeConverter
    fun leadSourceToString(source: LeadSource?): String? {
        return source?.name
    }

    @TypeConverter
    fun fromInventoryAlertType(value: String?): InventoryAlertType? {
        return value?.let { InventoryAlertType.valueOf(it) }
    }

    @TypeConverter
    fun inventoryAlertTypeToString(type: InventoryAlertType?): String? {
        return type?.name
    }
}
