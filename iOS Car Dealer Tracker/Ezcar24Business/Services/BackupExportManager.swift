import Foundation
import CoreData
import Combine
import UIKit

@MainActor
final class BackupExportManager: ObservableObject {
    private let context: NSManagedObjectContext
    weak var cloudSyncManager: CloudSyncManager?

    init(context: NSManagedObjectContext, cloudSyncManager: CloudSyncManager? = nil) {
        self.context = context
        self.cloudSyncManager = cloudSyncManager
    }

    func exportExpensesCSV(range: DateInterval? = nil) throws -> URL {
        let expenses = try fetchExpenses(range: range)
        var csv = "Date,Description,Category,Amount,Vehicle,User,Account\n"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for expense in expenses {
            let date = expense.date.map { formatter.string(from: $0) } ?? ""
            let description = expense.expenseDescription ?? ""
            let category = expense.category ?? ""
            let amount = (expense.amount?.decimalValue ?? 0).asCurrencyFallback()
            let vehicle = [expense.vehicle?.make, expense.vehicle?.model]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let user = expense.user?.name ?? ""
            let account = expense.account?.accountType ?? ""

            csv += [date, description, category, amount, vehicle, user, account]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }

        return try write(content: csv, fileName: "expenses-\(timestamp()).csv")
    }

    func exportVehiclesCSV() throws -> URL {
        let vehicles = try fetchVehicles()
        var csv = "Inventory ID,VIN,Make,Model,Year,Purchase Price,Status,Notes,Created At\n"
        let formatter = ISO8601DateFormatter()

        for vehicle in vehicles {
            let inventoryID = vehicle.inventoryIDValue ?? ""
            let vin = vehicle.vin ?? ""
            let make = vehicle.make ?? ""
            let model = vehicle.model ?? ""
            let year = vehicle.year
            let purchasePrice = (vehicle.purchasePrice?.decimalValue ?? 0).asCurrencyFallback()
            let status = vehicle.status ?? ""
            let notes = vehicle.notes ?? ""
            let createdAt = vehicle.createdAt.map { formatter.string(from: $0) } ?? ""

            csv += [inventoryID, vin, make, model, "\(year)", purchasePrice, status, notes, createdAt]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }

        return try write(content: csv, fileName: "vehicles-\(timestamp()).csv")
    }

    func exportClientsCSV() throws -> URL {
        let clients = try fetchClients()
        let formatter = ISO8601DateFormatter()
        var csv = "Name,Phone,Email,Notes,Created At,Next Reminder\n"

        for client in clients {
            let name = client.name ?? ""
            let phone = client.phone ?? ""
            let email = client.email ?? ""
            let notes = client.notes ?? ""
            let createdAt = client.createdAt.map { formatter.string(from: $0) } ?? ""
            let reminder = client.nextReminder?.dueDate.map { formatter.string(from: $0) } ?? ""

            csv += [name, phone, email, notes, createdAt, reminder]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }

        return try write(content: csv, fileName: "clients-\(timestamp()).csv")
    }

    func generateMonthlyReportPDF(for month: ReportMonth, dealerId: UUID?) throws -> URL {
        let snapshot = try makeSnapshot(for: month, dealerId: dealerId)
        let fileName = "monthly-report-\(month.id)-\(timestamp()).pdf"
        return try renderPDF(snapshot: snapshot, fileName: fileName)
    }

    func generateReportPDF(for range: DateInterval) throws -> URL {
        let snapshot = try makeSnapshot(for: range, dealerId: CloudSyncEnvironment.currentDealerId)
        let fileName = "report-\(timestamp()).pdf"
        return try renderPDF(snapshot: snapshot, fileName: fileName)
    }

    func createRangeArchive(for range: DateInterval, dealerId: UUID?) async throws -> URL {
        let expensesCSV = try exportExpensesCSV(range: range)
        let vehiclesCSV = try exportVehiclesCSV()
        let clientsCSV = try exportClientsCSV()
        let pdf = try generateReportPDF(for: range)
        let metadata = try makeMetadataSnapshot(range: range, dealerId: dealerId)

        let transientFiles = [expensesCSV, vehiclesCSV, clientsCSV, pdf]
        defer {
            transientFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        }

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

    private func fetchExpenses(range: DateInterval? = nil) throws -> [Expense] {
        let request = NSFetchRequest<Expense>(entityName: "Expense")
        var predicates = [NSPredicate(format: "deletedAt == nil")]
        if let range {
            predicates.append(NSPredicate(format: "date >= %@ AND date < %@", range.start as NSDate, range.end as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchVehicles() throws -> [Vehicle] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    private func fetchClients() throws -> [Client] {
        let request: NSFetchRequest<Client> = Client.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    private func makeSnapshot(for month: ReportMonth, dealerId: UUID?) throws -> MonthlyReportSnapshot {
        let builder = MonthlyReportSnapshotBuilder(context: context)
        if let dealerId {
            return try builder.build(for: month, dealerId: dealerId)
        }
        return try builder.build(
            for: month.interval,
            title: month.displayTitle,
            dealerId: nil,
            reportMonth: month
        )
    }

    private func makeSnapshot(for range: DateInterval, dealerId: UUID?) throws -> MonthlyReportSnapshot {
        let builder = MonthlyReportSnapshotBuilder(context: context)
        return try builder.build(for: range, dealerId: dealerId)
    }

    private func makeMetadataSnapshot(range: DateInterval, dealerId: UUID?) throws -> BackupMetadata {
        let snapshot = try makeSnapshot(for: range, dealerId: dealerId)
        let categories = Dictionary(uniqueKeysWithValues: snapshot.expenseCategories.map { ($0.key, $0.amount) })

        return BackupMetadata(
            generatedAt: Date(),
            rangeStart: range.start,
            rangeEnd: range.end,
            expenseTotal: snapshot.executiveSummary.monthlyExpenses,
            salesTotal: snapshot.executiveSummary.totalRevenue,
            netResult: snapshot.executiveSummary.realizedSalesProfit - snapshot.executiveSummary.monthlyExpenses,
            expenseTotalsByCategory: categories
        )
    }

    private func renderPDF(snapshot: MonthlyReportSnapshot, fileName: String) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let printableRect = CGRect(x: 26, y: 26, width: 560, height: 724)
        let formatter = UIMarkupTextPrintFormatter(markupText: makePDFHTML(snapshot: snapshot))
        let renderer = MonthlyReportPDFPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(pageRect, forKey: "paperRect")
        renderer.setValue(printableRect, forKey: "printableRect")

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        let pageCount = renderer.numberOfPages

        for pageIndex in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            let bounds = UIGraphicsGetPDFContextBounds()
            renderer.drawPage(at: pageIndex, in: bounds)
        }

        UIGraphicsEndPDFContext()

        let url = makeTempURL(fileName: fileName)
        try FileManager.default.removeIfExists(at: url)
        try pdfData.write(to: url)
        return url
    }

    private func makePDFHTML(snapshot: MonthlyReportSnapshot) -> String {
        let summary = snapshot.executiveSummary
        let executiveBrief = executiveBriefHTML(snapshot: snapshot)
        let financialChart = makeBarChartRows([
            PDFChartDatum(label: "Total revenue", value: summary.totalRevenue, colorHex: "#2563eb"),
            PDFChartDatum(label: "Realized sales profit", value: summary.realizedSalesProfit, colorHex: "#059669"),
            PDFChartDatum(label: "Monthly expenses", value: summary.monthlyExpenses, colorHex: "#ea580c"),
            PDFChartDatum(label: "Net cash movement", value: summary.netCashMovement, colorHex: summary.netCashMovement >= 0 ? "#4f46e5" : "#dc2626")
        ])

        let expenseMix = snapshot.topExpenseCategories.isEmpty
            ? emptyStateHTML("No expense categories in this period.")
            : makeBarChartRows(snapshot.topExpenseCategories.map {
                PDFChartDatum(
                    label: "\($0.title) (\($0.count) entries)",
                    value: $0.amount,
                    colorHex: "#f59e0b"
                )
            })

        let vehicleSalesSection = sectionHTML(
            title: "Vehicle Sales",
            subtitle: "Realized vehicle transactions with purchase, expense, holding, and VAT impact.",
            badges: [
                ("Sold", "\(snapshot.vehicleSales.count)"),
                ("Revenue", summary.vehicleRevenue.asCurrencyFallback()),
                ("Vehicle profit", summary.vehicleProfit.asCurrencyFallback())
            ],
            content: snapshot.vehicleSales.isEmpty
                ? emptyStateHTML("No vehicle sales recorded in this period.")
                : dataTableHTML(
                    headers: ["Vehicle", "Sold", "Revenue", "Profit"],
                    rows: snapshot.vehicleSales.map { sale in
                        [
                            primaryDetailCellHTML(
                                title: sale.title,
                                detail: "\(escapeHTML(shortDateString(sale.soldAt))) • \(escapeHTML(sale.buyerName))<br><span class=\"muted\">Purchase \(escapeHTML(sale.purchasePrice.asCurrencyFallback())) • Expenses \(escapeHTML(sale.vehicleExpenses.asCurrencyFallback())) • Holding \(escapeHTML(sale.holdingCost.asCurrencyFallback())) • VAT refund \(escapeHTML(sale.vatRefund.asCurrencyFallback()))</span>"
                            ),
                            plainCellHTML(shortDateString(sale.soldAt)),
                            amountCellHTML(sale.revenue),
                            amountCellHTML(sale.realizedProfit, emphasize: true)
                        ]
                    }
                )
        )

        let partSalesSection = sectionHTML(
            title: "Part Sales",
            subtitle: "Realized part sales with revenue and cost of goods sold.",
            badges: [
                ("Orders", "\(snapshot.partSales.count)"),
                ("Revenue", summary.partRevenue.asCurrencyFallback()),
                ("Part profit", summary.partProfit.asCurrencyFallback())
            ],
            content: snapshot.partSales.isEmpty
                ? emptyStateHTML("No part sales recorded in this period.")
                : dataTableHTML(
                    headers: ["Sale", "Buyer", "Revenue", "Profit"],
                    rows: snapshot.partSales.map { sale in
                        [
                            primaryDetailCellHTML(
                                title: sale.summary,
                                detail: "\(escapeHTML(shortDateString(sale.soldAt)))<br><span class=\"muted\">COGS \(escapeHTML(sale.costOfGoodsSold.asCurrencyFallback()))</span>"
                            ),
                            plainCellHTML(sale.buyerName),
                            amountCellHTML(sale.revenue),
                            amountCellHTML(sale.realizedProfit, emphasize: true)
                        ]
                    }
                )
        )

        let expenseSection = sectionHTML(
            title: "Expense Activity",
            subtitle: "Monthly expenses tracked separately from realized sales profit.",
            badges: [
                ("Entries", "\(snapshot.expenseActivity.count)"),
                ("Monthly expenses", summary.monthlyExpenses.asCurrencyFallback())
            ],
            content: snapshot.expenseActivity.isEmpty
                ? emptyStateHTML("No expenses recorded in this period.")
                : dataTableHTML(
                    headers: ["Expense", "Date", "Category", "Amount"],
                    rows: snapshot.expenseActivity.map { expense in
                        [
                            primaryDetailCellHTML(
                                title: expense.title,
                                detail: expense.vehicleTitle.map { "Vehicle: \(escapeHTML($0))" } ?? "General expense"
                            ),
                            plainCellHTML(shortDateString(expense.date)),
                            plainCellHTML(expense.categoryTitle),
                            amountCellHTML(expense.amount)
                        ]
                    }
                )
        )

        let cashSection = sectionHTML(
            title: "Account Transaction Cash Movement",
            subtitle: "Deposits and withdrawals that affected cash during the month.",
            badges: [
                ("Deposits", summary.depositsTotal.asCurrencyFallback()),
                ("Withdrawals", summary.withdrawalsTotal.asCurrencyFallback()),
                ("Net movement", summary.netCashMovement.asCurrencyFallback())
            ],
            content: snapshot.cashMovement.rows.isEmpty
                ? emptyStateHTML("No account transactions recorded in this period.")
                : dataTableHTML(
                    headers: ["Account", "Date", "Note", "Amount"],
                    rows: snapshot.cashMovement.rows.map { row in
                        [
                            plainCellHTML(row.title),
                            plainCellHTML(shortDateString(row.date)),
                            plainCellHTML(row.note),
                            amountCellHTML(row.signedAmount, emphasize: true)
                        ]
                    }
                )
        )

        let inventorySection = sectionHTML(
            title: "Inventory Snapshot",
            subtitle: "Current non-deleted vehicles still in stock at report time.",
            badges: [
                ("Vehicles in stock", "\(summary.inventoryCount)"),
                ("Inventory capital", summary.inventoryCapital.asCurrencyFallback())
            ],
            content: snapshot.inventorySnapshot.isEmpty
                ? emptyStateHTML("No active vehicles in stock.")
                : dataTableHTML(
                    headers: ["Vehicle", "Status", "Purchase", "Cost basis"],
                    rows: snapshot.inventorySnapshot.map { vehicle in
                        [
                            primaryDetailCellHTML(
                                title: vehicle.title,
                                detail: "Expenses \(escapeHTML(vehicle.totalExpenses.asCurrencyFallback()))"
                            ),
                            plainCellHTML(vehicle.status.replacingOccurrences(of: "_", with: " ").capitalized),
                            amountCellHTML(vehicle.purchasePrice),
                            amountCellHTML(vehicle.costBasis, emphasize: true)
                        ]
                    }
                )
        )

        let partsSection = sectionHTML(
            title: "Parts Snapshot",
            subtitle: "Current non-deleted parts inventory and on-hand cost.",
            badges: [
                ("Units in stock", decimalString(summary.partsUnitsInStock)),
                ("Inventory cost", summary.partsInventoryCost.asCurrencyFallback())
            ],
            content: snapshot.partsSnapshot.isEmpty
                ? emptyStateHTML("No parts inventory in stock.")
                : dataTableHTML(
                    headers: ["Part", "Code", "Qty", "Inventory cost"],
                    rows: snapshot.partsSnapshot.map { part in
                        [
                            plainCellHTML(part.name),
                            plainCellHTML(part.code.isEmpty ? "-" : part.code),
                            plainCellHTML(decimalString(part.quantityOnHand)),
                            amountCellHTML(part.inventoryCost, emphasize: true)
                        ]
                    }
                )
        )

        let topProfitableSection = sectionHTML(
            title: "Top Profitable Vehicles",
            subtitle: "Best realized vehicle sales in the selected month.",
            badges: [],
            content: snapshot.topProfitableVehicles.isEmpty
                ? emptyStateHTML("No profitable vehicle sales in this period.")
                : dataTableHTML(
                    headers: ["Vehicle", "Sold", "Profit"],
                    rows: snapshot.topProfitableVehicles.map { sale in
                        [
                            plainCellHTML(sale.title),
                            plainCellHTML(shortDateString(sale.soldAt)),
                            amountCellHTML(sale.realizedProfit, emphasize: true)
                        ]
                    }
                )
        )

        let lossMakingSection = sectionHTML(
            title: "Loss-Making Vehicles",
            subtitle: "Vehicle sales that closed below their realized cost basis.",
            badges: [],
            content: snapshot.lossMakingVehicles.isEmpty
                ? emptyStateHTML("No loss-making vehicle sales in this period.")
                : dataTableHTML(
                    headers: ["Vehicle", "Sold", "Profit"],
                    rows: snapshot.lossMakingVehicles.map { sale in
                        [
                            plainCellHTML(sale.title),
                            plainCellHTML(shortDateString(sale.soldAt)),
                            amountCellHTML(sale.realizedProfit, emphasize: true)
                        ]
                    }
                )
        )

        let expenseCategorySection = sectionHTML(
            title: "Top Expense Categories",
            subtitle: "Where monthly spend concentrated the most.",
            badges: [],
            content: snapshot.topExpenseCategories.isEmpty
                ? emptyStateHTML("No expense categories in this period.")
                : dataTableHTML(
                    headers: ["Category", "Entries", "Amount"],
                    rows: snapshot.topExpenseCategories.map { category in
                        [
                            plainCellHTML(category.title),
                            plainCellHTML("\(category.count)"),
                            amountCellHTML(category.amount, emphasize: true)
                        ]
                    }
                )
        )

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
            color: #0f172a;
            background: #f3f6fb;
            font-size: 12px;
            line-height: 1.45;
        }
        .shell { padding: 18px; }
        .hero {
            background: #11233a;
            color: #ffffff;
            border-radius: 24px;
            padding: 26px 28px;
            margin-bottom: 16px;
        }
        .eyebrow {
            font-size: 10px;
            letter-spacing: 1.6px;
            text-transform: uppercase;
            color: rgba(255,255,255,0.74);
            margin-bottom: 8px;
        }
        .hero h1 {
            margin: 0 0 6px 0;
            font-size: 30px;
            line-height: 1.1;
            font-weight: 750;
        }
        .hero h2 {
            margin: 0;
            font-size: 17px;
            color: rgba(255,255,255,0.78);
            font-weight: 600;
        }
        .hero-meta {
            margin-top: 18px;
            width: 100%;
            border-collapse: separate;
            border-spacing: 12px;
        }
        .hero-meta td {
            background: rgba(255,255,255,0.08);
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 14px;
            padding: 12px 14px;
            vertical-align: top;
        }
        .meta-label {
            display: block;
            font-size: 10px;
            letter-spacing: 1px;
            text-transform: uppercase;
            color: rgba(255,255,255,0.66);
            margin-bottom: 4px;
        }
        .metric-grid {
            width: 100%;
            border-collapse: separate;
            border-spacing: 12px;
            margin-bottom: 16px;
        }
        .metric-card {
            background: #ffffff;
            border: 1px solid #d9e3ef;
            border-top: 5px solid #2563eb;
            border-radius: 18px;
            padding: 16px 16px 14px;
        }
        .metric-card.green { border-top-color: #059669; }
        .metric-card.orange { border-top-color: #ea580c; }
        .metric-card.indigo { border-top-color: #4f46e5; }
        .metric-title {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #64748b;
            margin-bottom: 8px;
        }
        .metric-value {
            font-size: 24px;
            font-weight: 760;
            line-height: 1.15;
            color: #0f172a;
        }
        .metric-detail {
            margin-top: 6px;
            font-size: 11px;
            color: #64748b;
        }
        .signal-banner {
            border-radius: 18px;
            padding: 16px 18px;
            margin-bottom: 14px;
            border: 1px solid #dbe5f0;
        }
        .signal-banner.good {
            background: #ecfdf5;
            border-color: #a7f3d0;
        }
        .signal-banner.mixed {
            background: #eff6ff;
            border-color: #bfdbfe;
        }
        .signal-banner.warning {
            background: #fff7ed;
            border-color: #fed7aa;
        }
        .signal-title {
            font-size: 17px;
            font-weight: 760;
            color: #0f172a;
            margin-bottom: 4px;
        }
        .signal-detail {
            color: #475569;
        }
        .highlight-grid {
            width: 100%;
            border-collapse: separate;
            border-spacing: 12px;
            margin-bottom: 8px;
        }
        .highlight-card {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 18px;
            padding: 14px 14px 13px;
        }
        .highlight-card.blue { background: #eff6ff; border-color: #bfdbfe; }
        .highlight-card.green { background: #ecfdf5; border-color: #a7f3d0; }
        .highlight-card.orange { background: #fff7ed; border-color: #fed7aa; }
        .highlight-card.indigo { background: #eef2ff; border-color: #c7d2fe; }
        .highlight-title {
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #64748b;
            margin-bottom: 8px;
        }
        .highlight-value {
            font-size: 18px;
            font-weight: 760;
            line-height: 1.2;
            color: #0f172a;
            margin-bottom: 6px;
        }
        .highlight-detail {
            font-size: 11px;
            color: #475569;
        }
        .panel {
            background: #ffffff;
            border: 1px solid #d9e3ef;
            border-radius: 20px;
            padding: 18px 18px 16px;
            margin-bottom: 16px;
        }
        .panel h3 {
            margin: 0;
            font-size: 21px;
            line-height: 1.2;
            font-weight: 760;
            color: #0f172a;
        }
        .panel-subtitle {
            margin-top: 6px;
            margin-bottom: 14px;
            color: #64748b;
            font-size: 12px;
        }
        .badge-row {
            margin-bottom: 14px;
        }
        .badge {
            display: inline-block;
            margin-right: 8px;
            margin-bottom: 8px;
            padding: 8px 12px;
            border-radius: 999px;
            background: #eef4ff;
            color: #1e3a8a;
            font-size: 11px;
            font-weight: 600;
        }
        .badge .muted-inline {
            color: #64748b;
            font-weight: 500;
            margin-right: 4px;
        }
        .chart-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0 10px;
        }
        .chart-label {
            width: 31%;
            padding-right: 10px;
            color: #334155;
            font-weight: 600;
            vertical-align: middle;
        }
        .chart-bar {
            width: 49%;
            vertical-align: middle;
        }
        .bar-track {
            background: #e7edf5;
            border-radius: 999px;
            height: 12px;
            overflow: hidden;
        }
        .bar-fill {
            height: 12px;
            border-radius: 999px;
        }
        .chart-value {
            width: 20%;
            text-align: right;
            font-weight: 700;
            color: #0f172a;
            vertical-align: middle;
            white-space: nowrap;
        }
        .data-table {
            width: 100%;
            border-collapse: collapse;
        }
        .data-table thead th {
            padding: 0 0 10px 0;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.8px;
            color: #64748b;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
        }
        .data-table tbody tr {
            page-break-inside: avoid;
        }
        .data-table tbody td {
            padding: 12px 0;
            border-bottom: 1px solid #edf2f7;
            vertical-align: top;
        }
        .data-table tbody tr:last-child td {
            border-bottom: none;
        }
        .primary-cell {
            font-weight: 650;
            color: #0f172a;
        }
        .muted {
            color: #64748b;
            font-size: 11px;
            font-weight: 500;
        }
        .amount {
            text-align: right;
            font-weight: 700;
            white-space: nowrap;
        }
        .amount.positive {
            color: #059669;
        }
        .amount.negative {
            color: #dc2626;
        }
        .amount.neutral {
            color: #0f172a;
        }
        .empty-state {
            padding: 14px 16px;
            border-radius: 14px;
            background: #f8fafc;
            color: #64748b;
            border: 1px dashed #d4dde8;
        }
        .split-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 12px;
        }
        .split-table td {
            width: 50%;
            vertical-align: top;
        }
        .mini-panel {
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 18px;
            padding: 14px;
        }
        .mini-title {
            font-size: 14px;
            font-weight: 720;
            color: #0f172a;
            margin-bottom: 3px;
        }
        .mini-subtitle {
            font-size: 11px;
            color: #64748b;
            margin-bottom: 10px;
        }
        .stack-track {
            width: 100%;
            height: 14px;
            overflow: hidden;
            border-radius: 999px;
            background: #e7edf5;
            margin-bottom: 12px;
            font-size: 0;
        }
        .stack-segment {
            display: inline-block;
            height: 14px;
        }
        .legend-table {
            width: 100%;
            border-collapse: collapse;
        }
        .legend-table td {
            padding: 4px 0;
            vertical-align: top;
        }
        .legend-swatch {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 999px;
            margin-right: 7px;
            vertical-align: middle;
        }
        .legend-label {
            color: #334155;
            font-weight: 600;
        }
        .legend-value {
            text-align: right;
            white-space: nowrap;
            font-weight: 700;
            color: #0f172a;
        }
        </style>
        </head>
        <body>
        <div class="shell">
            <div class="hero">
                <div class="eyebrow">Car Dealer Tracker</div>
                <h1>Monthly Report Snapshot</h1>
                <h2>\(escapeHTML(snapshot.title))</h2>
                <table class="hero-meta">
                    <tr>
                        <td>
                            <span class="meta-label">Period</span>
                            \(escapeHTML(rangeString(snapshot.range)))
                        </td>
                        <td>
                            <span class="meta-label">Generated</span>
                            \(escapeHTML(DateFormatter.localizedString(from: snapshot.generatedAt, dateStyle: .medium, timeStyle: .short)))
                        </td>
                        <td>
                            <span class="meta-label">Reporting model</span>
                            Accurate split of revenue, realized sales profit, monthly expenses, and cash movement
                        </td>
                    </tr>
                </table>
            </div>

            <div class="panel">
                <h3>Executive Summary</h3>
                <div class="panel-subtitle">A fast scan of revenue, realized profit, expenses, cash movement, and current stock.</div>
                <table class="metric-grid">
                    <tr>
                        <td>\(summaryCardHTML(title: "Total Revenue", value: summary.totalRevenue.asCurrencyFallback(), detail: "Vehicle \(summary.vehicleRevenue.asCurrencyFallback()) • Parts \(summary.partRevenue.asCurrencyFallback())", toneClass: ""))</td>
                        <td>\(summaryCardHTML(title: "Realized Sales Profit", value: summary.realizedSalesProfit.asCurrencyFallback(), detail: "Vehicle \(summary.vehicleProfit.asCurrencyFallback()) • Parts \(summary.partProfit.asCurrencyFallback())", toneClass: "green"))</td>
                    </tr>
                    <tr>
                        <td>\(summaryCardHTML(title: "Monthly Expenses", value: summary.monthlyExpenses.asCurrencyFallback(), detail: "Top categories below", toneClass: "orange"))</td>
                        <td>\(summaryCardHTML(title: "Net Cash Movement", value: summary.netCashMovement.asCurrencyFallback(), detail: "Deposits \(summary.depositsTotal.asCurrencyFallback()) • Withdrawals \(summary.withdrawalsTotal.asCurrencyFallback())", toneClass: "indigo"))</td>
                    </tr>
                </table>
            </div>

            \(executiveBrief)

            <table class="split-table">
                <tr>
                    <td>
                        <div class="panel">
                            <h3>Financial Overview</h3>
                            <div class="panel-subtitle">Relative bar view of the month’s key financial signals.</div>
                            \(financialChart)
                        </div>
                    </td>
                    <td>
                        <div class="panel">
                            <h3>Expense Mix</h3>
                            <div class="panel-subtitle">Top expense categories ranked by amount.</div>
                            \(expenseMix)
                        </div>
                    </td>
                </tr>
            </table>

            \(vehicleSalesSection)
            \(partSalesSection)
            \(expenseSection)
            \(cashSection)
            \(inventorySection)
            \(partsSection)
            \(topProfitableSection)
            \(lossMakingSection)
            \(expenseCategorySection)
        </div>
        </body>
        </html>
        """
    }

    private func sectionHTML(title: String, subtitle: String, badges: [(String, String)], content: String) -> String {
        """
        <div class="panel">
            <h3>\(escapeHTML(title))</h3>
            <div class="panel-subtitle">\(escapeHTML(subtitle))</div>
            \(badgeRowHTML(badges))
            \(content)
        </div>
        """
    }

    private func summaryCardHTML(title: String, value: String, detail: String, toneClass: String) -> String {
        """
        <div class="metric-card \(toneClass)">
            <div class="metric-title">\(escapeHTML(title))</div>
            <div class="metric-value">\(escapeHTML(value))</div>
            <div class="metric-detail">\(escapeHTML(detail))</div>
        </div>
        """
    }

    private func executiveBriefHTML(snapshot: MonthlyReportSnapshot) -> String {
        let summary = snapshot.executiveSummary
        let signal = reportHealthSignal(snapshot)
        let highlights = executiveHighlightCards(snapshot)
        let revenueComposition = stackedComparisonHTML(
            title: "Revenue Composition",
            subtitle: "Vehicle versus part revenue in the selected month.",
            items: [
                PDFStackDatum(label: "Vehicle revenue", value: summary.vehicleRevenue, colorHex: "#2563eb"),
                PDFStackDatum(label: "Part revenue", value: summary.partRevenue, colorHex: "#0ea5e9")
            ],
            emptyMessage: "No revenue recorded in this period."
        )
        let capitalComposition = stackedComparisonHTML(
            title: "Capital Parked In Stock",
            subtitle: "Vehicles versus parts inventory cost at report time.",
            items: [
                PDFStackDatum(label: "Vehicle inventory", value: summary.inventoryCapital, colorHex: "#4f46e5"),
                PDFStackDatum(label: "Parts inventory", value: summary.partsInventoryCost, colorHex: "#f59e0b")
            ],
            emptyMessage: "No inventory capital recorded."
        )

        return """
        <div class="panel">
            <h3>Executive Brief</h3>
            <div class="panel-subtitle">A faster operator-level scan before the detail tables.</div>
            <div class="signal-banner \(signal.toneClass)">
                <div class="signal-title">\(escapeHTML(signal.title))</div>
                <div class="signal-detail">\(escapeHTML(signal.detail))</div>
            </div>
            \(highlightGridHTML(highlights))
            <table class="split-table">
                <tr>
                    <td>\(revenueComposition)</td>
                    <td>\(capitalComposition)</td>
                </tr>
            </table>
        </div>
        """
    }

    private func badgeRowHTML(_ badges: [(String, String)]) -> String {
        guard !badges.isEmpty else { return "" }

        let content = badges.map { title, value in
            """
            <span class="badge"><span class="muted-inline">\(escapeHTML(title))</span>\(escapeHTML(value))</span>
            """
        }
        .joined()

        return "<div class=\"badge-row\">\(content)</div>"
    }

    private func highlightGridHTML(_ cards: [PDFHighlightCard]) -> String {
        let rows = stride(from: 0, to: cards.count, by: 2).map { index in
            let first = highlightCardHTML(cards[index])
            let second = index + 1 < cards.count ? highlightCardHTML(cards[index + 1]) : ""
            return "<tr><td>\(first)</td><td>\(second)</td></tr>"
        }
        .joined()

        return "<table class=\"highlight-grid\">\(rows)</table>"
    }

    private func highlightCardHTML(_ card: PDFHighlightCard) -> String {
        """
        <div class="highlight-card \(card.toneClass)">
            <div class="highlight-title">\(escapeHTML(card.title))</div>
            <div class="highlight-value">\(escapeHTML(card.value))</div>
            <div class="highlight-detail">\(escapeHTML(card.detail))</div>
        </div>
        """
    }

    private func makeBarChartRows(_ values: [PDFChartDatum]) -> String {
        let maxValue = values.map { absoluteDecimal($0.value) }.max() ?? 0
        let safeMax = maxValue > 0 ? maxValue : 1
        let rows = values.map { datum in
            let width = datum.value == 0 ? 0 : max(0.12, min(1, decimalToDouble(absoluteDecimal(datum.value) / safeMax)))
            let toneClass = datum.value > 0 ? "positive" : datum.value < 0 ? "negative" : "neutral"
            return """
            <tr>
                <td class="chart-label">\(escapeHTML(datum.label))</td>
                <td class="chart-bar">
                    <div class="bar-track">
                        <div class="bar-fill" style="width: \(Int(width * 100))%; background: \(datum.colorHex);"></div>
                    </div>
                </td>
                <td class="chart-value \(toneClass)">\(escapeHTML(datum.value.asCurrencyFallback()))</td>
            </tr>
            """
        }
        .joined()

        return "<table class=\"chart-table\">\(rows)</table>"
    }

    private func stackedComparisonHTML(title: String, subtitle: String, items: [PDFStackDatum], emptyMessage: String) -> String {
        let activeItems = items.filter { $0.value > 0 }
        guard !activeItems.isEmpty else {
            return """
            <div class="mini-panel">
                <div class="mini-title">\(escapeHTML(title))</div>
                <div class="mini-subtitle">\(escapeHTML(subtitle))</div>
                \(emptyStateHTML(emptyMessage))
            </div>
            """
        }

        let total = activeItems.reduce(Decimal.zero) { $0 + $1.value }
        let safeTotal = total > 0 ? total : 1
        let segments = activeItems.map { item in
            let width = min(1, max(0, decimalToDouble(item.value / safeTotal)))
            return "<span class=\"stack-segment\" style=\"width: \(Int(width * 100))%; background: \(item.colorHex);\"></span>"
        }
        .joined()

        let legends = activeItems.map { item in
            """
            <tr>
                <td>
                    <span class="legend-swatch" style="background: \(item.colorHex);"></span>
                    <span class="legend-label">\(escapeHTML(item.label))</span>
                </td>
                <td class="legend-value">\(escapeHTML(item.value.asCurrencyFallback())) • \(escapeHTML(percentageString(item.value, total: safeTotal)))</td>
            </tr>
            """
        }
        .joined()

        return """
        <div class="mini-panel">
            <div class="mini-title">\(escapeHTML(title))</div>
            <div class="mini-subtitle">\(escapeHTML(subtitle))</div>
            <div class="stack-track">\(segments)</div>
            <table class="legend-table">\(legends)</table>
        </div>
        """
    }

    private func dataTableHTML(headers: [String], rows: [[String]]) -> String {
        let headerHTML = headers.map { "<th>\(escapeHTML($0))</th>" }.joined()
        let bodyHTML = rows.map { row in
            "<tr>\(row.joined())</tr>"
        }
        .joined()

        return """
        <table class="data-table">
            <thead><tr>\(headerHTML)</tr></thead>
            <tbody>\(bodyHTML)</tbody>
        </table>
        """
    }

    private func primaryDetailCellHTML(title: String, detail: String) -> String {
        """
        <td>
            <div class="primary-cell">\(escapeHTML(title))</div>
            <div class="muted">\(detail)</div>
        </td>
        """
    }

    private func plainCellHTML(_ value: String) -> String {
        "<td>\(escapeHTML(value))</td>"
    }

    private func amountCellHTML(_ value: Decimal, emphasize: Bool = false) -> String {
        let toneClass = value > 0 ? "positive" : value < 0 ? "negative" : "neutral"
        let strongClass = emphasize ? " amount \(toneClass)" : " amount neutral"
        return "<td class=\"\(strongClass)\">\(escapeHTML(value.asCurrencyFallback()))</td>"
    }

    private func emptyStateHTML(_ message: String) -> String {
        "<div class=\"empty-state\">\(escapeHTML(message))</div>"
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func absoluteDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private func percentageString(_ value: Decimal, total: Decimal) -> String {
        guard total > 0 else { return "0%" }
        let percentage = (NSDecimalNumber(decimal: value / total).doubleValue * 100).rounded()
        return "\(Int(percentage))%"
    }

    private func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func reportHealthSignal(_ snapshot: MonthlyReportSnapshot) -> PDFHealthSignal {
        let summary = snapshot.executiveSummary

        if summary.totalRevenue == 0 && summary.monthlyExpenses > 0 {
            return PDFHealthSignal(
                title: "Expense-only month",
                detail: "No realized sales were recorded while expenses still reached \(summary.monthlyExpenses.asCurrencyFallback()).",
                toneClass: "warning"
            )
        }

        if summary.realizedSalesProfit >= summary.monthlyExpenses && summary.netCashMovement >= 0 {
            return PDFHealthSignal(
                title: "Healthy operating month",
                detail: "Realized sales profit covered expenses and cash movement stayed non-negative at \(summary.netCashMovement.asCurrencyFallback()).",
                toneClass: "good"
            )
        }

        if summary.totalRevenue > 0 || summary.realizedSalesProfit > 0 {
            return PDFHealthSignal(
                title: "Mixed month",
                detail: "Commercial activity happened, but expense pressure or cash movement still needs review.",
                toneClass: "mixed"
            )
        }

        return PDFHealthSignal(
            title: "Needs attention",
            detail: "The month did not generate enough realized activity to offset current operating load.",
            toneClass: "warning"
        )
    }

    private func executiveHighlightCards(_ snapshot: MonthlyReportSnapshot) -> [PDFHighlightCard] {
        let summary = snapshot.executiveSummary
        let bestVehicle = snapshot.topProfitableVehicles.first
        let topExpense = snapshot.topExpenseCategories.first

        return [
            PDFHighlightCard(
                title: "Sales closed",
                value: "\(snapshot.vehicleSales.count) vehicle • \(snapshot.partSales.count) part",
                detail: "Revenue \(summary.totalRevenue.asCurrencyFallback())",
                toneClass: "blue"
            ),
            PDFHighlightCard(
                title: "Best close",
                value: bestVehicle?.title ?? "No profitable close",
                detail: bestVehicle.map { "Profit \($0.realizedProfit.asCurrencyFallback())" } ?? "No realized profitable vehicle sale in this month.",
                toneClass: "green"
            ),
            PDFHighlightCard(
                title: "Expense pressure",
                value: topExpense?.title ?? "No dominant category",
                detail: topExpense.map { "\($0.amount.asCurrencyFallback()) across \($0.count) entries" } ?? "No expense category concentration this month.",
                toneClass: "orange"
            ),
            PDFHighlightCard(
                title: "Inventory exposure",
                value: "\(summary.inventoryCount) vehicles in stock",
                detail: "Vehicle capital \(summary.inventoryCapital.asCurrencyFallback()) • Parts \(summary.partsInventoryCost.asCurrencyFallback())",
                toneClass: "indigo"
            )
        ]
    }

    private func write(content: String, fileName: String) throws -> URL {
        let url = makeTempURL(fileName: fileName)
        try FileManager.default.removeIfExists(at: url)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func rangeString(_ range: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .long
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end.addingTimeInterval(-1)))"
    }

    private func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func decimalString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private struct PDFChartDatum {
    let label: String
    let value: Decimal
    let colorHex: String
}

private struct PDFStackDatum {
    let label: String
    let value: Decimal
    let colorHex: String
}

private struct PDFHighlightCard {
    let title: String
    let value: String
    let detail: String
    let toneClass: String
}

private struct PDFHealthSignal {
    let title: String
    let detail: String
    let toneClass: String
}

private final class MonthlyReportPDFPageRenderer: UIPrintPageRenderer {
    override init() {
        super.init()
        headerHeight = 0
        footerHeight = 20
    }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let footerText = "Page \(pageIndex + 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = NSString(string: footerText).size(withAttributes: attributes)
        let x = footerRect.maxX - size.width - 4
        let y = footerRect.minY + ((footerRect.height - size.height) / 2)
        NSString(string: footerText).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
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
