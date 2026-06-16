package com.ezcar24.business.data.billing

import android.app.Activity
import android.content.Context
import android.util.Log
import com.ezcar24.business.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.Package as RevenueCatPackage
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.interfaces.PurchaseCallback
import com.revenuecat.purchases.logInWith
import com.revenuecat.purchases.logOutWith
import com.revenuecat.purchases.models.StoreTransaction
import com.revenuecat.purchases.restorePurchasesWith
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@EntryPoint
@InstallIn(SingletonComponent::class)
interface SubscriptionManagerEntryPoint {
    fun subscriptionManager(): SubscriptionManager
}

data class SubscriptionOffer(
    val revenueCatPackage: RevenueCatPackage,
    val productId: String,
    val price: String,
    val period: String,
    val hasFreeTrial: Boolean
)

@Singleton
class SubscriptionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val _isProAccessActive = MutableStateFlow(false)
    val isProAccessActive: StateFlow<Boolean> = _isProAccessActive.asStateFlow()

    private val _isCheckingStatus = MutableStateFlow(true)
    val isCheckingStatus: StateFlow<Boolean> = _isCheckingStatus.asStateFlow()

    private val _offerings = MutableStateFlow<List<SubscriptionOffer>>(emptyList())
    val offerings: StateFlow<List<SubscriptionOffer>> = _offerings.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isBillingReady = MutableStateFlow(false)
    val isBillingReady: StateFlow<Boolean> = _isBillingReady.asStateFlow()

    private val revenueCatApiKey = BuildConfig.REVENUECAT_ANDROID_API_KEY.trim()

    companion object {
        private const val TAG = "SubscriptionManager"
        private val WEEKLY_PRODUCT_IDS = setOf(
            "com.ezcar24.business.weekly",
            "ezcar24_weekly",
            "weekly"
        )
        private val MONTHLY_PRODUCT_IDS = setOf(
            "com.ezcar24.business.monthly",
            "ezcar24_monthly",
            "monthly"
        )
        private val YEARLY_PRODUCT_IDS = setOf(
            "com.ezcar24.business.yearly",
            "ezcar24_yearly",
            "yearly"
        )
        private val QUARTERLY_PRODUCT_IDS = setOf(
            "com.ezcar24.business.quarterly",
            "ezcar24_quarterly",
            "quarterly"
        )

        internal fun billingPeriod(packageType: PackageType, productId: String): String? {
            val normalizedProductId = productId.substringBefore(":")
            return when (packageType) {
                PackageType.WEEKLY -> "weekly"
                PackageType.MONTHLY -> "monthly"
                PackageType.ANNUAL -> "yearly"
                PackageType.THREE_MONTH -> "quarterly"
                else -> when (normalizedProductId) {
                    in WEEKLY_PRODUCT_IDS -> "weekly"
                    in MONTHLY_PRODUCT_IDS -> "monthly"
                    in YEARLY_PRODUCT_IDS -> "yearly"
                    in QUARTERLY_PRODUCT_IDS -> "quarterly"
                    else -> null
                }
            }
        }
    }

    init {
        if (BuildConfig.DEBUG) {
            _isProAccessActive.value = true
            _isCheckingStatus.value = false
        }
        initializeRevenueCat()
    }

    private fun initializeRevenueCat() {
        if (revenueCatApiKey.isBlank()) {
            _isBillingReady.value = false
            _isCheckingStatus.value = false
            Log.w(TAG, "RevenueCat Android API key is missing")
            return
        }

        if (!Purchases.isConfigured) {
            Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
            Purchases.configure(
                PurchasesConfiguration.Builder(context, revenueCatApiKey).build()
            )
        }

        _isBillingReady.value = true
        queryProducts()
        checkProAccess()
    }

    fun queryProducts() {
        if (!canUseRevenueCat()) {
            _isLoading.value = false
            _offerings.value = emptyList()
            return
        }

        _isLoading.value = true
        Purchases.sharedInstance.getOfferingsWith(
            onError = { error ->
                Log.e(TAG, "RevenueCat offerings failed: ${error.message}")
                _isLoading.value = false
            },
            onSuccess = { offerings ->
                val packages = offerings.current?.availablePackages.orEmpty()
                _offerings.value = packages
                    .mapNotNull(::subscriptionOfferFromPackage)
                    .sortedBy { offer ->
                        when (offer.period) {
                            "weekly" -> 0
                            "monthly" -> 1
                            "yearly" -> 2
                            "quarterly" -> 3
                            else -> 4
                        }
                    }
                _isLoading.value = false
            }
        )
    }

    fun checkProAccess() {
        if (!canUseRevenueCat()) {
            _isCheckingStatus.value = false
            _isProAccessActive.value = BuildConfig.DEBUG
            return
        }

        _isCheckingStatus.value = true
        Purchases.sharedInstance.getCustomerInfoWith(
            onError = { error ->
                Log.e(TAG, "RevenueCat customer info failed: ${error.message}")
                _isCheckingStatus.value = false
                _isProAccessActive.value = BuildConfig.DEBUG
            },
            onSuccess = { customerInfo ->
                updateProStatus(customerInfo)
                _isCheckingStatus.value = false
            }
        )
    }

    fun launchBillingFlow(activity: Activity, offer: SubscriptionOffer) {
        if (!canUseRevenueCat()) {
            Log.e(TAG, "Cannot launch purchase flow: RevenueCat is not configured")
            return
        }

        _isLoading.value = true
        Purchases.sharedInstance.purchase(
            PurchaseParams.Builder(activity, offer.revenueCatPackage).build(),
            object : PurchaseCallback {
                override fun onError(error: PurchasesError, userCancelled: Boolean) {
                    if (!userCancelled) {
                        Log.e(TAG, "RevenueCat purchase failed: ${error.message}")
                    }
                    _isLoading.value = false
                }

                override fun onCompleted(
                    storeTransaction: StoreTransaction,
                    customerInfo: CustomerInfo
                ) {
                    updateProStatus(customerInfo)
                    _isLoading.value = false
                }
            }
        )
    }

    fun restorePurchases() {
        if (!canUseRevenueCat()) {
            _isLoading.value = false
            _isProAccessActive.value = BuildConfig.DEBUG
            return
        }

        _isLoading.value = true
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error ->
                Log.e(TAG, "RevenueCat restore failed: ${error.message}")
                _isLoading.value = false
            },
            onSuccess = { customerInfo ->
                updateProStatus(customerInfo)
                _isLoading.value = false
            }
        )
    }

    fun logIn(userId: String?) {
        val normalizedUserId = userId?.trim().orEmpty()
        if (!canUseRevenueCat() || normalizedUserId.isBlank()) {
            checkProAccess()
            return
        }

        _isCheckingStatus.value = true
        Purchases.sharedInstance.logInWith(
            appUserID = normalizedUserId,
            onError = { error ->
                Log.e(TAG, "RevenueCat login failed: ${error.message}")
                _isCheckingStatus.value = false
                _isProAccessActive.value = BuildConfig.DEBUG
            },
            onSuccess = { customerInfo, _ ->
                updateProStatus(customerInfo)
                _isCheckingStatus.value = false
            }
        )
    }

    fun logOut() {
        if (!canUseRevenueCat()) {
            _isProAccessActive.value = BuildConfig.DEBUG
            _offerings.value = emptyList()
            _isCheckingStatus.value = false
            return
        }

        _isCheckingStatus.value = true
        Purchases.sharedInstance.logOutWith(
            onError = { error ->
                Log.e(TAG, "RevenueCat logout failed: ${error.message}")
                _isCheckingStatus.value = false
            },
            onSuccess = { customerInfo ->
                updateProStatus(customerInfo)
                _isCheckingStatus.value = false
            }
        )
    }

    private fun canUseRevenueCat(): Boolean {
        return revenueCatApiKey.isNotBlank() && Purchases.isConfigured
    }

    private fun updateProStatus(customerInfo: CustomerInfo) {
        _isProAccessActive.value = customerInfo.entitlements.active.isNotEmpty()
    }

    private fun subscriptionOfferFromPackage(packageToMap: RevenueCatPackage): SubscriptionOffer? {
        val productId = packageToMap.product.id
        val period = billingPeriod(packageToMap.packageType, productId) ?: return null

        return SubscriptionOffer(
            revenueCatPackage = packageToMap,
            productId = productId,
            price = packageToMap.product.price.formatted,
            period = period,
            hasFreeTrial = packageToMap.product.subscriptionOptions?.freeTrial != null
        )
    }

}
