package com.ezcar24.business.util

import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

object DateUtils {
    private val isoParser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSX", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    private val isoParserNoMillis = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssX", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    private val dateOnlyParser = SimpleDateFormat("yyyy-MM-dd", Locale.US) // Local TZ

    fun parseIso8601(str: String): Date? = parseDateAndTime(str)

    fun formatIso8601(date: Date): String = formatDateAndTime(date)

    fun parseDateAndTime(str: String): Date? {
        return try {
            isoParser.parse(str)
        } catch (e: Exception) {
            try {
                isoParserNoMillis.parse(str)
            } catch (e2: Exception) {
                null
            }
        }
    }

    fun formatDateAndTime(date: Date): String {
        return isoParser.format(date)
    }

    fun parseDateOnly(str: String): Date? {
        return try { dateOnlyParser.parse(str) } catch (e: Exception) { null }
    }

    fun formatDateOnly(date: Date): String {
        return dateOnlyParser.format(date)
    }

    fun parseRemoteDateOnly(str: String): Date? {
        parseDateOnly(str)?.let { return it }
        val parsed = parseDateAndTime(str) ?: return null
        return normalizeDateOnly(parsed)
    }

    private fun normalizeDateOnly(date: Date): Date {
        val utcCalendar = java.util.Calendar.getInstance(TimeZone.getTimeZone("UTC"), Locale.US)
        utcCalendar.time = date
        val year = utcCalendar.get(java.util.Calendar.YEAR)
        val month = utcCalendar.get(java.util.Calendar.MONTH)
        val day = utcCalendar.get(java.util.Calendar.DAY_OF_MONTH)

        val localCalendar = java.util.Calendar.getInstance(TimeZone.getDefault(), Locale.US)
        localCalendar.clear()
        localCalendar.set(year, month, day, 0, 0, 0)
        localCalendar.set(java.util.Calendar.MILLISECOND, 0)
        return localCalendar.time
    }
}

fun String.toBigDecimalOrZero(): BigDecimal = try { BigDecimal(this) } catch(e:Exception) { BigDecimal.ZERO }
fun String.toBigDecimalOrNull(): BigDecimal? = try { BigDecimal(this) } catch(e:Exception) { null }
fun String.toUUID(): UUID? = try { UUID.fromString(this) } catch(e:Exception) { null }


object BigDecimalSerializer : KSerializer<BigDecimal> {

    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("BigDecimal", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: BigDecimal) {
        encoder.encodeString(value.toPlainString())
    }

    override fun deserialize(decoder: Decoder): BigDecimal {
        // Handle both String and Number JSON types
        return if (decoder is JsonDecoder) {
            val element = decoder.decodeJsonElement()
            val primitive = element.jsonPrimitive
            if (primitive.isString) {
                try { BigDecimal(primitive.content) } catch(e: Exception) { BigDecimal.ZERO }
            } else {
                // It's a number
                val doubleVal = primitive.doubleOrNull
                if (doubleVal != null) BigDecimal.valueOf(doubleVal) 
                else BigDecimal.ZERO
            }
        } else {
            // Fallback for non-JSON decoders
            try { BigDecimal(decoder.decodeString()) } catch(e: Exception) { BigDecimal.ZERO }
        }
    }
}
