//
//  MonthlyReportSnapshotBuilder.swift
//  Ezcar24Business
//
//  Builds a shared monthly report snapshot from Core Data.
//

import Foundation
import CoreData

struct MonthlyReportExecutiveSummary: Equatable {
    let totalRevenue: Decimal
    let vehicleRevenue: Decimal
    let partRevenue: Decimal
    let realizedSalesProfit: Decimal
    let vehicleProfit: Decimal
    let partProfit: Decimal
    let monthlyExpenses: Decimal
    let netCashMovement: Decimal
    let depositsTotal: Decimal
    let withdrawalsTotal: Decimal
    let vehicleSalesCount: Int
    let partSalesCount: Int
    let inventoryCount: Int
    let inventoryCapital: Decimal
    let partsUnitsInStock: Decimal
    let partsInventoryCost: Decimal
}

struct MonthlyReportVehicleSaleRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let buyerName: String
    let soldAt: Date
    let revenue: Decimal
    let purchasePrice: Decimal
    let vehicleExpenses: Decimal
    let holdingCost: Decimal
    let vatRefund: Decimal
    let realizedProfit: Decimal
}

struct MonthlyReportPartSaleRow: Identifiable, Equatable {
    let id: UUID
    let soldAt: Date
    let buyerName: String
    let summary: String
    let revenue: Decimal
    let costOfGoodsSold: Decimal
    let realizedProfit: Decimal
}

struct MonthlyReportExpenseRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let categoryTitle: String
    let vehicleTitle: String?
    let date: Date
    let amount: Decimal
}

struct MonthlyReportExpenseCategoryRow: Identifiable, Equatable {
    let key: String
    let title: String
    let amount: Decimal
    let count: Int
    let share: Double

    var id: String {
        key
    }
}

struct MonthlyReportCashMovementRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let note: String
    let transactionType: AccountTransactionType
    let date: Date
    let signedAmount: Decimal
}

struct MonthlyReportCashMovementSummary: Equatable {
    let depositsTotal: Decimal
    let withdrawalsTotal: Decimal
    let netMovement: Decimal
    let transactionCount: Int
    let rows: [MonthlyReportCashMovementRow]
}

struct MonthlyReportInventoryVehicleRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let status: String
    let purchaseDate: Date?
    let purchasePrice: Decimal
    let totalExpenses: Decimal
    let costBasis: Decimal
}

struct MonthlyReportPartsInventoryRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let code: String
    let quantityOnHand: Decimal
    let inventoryCost: Decimal
}

struct MonthlyReportSnapshot: Equatable {
    let reportMonth: ReportMonth?
    let range: DateInterval
    let title: String
    let generatedAt: Date
    let executiveSummary: MonthlyReportExecutiveSummary
    let vehicleSales: [MonthlyReportVehicleSaleRow]
    let partSales: [MonthlyReportPartSaleRow]
    let expenseActivity: [MonthlyReportExpenseRow]
    let expenseCategories: [MonthlyReportExpenseCategoryRow]
    let cashMovement: MonthlyReportCashMovementSummary
    let inventorySnapshot: [MonthlyReportInventoryVehicleRow]
    let partsSnapshot: [MonthlyReportPartsInventoryRow]
    let topProfitableVehicles: [MonthlyReportVehicleSaleRow]
    let lossMakingVehicles: [MonthlyReportVehicleSaleRow]
    let topExpenseCategories: [MonthlyReportExpenseCategoryRow]
}

final class MonthlyReportSnapshotBuilder {
    private let context: NSManagedObjectContext
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .autoupdatingCurrent) {
        self.context = context
        self.calendar = calendar
    }

    func build(for month: ReportMonth, dealerId: UUID) throws -> MonthlyReportSnapshot {
        try build(
            for: month.interval,
            title: month.displayTitle,
            dealerId: dealerId,
            reportMonth: month
        )
    }

    func build(
        for range: DateInterval,
        title: String? = nil,
        dealerId: UUID? = nil,
        reportMonth: ReportMonth? = nil
    ) throws -> MonthlyReportSnapshot {
        var snapshot: MonthlyReportSnapshot?
        var capturedError: Error?

        context.performAndWait {
            do {
                snapshot = try buildSnapshot(
                    for: range,
                    title: title,
                    dealerId: dealerId,
                    reportMonth: reportMonth
                )
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            throw capturedError
        }

        guard let snapshot else {
            throw NSError(domain: "MonthlyReportSnapshotBuilder", code: 1)
        }

        return snapshot
    }

    private func buildSnapshot(
        for range: DateInterval,
        title: String?,
        dealerId: UUID?,
        reportMonth: ReportMonth?
    ) throws -> MonthlyReportSnapshot {
        let holdingCostSettings = try fetchHoldingCostSettings(dealerId: dealerId)
        let vehicleSales = try fetchVehicleSales(range: range).map { makeVehicleSaleRow(for: $0, settings: holdingCostSettings) }
        let partSales = try fetchPartSales(range: range).map(makePartSaleRow)
        let expenseActivity = try fetchExpenses(range: range).map(makeExpenseRow)
        let expenseCategories = makeExpenseCategories(from: expenseActivity)
        let cashMovementRows = try fetchAccountTransactions(range: range).map(makeCashMovementRow)
        let cashMovement = makeCashMovementSummary(from: cashMovementRows)
        let inventorySnapshot = try fetchInventoryVehicles().map(makeInventoryVehicleRow)
        let partsSnapshot = try fetchPartsInventory().map(makePartsInventoryRow)

        let vehicleRevenue = vehicleSales.reduce(Decimal(0)) { $0 + $1.revenue }
        let partRevenue = partSales.reduce(Decimal(0)) { $0 + $1.revenue }
        let vehicleProfit = vehicleSales.reduce(Decimal(0)) { $0 + $1.realizedProfit }
        let partProfit = partSales.reduce(Decimal(0)) { $0 + $1.realizedProfit }
        let monthlyExpenses = expenseActivity.reduce(Decimal(0)) { $0 + $1.amount }
        let inventoryCapital = inventorySnapshot.reduce(Decimal(0)) { $0 + $1.costBasis }
        let partsUnitsInStock = partsSnapshot.reduce(Decimal(0)) { $0 + $1.quantityOnHand }
        let partsInventoryCost = partsSnapshot.reduce(Decimal(0)) { $0 + $1.inventoryCost }

        let executiveSummary = MonthlyReportExecutiveSummary(
            totalRevenue: vehicleRevenue + partRevenue,
            vehicleRevenue: vehicleRevenue,
            partRevenue: partRevenue,
            realizedSalesProfit: vehicleProfit + partProfit,
            vehicleProfit: vehicleProfit,
            partProfit: partProfit,
            monthlyExpenses: monthlyExpenses,
            netCashMovement: cashMovement.netMovement,
            depositsTotal: cashMovement.depositsTotal,
            withdrawalsTotal: cashMovement.withdrawalsTotal,
            vehicleSalesCount: vehicleSales.count,
            partSalesCount: partSales.count,
            inventoryCount: inventorySnapshot.count,
            inventoryCapital: inventoryCapital,
            partsUnitsInStock: partsUnitsInStock,
            partsInventoryCost: partsInventoryCost
        )

        let sortedByProfit = vehicleSales.sorted { lhs, rhs in
            if lhs.realizedProfit != rhs.realizedProfit {
                return lhs.realizedProfit > rhs.realizedProfit
            }
            return lhs.soldAt > rhs.soldAt
        }

        return MonthlyReportSnapshot(
            reportMonth: reportMonth,
            range: range,
            title: title ?? formattedRangeTitle(range: range),
            generatedAt: Date(),
            executiveSummary: executiveSummary,
            vehicleSales: vehicleSales.sorted { $0.soldAt > $1.soldAt },
            partSales: partSales.sorted { $0.soldAt > $1.soldAt },
            expenseActivity: expenseActivity.sorted { $0.date > $1.date },
            expenseCategories: expenseCategories,
            cashMovement: cashMovement,
            inventorySnapshot: inventorySnapshot.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
            partsSnapshot: partsSnapshot.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            topProfitableVehicles: Array(sortedByProfit.filter { $0.realizedProfit > 0 }.prefix(5)),
            lossMakingVehicles: Array(sortedByProfit.reversed().filter { $0.realizedProfit < 0 }.prefix(5)),
            topExpenseCategories: Array(expenseCategories.prefix(5))
        )
    }

    private func fetchHoldingCostSettings(dealerId: UUID?) throws -> HoldingCostSettings? {
        let request = HoldingCostSettings.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \HoldingCostSettings.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \HoldingCostSettings.createdAt, ascending: false)
        ]

        if let dealerId {
            request.predicate = NSPredicate(format: "dealerId == %@", dealerId as CVarArg)
        }

        return try context.fetch(request).first
    }

    private func fetchVehicleSales(range: DateInterval) throws -> [Sale] {
        let request: NSFetchRequest<Sale> = Sale.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deletedAt == nil"),
            NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Sale.date, ascending: false)]

        return try context.fetch(request).filter { sale in
            sale.vehicle?.deletedAt == nil
        }
    }

    private func fetchPartSales(range: DateInterval) throws -> [PartSale] {
        let request = NSFetchRequest<PartSale>(entityName: "PartSale")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deletedAt == nil"),
            NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchExpenses(range: DateInterval) throws -> [Expense] {
        let request = NSFetchRequest<Expense>(entityName: "Expense")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deletedAt == nil"),
            NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchAccountTransactions(range: DateInterval) throws -> [AccountTransaction] {
        let request = NSFetchRequest<AccountTransaction>(entityName: "AccountTransaction")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deletedAt == nil"),
            NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchInventoryVehicles() throws -> [Vehicle] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "deletedAt == nil"),
            NSPredicate(format: "status != %@", "sold")
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: false)]
        return try context.fetch(request)
    }

    private func fetchPartsInventory() throws -> [Part] {
        let request = NSFetchRequest<Part>(entityName: "Part")
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request).filter { part in
            part.activeBatches.contains { ($0.quantityRemaining?.decimalValue ?? 0) > 0 }
        }
    }

    private func makeVehicleSaleRow(for sale: Sale, settings: HoldingCostSettings?) -> MonthlyReportVehicleSaleRow {
        let vehicle = sale.vehicle
        let saleDate = sale.date ?? vehicle?.saleDate ?? Date()
        let title = vehicleTitle(vehicle)
        let buyerName = trimmedOrFallback(sale.buyerName, fallback: "Walk-in buyer")
        let revenue = sale.amount?.decimalValue ?? 0
        let purchasePrice = vehicle?.purchasePrice?.decimalValue ?? 0
        let vehicleExpenses = vehicleExpenseTotal(vehicle: vehicle, through: saleDate)
        let holdingCost = holdingCost(vehicle: vehicle, through: saleDate, settings: settings)
        let vatRefund = sale.vatRefundAmount?.decimalValue ?? 0
        let realizedProfit = revenue - purchasePrice - vehicleExpenses - holdingCost + vatRefund

        return MonthlyReportVehicleSaleRow(
            id: sale.id ?? UUID(),
            title: title,
            buyerName: buyerName,
            soldAt: saleDate,
            revenue: revenue,
            purchasePrice: purchasePrice,
            vehicleExpenses: vehicleExpenses,
            holdingCost: holdingCost,
            vatRefund: vatRefund,
            realizedProfit: realizedProfit
        )
    }

    private func makePartSaleRow(for sale: PartSale) -> MonthlyReportPartSaleRow {
        let saleDate = sale.date ?? Date()
        let buyerName = trimmedOrFallback(sale.buyerName, fallback: "Walk-in buyer")
        let lineItems = activePartSaleLineItems(for: sale)
        let summary = partSaleSummary(lineItems: lineItems)
        let revenue = sale.amount?.decimalValue ?? 0
        let costOfGoodsSold = lineItems.reduce(Decimal(0)) { total, item in
            total + ((item.unitCost?.decimalValue ?? 0) * (item.quantity?.decimalValue ?? 0))
        }

        return MonthlyReportPartSaleRow(
            id: sale.id ?? UUID(),
            soldAt: saleDate,
            buyerName: buyerName,
            summary: summary,
            revenue: revenue,
            costOfGoodsSold: costOfGoodsSold,
            realizedProfit: revenue - costOfGoodsSold
        )
    }

    private func makeExpenseRow(for expense: Expense) -> MonthlyReportExpenseRow {
        MonthlyReportExpenseRow(
            id: expense.id ?? UUID(),
            title: trimmedOrFallback(expense.expenseDescription, fallback: "Expense"),
            categoryTitle: expense.categoryTitle,
            vehicleTitle: expense.vehicle.map(vehicleTitle),
            date: expense.date ?? Date(),
            amount: expense.amount?.decimalValue ?? 0
        )
    }

    private func makeCashMovementRow(for transaction: AccountTransaction) -> MonthlyReportCashMovementRow {
        MonthlyReportCashMovementRow(
            id: transaction.id ?? UUID(),
            title: transaction.account?.displayTitle ?? "Account",
            note: trimmedOrFallback(transaction.note, fallback: transaction.transactionTypeEnum.title),
            transactionType: transaction.transactionTypeEnum,
            date: transaction.date ?? Date(),
            signedAmount: transaction.signedAmount
        )
    }

    private func makeInventoryVehicleRow(for vehicle: Vehicle) -> MonthlyReportInventoryVehicleRow {
        let expenses = activeVehicleExpenses(vehicle: vehicle).reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        return MonthlyReportInventoryVehicleRow(
            id: vehicle.id ?? UUID(),
            title: vehicleTitle(vehicle),
            status: trimmedOrFallback(vehicle.status, fallback: "owned"),
            purchaseDate: vehicle.purchaseDate,
            purchasePrice: purchasePrice,
            totalExpenses: expenses,
            costBasis: purchasePrice + expenses
        )
    }

    private func makePartsInventoryRow(for part: Part) -> MonthlyReportPartsInventoryRow {
        MonthlyReportPartsInventoryRow(
            id: part.id ?? UUID(),
            name: part.displayName,
            code: part.code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            quantityOnHand: part.quantityOnHand,
            inventoryCost: part.inventoryValue
        )
    }

    private func makeExpenseCategories(from expenses: [MonthlyReportExpenseRow]) -> [MonthlyReportExpenseCategoryRow] {
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        let grouped = Dictionary(grouping: expenses, by: { $0.categoryTitle })

        return grouped
            .map { title, rows in
                let amount = rows.reduce(Decimal(0)) { $0 + $1.amount }
                let share = total > 0 ? (amount as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue : 0
                return MonthlyReportExpenseCategoryRow(
                    key: title.lowercased(),
                    title: title,
                    amount: amount,
                    count: rows.count,
                    share: share
                )
            }
            .sorted {
                if $0.amount != $1.amount {
                    return $0.amount > $1.amount
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func makeCashMovementSummary(from rows: [MonthlyReportCashMovementRow]) -> MonthlyReportCashMovementSummary {
        let deposits = rows
            .filter { $0.transactionType == .deposit }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }
        let withdrawals = rows
            .filter { $0.transactionType == .withdrawal }
            .reduce(Decimal(0)) { total, row in
                total + (row.signedAmount < 0 ? -row.signedAmount : row.signedAmount)
            }
        let netMovement = rows.reduce(Decimal(0)) { $0 + $1.signedAmount }

        return MonthlyReportCashMovementSummary(
            depositsTotal: deposits,
            withdrawalsTotal: withdrawals,
            netMovement: netMovement,
            transactionCount: rows.count,
            rows: rows.sorted { $0.date > $1.date }
        )
    }

    private func holdingCost(vehicle: Vehicle?, through date: Date, settings: HoldingCostSettings?) -> Decimal {
        guard let vehicle else { return 0 }
        guard let settings, settings.isEnabled else { return 0 }
        guard HoldingCostCalculator.isHoldingCostEligible(vehicle: vehicle) else { return 0 }

        let purchaseDate = vehicle.purchaseDate ?? date
        let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
        let baseExpenses = activeVehicleExpenses(vehicle: vehicle)
            .filter {
                guard let expenseDate = $0.date else { return false }
                return expenseDate <= date && $0.categoryType != "holding_cost"
            }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }

        let days = max(0, calendar.dateComponents([.day], from: purchaseDate, to: date).day ?? 0)
        let annualRate = settings.annualRatePercent?.decimalValue ?? 15
        let dailyRate = HoldingCostCalculator.calculateDailyRate(annualRatePercent: annualRate)
        return Decimal(days) * dailyRate * (purchasePrice + baseExpenses)
    }

    private func vehicleExpenseTotal(vehicle: Vehicle?, through date: Date) -> Decimal {
        guard let vehicle else { return 0 }
        return activeVehicleExpenses(vehicle: vehicle)
            .filter {
                guard let expenseDate = $0.date else { return false }
                return expenseDate <= date
            }
            .reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
    }

    private func activeVehicleExpenses(vehicle: Vehicle) -> [Expense] {
        let expenses = vehicle.expenses?.allObjects as? [Expense] ?? []
        return expenses.filter { $0.deletedAt == nil }
    }

    private func activePartSaleLineItems(for sale: PartSale) -> [PartSaleLineItem] {
        let lineItems = sale.lineItems?.allObjects as? [PartSaleLineItem] ?? []
        return lineItems.filter { $0.deletedAt == nil }
    }

    private func partSaleSummary(lineItems: [PartSaleLineItem]) -> String {
        let titles = lineItems
            .compactMap { item -> String? in
                let name = item.part?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? nil : name
            }

        if titles.isEmpty {
            return "Parts sale"
        }

        if titles.count == 1 {
            return titles[0]
        }

        return "\(titles[0]) + \(titles.count - 1) more"
    }

    private func vehicleTitle(_ vehicle: Vehicle?) -> String {
        let title = [vehicle?.make, vehicle?.model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return title.isEmpty ? "Vehicle" : title
    }

    private func trimmedOrFallback(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func formattedRangeTitle(range: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end.addingTimeInterval(-1)))"
    }
}
