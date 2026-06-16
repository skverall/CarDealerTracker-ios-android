package com.ezcar24.business.data.billing

import com.revenuecat.purchases.PackageType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubscriptionManagerTest {

    @Test
    fun billingPeriodMapsRevenueCatProductIdentifiers() {
        assertEquals(
            "monthly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.monthly")
        )
        assertEquals(
            "yearly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.yearly")
        )
        assertEquals(
            "weekly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.weekly")
        )
        assertEquals(
            "quarterly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.quarterly")
        )
    }

    @Test
    fun billingPeriodKeepsLegacyAndroidAliases() {
        assertEquals("monthly", SubscriptionManager.billingPeriod(PackageType.CUSTOM, "ezcar24_monthly"))
        assertEquals("yearly", SubscriptionManager.billingPeriod(PackageType.CUSTOM, "ezcar24_yearly"))
        assertEquals("weekly", SubscriptionManager.billingPeriod(PackageType.CUSTOM, "ezcar24_weekly"))
        assertEquals("quarterly", SubscriptionManager.billingPeriod(PackageType.CUSTOM, "ezcar24_quarterly"))
    }

    @Test
    fun billingPeriodMapsGooglePlayBasePlanIdentifiers() {
        assertEquals(
            "monthly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.monthly:monthly")
        )
        assertEquals(
            "yearly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.yearly:yearly")
        )
        assertEquals(
            "weekly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.weekly:weekly")
        )
        assertEquals(
            "quarterly",
            SubscriptionManager.billingPeriod(PackageType.CUSTOM, "com.ezcar24.business.quarterly:quarterly")
        )
    }

    @Test
    fun billingPeriodPrefersRevenueCatPackageType() {
        assertEquals("weekly", SubscriptionManager.billingPeriod(PackageType.WEEKLY, "unexpected"))
        assertEquals("monthly", SubscriptionManager.billingPeriod(PackageType.MONTHLY, "unexpected"))
        assertEquals("yearly", SubscriptionManager.billingPeriod(PackageType.ANNUAL, "unexpected"))
        assertEquals("quarterly", SubscriptionManager.billingPeriod(PackageType.THREE_MONTH, "unexpected"))
    }

    @Test
    fun billingPeriodRejectsUnrelatedProducts() {
        assertNull(SubscriptionManager.billingPeriod(PackageType.CUSTOM, "other_product"))
        assertNull(SubscriptionManager.billingPeriod(PackageType.LIFETIME, "other_product"))
    }
}
