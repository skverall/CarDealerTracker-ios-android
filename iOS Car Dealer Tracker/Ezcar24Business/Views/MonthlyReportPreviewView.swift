//
//  MonthlyReportPreviewView.swift
//  Ezcar24Business
//
//  Preview screen for the previous calendar month's report snapshot.
//

import SwiftUI

@MainActor
struct MonthlyReportPreviewView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var snapshot: MonthlyReportSnapshot?
    @State private var isLoading = false
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var shareURL: URL?

    let referenceDate: Date

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    private var reportMonth: ReportMonth {
        ReportMonth.previousCalendarMonth(from: referenceDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summarySection

                if let snapshot {
                    executiveBriefSection(snapshot)
                    financialOverviewSection(snapshot)
                    expenseMixSection(snapshot)
                    vehicleSalesSection(snapshot)
                    partSalesSection(snapshot)
                    expenseSection(snapshot)
                    cashMovementSection(snapshot)
                    inventorySection(snapshot)
                    partsSection(snapshot)
                    topProfitableVehiclesSection(snapshot)
                    lossMakingVehiclesSection(snapshot)
                    topExpenseCategoriesSection(snapshot)
                } else if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let errorMessage {
                    errorCard(errorMessage)
                }
            }
            .padding(16)
        }
        .background(ColorTheme.background.ignoresSafeArea())
        .navigationTitle(reportMonth.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    exportPDF()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Text("Export PDF".localizedString)
                    }
                }
                .disabled(isExporting || isLoading || snapshot == nil)
            }
        }
        .task(id: sessionStore.activeOrganizationId) {
            await loadSnapshot()
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ShareSheet(items: [shareURL]) {
                    self.shareURL = nil
                }
            }
        }
    }

    private var summarySection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Previous calendar month".localizedString)
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                        Text(reportMonth.displayTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(ColorTheme.primaryText)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }

                if let snapshot {
                    let summary = snapshot.executiveSummary

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(title: "Revenue", value: summary.totalRevenue.asCurrency(), tint: .blue)
                        metricCard(title: "Realized sales profit", value: summary.realizedSalesProfit.asCurrency(), tint: .green)
                        metricCard(title: "Monthly expenses", value: summary.monthlyExpenses.asCurrency(), tint: .orange)
                        metricCard(title: "Net cash movement", value: summary.netCashMovement.asCurrency(), tint: .indigo)
                    }

                    Text("Structured around realized sales profit, monthly expenses, and cash movement instead of one synthetic net figure.".localizedString)
                        .font(.footnote)
                        .foregroundColor(ColorTheme.secondaryText)
                }

                if let errorMessage {
                    errorCard(errorMessage)
                }
            }
        }
    }

    private func executiveBriefSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        let signal = reportHealthSignal(snapshot)
        let highlights = reportHighlightCards(snapshot)

        return card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Executive brief")
                Text("A faster operator-level scan before the detailed tables.".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)

                healthSignalCard(signal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(highlights) { highlight in
                        executiveHighlightCard(highlight)
                    }
                }

                compositionCard(
                    title: "Revenue composition",
                    subtitle: "Vehicle versus part revenue in the selected month.",
                    items: revenueCompositionItems(snapshot),
                    emptyMessage: "No revenue recorded in this month."
                )

                compositionCard(
                    title: "Capital parked in stock",
                    subtitle: "Vehicles versus parts inventory cost at report time.",
                    items: stockCompositionItems(snapshot),
                    emptyMessage: "No inventory capital recorded."
                )
            }
        }
    }

    private func financialOverviewSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        let items = financialBarItems(snapshot)
        let maxValue = items.map(\.magnitude).max() ?? 1

        return card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Financial overview")
                Text("Fast visual comparison of the month’s core metrics.".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)

                ForEach(items) { item in
                    chartRow(item: item, maxValue: maxValue)
                }
            }
        }
    }

    private func expenseMixSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Expense mix")
                Text("Where spend concentrated the most in the month.".localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)

                if snapshot.topExpenseCategories.isEmpty {
                    emptyState("No expense categories in this month.")
                } else {
                    let items = expenseBarItems(snapshot)
                    let maxValue = items.map(\.magnitude).max() ?? 1

                    ForEach(items) { item in
                        chartRow(item: item, maxValue: maxValue)
                    }
                }
            }
        }
    }

    private func vehicleSalesSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Vehicle sales")

                if snapshot.vehicleSales.isEmpty {
                    emptyState("No vehicle sales in this month.")
                } else {
                    ForEach(Array(snapshot.vehicleSales.enumerated()), id: \.element.id) { index, sale in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(sale.title)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(sale.realizedProfit.asCurrency())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sale.realizedProfit >= 0 ? .green : .red)
                                    .lineLimit(1)
                            }

                            Text("\(dateString(sale.soldAt)) • \(sale.buyerName)")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)

                            Text(String(format: "Revenue %@ • Purchase %@ • Expenses %@ • Holding %@ • VAT refund %@".localizedString, sale.revenue.asCurrency(), sale.purchasePrice.asCurrency(), sale.vehicleExpenses.asCurrency(), sale.holdingCost.asCurrency(), sale.vatRefund.asCurrency()))
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.vehicleSales.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func partSalesSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Part sales")

                if snapshot.partSales.isEmpty {
                    emptyState("No part sales in this month.")
                } else {
                    ForEach(Array(snapshot.partSales.enumerated()), id: \.element.id) { index, sale in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(sale.summary)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(sale.realizedProfit.asCurrency())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sale.realizedProfit >= 0 ? .green : .red)
                                    .lineLimit(1)
                            }

                            Text("\(dateString(sale.soldAt)) • \(sale.buyerName)")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)

                            Text(String(format: "Revenue %@ • COGS %@".localizedString, sale.revenue.asCurrency(), sale.costOfGoodsSold.asCurrency()))
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.partSales.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func expenseSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Expense activity")

                if snapshot.expenseActivity.isEmpty {
                    emptyState("No expenses in this month.")
                } else {
                    ForEach(Array(snapshot.expenseActivity.enumerated()), id: \.element.id) { index, expense in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(expense.title)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(expense.amount.asCurrency())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(1)
                            }

                            let vehicleLabel = expense.vehicleTitle.map { " • \($0)" } ?? ""
                            Text("\(dateString(expense.date)) • \(expense.categoryTitle)\(vehicleLabel)")
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.expenseActivity.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func cashMovementSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Cash movement")

                let cash = snapshot.cashMovement
                detailLine(title: "Deposits", value: cash.depositsTotal.asCurrency())
                detailLine(title: "Withdrawals", value: cash.withdrawalsTotal.asCurrency())
                detailLine(title: "Net movement", value: cash.netMovement.asCurrency())

                if cash.rows.isEmpty {
                    emptyState("No account transactions in this month.")
                } else {
                    Divider()

                    ForEach(Array(cash.rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(dateString(row.date)) • \(row.note)")
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(row.signedAmount.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(row.signedAmount >= 0 ? .green : .red)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < min(cash.rows.count, 10) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func inventorySection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Inventory snapshot")

                let summary = snapshot.executiveSummary
                detailLine(title: "Vehicles in stock", value: "\(summary.inventoryCount)")
                detailLine(title: "Inventory capital", value: summary.inventoryCapital.asCurrency())

                if snapshot.inventorySnapshot.isEmpty {
                    emptyState("No active vehicles in stock.")
                } else {
                    Divider()

                    ForEach(Array(snapshot.inventorySnapshot.enumerated()), id: \.element.id) { index, vehicle in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(vehicle.title)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(vehicle.costBasis.asCurrency())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(1)
                            }

                            Text(String(format: "%@ • Purchase %@ • Expenses %@".localizedString, vehicle.status.localizedString.capitalized, vehicle.purchasePrice.asCurrency(), vehicle.totalExpenses.asCurrency()))
                                .font(.caption)
                                .foregroundColor(ColorTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.inventorySnapshot.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func partsSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Parts snapshot")

                let summary = snapshot.executiveSummary
                detailLine(title: "Units in stock", value: decimalString(summary.partsUnitsInStock))
                detailLine(title: "Inventory cost", value: summary.partsInventoryCost.asCurrency())

                if snapshot.partsSnapshot.isEmpty {
                    emptyState("No part inventory in stock.")
                } else {
                    Divider()

                    ForEach(Array(snapshot.partsSnapshot.enumerated()), id: \.element.id) { index, part in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(part.name)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !part.code.isEmpty {
                                    Text(part.code)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.secondaryText)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(decimalString(part.quantityOnHand))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(ColorTheme.primaryText)
                                    .lineLimit(1)
                                Text(part.inventoryCost.asCurrency())
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.partsSnapshot.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func topProfitableVehiclesSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Top profitable vehicles")

                if snapshot.topProfitableVehicles.isEmpty {
                    emptyState("No profitable vehicle sales in this month.")
                } else {
                    ForEach(Array(snapshot.topProfitableVehicles.enumerated()), id: \.element.id) { index, sale in
                        HStack(alignment: .firstTextBaseline) {
                            Text(sale.title)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(sale.realizedProfit.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.topProfitableVehicles.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func lossMakingVehiclesSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Loss-making vehicles")

                if snapshot.lossMakingVehicles.isEmpty {
                    emptyState("No loss-making vehicle sales in this month.")
                } else {
                    ForEach(Array(snapshot.lossMakingVehicles.enumerated()), id: \.element.id) { index, sale in
                        HStack(alignment: .firstTextBaseline) {
                            Text(sale.title)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(sale.realizedProfit.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.lossMakingVehicles.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func topExpenseCategoriesSection(_ snapshot: MonthlyReportSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Top expense categories")

                if snapshot.topExpenseCategories.isEmpty {
                    emptyState("No expense categories in this month.")
                } else {
                    ForEach(Array(snapshot.topExpenseCategories.enumerated()), id: \.element.id) { index, category in
                        HStack(alignment: .firstTextBaseline) {
                            Text(category.title)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(category.amount.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < snapshot.topExpenseCategories.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func loadSnapshot() async {
        isLoading = true
        errorMessage = nil

        let dealerId = sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId

        do {
            let builder = MonthlyReportSnapshotBuilder(context: viewContext)
            if let dealerId {
                snapshot = try builder.build(for: reportMonth, dealerId: dealerId)
            } else {
                snapshot = try builder.build(for: reportMonth.interval, title: reportMonth.displayTitle, dealerId: nil, reportMonth: reportMonth)
            }
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func exportPDF() {
        isExporting = true

        do {
            let exporter = BackupExportManager(context: viewContext)
            shareURL = try exporter.generateMonthlyReportPDF(
                for: reportMonth,
                dealerId: sessionStore.activeOrganizationId ?? CloudSyncEnvironment.currentDealerId
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.cardBackground)
        .cornerRadius(18)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value.localizedString)
            .font(.headline)
            .foregroundColor(ColorTheme.primaryText)
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.localizedString)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 88, alignment: .top)
        .background(tint.opacity(0.08))
        .cornerRadius(14)
    }

    private func healthSignalCard(_ signal: ReportHealthSignal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(signal.title.localizedString)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
            Text(signal.detail.localizedString)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(signal.tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(signal.tint.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func executiveHighlightCard(_ highlight: ReportHighlightCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlight.title.localizedString)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
            Text(highlight.value)
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(highlight.detail.localizedString)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(minHeight: 110, alignment: .top)
        .background(highlight.tint.opacity(0.1))
        .cornerRadius(14)
    }

    private func chartRow(item: ReportChartItem, maxValue: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title.localizedString)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(item.valueLabel)
                    .font(.subheadline)
                    .foregroundColor(item.tint)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.secondaryBackground)

                    Capsule()
                        .fill(item.tint.opacity(0.92))
                        .frame(width: max(0, geometry.size.width * normalizedWidth(for: item.magnitude, maxValue: maxValue)))
                }
            }
            .frame(height: 12)

            if let detail = item.detail {
                Text(detail.localizedString)
                    .font(.caption)
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .frame(minHeight: 56, alignment: .top)
    }

    private func compositionCard(title: String, subtitle: String, items: [ReportCompositionItem], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.localizedString)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(ColorTheme.primaryText)

            Text(subtitle.localizedString)
                .font(.caption)
                .foregroundColor(ColorTheme.secondaryText)

            if items.isEmpty {
                emptyState(emptyMessage)
            } else {
                compositionBar(items: items)

                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.tint)
                                .frame(width: 10, height: 10)
                            Text(item.title.localizedString)
                                .font(.caption)
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text("\(item.valueLabel) • \(item.shareLabel)")
                            .font(.caption)
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(16)
    }

    private func compositionBar(items: [ReportCompositionItem]) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(items) { item in
                    item.tint
                        .frame(width: geometry.size.width * compositionWidth(for: item.share))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }

    private func detailLine(title: String, value: String) -> some View {
        HStack {
            Text(title.localizedString)
                .foregroundColor(ColorTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundColor(ColorTheme.primaryText)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message.localizedString)
            .font(.subheadline)
            .foregroundColor(ColorTheme.secondaryText)
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
    }

    private func dateString(_ date: Date) -> String {
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

    private func normalizedWidth(for value: Decimal, maxValue: Decimal) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        guard value > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: value / maxValue).doubleValue
        return CGFloat(min(max(ratio, 0.08), 1))
    }

    private func financialBarItems(_ snapshot: MonthlyReportSnapshot) -> [ReportChartItem] {
        let summary = snapshot.executiveSummary
        return [
            ReportChartItem(
                title: "Total revenue",
                valueLabel: summary.totalRevenue.asCurrency(),
                magnitude: absoluteDecimal(summary.totalRevenue),
                tint: .blue,
                detail: String(format: "Vehicle %@ • Parts %@".localizedString, summary.vehicleRevenue.asCurrency(), summary.partRevenue.asCurrency())
            ),
            ReportChartItem(
                title: "Realized sales profit",
                valueLabel: summary.realizedSalesProfit.asCurrency(),
                magnitude: absoluteDecimal(summary.realizedSalesProfit),
                tint: .green,
                detail: String(format: "Vehicle %@ • Parts %@".localizedString, summary.vehicleProfit.asCurrency(), summary.partProfit.asCurrency())
            ),
            ReportChartItem(
                title: "Monthly expenses",
                valueLabel: summary.monthlyExpenses.asCurrency(),
                magnitude: absoluteDecimal(summary.monthlyExpenses),
                tint: .orange,
                detail: String(format: "%lld recorded entries".localizedString, Int64(snapshot.expenseActivity.count))
            ),
            ReportChartItem(
                title: "Net cash movement",
                valueLabel: summary.netCashMovement.asCurrency(),
                magnitude: absoluteDecimal(summary.netCashMovement),
                tint: summary.netCashMovement >= 0 ? .indigo : .red,
                detail: String(format: "Deposits %@ • Withdrawals %@".localizedString, summary.depositsTotal.asCurrency(), summary.withdrawalsTotal.asCurrency())
            )
        ]
    }

    private func expenseBarItems(_ snapshot: MonthlyReportSnapshot) -> [ReportChartItem] {
        snapshot.topExpenseCategories.map { category in
            ReportChartItem(
                title: category.title,
                valueLabel: category.amount.asCurrency(),
                magnitude: absoluteDecimal(category.amount),
                tint: ColorTheme.accent,
                detail: String(format: "%lld entries".localizedString, Int64(category.count))
            )
        }
    }

    private func reportHealthSignal(_ snapshot: MonthlyReportSnapshot) -> ReportHealthSignal {
        let summary = snapshot.executiveSummary

        if summary.totalRevenue == 0 && summary.monthlyExpenses > 0 {
            return ReportHealthSignal(
                title: "Expense-only month",
                detail: String(format: "No realized sales were recorded while expenses still reached %@.".localizedString, summary.monthlyExpenses.asCurrency()),
                tint: .orange
            )
        }

        if summary.realizedSalesProfit >= summary.monthlyExpenses && summary.netCashMovement >= 0 {
            return ReportHealthSignal(
                title: "Healthy operating month",
                detail: String(format: "Realized sales profit covered expenses and cash movement stayed non-negative at %@.".localizedString, summary.netCashMovement.asCurrency()),
                tint: .green
            )
        }

        if summary.totalRevenue > 0 || summary.realizedSalesProfit > 0 {
            return ReportHealthSignal(
                title: "Mixed month",
                detail: "Commercial activity happened, but expense pressure or cash movement still needs review.",
                tint: .blue
            )
        }

        return ReportHealthSignal(
            title: "Needs attention",
            detail: "The month did not generate enough realized activity to offset the current operating load.",
            tint: .orange
        )
    }

    private func reportHighlightCards(_ snapshot: MonthlyReportSnapshot) -> [ReportHighlightCard] {
        let summary = snapshot.executiveSummary
        let bestVehicle = snapshot.topProfitableVehicles.first
        let topExpense = snapshot.topExpenseCategories.first

        return [
            ReportHighlightCard(
                title: "Sales closed",
                value: String(format: "%lld vehicle • %lld part".localizedString, Int64(snapshot.vehicleSales.count), Int64(snapshot.partSales.count)),
                detail: String(format: "Revenue %@".localizedString, summary.totalRevenue.asCurrency()),
                tint: .blue
            ),
            ReportHighlightCard(
                title: "Best close",
                value: bestVehicle?.title ?? "No profitable close",
                detail: bestVehicle.map { String(format: "Profit %@".localizedString, $0.realizedProfit.asCurrency()) } ?? "No realized profitable vehicle sale in this month.",
                tint: .green
            ),
            ReportHighlightCard(
                title: "Expense pressure",
                value: topExpense?.title ?? "No dominant category",
                detail: topExpense.map { String(format: "%@ across %lld entries".localizedString, $0.amount.asCurrency(), Int64($0.count)) } ?? "No expense category concentration this month.",
                tint: .orange
            ),
            ReportHighlightCard(
                title: "Inventory exposure",
                value: String(format: "%lld vehicles in stock".localizedString, Int64(summary.inventoryCount)),
                detail: String(format: "Vehicle capital %@ • Parts %@".localizedString, summary.inventoryCapital.asCurrency(), summary.partsInventoryCost.asCurrency()),
                tint: .indigo
            )
        ]
    }

    private func revenueCompositionItems(_ snapshot: MonthlyReportSnapshot) -> [ReportCompositionItem] {
        let summary = snapshot.executiveSummary
        return compositionItems(for: [
            ("Vehicle revenue", summary.vehicleRevenue, Color.blue),
            ("Part revenue", summary.partRevenue, Color.cyan)
        ])
    }

    private func stockCompositionItems(_ snapshot: MonthlyReportSnapshot) -> [ReportCompositionItem] {
        let summary = snapshot.executiveSummary
        return compositionItems(for: [
            ("Vehicle inventory", summary.inventoryCapital, Color.indigo),
            ("Parts inventory", summary.partsInventoryCost, ColorTheme.accent)
        ])
    }

    private func compositionItems(for values: [(String, Decimal, Color)]) -> [ReportCompositionItem] {
        let activeValues = values.filter { $0.1 > 0 }
        let total = activeValues.reduce(Decimal.zero) { $0 + $1.1 }
        guard total > 0 else { return [] }

        return activeValues.map { title, amount, tint in
            let share = NSDecimalNumber(decimal: amount / total).doubleValue
            return ReportCompositionItem(
                title: title,
                valueLabel: amount.asCurrency(),
                share: share,
                shareLabel: percentageString(share),
                tint: tint
            )
        }
    }

    private func absoluteDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private func compositionWidth(for share: Double) -> CGFloat {
        CGFloat(min(max(share, 0), 1))
    }

    private func percentageString(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

private struct ReportChartItem: Identifiable {
    var id: String { title }
    let title: String
    let valueLabel: String
    let magnitude: Decimal
    let tint: Color
    let detail: String?
}

private struct ReportHighlightCard: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let detail: String
    let tint: Color
}

private struct ReportHealthSignal {
    let title: String
    let detail: String
    let tint: Color
}

private struct ReportCompositionItem: Identifiable {
    var id: String { title }
    let title: String
    let valueLabel: String
    let share: Double
    let shareLabel: String
    let tint: Color
}
