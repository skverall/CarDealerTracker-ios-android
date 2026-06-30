package com.ezcar24.business.util

import java.util.Locale

enum class FinancialAccountKind(val routeValue: String, val titleSource: String) {
    CASH("cash", "Cash"),
    BANK("bank", "Bank"),
    CREDIT_CARD("credit_card", "Credit Card"),
    OTHER("other", "Other");

    companion object {
        const val SEPARATOR = " - "

        fun fromRoute(value: String?): FinancialAccountKind? {
            return when (value?.trim()?.lowercase(Locale.US)) {
                "cash" -> CASH
                "bank" -> BANK
                "credit", "credit_card", "credit-card", "credit card", "card" -> CREDIT_CARD
                "other" -> OTHER
                else -> null
            }
        }

        fun fromPrefix(value: String): FinancialAccountKind {
            return when (value.trim().lowercase(Locale.US)) {
                "cash" -> CASH
                "bank" -> BANK
                "card", "credit", "creditcard", "credit card", "credit_card", "credit-card" -> CREDIT_CARD
                else -> OTHER
            }
        }
    }
}

data class ParsedFinancialAccountType(
    val kind: FinancialAccountKind,
    val name: String?
)

fun parseFinancialAccountType(accountType: String?): ParsedFinancialAccountType {
    val raw = accountType?.trim().orEmpty()
    if (raw.isEmpty()) return ParsedFinancialAccountType(FinancialAccountKind.OTHER, null)

    val separatorIndex = raw.indexOf(FinancialAccountKind.SEPARATOR)
    if (separatorIndex >= 0) {
        val prefix = raw.substring(0, separatorIndex).trim()
        val name = raw.substring(separatorIndex + FinancialAccountKind.SEPARATOR.length).trim()
        return ParsedFinancialAccountType(
            kind = FinancialAccountKind.fromPrefix(prefix),
            name = name.ifBlank { null }
        )
    }

    val kind = FinancialAccountKind.fromPrefix(raw)
    return if (kind == FinancialAccountKind.OTHER) {
        ParsedFinancialAccountType(kind, raw)
    } else {
        ParsedFinancialAccountType(kind, null)
    }
}

fun financialAccountKindFor(accountType: String?): FinancialAccountKind {
    return parseFinancialAccountType(accountType).kind
}

fun composeFinancialAccountType(kind: FinancialAccountKind, name: String?): String {
    val trimmedName = name?.trim().orEmpty()
    if (trimmedName.isEmpty()) return kind.titleSource
    if (kind == FinancialAccountKind.OTHER) return trimmedName
    return "${kind.titleSource}${FinancialAccountKind.SEPARATOR}$trimmedName"
}

fun financialAccountDisplayTitle(accountType: String?): String {
    val parsed = parseFinancialAccountType(accountType)
    val name = parsed.name
    if (!name.isNullOrBlank()) {
        if (parsed.kind == FinancialAccountKind.OTHER) return name
        return "${parsed.kind.titleSource}${FinancialAccountKind.SEPARATOR}$name"
    }
    if (parsed.kind == FinancialAccountKind.OTHER) {
        val raw = accountType?.trim().orEmpty()
        return raw.ifBlank { "Account" }
    }
    return parsed.kind.titleSource
}

fun financialAccountShortTitle(accountType: String?): String {
    val parsed = parseFinancialAccountType(accountType)
    val name = parsed.name
    if (!name.isNullOrBlank()) return name
    if (parsed.kind == FinancialAccountKind.OTHER) {
        val raw = accountType?.trim().orEmpty()
        return raw.ifBlank { "Account" }
    }
    return parsed.kind.titleSource
}

fun financialAccountSubtitleTitle(accountType: String?): String? {
    val parsed = parseFinancialAccountType(accountType)
    return if (!parsed.name.isNullOrBlank() && parsed.kind != FinancialAccountKind.OTHER) {
        parsed.kind.titleSource
    } else {
        null
    }
}
