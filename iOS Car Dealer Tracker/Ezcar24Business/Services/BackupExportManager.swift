import Foundation
import CoreData
import PDFKit
import UIKit

// Centralized export/backup helper. Creates CSV/PDF snapshots and bundles monthly archives.
final class BackupExportManager: ObservableObject {
    private let context: NSManagedObjectContext
    weak var cloudSyncManager: CloudSyncManager?

    init(context: NSManagedObjectContext, cloudSyncManager: CloudSyncManager? = nil) {
        self.context = context
        self.cloudSyncManager = cloudSyncManager
    }

    // MARK: - Public API

    func exportExpensesCSV(range: DateInterval? = nil) throws -> URL {
        let expenses = try fetchExpenses(range: range)
        var csv = "Date,Description,Category,Amount,Vehicle,User,Account\n"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateStyle = .short
        df.timeStyle = .short

        for expense in expenses {
            let dateStr = expense.date.map { df.string(from: $0) } ?? ""
            let desc = expense.expenseDescription ?? ""
            let cat = expense.category ?? ""
            let amt = (expense.amount?.decimalValue ?? 0).asCurrencyFallback()
            let vehicle = [expense.vehicle?.make, expense.vehicle?.model].compactMap { $0 }.joined(separator: " ")
            let user = expense.user?.name ?? ""
            let account = expense.account?.accountType ?? ""
            csv += [dateStr, desc, cat, amt, vehicle, user, account]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }

        return try write(content: csv, fileName: "expenses-\(timestamp()).csv")
    }

    func exportVehiclesCSV() throws -> URL {
        let vehicles = try fetchVehicles()
        var csv = "VIN,Make,Model,Year,Purchase Price,Status,Notes,Created At\n"
        let df = ISO8601DateFormatter()
        for vehicle in vehicles {
            let vin = vehicle.vin ?? ""
            let make = vehicle.make ?? ""
            let model = vehicle.model ?? ""
            let year = vehicle.year
            let price = (vehicle.purchasePrice?.decimalValue ?? 0).asCurrencyFallback()
            let status = vehicle.status ?? ""
            let notes = vehicle.notes ?? ""
            let created = vehicle.createdAt.map { df.string(from: $0) } ?? ""
            csv += [vin, make, model, "\(year)", price, status, notes, created]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }
        return try write(content: csv, fileName: "vehicles-\(timestamp()).csv")
    }

    func exportClientsCSV() throws -> URL {
        let clients = try fetchClients()
        let df = ISO8601DateFormatter()
        var csv = "Name,Phone,Email,Notes,Created At,Next Reminder\n"
        for client in clients {
            let name = client.name ?? ""
            let phone = client.phone ?? ""
            let email = client.email ?? ""
            let notes = client.notes ?? ""
            let created = client.createdAt.map { df.string(from: $0) } ?? ""
            let reminder = (client.reminders as? Set<ClientReminder>)?.first
            let reminderStr = reminder?.dueDate.map { df.string(from: $0) } ?? ""
            csv += [name, phone, email, notes, created, reminderStr]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }
        return try write(content: csv, fileName: "clients-\(timestamp()).csv")
    }

    func generateReportPDF(for range: DateInterval) throws -> URL {
        let data = try prepareReportData(range: range)
        
        // Previous period for comparison
        let previousRange = DateInterval(start: Calendar.current.date(byAdding: .month, value: -1, to: range.start)!, end: range.start)
        let previousData = try? prepareReportData(range: previousRange)
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let df = DateFormatter()
        df.dateStyle = .medium
        
        let pdfData = renderer.pdfData { ctx in
            // --- PAGE 1: Executive Summary & Financial Overview ---
            ctx.beginPage()
            
            let margin: CGFloat = 40
            var y: CGFloat = 40
            let contentWidth = pageRect.width - (margin * 2)
            
            // Header
            drawHeader(ctx: ctx.cgContext, title: "Executive Summary", range: range, margin: margin, y: &y, width: contentWidth)
            
            // Financial Snapshot Table (Income Statement style)
            drawSectionTitle("Financial Overview", at: CGPoint(x: margin, y: y))
            y += 25
            drawFinancialOverview(data: data, previousData: previousData, margin: margin, y: &y, width: contentWidth)
            
            y += 30
            
            // Key Performance Indicators
            drawSectionTitle("Key Performance Indicators", at: CGPoint(x: margin, y: y))
            y += 25
            drawKPIGrid(data: data, previousData: previousData, margin: margin, y: &y, width: contentWidth)
            
            y += 30
            
            // Inventory Status
            drawSectionTitle("Inventory Snapshot", at: CGPoint(x: margin, y: y))
            y += 25
            drawInventorySnapshot(data: data, margin: margin, y: &y, width: contentWidth)

            drawFooter(page: 1)
            
            // --- PAGE 2: Sales Performance ---
            ctx.beginPage()
            y = 40
            drawHeader(ctx: ctx.cgContext, title: "Sales Analysis", range: range, margin: margin, y: &y, width: contentWidth)
            
            // Top Performers (Strictly Profitable)
            drawSectionTitle("Top Profitable Vehicles", at: CGPoint(x: margin, y: y))
            y += 25
            drawTopProfitable(data: data, margin: margin, y: &y, width: contentWidth)
            
            y += 30
            
            // Loss Makers (if any)
            let lossMakers = data.soldVehicles.filter {
                let profit = ($0.salePrice?.decimalValue ?? 0) - ($0.purchasePrice?.decimalValue ?? 0) - totalCostExpenses($0)
                return profit < 0
            }
            
            if !lossMakers.isEmpty {
                drawSectionTitle("Loss Making Sales", at: CGPoint(x: margin, y: y), color: .systemRed)
                y += 25
                drawLossMakers(vehicles: lossMakers, margin: margin, y: &y, width: contentWidth)
                 y += 30
            }
            
            // Detailed Sold Vehicles Table
            drawSectionTitle("Sold Vehicles Register", at: CGPoint(x: margin, y: y))
            y += 25
            drawTransactionTable(data: data, margin: margin, y: &y, width: contentWidth, pageRect: pageRect, ctx: ctx)
            
            drawFooter(page: 2)
            
            // --- PAGE 3: Expense Analysis ---
            ctx.beginPage()
            y = 40
            drawHeader(ctx: ctx.cgContext, title: "Expense Breakdown", range: range, margin: margin, y: &y, width: contentWidth)
            
            // Expenses by Category
            drawSectionTitle("Expenses by Category", at: CGPoint(x: margin, y: y))
            y += 25
            drawExpenseAnalysis(data: data, margin: margin, y: &y, width: contentWidth)
            
            y += 30
            
            // Top Expense Generators (Vehicles with highest expenses)
            drawSectionTitle("Top Cost-Heavy Vehicles (In Stock)", at: CGPoint(x: margin, y: y))
            y += 25
            drawTopExpenseVehicles(data: data, margin: margin, y: &y, width: contentWidth)
             
            drawFooter(page: 3)
        }
        
        let url = makeTempURL(fileName: "Report-\(df.string(from: range.start))-\(df.string(from: range.end)).pdf")
        try pdfData.write(to: url)
        return url
    }
    
    // MARK: - Drawing Helpers
    
    private func drawHeader(ctx: CGContext, title: String, range: DateInterval, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        // Logo or Company Name placeholder could go here
        let companyName = "Car Dealer Tracker"
        let companyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.secondaryLabel]
        companyName.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: companyAttrs)
        
        y += 15
        
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: UIColor.black]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 35
        
        let df = DateFormatter()
        df.dateStyle = .long
        let dateStr = "Period: \(df.string(from: range.start)) — \(df.string(from: range.end))"
        let subAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: UIColor.darkGray]
        dateStr.draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
        
        // Generator timestamp
        let genStr = "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        let genAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.lightGray]
        let genSize = genStr.size(withAttributes: genAttrs)
        genStr.draw(at: CGPoint(x: margin + width - genSize.width, y: y + 4), withAttributes: genAttrs)
        
        y += 30
        
        // Professional Divider
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + width, y: y))
        UIColor.black.setStroke()
        path.lineWidth = 1.5
        path.stroke()
        y += 30
    }
    
    private func drawFinancialOverview(data: ReportData, previousData: ReportData?, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        let labels = ["Revenue (Sales)", "Cost of Goods Sold", "Gross Profit", "Operating Expenses", "Net Profit"]
        let values = [
            data.totalSales,
            data.costOfGoodsSold,
            data.grossProfit,
            data.totalExpenses,
            data.netProfit
        ]
        
        let rowHeight: CGFloat = 24
        
        // Draw Header
        "ITEM".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.gray])
        let valX = margin + width - 100
        "AMOUNT".draw(at: CGPoint(x: valX, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.gray])
        y += 15
        
        UIColor.systemGray5.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + width, y: y))
        path.lineWidth = 0.5
        path.stroke()
        y += 10
        
        for (i, label) in labels.enumerated() {
            let val = values[i]
            let isBold = i == 2 || i == 4 // Gross Profit & Net Profit
            let isNet = i == 4
            let font = isBold ? UIFont.systemFont(ofSize: 12, weight: .bold) : UIFont.systemFont(ofSize: 12)
            let color = isNet ? (val >= 0 ? UIColor.black : UIColor.systemRed) : UIColor.black
            
            label.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            
            let valStr = val.asCurrencyFallback()
            let valAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let valSize = valStr.size(withAttributes: valAttrs)
            valStr.draw(at: CGPoint(x: margin + width - valSize.width, y: y), withAttributes: valAttrs)
            
            y += rowHeight
            
            if i == 2 { y += 5 } // Spacer after Gross Profit
        }
    }
    
    private func drawKPIGrid(data: ReportData, previousData: ReportData?, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        let cols = 3
        let cardW = (width - CGFloat(cols - 1) * 15) / CGFloat(cols)
        let cardH: CGFloat = 70
        
        let kpis: [(String, String, UIColor)] = [
            ("Profit Margin", String(format: "%.1f%%", NSDecimalNumber(decimal: data.margin).doubleValue), data.margin >= 10 ? .systemGreen : (data.margin > 0 ? .systemOrange : .systemRed)),
            ("Vehicles Sold", "\(data.soldVehicles.count)", .black),
            ("Avg Days to Sell", "\(data.avgDaysToSell)", data.avgDaysToSell < 45 ? .systemGreen : .systemOrange)
        ]
        
        for (i, kpi) in kpis.enumerated() {
            let col = CGFloat(i % cols)
            let x = margin + col * (cardW + 15)
            
            // Draw Container
            let rect = CGRect(x: x, y: y, width: cardW, height: cardH)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            UIColor(white: 0.96, alpha: 1).setFill()
            path.fill()
            
            // Title
            kpi.0.uppercased().draw(at: CGPoint(x: x + 10, y: y + 12), withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: UIColor.secondaryLabel])
            
            // Value
            kpi.1.draw(at: CGPoint(x: x + 10, y: y + 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .heavy), .foregroundColor: kpi.2])
        }
        
        y += cardH + 10
    }
    
    private func drawInventorySnapshot(data: ReportData, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        let stats = [
            "Current Inventory:": "\(data.inventory.count) vehicles",
            "Capital Locked/Invested:": data.capitalLocked.asCurrencyFallback(),
            "Est. Projected Profit (Avg):": (data.avgProfitPerCar * Decimal(data.inventory.count)).asCurrencyFallback()
        ]
        
        for (label, val) in stats {
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.secondaryLabel]
            label.draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            
            let valAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.label]
            let valSize = val.size(withAttributes: valAttrs)
            val.draw(at: CGPoint(x: margin + width - valSize.width, y: y), withAttributes: valAttrs)
            
            y += 20
        }
    }
    
    private func drawTopProfitable(data: ReportData, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        // Only strictly profitable
        let profitable = data.soldVehicles.filter {
            let profit = ($0.salePrice?.decimalValue ?? 0) - ($0.purchasePrice?.decimalValue ?? 0) - totalCostExpenses($0)
            return profit > 0
        }.sorted { v1, v2 in
            let p1 = (v1.salePrice?.decimalValue ?? 0) - (v1.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v1)
            let p2 = (v2.salePrice?.decimalValue ?? 0) - (v2.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v2)
            return p1 > p2
        }
        
        if profitable.isEmpty {
            "No profitable sales recorded in this period.".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12), .foregroundColor: UIColor.secondaryLabel])
            y += 20
            return
        }
        
        for (i, v) in profitable.prefix(3).enumerated() {
            let profit = (v.salePrice?.decimalValue ?? 0) - (v.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v)
            let name = "\(v.make ?? "") \(v.model ?? "")"
            
            let text = "\(i+1). \(name)"
            text.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium)])
            
            let amount = profit.asCurrencyFallback()
            let amountAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.systemGreen]
            let size = amount.size(withAttributes: amountAttrs)
            amount.draw(at: CGPoint(x: margin + width - size.width, y: y), withAttributes: amountAttrs)
            
            y += 20
        }
    }
    
    private func drawLossMakers(vehicles: [Vehicle], margin: CGFloat, y: inout CGFloat, width: CGFloat) {
         let sorted = vehicles.sorted { v1, v2 in
            let p1 = (v1.salePrice?.decimalValue ?? 0) - (v1.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v1)
            let p2 = (v2.salePrice?.decimalValue ?? 0) - (v2.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v2)
            return p1 < p2 // Most negative first
        }
        
        for v in sorted {
            let profit = (v.salePrice?.decimalValue ?? 0) - (v.purchasePrice?.decimalValue ?? 0) - totalCostExpenses(v)
            let name = "\(v.make ?? "") \(v.model ?? "")"
            
            let text = "• \(name)"
            text.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.systemRed])
            
            let amount = profit.asCurrencyFallback()
            let amountAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.systemRed]
            let size = amount.size(withAttributes: amountAttrs)
            amount.draw(at: CGPoint(x: margin + width - size.width, y: y), withAttributes: amountAttrs)
            
            y += 20
        }
    }
    
    private func drawTransactionTable(data: ReportData, margin: CGFloat, y: inout CGFloat, width: CGFloat, pageRect: CGRect, ctx: UIGraphicsPDFRendererContext) {
        // Table Headers
        let headers = ["Vehicle", "Sold Date", "Sale Price", "Cost+Exp", "Profit"]
        let colWidths: [CGFloat] = [width * 0.4, width * 0.15, width * 0.15, width * 0.15, width * 0.15]
        
        let headerBg = CGRect(x: margin, y: y - 5, width: width, height: 20)
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: headerBg, cornerRadius: 4).fill()
        
        var x = margin + 5
        for (i, h) in headers.enumerated() {
            h.uppercased().draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: UIColor.darkGray])
            x += colWidths[i]
        }
        y += 25
        
        for v in data.soldVehicles {
            // New page check
            if y > pageRect.height - 60 {
                ctx.beginPage()
                y = 40
                // Re-draw header if needed, for now just continue
            }
            
            let sellPrice = v.salePrice?.decimalValue ?? 0
            let buyPrice = v.purchasePrice?.decimalValue ?? 0
            let expenses = totalCostExpenses(v)
            let totalCost = buyPrice + expenses
            let profit = sellPrice - totalCost
            
            let dateStr = v.saleDate?.formatted(date: .numeric, time: .omitted) ?? "-"
            
            x = margin + 5
            
            // Name
            "\(v.make ?? "") \(v.model ?? "")".draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            x += colWidths[0]
            
            // Date
            dateStr.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            x += colWidths[1]
            
            // Sale Price
            sellPrice.asCurrencyFallback().draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            x += colWidths[2]
            
            // Total Cost
            totalCost.asCurrencyFallback().draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            x += colWidths[3]
            
            // Profit
            let color = profit >= 0 ? UIColor.systemGreen : UIColor.systemRed
            profit.asCurrencyFallback().draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: color])
            
            y += 20
        }
    }
    
    private func drawExpenseAnalysis(data: ReportData, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        let categories = Dictionary(grouping: data.expenses, by: { $0.category ?? "Uncategorized" })
            .mapValues { $0.reduce(Decimal(0)) { sum, e in sum + (e.amount?.decimalValue ?? 0) } }
            .sorted { $0.value > $1.value }
        
        let maxVal = categories.first?.value ?? 1
        
        for (cat, amount) in categories.prefix(6) {
            cat.capitalized.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            
            let barStart: CGFloat = margin + 100
            let barMaxW: CGFloat = width - 180
            let pct = NSDecimalNumber(decimal: amount / maxVal).doubleValue
            let barW = CGFloat(pct) * barMaxW
            
            let rect = CGRect(x: barStart, y: y + 3, width: max(barW, 2), height: 8)
            UIColor.systemBlue.withAlphaComponent(0.7).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2.5).fill()
            
            amount.asCurrencyFallback().draw(at: CGPoint(x: barStart + barW + 10, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold)])
            
            y += 18
        }
    }
    
    private func drawTopExpenseVehicles(data: ReportData, margin: CGFloat, y: inout CGFloat, width: CGFloat) {
        // Group expenses by vehicle
        var vehicleExpenses: [UUID: Decimal] = [:]
        var vehicleNames: [UUID: String] = [:]
        
        for exp in data.expenses {
            if let v = exp.vehicle, let id = v.id {
                vehicleExpenses[id, default: 0] += (exp.amount?.decimalValue ?? 0)
                vehicleNames[id] = "\(v.make ?? "") \(v.model ?? "")"
            }
        }
        
        let sorted = vehicleExpenses.sorted { $0.value > $1.value }
        
        if sorted.isEmpty {
            "No vehicle-specific expenses recorded.".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12), .foregroundColor: UIColor.secondaryLabel])
            return
        }
        
        let headers = ["Vehicle", "Total Spent"]
        "\(headers[0])".draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.gray])
        "\(headers[1])".draw(at: CGPoint(x: margin + width - 60, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.gray])
        y += 15
        
        for (id, amount) in sorted.prefix(5) {
            let name = vehicleNames[id] ?? "Unknown Vehicle"
            name.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            
            let val = amount.asCurrencyFallback()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            let size = val.size(withAttributes: attrs)
            val.draw(at: CGPoint(x: margin + width - size.width, y: y), withAttributes: attrs)
            
            y += 18
        }
    }

    private func drawSectionTitle(_ title: String, at point: CGPoint, color: UIColor = .black) {
        title.draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: color])
    }
    
    private func drawFooter(page: Int) {
        let text = "Car Dealer Tracker — Confidential Report • Page \(page)"
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.systemGray]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: 306 - size.width/2, y: 760), withAttributes: attrs)
    }

    // Helper to calculate total expenses for a vehicle
    private func totalCostExpenses(_ vehicle: Vehicle) -> Decimal {
        if let expenses = vehicle.expenses as? Set<Expense> {
            return expenses.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        }
        return 0
    }

    func createRangeArchive(for range: DateInterval, dealerId: UUID?) async throws -> URL {
        let expensesCSV = try exportExpensesCSV(range: range)
        let vehiclesCSV = try exportVehiclesCSV()
        let clientsCSV = try exportClientsCSV()
        let pdf = try generateReportPDF(for: range)
        let metadata = try makeMetadataSnapshot(range: range)

        func filePayload(for url: URL, contentType: String) throws -> ArchiveFilePayload {
            let data = try Data(contentsOf: url)
            return ArchiveFilePayload(
                name: url.lastPathComponent,
                contentType: contentType,
                base64: data.base64EncodedString()
            )
        }

        let payload = BackupArchivePayload(
            generatedAt: Date(),
            rangeStart: range.start,
            rangeEnd: range.end,
            metadata: metadata,
            files: try [
                filePayload(for: expensesCSV, contentType: "text/csv"),
                filePayload(for: vehiclesCSV, contentType: "text/csv"),
                filePayload(for: clientsCSV, contentType: "text/csv"),
                filePayload(for: pdf, contentType: "application/pdf")
            ]
        )

        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("ezcar-backup-\(timestamp()).json")
        try FileManager.default.removeIfExists(at: archiveURL)
        try JSONEncoder().encode(payload).write(to: archiveURL)

        if let dealerId = dealerId {
            await cloudSyncManager?.uploadBackupArchive(at: archiveURL, dealerId: dealerId)
        }

        return archiveURL
    }

    // MARK: - Helpers

    // MARK: - Data Fetching Helpers

    private func fetchExpenses(range: DateInterval? = nil) throws -> [Expense] {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        if let range {
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        }
        var results: [Expense] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }

    private func fetchVehicles() throws -> [Vehicle] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        var results: [Vehicle] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }
    
    private func fetchInventory() throws -> [Vehicle] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "status != %@", "sold")
        var results: [Vehicle] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }
    
    private func fetchSoldVehicles(range: DateInterval) throws -> [Vehicle] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        // Assuming 'saleDate' is the property for when it was sold
        request.predicate = NSPredicate(format: "status == %@ AND saleDate >= %@ AND saleDate < %@", "sold", range.start as NSDate, range.end as NSDate)
        var results: [Vehicle] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }

    private func fetchClients() throws -> [Client] {
        let request: NSFetchRequest<Client> = Client.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        var results: [Client] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }

    private func fetchSales(range: DateInterval? = nil) throws -> [Sale] {
        let request: NSFetchRequest<Sale> = Sale.fetchRequest()
        if let range {
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate)
        }
        var results: [Sale] = []
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }
    
    // MARK: - Analytics Calculation
    
    struct ReportData {
        let range: DateInterval
        let soldVehicles: [Vehicle]
        let expenses: [Expense]
        let inventory: [Vehicle]
        
        // KPIs
        var totalSales: Decimal {
            soldVehicles.reduce(Decimal(0)) { $0 + ($1.salePrice?.decimalValue ?? 0) }
        }
        var totalExpenses: Decimal {
            expenses.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) }
        }
        var costOfGoodsSold: Decimal {
            soldVehicles.reduce(Decimal(0)) { $0 + ($1.purchasePrice?.decimalValue ?? 0) }
        }
        // Gross Profit (Sales - COGS)
        var grossProfit: Decimal {
            totalSales - costOfGoodsSold
        }
        // Net Profit (Gross Profit - Expenses)
        var netProfit: Decimal {
            grossProfit - totalExpenses
        }
        var margin: Decimal {
            totalSales > 0 ? (netProfit / totalSales) * 100 : 0
        }
        var avgProfitPerCar: Decimal {
            soldVehicles.isEmpty ? 0 : netProfit / Decimal(soldVehicles.count)
        }
        var roi: Decimal {
            let invested = costOfGoodsSold + totalExpenses
            return invested > 0 ? (netProfit / invested) * 100 : 0
        }
        
        // Inventory
        var capitalLocked: Decimal {
            inventory.reduce(Decimal(0)) { $0 + ($1.purchasePrice?.decimalValue ?? 0) }
        }
        
        // Time
        var avgDaysToSell: Int {
            let days = soldVehicles.compactMap { vehicle -> Int? in
                guard let sold = vehicle.saleDate, let bought = vehicle.purchaseDate else { return nil }
                return Calendar.current.dateComponents([.day], from: bought, to: sold).day
            }
            return days.isEmpty ? 0 : days.reduce(0, +) / days.count
        }
    }
    
    private func prepareReportData(range: DateInterval) throws -> ReportData {
        let sold = try fetchSoldVehicles(range: range)
        let expenses = try fetchExpenses(range: range)
        let inventory = try fetchInventory()
        return ReportData(range: range, soldVehicles: sold, expenses: expenses, inventory: inventory)
    }

    private func makeMetadataSnapshot(range: DateInterval) throws -> BackupMetadata {
        let data = try prepareReportData(range: range)
        
        let categories = Dictionary(grouping: data.expenses, by: { $0.category ?? "uncategorized" })
            .mapValues { group in group.reduce(Decimal(0)) { $0 + ($1.amount?.decimalValue ?? 0) } }

        return BackupMetadata(
            generatedAt: Date(),
            rangeStart: range.start,
            rangeEnd: range.end,
            expenseTotal: data.totalExpenses,
            salesTotal: data.totalSales,
            netResult: data.netProfit,
            expenseTotalsByCategory: categories
        )
    }

    private func write(content: String, fileName: String) throws -> URL {
        let url = makeTempURL(fileName: fileName)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }

    private func monthDateRange(for date: Date) -> DateInterval {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }
}

struct BackupMetadata: Codable {
    let generatedAt: Date
    let rangeStart: Date
    let rangeEnd: Date
    let expenseTotal: Decimal
    let salesTotal: Decimal
    let netResult: Decimal
    let expenseTotalsByCategory: [String: Decimal]
}

struct ArchiveFilePayload: Codable {
    let name: String
    let contentType: String
    let base64: String
}

struct BackupArchivePayload: Codable {
    let generatedAt: Date
    let rangeStart: Date
    let rangeEnd: Date
    let metadata: BackupMetadata
    let files: [ArchiveFilePayload]
}

private extension FileManager {
    func removeIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
