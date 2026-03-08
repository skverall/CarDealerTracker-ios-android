//
//  HoldingCostSettingsViewModel.swift
//  Ezcar24Business
//
//  ViewModel for holding cost settings management
//

import Foundation
import CoreData
import Combine
import Supabase

@MainActor
class HoldingCostSettingsViewModel: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published var annualRatePercent: Decimal = 15.0
    @Published var dailyRatePercent: Decimal = 0.0
    @Published var isLoading: Bool = false
    @Published var saveError: String? = nil
    @Published var saveSuccess: Bool = false
    
    let presetRates: [Decimal] = [10.0, 15.0, 20.0, 25.0]
    
    private let context: NSManagedObjectContext
    private let client: SupabaseClient
    private var settings: HoldingCostSettings?
    private var cancellables = Set<AnyCancellable>()
    
    init(
        context: NSManagedObjectContext,
        client: SupabaseClient = SupabaseClientProvider().client
    ) {
        self.context = context
        self.client = client
        loadSettings()
    }

    convenience init() {
        self.init(context: PersistenceController.shared.container.viewContext)
    }
    
    func loadSettings() {
        isLoading = true
        
        let request = HoldingCostSettings.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \HoldingCostSettings.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \HoldingCostSettings.createdAt, ascending: false)
        ]
        if let dealerId = CloudSyncEnvironment.currentDealerId {
            request.predicate = NSPredicate(format: "dealerId == %@", dealerId as CVarArg)
        }
        
        do {
            let results = try context.fetch(request)
            
            if let existingSettings = results.first {
                settings = existingSettings
                if settings?.dealerId == nil, let dealerId = CloudSyncEnvironment.currentDealerId {
                    settings?.dealerId = dealerId
                    settings?.updatedAt = Date()
                    try? context.save()
                }
                isEnabled = existingSettings.isEnabled
                annualRatePercent = existingSettings.annualRatePercent?.decimalValue ?? 15.0
            } else {
                createDefaultSettings()
            }
            
            calculateDailyRate()
        } catch {
            saveError = "Failed to load settings"
            createDefaultSettings()
        }
        
        isLoading = false
    }
    
    func saveSettings() {
        guard validateSettings() else { return }
        
        isLoading = true
        saveError = nil
        
        do {
            if settings == nil {
                settings = HoldingCostSettings(context: context)
                settings?.id = UUID()
                settings?.dealerId = CloudSyncEnvironment.currentDealerId
                settings?.createdAt = Date()
            }
            
            if settings?.dealerId == nil {
                settings?.dealerId = CloudSyncEnvironment.currentDealerId
            }
            settings?.isEnabled = isEnabled
            settings?.annualRatePercent = NSDecimalNumber(decimal: annualRatePercent)
            settings?.dailyRatePercent = NSDecimalNumber(decimal: dailyRatePercent)
            settings?.updatedAt = Date()
            
            try context.save()

            let organizationId = settings?.dealerId
            let currentEnabled = isEnabled
            let currentRate = annualRatePercent

            if let organizationId {
                Task {
                    await syncRemoteSettings(
                        organizationId: organizationId,
                        isEnabled: currentEnabled,
                        annualRatePercent: currentRate
                    )
                }
            } else {
                presentSaveSuccess()
            }
        } catch {
            saveError = "Failed to save settings"
        }
        
        isLoading = false
    }
    
    func setAnnualRate(_ rate: Decimal) {
        annualRatePercent = rate
        calculateDailyRate()
    }
    
    func calculateDailyRate() {
        dailyRatePercent = HoldingCostCalculator.calculateDailyRate(annualRatePercent: annualRatePercent)
    }
    
    func calculateDailyCost(for vehicle: Vehicle, expenses: [Expense]) -> Decimal {
        guard let settings = settings, settings.isEnabled else { return 0 }
        
        let baseExpenses = HoldingCostCalculator.getHoldingCostBaseExpenses(allExpenses: expenses)
        return HoldingCostCalculator.calculateDailyHoldingCost(
            vehicle: vehicle,
            settings: settings,
            improvementExpenses: baseExpenses
        )
    }
    
    func calculateAccumulatedCost(for vehicle: Vehicle, expenses: [Expense]) -> Decimal {
        guard let settings = settings, settings.isEnabled else { return 0 }
        
        return HoldingCostCalculator.calculateAccumulatedHoldingCost(
            vehicle: vehicle,
            settings: settings,
            allExpenses: expenses
        )
    }
    
    private func createDefaultSettings() {
        settings = HoldingCostSettings(context: context)
        settings?.id = UUID()
        settings?.dealerId = CloudSyncEnvironment.currentDealerId
        settings?.isEnabled = false
        settings?.annualRatePercent = NSDecimalNumber(decimal: 15.0)
        settings?.dailyRatePercent = NSDecimalNumber(decimal: 0.0411)
        settings?.createdAt = Date()
        settings?.updatedAt = Date()
        
        isEnabled = false
        annualRatePercent = 15.0
        calculateDailyRate()
        
        try? context.save()
    }
    
    private func validateSettings() -> Bool {
        guard annualRatePercent >= 0 && annualRatePercent <= 100 else {
            saveError = "Annual rate must be between 0% and 100%"
            return false
        }
        
        return true
    }

    private func syncRemoteSettings(
        organizationId: UUID,
        isEnabled: Bool,
        annualRatePercent: Decimal
    ) async {
        let params: [String: AnyJSON] = [
            "p_organization_id": .string(organizationId.uuidString),
            "p_is_enabled": .bool(isEnabled),
            "p_annual_rate_percent": .double(NSDecimalNumber(decimal: annualRatePercent).doubleValue)
        ]

        do {
            _ = try await client
                .rpc("upsert_organization_holding_cost_settings", params: params)
                .execute()
            saveError = nil
            presentSaveSuccess()
        } catch {
            saveSuccess = false
            saveError = error.localizedDescription
        }
    }

    private func presentSaveSuccess() {
        saveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveSuccess = false
        }
    }
}

extension HoldingCostSettingsViewModel {
    var formattedAnnualRate: String {
        return String(format: "%.1f%%", NSDecimalNumber(decimal: annualRatePercent).doubleValue)
    }
    
    var formattedDailyRate: String {
        let rate = NSDecimalNumber(decimal: dailyRatePercent).doubleValue
        if rate < 0.01 {
            return String(format: "%.4f%%", rate)
        }
        return String(format: "%.3f%%", rate)
    }
    
    var explanationText: String {
        return """
        Holding cost represents the cost of keeping a vehicle in inventory. \
        It includes capital costs (the money tied up in the vehicle) and is \
        calculated based on your annual rate percentage.
        
        Daily Rate = Annual Rate ÷ 365 days
        
        Example: With a 15% annual rate on a $10,000 vehicle:
        • Daily holding cost: $4.11
        • Monthly holding cost: ~$125
        
        This helps you understand the true cost of inventory aging and \
        make better pricing decisions.
        
        If you don't need this, you can turn it off anytime with the toggle above.
        """
    }
}
