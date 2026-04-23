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
    @Published var bonusAccessUntil: Date?
    @Published var bonusMonths: Int = 0
    
    private var expectedAppUserId: String?
    private var canUseRevenueCat: Bool {
        Purchases.isConfigured
    }

    var currentSubscriptionPackages: [Package] {
        guard let currentOffering else { return [] }
        return filteredPackages(currentOffering.availablePackages)
    }
    
    enum RestoreStatus: Equatable {
        case idle
        case success
        case error(String)
        case noPurchases
    }
    
    private init() {
        if canUseRevenueCat {
            checkSubscriptionStatus(forceRefresh: true)
        } else {
            isCheckingStatus = false
        }
    }
    
    func checkSubscriptionStatus(forceRefresh: Bool = false) {
        guard canUseRevenueCat else {
            clearCachedStatus()
            isCheckingStatus = false
            return
        }
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
        guard canUseRevenueCat else {
            currentOffering = nil
            isLoading = false
            return
        }
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
                    
                    let products = self.currentSubscriptionPackages.map(\.storeProduct)
                    self.checkIntroEligibility(for: products)
                }
            }
        }
    }
    
    func checkIntroEligibility(for products: [StoreProduct]) {
        guard canUseRevenueCat else {
            introEligibility = [:]
            return
        }
        Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: products.map { $0.productIdentifier }) { [weak self] eligibility in
            DispatchQueue.main.async {
                self?.introEligibility = eligibility
            }
        }
    }
    
    func purchase(package: Package, completion: @escaping (Bool) -> Void = { _ in }) {
        guard canUseRevenueCat else {
            isLoading = false
            completion(false)
            return
        }
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
        guard canUseRevenueCat else {
            isLoading = false
            isRestoring = false
            restoreStatus = .noPurchases
            return
        }
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
        guard canUseRevenueCat else {
            isCheckingStatus = false
            return
        }
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
        guard canUseRevenueCat else {
            reset()
            return
        }
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
        guard canUseRevenueCat else { return }
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
            self.bonusAccessUntil = nil
            self.bonusMonths = 0
        }
    }
    
    private func updateProStatus(from customerInfo: CustomerInfo) {
        DispatchQueue.main.async {
            self.customerInfo = customerInfo
            self.recomputeProAccess()
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
            self.recomputeProAccess()
        }
    }

    func updateReferralBonus(until date: Date?, months: Int?) {
        DispatchQueue.main.async {
            self.bonusAccessUntil = date
            self.bonusMonths = months ?? 0
            self.recomputeProAccess()
        }
    }

    private func recomputeProAccess() {
        if let expected = expectedAppUserId, canUseRevenueCat {
            let currentAppUser = Purchases.shared.appUserID
            if currentAppUser != expected {
                self.isProAccessActive = (bonusAccessUntil ?? .distantPast) > Date()
                return
            }
        }
        let hasRevenueCat = !(customerInfo?.entitlements.active.isEmpty ?? true)
        let hasBonus = (bonusAccessUntil ?? .distantPast) > Date()
        self.isProAccessActive = hasRevenueCat || hasBonus
    }

    private func filteredPackages(_ packages: [Package]) -> [Package] {
        packages
            .filter {
                guard $0.storeProduct.productType != .nonConsumable,
                      let period = $0.storeProduct.subscriptionPeriod else { return false }
                return period.unit == .month || period.unit == .year
            }
            .sorted { lhs, rhs in
                sortOrder(for: lhs) < sortOrder(for: rhs)
            }
    }

    private func sortOrder(for package: Package) -> Int {
        guard let period = package.storeProduct.subscriptionPeriod else { return 99 }

        switch period.unit {
        case .month:
            return period.value == 1 ? 1 : 2
        case .year:
            return 3
        default:
            return 99
        }
    }
}
