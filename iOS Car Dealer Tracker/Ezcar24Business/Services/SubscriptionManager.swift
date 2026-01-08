import Foundation
import RevenueCat
import SwiftUI

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var isProAccessActive: Bool = false
    @Published var currentOffering: Offering?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var customerInfo: CustomerInfo?
    @Published var restoreStatus: RestoreStatus = .idle
    @Published var isRestoring: Bool = false
    @Published var isCheckingStatus: Bool = true
    @Published var introEligibility: [String: IntroEligibility] = [:]
    
    private var expectedAppUserId: String?
    
    enum RestoreStatus: Equatable {
        case idle
        case success
        case error(String)
        case noPurchases
    }
    
    private init() {
        // Check status on launch (will be refreshed again after auth bootstrap)
        checkSubscriptionStatus(forceRefresh: true)
    }
    
    func checkSubscriptionStatus(forceRefresh: Bool = false) {
        isCheckingStatus = true
        if forceRefresh {
            Purchases.shared.invalidateCustomerInfoCache()
        }
        Purchases.shared.getCustomerInfo { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            defer { self.isCheckingStatus = false }
            if let customerInfo = customerInfo {
                self.updateProStatus(from: customerInfo)
            } else {
                self.clearCachedStatus()
                if let error {
                    print("RevenueCat getCustomerInfo error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func fetchOfferings() {
        self.isLoading = true
        Purchases.shared.getOfferings { [weak self] (offerings, error) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("Error fetching offerings: \(error.localizedDescription)")
                } else if let offerings = offerings {
                    self.currentOffering = offerings.current
                    print("Offerings fetched: \(offerings.current?.identifier ?? "None")")
                    
                    // Check eligibility for available packages
                    if let packages = offerings.current?.availablePackages {
                        let products = packages.map { $0.storeProduct }
                        self.checkIntroEligibility(for: products)
                    }
                }
            }
        }
    }
    
    func checkIntroEligibility(for products: [StoreProduct]) {
        Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: products.map { $0.productIdentifier }) { [weak self] eligibility in
            DispatchQueue.main.async {
                self?.introEligibility = eligibility
            }
        }
    }
    
    func purchase(package: Package, completion: @escaping (Bool) -> Void = { _ in }) {
        self.isLoading = true
        Purchases.shared.purchase(package: package) { [weak self] (transaction, customerInfo, error, userCancelled) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    if !userCancelled {
                        self.errorMessage = error.localizedDescription
                    }
                    completion(false)
                } else if let customerInfo = customerInfo {
                    self.updateProStatus(from: customerInfo)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
    
    func restorePurchases() {
        self.isLoading = true
        self.isRestoring = true
        self.restoreStatus = .idle
        
        Purchases.shared.restorePurchases { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.isRestoring = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.restoreStatus = .error(error.localizedDescription)
                } else if let customerInfo = customerInfo {
                    self.updateProStatus(from: customerInfo)
                    
                    if !customerInfo.entitlements.active.isEmpty {
                        self.restoreStatus = .success
                    } else {
                        self.restoreStatus = .noPurchases
                    }
                }
            }
        }
    }
    
    func logIn(userId: String) {
        expectedAppUserId = userId
        clearCachedStatus()
        isCheckingStatus = true
        Purchases.shared.logIn(userId) { [weak self] (customerInfo, created, error) in
            guard let self = self else { return }
            defer { self.isCheckingStatus = false }
            if let error = error {
                print("RevenueCat login error: \(error.localizedDescription)")
                self.clearCachedStatus()
            } else if let customerInfo = customerInfo {
                self.updateProStatus(from: customerInfo)
            } else {
                self.clearCachedStatus()
            }
        }
    }
    
    func logOut() {
        expectedAppUserId = nil
        isCheckingStatus = true
        Purchases.shared.logOut { [weak self] (customerInfo, error) in
            guard let self = self else { return }
            if let error = error {
                print("RevenueCat logout error: \(error.localizedDescription)")
            }
            self.reset()
        }
    }
    
    func showManageSubscriptions() {
        Purchases.shared.showManageSubscriptions { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func reset() {
        DispatchQueue.main.async {
            self.isProAccessActive = false
            self.currentOffering = nil
            self.errorMessage = nil
            self.customerInfo = nil
            self.restoreStatus = .idle
            self.isRestoring = false
            self.isLoading = false
            self.isCheckingStatus = false
        }
    }
    
    private func updateProStatus(from customerInfo: CustomerInfo) {
        DispatchQueue.main.async {
            self.customerInfo = customerInfo
            if let expected = self.expectedAppUserId {
                let currentAppUser = Purchases.shared.appUserID
                guard currentAppUser == expected else {
                    self.isProAccessActive = false
                    return
                }
            }
            // CRITICAL FIX: Check if ANY entitlement is active.
            // This solves the issue where the specific entitlement name might differ (e.g. "pro" vs "monthly").
            // If the user has paid for ANYTHING that is currently active, they get access.
            self.isProAccessActive = !customerInfo.entitlements.active.isEmpty
        }
    }
    
    var activeEntitlement: EntitlementInfo? {
        customerInfo?.entitlements.active.first?.value
    }
    
    var expirationDate: Date? {
        activeEntitlement?.expirationDate
    }
    
    var isTrial: Bool {
        activeEntitlement?.periodType == .trial
    }
    
    private func clearCachedStatus() {
        DispatchQueue.main.async {
            self.isProAccessActive = false
            self.customerInfo = nil
        }
    }
}
