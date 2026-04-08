package com.ezcar24.business.data.billing

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@EntryPoint
@InstallIn(SingletonComponent::class)
interface SubscriptionManagerEntryPoint {
    fun subscriptionManager(): SubscriptionManager
}

data class SubscriptionOffer(
    val productDetails: ProductDetails,
    val offerToken: String,
    val pricingPhase: String,
    val price: String,
    val period: String,
    val hasFreeTrial: Boolean
)

@Singleton
class SubscriptionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _isProAccessActive = MutableStateFlow(false)
    val isProAccessActive: StateFlow<Boolean> = _isProAccessActive.asStateFlow()

    private val _offerings = MutableStateFlow<List<SubscriptionOffer>>(emptyList())
    val offerings: StateFlow<List<SubscriptionOffer>> = _offerings.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isBillingReady = MutableStateFlow(false)
    val isBillingReady: StateFlow<Boolean> = _isBillingReady.asStateFlow()

    private var billingClient: BillingClient? = null

    companion object {
        private const val TAG = "SubscriptionManager"
        const val PRODUCT_MONTHLY = "ezcar24_monthly"
        const val PRODUCT_YEARLY = "ezcar24_yearly"
        private val SUBSCRIPTION_IDS = listOf(PRODUCT_MONTHLY, PRODUCT_YEARLY)
    }

    init {
        if (com.ezcar24.business.BuildConfig.DEBUG) {
            _isProAccessActive.value = true
            Log.d(TAG, "Debug build — Pro access granted automatically")
        }
        initialize()
    }

    private fun initialize() {
        val purchasesUpdatedListener = PurchasesUpdatedListener { billingResult, purchases ->
            when (billingResult.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    purchases?.forEach { purchase ->
                        acknowledgePurchase(purchase)
                    }
                    checkProAccess()
                }
                BillingClient.BillingResponseCode.USER_CANCELED -> {
                    Log.d(TAG, "User canceled the purchase")
                }
                else -> {
                    Log.e(TAG, "Purchase error: ${billingResult.debugMessage}")
                }
            }
        }

        billingClient = BillingClient.newBuilder(context)
            .setListener(purchasesUpdatedListener)
            .enablePendingPurchases()
            .build()

        billingClient?.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    Log.d(TAG, "Billing client ready")
                    _isBillingReady.value = true
                    queryProducts()
                    checkProAccess()
                } else {
                    Log.e(TAG, "Billing setup failed: ${billingResult.debugMessage}")
                }
            }

            override fun onBillingServiceDisconnected() {
                Log.w(TAG, "Billing service disconnected")
                _isBillingReady.value = false
            }
        })
    }

    fun queryProducts() {
        val client = billingClient ?: return
        scope.launch(Dispatchers.IO) {
            _isLoading.value = true
            try {
                val productList = SUBSCRIPTION_IDS.map { id ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(id)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                }

                val params = QueryProductDetailsParams.newBuilder()
                    .setProductList(productList)
                    .build()

                val result = client.queryProductDetails(params)

                if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    val offers = result.productDetailsList?.mapNotNull { details ->
                        val basePlan = details.subscriptionOfferDetails?.firstOrNull() ?: return@mapNotNull null
                        val pricingPhase = basePlan.pricingPhases.pricingPhaseList.firstOrNull()

                        SubscriptionOffer(
                            productDetails = details,
                            offerToken = basePlan.offerToken,
                            pricingPhase = pricingPhase?.billingPeriod ?: "",
                            price = pricingPhase?.formattedPrice ?: "",
                            period = when (details.productId) {
                                PRODUCT_MONTHLY -> "monthly"
                                PRODUCT_YEARLY -> "yearly"
                                else -> "unknown"
                            },
                            hasFreeTrial = basePlan.pricingPhases.pricingPhaseList.size > 1
                        )
                    }?.sortedBy { offer ->
                        when (offer.period) {
                            "monthly" -> 0
                            "yearly" -> 1
                            else -> 2
                        }
                    } ?: emptyList()

                    _offerings.value = offers
                } else {
                    Log.e(TAG, "Query products failed: ${result.billingResult.debugMessage}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying products", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun checkProAccess() {
        val client = billingClient ?: return
        scope.launch(Dispatchers.IO) {
            try {
                val params = QueryPurchasesParams.newBuilder()
                    .setProductType(BillingClient.ProductType.SUBS)
                    .build()

                val result = client.queryPurchasesAsync(params)
                val hasActive = result.purchasesList.any { purchase ->
                    purchase.purchaseState == com.android.billingclient.api.Purchase.PurchaseState.PURCHASED &&
                        purchase.isAcknowledged
                }
                _isProAccessActive.value = hasActive
            } catch (e: Exception) {
                Log.e(TAG, "Error checking pro access", e)
            }
        }
    }

    fun launchBillingFlow(activity: Activity, offer: SubscriptionOffer) {
        val client = billingClient ?: return
        val productDetailsParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(offer.productDetails)
            .setOfferToken(offer.offerToken)
            .build()

        val billingFlowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productDetailsParams))
            .build()

        val billingResult = client.launchBillingFlow(activity, billingFlowParams)
        if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
            Log.e(TAG, "Billing flow launch failed: ${billingResult.debugMessage}")
        }
    }

    fun restorePurchases() {
        checkProAccess()
    }

    private fun acknowledgePurchase(purchase: com.android.billingclient.api.Purchase) {
        val client = billingClient ?: return
        if (purchase.purchaseState != com.android.billingclient.api.Purchase.PurchaseState.PURCHASED) return
        if (purchase.isAcknowledged) return

        scope.launch(Dispatchers.IO) {
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            val result = client.acknowledgePurchase(params)
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                Log.d(TAG, "Purchase acknowledged")
                checkProAccess()
            } else {
                Log.e(TAG, "Acknowledge failed: ${result.debugMessage}")
            }
        }
    }
}
