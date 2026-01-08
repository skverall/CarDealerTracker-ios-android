//
//  DashboardViewModel.swift
//  Ezcar24Business
//
//  ViewModel for financial dashboard
//

import Foundation
import CoreData
import Combine


enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case today, week, month, threeMonths, sixMonths, all
    var id: String { rawValue }
    var startDate: Date? {
        let now = Date()
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
            return calendar.startOfDay(for: start)
        case .month:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return calendar.startOfDay(for: start)
        case .threeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return calendar.startOfDay(for: start)
        case .sixMonths:
            let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return calendar.startOfDay(for: start)
        case .all:
            return nil
        }
    }

    var endDate: Date? {
        let now = Date()
        let calendar = Calendar.current
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: start)
        case .week, .month, .threeMonths, .sixMonths:
            return now
        case .all:
            return nil
        }
    }

    @MainActor var displayLabel: String {
        switch self {
        case .today: return "time_range_1d".localizedString
        case .week: return "time_range_1w".localizedString
        case .month: return "time_range_1m".localizedString
        case .threeMonths: return "time_range_3m".localizedString
        case .sixMonths: return "time_range_6m".localizedString
        case .all: return "all_filter".localizedString
        }
    }

    @MainActor var comparisonLabel: String {
        switch self {
        case .today: return "vs_yesterday".localizedString
        case .week: return "vs_last_week".localizedString
        case .month: return "vs_last_month".localizedString
        case .threeMonths: return "vs_prev_3m".localizedString
        case .sixMonths: return "vs_prev_6m".localizedString
        case .all: return ""
        }
    }
}

struct CategoryStat: Identifiable {
    let id = UUID()
    let key: String   // e.g., "vehicle", "personal", "employee"
    let title: String
    let amount: Decimal
    let percent: Double
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let delta: Double
}

struct VehicleSpendStat: Identifiable {
    let id = UUID()
    let vehicle: Vehicle
    let title: String
    let amount: Decimal
}


@MainActor
class DashboardViewModel: ObservableObject {
    @Published var totalCash: Decimal = 0
    @Published var totalBank: Decimal = 0
    @Published var totalVehicleValue: Decimal = 0
    @Published var totalExpenses: Decimal = 0
    @Published var vehicleExpenses: Decimal = 0
    @Published var personalExpenses: Decimal = 0
    @Published var employeeExpenses: Decimal = 0
    @Published var vehicleCount: Int = 0
    // Vehicle status counts
    @Published var ownedCount: Int = 0
    @Published var onSaleCount: Int = 0
    @Published var soldCount: Int = 0
    @Published var inTransitCount: Int = 0
    @Published var underServiceCount: Int = 0
    @Published var totalSalesIncome: Decimal = 0

    // Sales performance
    @Published var totalSalesProfit: Decimal = 0
    @Published var periodSalesProfit: Decimal = 0
    @Published var soldInPeriod: Int = 0
    @Published var avgProfitPerSale: Decimal = 0
    @Published var soldChange: Int? = nil

    // Analytics additions
    @Published var categoryStats: [CategoryStat] = []
    @Published var trendPoints: [TrendPoint] = []
    @Published var profitTrendPoints: [TrendPoint] = []
    @Published var periodChangePercent: Double? = nil
    @Published var monthlyNetProfit: Decimal = 0
    @Published var monthlyProfitTrendPoints: [TrendPoint] = []
    @Published var currentRange: DashboardTimeRange = .all
    @Published var periodTransactionCount: Int = 0
    @Published var periodUniqueVehicles: Int = 0

    @Published var todaysExpenses: [Expense] = []
    @Published var recentExpenses: [Expense] = []
    @Published var topVehicles: [VehicleSpendStat] = []


    private var cancellables = Set<AnyCancellable>()

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        fetchFinancialData(range: .all)
        observeContextChanges()
    }

    private func observeContextChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                guard let self, let info = notification.userInfo else { return }
                
                // Check if any relevant entities changed
                if self.shouldRefresh(userInfo: info) {
                    // Debounce or just refresh on main thread
                    DispatchQueue.main.async {
                        self.fetchFinancialData(range: self.currentRange)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func shouldRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        let keys = [NSInsertedObjectsKey, NSDeletedObjectsKey, NSUpdatedObjectsKey]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { obj in
                obj is Expense || obj is Vehicle || obj is Sale || obj is FinancialAccount
            }) {
                return true
            }
        }
        return false
    }

    func fetchFinancialData(range: DashboardTimeRange = .all) {
        currentRange = range
        // If range is all, we default it to month in logic if needed, but here we just use it.
        // Actually for "all" we often want "All Time", so leaving as is.
        
        let rangeStart = range.startDate
        let rangeEnd = range.endDate
        // Fetch financial accounts
        let accountRequest: NSFetchRequest<FinancialAccount> = FinancialAccount.fetchRequest()

        do {
            let accounts = try context.fetch(accountRequest)
            totalCash = sumAccountBalances(accounts, type: "cash")
            totalBank = sumAccountBalances(accounts, type: "bank")
        } catch {
            print("Error fetching accounts: \(error)")
        }

        // Fetch vehicles
        let vehicleRequest: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()

        do {
            let vehicles = try context.fetch(vehicleRequest)
            vehicleCount = vehicles.count

            // Status counts
            ownedCount = vehicles.filter { $0.status == "owned" }.count
            onSaleCount = vehicles.filter { $0.status == "on_sale" || $0.status == "available" }.count // include legacy
            soldCount = vehicles.filter { $0.status == "sold" }.count
            inTransitCount = vehicles.filter { $0.status == "in_transit" }.count
            underServiceCount = vehicles.filter { $0.status == "under_service" }.count

            // Calculate total vehicle value (use sale price when available, otherwise fall back to cost basis)
            // EXCLUDE sold vehicles from Assets
            totalVehicleValue = vehicles.filter { $0.status != "sold" }.reduce(Decimal(0)) { total, vehicle in
                if let salePrice = vehicle.salePrice?.decimalValue, salePrice > 0 {
                    return total + salePrice
                }

                let purchasePrice = vehicle.purchasePrice?.decimalValue ?? 0
                let vehicleExpenses = (vehicle.expenses as? Set<Expense>)?.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) } ?? 0
                return total + purchasePrice + vehicleExpenses
            }
        } catch {
            print("Error fetching vehicles: \(error)")
        }

        // Fetch Sales for Revenue/Profit calculations
        let saleRequest: NSFetchRequest<Sale> = Sale.fetchRequest()
        do {
            let sales = try context.fetch(saleRequest)
            


            // Calculate Revenue (Total Sales Income) - ALWAYS ALL TIME
            totalSalesIncome = sales.reduce(Decimal(0)) { sum, sale in
                sum + (sale.amount?.decimalValue ?? 0)
            }
            
            // Calculate All-Time Profit (for the Key Metric Card)
             let (allTimeProfit, _) = calculateProfitData(sales: sales, range: .all)
             totalSalesProfit = allTimeProfit

            // Calculate Profit for Current Range
            let (profit, trend) = calculateProfitData(sales: sales, range: range)
            periodSalesProfit = profit
            profitTrendPoints = trend
            
            // Calculate Profit for Pinned Monthly Range
            let (moProfit, moTrend) = calculateProfitData(sales: sales, range: .month)
            monthlyNetProfit = moProfit
            monthlyProfitTrendPoints = moTrend

        } catch {
            print("Error fetching sales: \(error)")
        }

        // Fetch expenses (optionally filtered by date range)
        let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
        let currentStart: Date? = rangeStart
        var currentEnd: Date? = rangeEnd
        if currentStart != nil, currentEnd == nil {
            currentEnd = Date()
        }
        var expensePredicates: [NSPredicate] = []
        if let start = currentStart {
            expensePredicates.append(NSPredicate(format: "date >= %@", start as NSDate))
        }
        if let end = currentEnd {
            expensePredicates.append(NSPredicate(format: "date < %@", end as NSDate))
        }
        if !expensePredicates.isEmpty {
            expenseRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: expensePredicates)
        }

        do {
            let expenses = try context.fetch(expenseRequest)
            totalExpenses = expenses.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }

            // KPIs for the selected period
            periodTransactionCount = expenses.count
            let uniqueVehicles = Set(expenses.compactMap { $0.vehicle?.objectID })
            periodUniqueVehicles = uniqueVehicles.count

            vehicleExpenses = expenses.filter { $0.category == "vehicle" }.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
            personalExpenses = expenses.filter { $0.category == "personal" }.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
            employeeExpenses = expenses.filter { $0.category == "employee" }.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }

            // Build category stats sorted by amount desc
            let items: [(String,String,Decimal)] = [
                ("vehicle", "vehicle".localizedString, vehicleExpenses),
                ("personal", "personal".localizedString, personalExpenses),
                ("employee", "employee".localizedString, employeeExpenses)
            ]
            let total = (totalExpenses as NSDecimalNumber).doubleValue
            categoryStats = items
                .map { key, title, amount in
                    let amt = (amount as NSDecimalNumber).doubleValue
                    let pct = total > 0 ? (amt / total) * 100.0 : 0
                    return CategoryStat(key: key, title: title, amount: amount, percent: pct)
                }
                .sorted { ($0.amount as NSDecimalNumber).doubleValue > ($1.amount as NSDecimalNumber).doubleValue }

            // Build trend points
            trendPoints = buildTrendPoints(expenses: expenses, range: range)

            // Top Vehicles by spend in selected period (top 3)
            var vehicleSums: [NSManagedObjectID: Decimal] = [:]
            var vehicleRef: [NSManagedObjectID: Vehicle] = [:]
            for e in expenses {
                if let v = e.vehicle {
                    let key = v.objectID
                    vehicleSums[key, default: 0] += (e.amount?.decimalValue ?? 0)
                    vehicleRef[key] = v
                }
            }
            let sorted = vehicleSums.sorted { (a, b) in
                (a.value as NSDecimalNumber).doubleValue > (b.value as NSDecimalNumber).doubleValue
            }
            topVehicles = Array(sorted.prefix(3)).compactMap { (key, sum) in
                guard let v = vehicleRef[key] else { return nil }
                let title = "\(v.make ?? "") \(v.model ?? "")".trimmingCharacters(in: .whitespaces)
                return VehicleSpendStat(vehicle: v, title: title.isEmpty ? "Unnamed Vehicle" : title, amount: sum)
            }

            // Compute change vs previous period (for week/month/today)
            if let start = currentStart, range != .all {
                let end = currentEnd ?? Date()
                let length: TimeInterval = max(end.timeIntervalSince(start), 0)
                let prevStart = start.addingTimeInterval(-length)
                
                // Expenses Trend
                let prevReq: NSFetchRequest<Expense> = Expense.fetchRequest()
                prevReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", prevStart as NSDate, start as NSDate)
                let prevExpenses = try context.fetch(prevReq)
                let prevTotal = prevExpenses.reduce(0) { $0 + ($1.amount?.decimalValue ?? 0) }
                let prev = (prevTotal as NSDecimalNumber).doubleValue

                let curr = (totalExpenses as NSDecimalNumber).doubleValue
                periodChangePercent = prev > 0 ? ((curr - prev) / prev) * 100.0 : nil
                
                // Sales Trend
                let prevSaleReq: NSFetchRequest<Sale> = Sale.fetchRequest()
                prevSaleReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", prevStart as NSDate, start as NSDate)
                let prevSalesCount = try context.count(for: prevSaleReq)
                soldChange = soldInPeriod - prevSalesCount
            } else {
                periodChangePercent = nil
                soldChange = nil
            }
        } catch {
            print("Error fetching expenses: \(error)")
        }

        loadTodaysExpenses()
        loadRecentExpenses()
    }

    private func sumAccountBalances(_ accounts: [FinancialAccount], type: String) -> Decimal {
        let target = type.lowercased()
        return accounts.reduce(Decimal(0)) { total, account in
            guard account.accountType?.lowercased() == target else { return total }
            return total + (account.balance?.decimalValue ?? 0)
        }
    }

    private func buildTrendPoints(expenses: [Expense], range: DashboardTimeRange) -> [TrendPoint] {
        let cal = Calendar.current
        var points: [TrendPoint] = []

        guard !expenses.isEmpty else { return [] }
        
        var runningTotal = 0.0
        
        switch range {
        case .today:
            let startOfDay = cal.startOfDay(for: Date())
            // Create a bucket for each hour 0-23
            var buckets: [Int: Double] = [:]
            for e in expenses {
                guard let d = e.date, d >= startOfDay else { continue }
                let timestamp = e.createdAt ?? e.updatedAt ?? d
                let hour = cal.component(.hour, from: timestamp)
                buckets[hour, default: 0] += (e.amount?.doubleValue ?? 0)
            }
            
            for hour in 0...23 {
                if let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) {
                    let delta = buckets[hour] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .week:
            let today = cal.startOfDay(for: Date())
            let startOfWeek = cal.date(byAdding: .day, value: -6, to: today) ?? today
            
            var buckets: [Date: Double] = [:]
            for e in expenses {
                guard let d = e.date, d >= startOfWeek else { continue }
                let dayStart = cal.startOfDay(for: d)
                buckets[dayStart, default: 0] += (e.amount?.doubleValue ?? 0)
            }
            
            for i in 0...6 {
                if let date = cal.date(byAdding: .day, value: i, to: startOfWeek) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .month:
            let today = cal.startOfDay(for: Date())
            let startOfMonth = cal.date(byAdding: .day, value: -29, to: today) ?? today
            
            var buckets: [Date: Double] = [:]
            for e in expenses {
                guard let d = e.date, d >= startOfMonth else { continue }
                let dayStart = cal.startOfDay(for: d)
                buckets[dayStart, default: 0] += (e.amount?.doubleValue ?? 0)
            }
            
            for i in 0...29 {
                if let date = cal.date(byAdding: .day, value: i, to: startOfMonth) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .threeMonths, .sixMonths:
            let today = cal.startOfDay(for: Date())
            let monthsBack = range == .threeMonths ? -3 : -6
            let startOfPeriod = cal.date(byAdding: .month, value: monthsBack, to: today) ?? today
            
            // Align start to Sunday/Monday
            let weekday = cal.component(.weekday, from: startOfPeriod)
            let daysToSubtract = weekday - cal.firstWeekday
            let alignedStart = cal.date(byAdding: .day, value: -daysToSubtract, to: startOfPeriod) ?? startOfPeriod
            
            var buckets: [Date: Double] = [:]
            
            for e in expenses {
                guard let d = e.date, d >= alignedStart else { continue }
                // Find start of week for this date
                let sWeekday = cal.component(.weekday, from: d)
                let sDaysToSubtract = sWeekday - cal.firstWeekday
                if let weekStart = cal.date(byAdding: .day, value: -sDaysToSubtract, to: cal.startOfDay(for: d)) {
                    buckets[weekStart, default: 0] += (e.amount?.doubleValue ?? 0)
                }
            }
            
            // Iterate week by week
            var currentDate = alignedStart
            while currentDate <= today {
                let delta = buckets[currentDate] ?? 0
                runningTotal += delta
                points.append(TrendPoint(date: currentDate, value: runningTotal, delta: delta))
                currentDate = cal.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
            }

        case .all:
            // For 'All', we group by month for the last 12 months for better readability
            let today = cal.startOfDay(for: Date())
            let startOfYear = cal.date(byAdding: .month, value: -11, to: today) ?? today
             // Align to 1st of month
            let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: startOfYear)) ?? startOfYear

            var buckets: [Date: Double] = [:]
            for e in expenses {
                guard let d = e.date, d >= alignedStart else { continue }
                if let monthStart = cal.dateInterval(of: .month, for: d)?.start {
                    buckets[monthStart, default: 0] += (e.amount?.doubleValue ?? 0)
                }
            }
            
            for i in 0...11 {
                if let date = cal.date(byAdding: .month, value: i, to: alignedStart) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
        }

        
        if let lastIndex = points.lastIndex(where: { $0.delta != 0 }) {
            return Array(points.prefix(through: lastIndex))
        }
        return []
    }

    private func buildProfitTrendPoints(sales: [Sale], range: DashboardTimeRange) -> [TrendPoint] {
        let cal = Calendar.current
        var points: [TrendPoint] = []
        
        guard !sales.isEmpty else { return [] }
        
        // Helper to calculate profit for a single sale
        func calculateProfit(sale: Sale) -> Double {
            let revenue = sale.amount?.decimalValue ?? 0
            let vehicle = sale.vehicle
            let cost = vehicle?.purchasePrice?.decimalValue ?? 0
            let expenses = (vehicle?.expenses as? Set<Expense>)?.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) } ?? 0
            return NSDecimalNumber(decimal: revenue - (cost + expenses)).doubleValue
        }

        switch range {
        case .today:
            // Group by hour
            let startOfDay = cal.startOfDay(for: Date())
            var buckets: [Int: Double] = [:]
            for s in sales {
                guard let d = s.date, d >= startOfDay else { continue }
                let hour = cal.component(.hour, from: d)
                buckets[hour, default: 0] += calculateProfit(sale: s)
            }
            
            var runningTotal = 0.0
            for hour in 0...23 {
                if let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) {
                    let delta = buckets[hour] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .week:
            let today = cal.startOfDay(for: Date())
            let startOfWeek = cal.date(byAdding: .day, value: -6, to: today) ?? today
            
            var buckets: [Date: Double] = [:]
            for s in sales {
                guard let d = s.date, d >= startOfWeek else { continue }
                let dayStart = cal.startOfDay(for: d)
                buckets[dayStart, default: 0] += calculateProfit(sale: s)
            }
            
            var runningTotal = 0.0
            for i in 0...6 {
                if let date = cal.date(byAdding: .day, value: i, to: startOfWeek) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .month:
            let today = cal.startOfDay(for: Date())
            let startOfMonth = cal.date(byAdding: .day, value: -29, to: today) ?? today
            
            var buckets: [Date: Double] = [:]
            for s in sales {
                guard let d = s.date, d >= startOfMonth else { continue }
                let dayStart = cal.startOfDay(for: d)
                buckets[dayStart, default: 0] += calculateProfit(sale: s)
            }
            
            var runningTotal = 0.0
            for i in 0...29 {
                if let date = cal.date(byAdding: .day, value: i, to: startOfMonth) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
            
        case .threeMonths, .sixMonths:
            // For longer periods, group by week or month? Let's do by Week to show granularity
            // Actually, for 3-6 months, grouping by Week is better.
            let today = cal.startOfDay(for: Date())
            let monthsBack = range == .threeMonths ? -3 : -6
            let startOfPeriod = cal.date(byAdding: .month, value: monthsBack, to: today) ?? today
            
            // We align start to Sunday/Monday
            let weekday = cal.component(.weekday, from: startOfPeriod)
            let daysToSubtract = weekday - cal.firstWeekday
            let alignedStart = cal.date(byAdding: .day, value: -daysToSubtract, to: startOfPeriod) ?? startOfPeriod
            
            var buckets: [Date: Double] = [:]
            
            for s in sales {
                guard let d = s.date, d >= alignedStart else { continue }
                // Find start of week for this date
                let sWeekday = cal.component(.weekday, from: d)
                let sDaysToSubtract = sWeekday - cal.firstWeekday
                if let weekStart = cal.date(byAdding: .day, value: -sDaysToSubtract, to: cal.startOfDay(for: d)) {
                    buckets[weekStart, default: 0] += calculateProfit(sale: s)
                }
            }
            
            // Iterate week by week
            var currentDate = alignedStart
            var runningTotal = 0.0
            while currentDate <= today {
                let delta = buckets[currentDate] ?? 0
                runningTotal += delta
                points.append(TrendPoint(date: currentDate, value: runningTotal, delta: delta))
                currentDate = cal.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? currentDate
            }
            
        case .all:
            // Group by Month (last 12 months)
             let today = cal.startOfDay(for: Date())
             let startOfYear = cal.date(byAdding: .month, value: -11, to: today) ?? today
             let alignedStart = cal.date(from: cal.dateComponents([.year, .month], from: startOfYear)) ?? startOfYear
 
             var buckets: [Date: Double] = [:]
             for s in sales {
                 guard let d = s.date, d >= alignedStart else { continue }
                 if let monthStart = cal.dateInterval(of: .month, for: d)?.start {
                     buckets[monthStart, default: 0] += calculateProfit(sale: s)
                 }
             }
             
            var runningTotal = 0.0
            for i in 0...11 {
                if let date = cal.date(byAdding: .month, value: i, to: alignedStart) {
                    let delta = buckets[date] ?? 0
                    runningTotal += delta
                    points.append(TrendPoint(date: date, value: runningTotal, delta: delta))
                }
            }
        }
        
        if let lastIndex = points.lastIndex(where: { $0.delta != 0 }) {
            return Array(points.prefix(through: lastIndex))
        }
        return []
    }

    private func loadTodaysExpenses() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", todayStart as NSDate, tomorrowStart as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Expense.createdAt, ascending: false),
            NSSortDescriptor(keyPath: \Expense.date, ascending: false)
        ]

        do {
            todaysExpenses = try context.fetch(request)
        } catch {
            print("Error fetching today's expenses: \(error)")
            todaysExpenses = []
        }
    }

    private func loadRecentExpenses() {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.date, ascending: false)]
        request.fetchLimit = 4

        do {
            recentExpenses = try context.fetch(request)
        } catch {
            print("Error fetching recent expenses: \(error)")
            recentExpenses = []
        }
    }
    var averagePerVehicle: Decimal {
        guard periodUniqueVehicles > 0 else { return 0 }
        let total = totalExpenses as NSDecimalNumber
        let divisor = NSDecimalNumber(value: periodUniqueVehicles)
        return total.dividing(by: divisor).decimalValue
    }


    var totalAssets: Decimal {
        totalCash + totalBank + totalVehicleValue
    }

    var netPosition: Decimal {
        totalCash + totalBank
    }
    
    // MARK: - Helpers
    
    private func calculateProfitData(sales: [Sale], range: DashboardTimeRange) -> (Decimal, [TrendPoint]) {
        let rangeStart = range.startDate
        let rangeEnd = range.endDate
        
        let filteredSales: [Sale]
        if let start = rangeStart {
            let end = rangeEnd ?? Date()
            filteredSales = sales.filter { sale in
                guard let date = sale.date else { return false }
                return date >= start && date < end
            }
        } else {
            filteredSales = sales
        }
        
        let profit = filteredSales.reduce(Decimal(0)) { sum, sale in
            let revenue = sale.amount?.decimalValue ?? 0
            let vehicle = sale.vehicle
            let cost = vehicle?.purchasePrice?.decimalValue ?? 0
            let expenses = (vehicle?.expenses as? Set<Expense>)?.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) } ?? 0
            return sum + (revenue - (cost + expenses))
        }
        
        let trend = buildProfitTrendPoints(sales: filteredSales, range: range)
        return (profit, trend)
    }
}
