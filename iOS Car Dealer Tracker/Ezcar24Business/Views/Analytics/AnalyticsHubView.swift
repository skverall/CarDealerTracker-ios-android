import SwiftUI
import CoreData
import CryptoKit
import Supabase

@MainActor
final class CRMAnalyticsViewModel: ObservableObject {
    @Published var totalLeads: Int = 0
    @Published var activeLeads: Int = 0
    @Published var conversionRate: Double = 0
    @Published var stageCounts: [ClientStatus: Int] = [:]

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext? = nil) {
        self.context = context ?? PersistenceController.shared.container.viewContext
        refresh()
    }

    func refresh() {
        let request: NSFetchRequest<Client> = Client.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")

        do {
            let clients = try context.fetch(request)
            var counts: [ClientStatus: Int] = [:]
            for client in clients {
                let status = client.clientStatus
                counts[status, default: 0] += 1
            }

            stageCounts = counts
            totalLeads = clients.count
            let soldCount = counts[.sold] ?? 0
            activeLeads = max(0, totalLeads - soldCount)
            conversionRate = totalLeads > 0 ? (Double(soldCount) / Double(totalLeads)) * 100.0 : 0
        } catch {
            totalLeads = 0
            activeLeads = 0
            conversionRate = 0
            stageCounts = [:]
        }
    }
}

struct AnalyticsHubView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject private var permissionService = PermissionService.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @StateObject private var financeViewModel: DashboardViewModel
    @StateObject private var inventoryViewModel: InventoryAnalyticsViewModel
    @StateObject private var crmViewModel: CRMAnalyticsViewModel
    @StateObject private var aiInsightsViewModel: AIInsightsViewModel

    @State private var selectedRange: DashboardTimeRange = .month
    @State private var showingAIInsightsPaywall = false
    @State private var confirmingAIRegenerationRange: DashboardTimeRange?
    @Namespace private var namespace

    init() {
        let context = PersistenceController.shared.container.viewContext
        _financeViewModel = StateObject(wrappedValue: DashboardViewModel(context: context, initialRange: .month))
        _inventoryViewModel = StateObject(wrappedValue: InventoryAnalyticsViewModel(context: context))
        _crmViewModel = StateObject(wrappedValue: CRMAnalyticsViewModel(context: context))
        _aiInsightsViewModel = StateObject(wrappedValue: AIInsightsViewModel(context: context))
    }

    private var shouldGatePermissions: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var canViewInventory: Bool {
        !shouldGatePermissions || permissionService.can(.viewInventory)
    }

    private var canViewFinance: Bool {
        !shouldGatePermissions || permissionService.can(.viewFinancials)
    }

    private var canViewCRM: Bool {
        !shouldGatePermissions || permissionService.can(.viewLeads)
    }

    private var isSignedIn: Bool {
        if case .signedIn = sessionStore.status { return true }
        return false
    }

    private var analyticsPulseStatus: AnalyticsPulseStatus {
        if !canViewInventory && !canViewFinance {
            return .neutral
        }
        if canViewInventory && (inventoryViewModel.healthScore < 65 || inventoryViewModel.burningVehicles.count > 0) {
            return .attention
        }
        if canViewFinance && financeViewModel.totalExpenses > financeViewModel.periodSalesRevenue && financeViewModel.totalExpenses > Decimal.zero {
            return .attention
        }
        if canViewCRM && crmViewModel.totalLeads > 0 && crmViewModel.conversionRate < 10 {
            return .watch
        }
        return .healthy
    }

    var body: some View {
        Group {
            if shouldGatePermissions && !permissionService.didLoad {
                PermissionLoadingView(title: "analytics_title".localizedString)
            } else {
                content
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                rangePicker

                analyticsPulseCard

                if canViewFinance && canViewInventory {
                    aiInsightsCard
                }

                if canViewInventory {
                    NavigationLink {
                        InventoryAnalyticsView(showNavigation: false)
                    } label: {
                        inventoryCard
                    }
                    .buttonStyle(.plain)
                } else {
                    AnalyticsRestrictedCard(title: "inventory_analytics".localizedString)
                }

                if canViewFinance {
                    NavigationLink {
                        DealerExpenseDashboardView(showNavigation: false)
                            .navigationTitle("finance_analytics".localizedString)
                            .navigationBarTitleDisplayMode(.large)
                    } label: {
                        financeCard
                    }
                    .buttonStyle(.plain)
                } else {
                    AnalyticsRestrictedCard(title: "finance_analytics".localizedString)
                }

                if canViewCRM {
                    NavigationLink {
                        ClientListView(showNavigation: false)
                            .navigationTitle("crm_analytics".localizedString)
                            .navigationBarTitleDisplayMode(.large)
                    } label: {
                        crmCard
                    }
                    .buttonStyle(.plain)
                } else {
                    AnalyticsRestrictedCard(title: "crm_analytics".localizedString)
                }
            }
            .padding(.top)
            .padding(.horizontal, 20)
            .padding(.bottom, 112)
        }
        .background(analyticsBackground)
        .navigationTitle("analytics_title".localizedString)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            refreshAll()
        }
        .task {
            if subscriptionManager.isProAccessActive {
                prepareAIInsights(for: selectedRange)
            }
        }
        .onChange(of: selectedRange) { _, newValue in
            confirmingAIRegenerationRange = nil
            financeViewModel.fetchFinancialData(range: newValue)
            if subscriptionManager.isProAccessActive {
                prepareAIInsights(for: newValue)
            }
        }
        .onChange(of: subscriptionManager.isProAccessActive) { _, isPro in
            if isPro {
                prepareAIInsights(for: selectedRange)
            }
        }
        .sheet(isPresented: $showingAIInsightsPaywall) {
            PaywallView(source: .aiInsights)
        }
    }

    private var analyticsBackground: some View {
        ColorTheme.background.ignoresSafeArea()
    }

    private func refreshAll() {
        financeViewModel.fetchFinancialData(range: selectedRange)
        inventoryViewModel.refreshData()
        crmViewModel.refresh()
        if subscriptionManager.isProAccessActive {
            prepareAIInsights(for: selectedRange)
        }
    }

    private func performAIInsightsAction() {
        let decision = AIInsightsActionPolicy.decision(
            isLoading: aiInsightsViewModel.isLoading(for: selectedRange),
            isCheckingAccess: subscriptionManager.isCheckingStatus,
            hasProAccess: subscriptionManager.isProAccessActive,
            isSignedIn: isSignedIn,
            hasResponse: aiInsightsViewModel.response(for: selectedRange) != nil,
            usage: aiInsightsViewModel.usage(for: selectedRange)
        )

        switch decision {
        case .showPaywall:
            showingAIInsightsPaywall = true
        case .confirmRegeneration:
            confirmingAIRegenerationRange = selectedRange
        case .generate(let forceRefresh):
            confirmingAIRegenerationRange = nil
            generateAIInsights(range: selectedRange, forceRefresh: forceRefresh)
        case .ignore:
            break
        }
    }

    private func confirmAIRegeneration() {
        let range = confirmingAIRegenerationRange ?? selectedRange
        confirmingAIRegenerationRange = nil
        generateAIInsights(range: range, forceRefresh: true)
    }

    private func prepareAIInsights(for range: DashboardTimeRange) {
        aiInsightsViewModel.prepare(range: range)
        guard isSignedIn else { return }
        Task {
            await aiInsightsViewModel.loadHistoryIndex(preferredRange: range, isProAccessActive: true)
        }
    }

    private func generateAIInsights(range: DashboardTimeRange, forceRefresh: Bool) {
        Task {
            await aiInsightsViewModel.generate(
                range: range,
                forceRefresh: forceRefresh,
                isProAccessActive: true
            )
        }
    }

    private func selectAIInsightReport(_ report: AIInsightsReport) {
        let reportRange = DashboardTimeRange(rawValue: report.period) ?? selectedRange
        if selectedRange != reportRange {
            selectedRange = reportRange
            financeViewModel.fetchFinancialData(range: reportRange)
        }
        aiInsightsViewModel.selectReport(report, range: reportRange)
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTimeRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.displayLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(selectedRange == range ? .white : ColorTheme.secondaryText)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if selectedRange == range {
                                    Capsule()
                                        .fill(ColorTheme.primary)
                                        .matchedGeometryEffect(id: "ActiveRangeTab", in: namespace)
                                        .shadow(color: ColorTheme.primary.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ColorTheme.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ColorTheme.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var analyticsPulseCard: some View {
        AnalyticsPulseCard(
            periodTitle: selectedRange.displayLabel,
            status: analyticsPulseStatus,
            inventoryScore: canViewInventory ? inventoryViewModel.healthScore : nil,
            inventoryMessage: canViewInventory ? inventoryViewModel.healthStatusMessage : "access_restricted".localizedString,
            revenue: canViewFinance ? financeViewModel.periodSalesRevenue.asCurrencyCompact() : "—",
            profit: canViewFinance ? financeViewModel.periodSalesProfit.asCurrencyCompact() : "—",
            spend: canViewFinance ? financeViewModel.totalExpenses.asCurrencyCompact() : "—",
            agingCount: canViewInventory ? inventoryViewModel.burningVehicles.count : nil,
            conversionRate: canViewCRM ? crmViewModel.conversionRate : nil
        )
    }

    private var aiInsightsCard: some View {
        let hasProAccess = subscriptionManager.isProAccessActive
        let response = hasProAccess ? aiInsightsViewModel.response(for: selectedRange) : nil
        let isLoading = hasProAccess && aiInsightsViewModel.isLoading(for: selectedRange)
        let errorMessage = hasProAccess ? aiInsightsViewModel.errorMessage(for: selectedRange) : nil
        let generatedAt = hasProAccess ? aiInsightsViewModel.generatedAt(for: selectedRange) : nil
        let history = hasProAccess ? aiInsightsViewModel.historyIndex() : []
        let selectedReportId = hasProAccess ? aiInsightsViewModel.selectedReportId(for: selectedRange) : nil
        let usage = hasProAccess ? aiInsightsViewModel.usage(for: selectedRange) : nil

        return AIInsightsPremiumCard(
            periodTitle: selectedRange.displayLabel,
            response: response,
            isLoading: isLoading,
            errorMessage: errorMessage,
            generatedAt: generatedAt,
            isSignedIn: isSignedIn,
            hasProAccess: hasProAccess,
            isCheckingAccess: subscriptionManager.isCheckingStatus,
            history: history,
            selectedReportId: selectedReportId,
            usage: usage,
            isConfirmingRegeneration: confirmingAIRegenerationRange == selectedRange
        ) {
            performAIInsightsAction()
        } onSelectReport: { report in
            selectAIInsightReport(report)
        } onConfirmRegeneration: {
            confirmAIRegeneration()
        } onCancelRegeneration: {
            confirmingAIRegenerationRange = nil
        }
    }

    private var inventoryCard: some View {
        AnalyticsSectionCard(
            title: "inventory_analytics".localizedString,
            subtitle: "analytics_inventory_headline".localizedString,
            icon: "car.fill",
            accent: ColorTheme.primary
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    InventoryHealthScoreCompact(score: inventoryViewModel.healthScore, size: 66)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(inventoryViewModel.healthStatusTitle)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundColor(ColorTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            AnalyticsSignalPill(
                                title: inventoryViewModel.getTurnoverStatus().0,
                                tint: inventoryViewModel.getTurnoverStatus().1.color
                            )
                        }

                        Text(inventoryViewModel.healthStatusMessage)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InventoryMomentumStrip(
                    days: inventoryViewModel.averageDaysInInventory,
                    agingCount: inventoryViewModel.burningVehicles.count,
                    holdingCost: inventoryViewModel.totalHoldingCost.asCurrencyCompact(),
                    totalVehicles: inventoryViewModel.totalVehicles
                )

                VStack(spacing: 10) {
                    AnalyticsSignalRow(
                        icon: "clock.arrow.circlepath",
                        title: "analytics_turnover_speed".localizedString,
                        value: String(format: "analytics_days_value".localizedString, Int64(inventoryViewModel.averageDaysInInventory)),
                        detail: "analytics_signal_inventory_turnover".localizedString,
                        tint: inventoryViewModel.getTurnoverStatus().1.color
                    )

                    AnalyticsSignalRow(
                        icon: "flame.fill",
                        title: "analytics_aging_stock".localizedString,
                        value: String(format: "analytics_units_value".localizedString, Int64(inventoryViewModel.burningVehicles.count)),
                        detail: "analytics_signal_inventory_aging".localizedString,
                        tint: inventoryViewModel.burningVehicles.count > 0 ? ColorTheme.danger : ColorTheme.success
                    )
                }
            }
        }
    }

    private var financeCard: some View {
        AnalyticsSectionCard(
            title: "finance_analytics".localizedString,
            subtitle: String(format: "analytics_period".localizedString, selectedRange.displayLabel),
            icon: "chart.bar.xaxis",
            accent: ColorTheme.success
        ) {
            VStack(spacing: 16) {
                FinanceFlowCard(
                    revenue: financeViewModel.periodSalesRevenue,
                    profit: financeViewModel.periodSalesProfit,
                    spend: financeViewModel.totalExpenses,
                    comparisonLabel: selectedRange.comparisonLabel,
                    spendChangePercent: financeViewModel.periodChangePercent
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    AnalyticsMetricTile(
                        title: "total_revenue".localizedString,
                        value: financeViewModel.periodSalesRevenue.asCurrencyCompact(),
                        icon: "arrow.down.left.circle.fill",
                        tint: ColorTheme.primary,
                        changePercent: financeViewModel.revenueChangePercent,
                        comparisonLabel: selectedRange.comparisonLabel,
                        isPositiveGood: true
                    )

                    AnalyticsMetricTile(
                        title: "net_profit".localizedString,
                        value: financeViewModel.periodSalesProfit.asCurrencyCompact(),
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        tint: financeViewModel.periodSalesProfit >= Decimal.zero ? ColorTheme.success : ColorTheme.danger,
                        changePercent: financeViewModel.profitChangePercent,
                        comparisonLabel: selectedRange.comparisonLabel,
                        isPositiveGood: true
                    )
                }
            }
        }
    }

    private var crmCard: some View {
        AnalyticsSectionCard(
            title: "analytics_sales_pipeline_title".localizedString,
            subtitle: "analytics_sales_pipeline_subtitle".localizedString,
            icon: "person.2.fill",
            accent: ColorTheme.primary
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    spacing: 12
                ) {
                    AnalyticsMetricTile(
                        title: "analytics_total_inquiries".localizedString,
                        value: "\(crmViewModel.totalLeads)"
                    )

                    AnalyticsMetricTile(
                        title: "analytics_active_opps".localizedString,
                        value: "\(crmViewModel.activeLeads)"
                    )

                    AnalyticsMetricTile(
                        title: "analytics_conversion".localizedString,
                        value: String(format: "%.1f%%", crmViewModel.conversionRate),
                        tint: crmViewModel.conversionRate > 5.0 ? ColorTheme.success : ColorTheme.warning
                    )
                }

                VStack(spacing: 9) {
                    ForEach(ClientStatus.allCases) { status in
                        let count = crmViewModel.stageCounts[status, default: 0]
                        PipelineStageRow(
                            title: status.displayName,
                            count: count,
                            total: max(crmViewModel.totalLeads, 1),
                            color: status.color
                        )
                    }
                }
            }
        }
    }
}

private enum AnalyticsPulseStatus {
    case healthy
    case watch
    case attention
    case neutral

    @MainActor var title: String {
        switch self {
        case .healthy: return "analytics_pulse_status_healthy".localizedString
        case .watch: return "analytics_pulse_status_watch".localizedString
        case .attention: return "analytics_pulse_status_attention".localizedString
        case .neutral: return "analytics_pulse_status_neutral".localizedString
        }
    }

    var icon: String {
        switch self {
        case .healthy: return "checkmark.seal.fill"
        case .watch: return "eye.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .neutral: return "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .healthy: return ColorTheme.success
        case .watch: return ColorTheme.warning
        case .attention: return ColorTheme.danger
        case .neutral: return ColorTheme.secondaryText
        }
    }
}

private struct AnalyticsPulseCard: View {
    let periodTitle: String
    let status: AnalyticsPulseStatus
    let inventoryScore: Int?
    let inventoryMessage: String
    let revenue: String
    let profit: String
    let spend: String
    let agingCount: Int?
    let conversionRate: Double?

    private let hairline = Color.white.opacity(0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("analytics_pulse_title".localizedString)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(String(format: "analytics_pulse_subtitle".localizedString, periodTitle))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                AnalyticsPulseStatusBadge(status: status)
            }

            HStack(alignment: .top, spacing: 14) {
                PulseKeyMetric(title: "total_revenue".localizedString, value: revenue)

                Rectangle()
                    .fill(hairline)
                    .frame(width: 1, height: 38)

                PulseKeyMetric(title: "total_spend".localizedString, value: spend)

                Rectangle()
                    .fill(hairline)
                    .frame(width: 1, height: 38)

                PulseKeyMetric(
                    title: "net_profit".localizedString,
                    value: profit,
                    valueColor: profit.hasPrefix("-") ? Color(red: 1.0, green: 0.52, blue: 0.52) : nil
                )
            }

            VStack(spacing: 0) {
                PulseDetailRow(
                    title: "inventory_analytics".localizedString,
                    subtitle: inventoryMessage,
                    value: inventoryScore.map(String.init) ?? "—"
                )

                if let agingCount {
                    Rectangle()
                        .fill(hairline.opacity(0.7))
                        .frame(height: 1)

                    PulseDetailRow(
                        title: "analytics_aging_stock".localizedString,
                        value: String(format: "analytics_units_value".localizedString, Int64(agingCount)),
                        valueColor: agingCount > 0 ? Color(red: 1.0, green: 0.52, blue: 0.52) : nil
                    )
                }

                if let conversionRate {
                    Rectangle()
                        .fill(hairline.opacity(0.7))
                        .frame(height: 1)

                    PulseDetailRow(
                        title: "analytics_conversion".localizedString,
                        value: String(format: "%.1f%%", conversionRate)
                    )
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.11, green: 0.24, blue: 0.47),
                                Color(red: 0.06, green: 0.13, blue: 0.30),
                                Color(red: 0.04, green: 0.09, blue: 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.10), Color.clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 320
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color(red: 0.05, green: 0.11, blue: 0.26).opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

private struct AnalyticsPulseStatusBadge: View {
    let status: AnalyticsPulseStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(status.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(1)
        }
        .padding(.top, 8)
    }

    private var dotColor: Color {
        switch status {
        case .healthy: return Color(red: 0.36, green: 0.85, blue: 0.55)
        case .watch: return Color(red: 1.0, green: 0.82, blue: 0.40)
        case .attention: return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .neutral: return Color.white.opacity(0.45)
        }
    }
}

private struct PulseKeyMetric: View {
    let title: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PulseDetailRow: View {
    let title: String
    var subtitle: String? = nil
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor ?? .white)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
    }
}

private struct AnalyticsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color
    let showsChevron: Bool
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        accent: Color,
        showsChevron: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.showsChevron = showsChevron
        self.content = content()
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.72), ColorTheme.primary.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: accent.opacity(0.26), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(ColorTheme.tertiaryText)
                }
            }

            content
        }
        .padding(20)
        .background(
            cardShape
                .fill(ColorTheme.cardBackground)
                .overlay(
                    cardShape.fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.08),
                                ColorTheme.secondaryBackground.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
        )
        .clipShape(cardShape)
        .contentShape(cardShape)
        .overlay(
            cardShape
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.16),
                            ColorTheme.primary.opacity(0.05),
                            Color.black.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.055), radius: 16, x: 0, y: 8)
    }
}

private struct AnalyticsSignalPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.64)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.16), lineWidth: 1))
    }
}

private struct InventoryMomentumStrip: View {
    let days: Int
    let agingCount: Int
    let holdingCost: String
    let totalVehicles: Int

    private var turnoverProgress: Double {
        min(max(Double(days) / 180.0, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("analytics_inventory_motion".localizedString)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                Spacer()
                Text(String(format: "analytics_days_value".localizedString, Int64(days)))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(days > 60 ? ColorTheme.danger : ColorTheme.success)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.secondaryBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ColorTheme.success, ColorTheme.warning, ColorTheme.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * turnoverProgress))
                }
            }
            .frame(height: 9)

            HStack(spacing: 8) {
                MomentumChip(title: "analytics_slow_stock".localizedString, value: "\(agingCount)", tint: agingCount > 0 ? ColorTheme.danger : ColorTheme.success)
                MomentumChip(title: "analytics_capital_watch".localizedString, value: holdingCost, tint: ColorTheme.accent)
                MomentumChip(title: "analytics_total_vehicles".localizedString, value: "\(totalVehicles)", tint: ColorTheme.primary)
            }
        }
        .padding(14)
        .background(ColorTheme.secondaryBackground.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MomentumChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalyticsSignalRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct FinanceFlowCard: View {
    let revenue: Decimal
    let profit: Decimal
    let spend: Decimal
    let comparisonLabel: String
    let spendChangePercent: Double?

    private var revenueRatio: CGFloat {
        let revenueValue = max(0, decimalDouble(revenue))
        let spendValue = max(0, decimalDouble(spend))
        let total = revenueValue + spendValue
        guard total > 0 else { return 0.5 }
        return CGFloat(min(max(revenueValue / total, 0.12), 0.88))
    }

    private var profitTint: Color {
        profit >= Decimal.zero ? ColorTheme.success : ColorTheme.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("analytics_money_flow".localizedString)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)

                    if !comparisonLabel.isEmpty {
                        Text(comparisonLabel)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Spacer(minLength: 8)

                if let spendChangePercent, !comparisonLabel.isEmpty {
                    ComparisonBadge(percent: spendChangePercent, isPositiveGood: false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("analytics_inflow".localizedString, systemImage: "arrow.down.left")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.success)

                    Spacer()

                    Label("analytics_outflow".localizedString, systemImage: "arrow.up.right")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.danger)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ColorTheme.danger.opacity(0.18))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [ColorTheme.success, ColorTheme.primary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, proxy.size.width * revenueRatio))
                    }
                }
                .frame(height: 12)
            }

            HStack(spacing: 10) {
                FinanceMiniMetric(
                    title: "total_revenue".localizedString,
                    value: revenue.asCurrencyCompact(),
                    tint: ColorTheme.primary
                )

                FinanceMiniMetric(
                    title: "total_spend".localizedString,
                    value: spend.asCurrencyCompact(),
                    tint: ColorTheme.accent
                )

                FinanceMiniMetric(
                    title: "net_profit".localizedString,
                    value: profit.asCurrencyCompact(),
                    tint: profitTint
                )
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ColorTheme.secondaryBackground.opacity(0.86))
                .overlay(
                    LinearGradient(
                        colors: [
                            ColorTheme.success.opacity(0.10),
                            ColorTheme.primary.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ColorTheme.success.opacity(0.10), lineWidth: 1)
        )
    }

    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private struct FinanceMiniMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(ColorTheme.cardBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct AnalyticsMetricTile: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: Color = ColorTheme.primary
    var changePercent: Double? = nil
    var comparisonLabel: String = ""
    var isPositiveGood: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }

            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.68)

            Text(value)
                .font(.system(size: icon == nil ? 18 : 20, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            if let changePercent, !comparisonLabel.isEmpty {
                ComparisonBadge(percent: changePercent, isPositiveGood: isPositiveGood)
            }
        }
        .frame(maxWidth: .infinity, minHeight: icon == nil ? 76 : 128, alignment: .leading)
        .padding(14)
        .background(ColorTheme.secondaryBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(tint.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct PipelineStageRow: View {
    let title: String
    let count: Int
    let total: Int
    let color: Color

    private var progress: CGFloat {
        CGFloat(min(max(Double(count) / Double(max(total, 1)), 0), 1))
    }

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.38), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 8)

                    Text("\(count)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.12), in: Capsule())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ColorTheme.secondaryBackground)

                        Capsule()
                            .fill(color)
                            .frame(width: max(count == 0 ? 0 : 6, proxy.size.width * progress))
                    }
                }
                .frame(height: 7)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(ColorTheme.secondaryBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MetricLine: View {
    let title: String
    let value: String
    var statusColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(statusColor ?? ColorTheme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct AnalyticsMetricRow: View {
    let title: String
    let value: String
    let changePercent: Double?
    let comparisonLabel: String
    let isPositiveGood: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText)

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
            }

            Spacer()

            if let changePercent, !comparisonLabel.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    ComparisonBadge(percent: changePercent, isPositiveGood: isPositiveGood)
                    Text(comparisonLabel)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(ColorTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ColorTheme.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct ComparisonBadge: View {
    let percent: Double
    let isPositiveGood: Bool

    private var isPositive: Bool { percent >= 0 }

    private var color: Color {
        let isGood = isPositiveGood ? isPositive : !isPositive
        return isGood ? ColorTheme.success : ColorTheme.danger
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPositive ? "arrow.up.forward" : "arrow.down.forward")
                .font(.system(size: 10, weight: .bold))

            Text("\(abs(percent).formatted(.number.precision(.fractionLength(1))))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct StageChip: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 1)

            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(ColorTheme.primaryText)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(color.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.secondaryBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct AnalyticsRestrictedCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ColorTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(ColorTheme.accent.opacity(0.12))
                    .clipShape(Circle())

                Text("access_restricted".localizedString)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
            }

            Text(String(format: "permission_access_restricted_message".localizedString, title))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

enum AIInsightsActionDecision: Equatable {
    case showPaywall
    case confirmRegeneration
    case generate(forceRefresh: Bool)
    case ignore
}

struct AIInsightsActionPolicy {
    static func decision(
        isLoading: Bool,
        isCheckingAccess: Bool,
        hasProAccess: Bool,
        isSignedIn: Bool,
        hasResponse: Bool,
        usage: AIInsightsUsage?
    ) -> AIInsightsActionDecision {
        guard !isLoading, !isCheckingAccess else { return .ignore }
        guard hasProAccess else { return .showPaywall }
        guard isSignedIn else { return .ignore }
        guard usage?.remaining != 0 else { return .ignore }
        return hasResponse ? .confirmRegeneration : .generate(forceRefresh: false)
    }

    static func titleKey(
        isLoading: Bool,
        isCheckingAccess: Bool,
        hasProAccess: Bool,
        isSignedIn: Bool,
        hasResponse: Bool,
        usage: AIInsightsUsage?
    ) -> String {
        if isLoading { return "ai_insights_generating" }
        if isCheckingAccess { return "ai_insights_checking" }
        if !hasProAccess { return "ai_insights_unlock" }
        if !isSignedIn { return "ai_insights_sign_in_cta" }
        if usage?.remaining == 0 { return "ai_insights_limit_reached_button" }
        if hasResponse { return "ai_insights_generate_new" }
        return "ai_insights_generate"
    }

    static func isEnabled(
        isLoading: Bool,
        isCheckingAccess: Bool,
        hasProAccess: Bool,
        isSignedIn: Bool,
        usage: AIInsightsUsage?
    ) -> Bool {
        if isLoading || isCheckingAccess { return false }
        if !hasProAccess { return true }
        if usage?.remaining == 0 { return false }
        return isSignedIn
    }
}

struct AIInsightsLanguagePolicy {
    static let promptVersion = 5

    static func normalizedCode(_ value: String?) -> String {
        let code = (value ?? "en")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0 == "-" || $0 == "_" }
            .first
            .map(String.init) ?? "en"
        let allowed: Set<String> = ["en", "ru", "ar", "ja", "ko", "uz", "hi", "pt"]
        return allowed.contains(code) ? code : "en"
    }

    static func cacheKey(dealerId: String, language: String, rangeRawValue: String) -> String {
        "ai_insights_cache_v\(promptVersion)_\(dealerId)_\(normalizedCode(language))_\(rangeRawValue)"
    }

    static func reports(_ reports: [AIInsightsReport], matching language: String) -> [AIInsightsReport] {
        let currentLanguage = normalizedCode(language)
        return reports.filter { report in
            guard let reportLanguage = report.language else { return false }
            return normalizedCode(reportLanguage) == currentLanguage
        }
    }
}

struct AIInsightsUsagePolicy {
    static let defaultDailyLimit = 15

    static func nextUTCResetDate(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }

    static func usage(used: Int, limit: Int = defaultDailyLimit, now: Date) -> AIInsightsUsage {
        let safeLimit = max(1, limit)
        let safeUsed = max(0, used)
        return AIInsightsUsage(
            used: safeUsed,
            limit: safeLimit,
            remaining: max(0, safeLimit - safeUsed),
            resetsAt: ISO8601DateFormatter().string(from: nextUTCResetDate(after: now))
        )
    }
}

private struct AIInsightsPremiumCard: View {
    let periodTitle: String
    let response: AIInsightsResponse?
    let isLoading: Bool
    let errorMessage: String?
    let generatedAt: Date?
    let isSignedIn: Bool
    let hasProAccess: Bool
    let isCheckingAccess: Bool
    let history: [AIInsightsReport]
    let selectedReportId: String?
    let usage: AIInsightsUsage?
    let isConfirmingRegeneration: Bool
    let action: () -> Void
    let onSelectReport: (AIInsightsReport) -> Void
    let onConfirmRegeneration: () -> Void
    let onCancelRegeneration: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AIInsightsHeader(
                periodTitle: periodTitle,
                isLoading: isLoading,
                hasResponse: response != nil,
                generatedAt: generatedAt,
                hasProAccess: hasProAccess,
                isCheckingAccess: isCheckingAccess
            )

            if let usage, hasProAccess {
                AIInsightsUsageBar(usage: usage)
            }

            if isLoading && response != nil {
                AIInsightsRegeneratingBanner()
            }

            if isConfirmingRegeneration && response != nil && !isLoading {
                AIInsightsRegenerationPrompt(
                    onConfirm: onConfirmRegeneration,
                    onCancel: onCancelRegeneration
                )
            }

            if !history.isEmpty {
                AIInsightsHistorySection(
                    reports: history,
                    selectedReportId: selectedReportId,
                    onSelectReport: onSelectReport
                )
            }

            Group {
                if isLoading && response == nil {
                    AIInsightsLoadingPreview()
                } else if let response {
                    VStack(alignment: .leading, spacing: 16) {
                        AIInsightsSummaryPanel(summary: response.summary)

                        Divider()

                        AIInsightsSection(
                            title: "ai_insights_section_insights".localizedString,
                            items: response.insights
                        )
                        AIInsightsSection(
                            title: "ai_insights_section_recommendations".localizedString,
                            items: response.recommendations
                        )
                    }
                } else {
                    AIInsightsEmptyState(
                        isSignedIn: isSignedIn,
                        hasProAccess: hasProAccess
                    )
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))

            if let errorMessage {
                AIInsightsErrorMessage(message: errorMessage)
            }

            if !isConfirmingRegeneration {
                AIInsightsActionButton(
                    title: buttonTitle,
                    isLoading: isLoading,
                    isEnabled: isActionEnabled,
                    action: action
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: isLoading)
        .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: response)
    }

    private var buttonTitle: String {
        AIInsightsActionPolicy.titleKey(
            isLoading: isLoading,
            isCheckingAccess: isCheckingAccess,
            hasProAccess: hasProAccess,
            isSignedIn: isSignedIn,
            hasResponse: response != nil,
            usage: usage
        ).localizedString
    }

    private var isActionEnabled: Bool {
        AIInsightsActionPolicy.isEnabled(
            isLoading: isLoading,
            isCheckingAccess: isCheckingAccess,
            hasProAccess: hasProAccess,
            isSignedIn: isSignedIn,
            usage: usage
        )
    }
}

private struct AIInsightsUsageBar: View {
    let usage: AIInsightsUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(usage.remaining > 0 ? ColorTheme.primary : ColorTheme.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "ai_insights_usage_format".localizedString, usage.used, usage.limit))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText)

                    if let resetDate = usage.resetDate {
                        Text(String(format: "ai_insights_usage_reset_format".localizedString, Self.resetFormatter.string(from: resetDate)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Spacer(minLength: 8)

                Text(String(format: "ai_insights_usage_remaining_format".localizedString, usage.remaining))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(usage.remaining > 0 ? ColorTheme.secondaryText : ColorTheme.warning)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorTheme.tertiaryText.opacity(0.14))

                    Capsule()
                        .fill(usage.remaining > 0 ? ColorTheme.primary : ColorTheme.warning)
                        .frame(width: proxy.size.width * usage.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct AIInsightsRegeneratingBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("ai_insights_regenerating_title".localizedString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorTheme.primaryText)

                Text("ai_insights_regenerating_message".localizedString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AIInsightsRegenerationPrompt: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorTheme.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ai_insights_regenerate_title".localizedString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText)

                    Text("ai_insights_regenerate_message".localizedString)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(2)
                        .foregroundColor(ColorTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("ai_insights_regenerate_keep".localizedString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ColorTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ColorTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.hapticScale)

                Button(action: onConfirm) {
                    Text("ai_insights_regenerate_confirm".localizedString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ColorTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.hapticScale)
            }
        }
        .padding(14)
        .background(ColorTheme.accent.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ColorTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct AIInsightsHistorySection: View {
    let reports: [AIInsightsReport]
    let selectedReportId: String?
    let onSelectReport: (AIInsightsReport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ColorTheme.primary)

                Text("ai_insights_history_title".localizedString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)

                Spacer(minLength: 8)

                Text("\(reports.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ColorTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ColorTheme.tertiaryText.opacity(0.12), in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(reports) { report in
                    Button {
                        onSelectReport(report)
                    } label: {
                        AIInsightsHistoryRow(
                            report: report,
                            isSelected: report.id == selectedReportId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(ColorTheme.secondaryBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ColorTheme.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct AIInsightsHistoryRow: View {
    let report: AIInsightsReport
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "doc.text.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? ColorTheme.success : ColorTheme.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.periodDisplayTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)

                    Text(report.displayDate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }

                Text(report.summary)
                    .font(.system(size: 12))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(isSelected ? ColorTheme.primary.opacity(0.08) : ColorTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? ColorTheme.primary.opacity(0.24) : ColorTheme.tertiaryText.opacity(0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AIInsightsHeader: View {
    let periodTitle: String
    let isLoading: Bool
    let hasResponse: Bool
    let generatedAt: Date?
    let hasProAccess: Bool
    let isCheckingAccess: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [statusColor, ColorTheme.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: statusColor.opacity(0.24), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("ai_insights_title".localizedString)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(String(format: "analytics_period".localizedString, periodTitle))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusTitle)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.11), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.16), lineWidth: 1))
        }
    }

    private var statusIcon: String {
        if isCheckingAccess { return "hourglass" }
        if !hasProAccess { return "lock.fill" }
        if isLoading { return "sparkles" }
        if hasResponse { return "checkmark.seal.fill" }
        return "sparkles"
    }

    private var statusColor: Color {
        if isCheckingAccess { return ColorTheme.warning }
        if !hasProAccess { return ColorTheme.accent }
        if isLoading { return ColorTheme.secondary }
        if hasResponse { return ColorTheme.success }
        return ColorTheme.primary
    }

    private var statusTitle: String {
        if isCheckingAccess { return "ai_insights_status_checking".localizedString }
        if !hasProAccess { return "ai_insights_status_pro".localizedString }
        if isLoading { return "ai_insights_status_live".localizedString }
        if hasResponse, let generatedAt {
            return String(format: "ai_insights_status_cached".localizedString, Self.timeFormatter.string(from: generatedAt))
        }
        return "ai_insights_status_ready".localizedString
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct AIInsightsSummaryPanel: View {
    let summary: String

    var body: some View {
        Text(summary)
            .font(.system(size: 15))
            .lineSpacing(4)
            .foregroundColor(ColorTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ColorTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ColorTheme.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct AIInsightsSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ColorTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    AIInsightsRow(index: index + 1, text: item)

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 26)
                    }
                }
            }
        }
    }
}

private struct AIInsightsRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(ColorTheme.tertiaryText)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundColor(ColorTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIInsightsEmptyState: View {
    let isSignedIn: Bool
    let hasProAccess: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ColorTheme.primaryText)

            Text(subtitle)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundColor(ColorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        if !hasProAccess { return "ai_insights_locked_title".localizedString }
        if !isSignedIn { return "ai_insights_sign_in_title".localizedString }
        return "ai_insights_ready_title".localizedString
    }

    private var subtitle: String {
        if !hasProAccess { return "ai_insights_locked_subtitle".localizedString }
        if !isSignedIn { return "ai_insights_sign_in_subtitle".localizedString }
        return "ai_insights_ready_subtitle".localizedString
    }
}

private struct AIInsightsLoadingPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()

                Text("ai_insights_loading".localizedString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ColorTheme.secondaryText)
            }

            VStack(spacing: 9) {
                AIInsightsShimmerLine(widthRatio: 0.92)
                AIInsightsShimmerLine(widthRatio: 0.72)
                AIInsightsShimmerLine(widthRatio: 0.84)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIInsightsShimmerLine: View {
    let widthRatio: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ColorTheme.tertiaryText.opacity(0.14))
                .frame(width: proxy.size.width * widthRatio, height: 10)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.42),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.42)
                    .offset(x: proxy.size.width * phase)
                    .mask(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .frame(width: proxy.size.width * widthRatio, height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
                )
        }
        .frame(height: 10)
        .onAppear {
            withAnimation(.linear(duration: 1.18).repeatForever(autoreverses: false)) {
                phase = 1.35
            }
        }
    }
}

private struct AIInsightsErrorMessage: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ColorTheme.danger)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ColorTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AIInsightsActionButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .heavy))
                }

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(buttonBackground)
            .overlay(buttonShine)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.26 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: ColorTheme.secondary.opacity(0.22),
                radius: 10,
                x: 0,
                y: 7
            )
        }
        .buttonStyle(.hapticScale)
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            isAnimating = true
        }
    }

    private var canAnimate: Bool {
        isEnabled && !isLoading && !reduceMotion
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isEnabled
                        ? [ColorTheme.secondary, ColorTheme.primary, ColorTheme.accent]
                        : [ColorTheme.tertiaryText.opacity(0.38), ColorTheme.tertiaryText.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private var buttonShine: some View {
        if canAnimate {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.48),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: max(44, proxy.size.width * 0.30), height: proxy.size.height * 1.6)
                .rotationEffect(.degrees(18))
                .offset(x: isAnimating ? proxy.size.width * 1.15 : -proxy.size.width * 0.50)
                .animation(.linear(duration: 2.15).repeatForever(autoreverses: false), value: isAnimating)
            }
            .allowsHitTesting(false)
        }
    }
}

struct AIInsightsResponse: Codable, Equatable {
    let summary: String
    let insights: [String]
    let recommendations: [String]
    let reportId: String?
    let generatedAt: String?
    let usage: AIInsightsUsage?
    let history: [AIInsightsReport]?

    init(
        summary: String,
        insights: [String],
        recommendations: [String],
        reportId: String? = nil,
        generatedAt: String? = nil,
        usage: AIInsightsUsage? = nil,
        history: [AIInsightsReport]? = nil
    ) {
        self.summary = summary
        self.insights = insights
        self.recommendations = recommendations
        self.reportId = reportId
        self.generatedAt = generatedAt
        self.usage = usage
        self.history = history
    }
}

struct AIInsightsUsage: Codable, Equatable {
    let used: Int
    let limit: Int
    let remaining: Int
    let resetsAt: String?

    var progress: CGFloat {
        guard limit > 0 else { return 0 }
        return min(1, max(0, CGFloat(used) / CGFloat(limit)))
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        if let date = Self.fractionalFormatter.date(from: resetsAt) {
            return date
        }
        return Self.plainFormatter.date(from: resetsAt)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct AIInsightsReport: Codable, Equatable, Identifiable {
    let id: String
    let period: String
    let language: String?
    let summary: String
    let insights: [String]
    let recommendations: [String]
    let createdAt: String

    var response: AIInsightsResponse {
        AIInsightsResponse(
            summary: summary,
            insights: insights,
            recommendations: recommendations,
            reportId: id,
            generatedAt: createdAt
        )
    }

    @MainActor
    var periodDisplayTitle: String {
        DashboardTimeRange(rawValue: period)?.displayLabel ?? period
    }

    var createdDate: Date? {
        Self.date(from: createdAt)
    }

    @MainActor
    var displayDate: String {
        guard let date = createdDate else { return createdAt }
        let formatter = DateFormatter()
        formatter.locale = RegionSettingsManager.shared.selectedLanguage.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        if let date = fractionalFormatter.date(from: string) {
            return date
        }
        return plainFormatter.date(from: string)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

}

private struct AIInsightsRequest: Encodable {
    let mode: String
    let sales: [AIInsightSalePayload]
    let expenses: [AIInsightExpensePayload]
    let inventory: [AIInsightInventoryPayload]
    let metadata: AIInsightMetadata
    let forceRefresh: Bool?
    let fingerprint: String?

    init(
        sales: [AIInsightSalePayload],
        expenses: [AIInsightExpensePayload],
        inventory: [AIInsightInventoryPayload],
        metadata: AIInsightMetadata,
        forceRefresh: Bool? = nil,
        fingerprint: String? = nil
    ) {
        self.mode = "generate"
        self.sales = sales
        self.expenses = expenses
        self.inventory = inventory
        self.metadata = metadata
        self.forceRefresh = forceRefresh
        self.fingerprint = fingerprint
    }

    func applying(fingerprint: String, forceRefresh: Bool) -> AIInsightsRequest {
        AIInsightsRequest(
            sales: sales,
            expenses: expenses,
            inventory: inventory,
            metadata: metadata,
            forceRefresh: forceRefresh,
            fingerprint: fingerprint
        )
    }
}

private struct AIInsightsHistoryRequest: Encodable {
    let mode = "history"
    let metadata: AIInsightMetadata
}

private struct AIInsightsHistoryEnvelope: Decodable {
    let reports: [AIInsightsReport]
    let usage: AIInsightsUsage?
}

private struct AIInsightsErrorResponse: Decodable {
    let error: String
    let code: String?
    let usage: AIInsightsUsage?
}

private struct AIInsightSalePayload: Encodable {
    let make: String
    let model: String
    let purchasePrice: Decimal
    let salePrice: Decimal
    let date: String
}

private struct AIInsightExpensePayload: Encodable {
    let category: String
    let amount: Decimal
    let date: String
}

private struct AIInsightInventoryPayload: Encodable {
    let make: String
    let model: String
    let purchasePrice: Decimal
    let askingPrice: Decimal?
    let status: String
    let purchaseDate: String
    let daysInInventory: Int
}

private struct AIInsightMetadata: Encodable {
    let language: String
    let promptVersion: Int
    let currencyCode: String
    let region: String
    let period: String
    let organizationId: String?
    let periodStart: String?
    let periodEnd: String?
}

private struct AIInsightsCacheEntry: Codable {
    let response: AIInsightsResponse
    let generatedAt: Date
    let fingerprint: String
}

@MainActor
private final class AIInsightsViewModel: ObservableObject {
    @Published private var responses: [DashboardTimeRange: AIInsightsResponse] = [:]
    @Published private var generatedDates: [DashboardTimeRange: Date] = [:]
    @Published private var errorMessages: [DashboardTimeRange: String] = [:]
    @Published private var loadingRanges: Set<DashboardTimeRange> = []
    @Published private var histories: [DashboardTimeRange: [AIInsightsReport]] = [:]
    @Published private var allHistory: [AIInsightsReport] = []
    @Published private var selectedReportIds: [DashboardTimeRange: String] = [:]
    @Published private var usageByRange: [DashboardTimeRange: AIInsightsUsage] = [:]
    @Published private var historyLoadingRanges: Set<DashboardTimeRange> = []

    private let context: NSManagedObjectContext
    private let client: SupabaseClient
    private let userDefaults: UserDefaults
    private var fingerprints: [DashboardTimeRange: String] = [:]
    private var loadedHistoryLanguage: String?
    private var isLoadingHistoryIndex = false

    init(
        context: NSManagedObjectContext,
        client: SupabaseClient = SupabaseClientProvider().client,
        userDefaults: UserDefaults = .standard
    ) {
        self.context = context
        self.client = client
        self.userDefaults = userDefaults
    }

    func response(for range: DashboardTimeRange) -> AIInsightsResponse? {
        responses[range]
    }

    func generatedAt(for range: DashboardTimeRange) -> Date? {
        generatedDates[range]
    }

    func errorMessage(for range: DashboardTimeRange) -> String? {
        errorMessages[range]
    }

    func isLoading(for range: DashboardTimeRange) -> Bool {
        loadingRanges.contains(range)
    }

    func history(for range: DashboardTimeRange) -> [AIInsightsReport] {
        histories[range] ?? []
    }

    func historyIndex() -> [AIInsightsReport] {
        Array(allHistory.prefix(12))
    }

    func selectedReportId(for range: DashboardTimeRange) -> String? {
        selectedReportIds[range]
    }

    func usage(for range: DashboardTimeRange) -> AIInsightsUsage? {
        usageByRange[range]
    }

    private func setLoading(_ isLoading: Bool, for range: DashboardTimeRange) {
        var updated = loadingRanges
        if isLoading {
            updated.insert(range)
        } else {
            updated.remove(range)
        }
        loadingRanges = updated
    }

    private func setHistoryLoading(_ isLoading: Bool, for range: DashboardTimeRange) {
        var updated = historyLoadingRanges
        if isLoading {
            updated.insert(range)
        } else {
            updated.remove(range)
        }
        historyLoadingRanges = updated
    }

    func selectReport(_ report: AIInsightsReport, range: DashboardTimeRange) {
        responses[range] = report.response
        generatedDates[range] = report.createdDate
        selectedReportIds[range] = report.id
        mergeIntoHistoryIndex([report])
        errorMessages[range] = nil
    }

    func prepare(range: DashboardTimeRange) {
        do {
            let request = try makeRequest(range: range)
            let fingerprint = try Self.fingerprint(for: request)
            if fingerprints[range] == fingerprint, responses[range] != nil {
                return
            }

            if let cached = cachedEntry(for: range, fingerprint: fingerprint) {
                responses[range] = cached.response
                generatedDates[range] = cached.generatedAt
                fingerprints[range] = fingerprint
                selectedReportIds[range] = cached.response.reportId
                errorMessages[range] = nil
            } else if responses[range]?.reportId != nil {
                fingerprints[range] = fingerprint
                errorMessages[range] = nil
            } else {
                responses[range] = nil
                generatedDates[range] = nil
                fingerprints[range] = fingerprint
                selectedReportIds[range] = nil
                errorMessages[range] = nil
            }
        } catch {
            responses[range] = nil
            generatedDates[range] = nil
            fingerprints[range] = nil
            selectedReportIds[range] = nil
            errorMessages[range] = nil
        }
    }

    func loadHistory(range: DashboardTimeRange, isProAccessActive: Bool) async {
        guard isProAccessActive else { return }
        guard !historyLoadingRanges.contains(range) else { return }
        setHistoryLoading(true, for: range)

        do {
            let metadata = makeMetadata(range: range)
            let envelope: AIInsightsHistoryEnvelope = try await client.functions.invoke(
                "ai-insights",
                options: FunctionInvokeOptions(body: AIInsightsHistoryRequest(metadata: metadata))
            )
            let reports = AIInsightsLanguagePolicy.reports(envelope.reports, matching: metadata.language)
            histories[range] = reports
            mergeIntoHistoryIndex(reports)
            if let usage = envelope.usage {
                usageByRange[range] = usage
            }

            if let selectedId = selectedReportIds[range],
               !envelope.reports.contains(where: { $0.id == selectedId }) {
                selectedReportIds[range] = responses[range]?.reportId
            }
        } catch {
            if responses[range] == nil {
                errorMessages[range] = Self.userFacingErrorMessage(from: error)
            }
        }

        setHistoryLoading(false, for: range)
    }

    func loadHistoryIndex(preferredRange: DashboardTimeRange, isProAccessActive: Bool) async {
        guard isProAccessActive else { return }
        guard !isLoadingHistoryIndex else { return }
        let language = AIInsightsLanguagePolicy.normalizedCode(RegionSettingsManager.shared.selectedLanguage.rawValue)
        if loadedHistoryLanguage == language, !allHistory.isEmpty {
            return
        }

        isLoadingHistoryIndex = true
        if loadedHistoryLanguage != language {
            allHistory = []
            histories = [:]
            loadedHistoryLanguage = language
        }

        let ranges = [preferredRange] + DashboardTimeRange.allCases.filter { $0 != preferredRange }
        for range in ranges {
            await loadHistory(range: range, isProAccessActive: isProAccessActive)
        }
        isLoadingHistoryIndex = false
    }

    private func mergeIntoHistoryIndex(_ reports: [AIInsightsReport]) {
        guard !reports.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allHistory.map { ($0.id, $0) })
        for report in reports {
            byId[report.id] = report
        }
        allHistory = byId.values.sorted { lhs, rhs in
            let lhsDate = lhs.createdDate ?? .distantPast
            let rhsDate = rhs.createdDate ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    func generate(range: DashboardTimeRange, forceRefresh: Bool = false, isProAccessActive: Bool) async {
        guard isProAccessActive else {
            errorMessages[range] = "ai_insights_pro_required_error".localizedString
            return
        }
        guard !loadingRanges.contains(range) else { return }
        setLoading(true, for: range)
        errorMessages[range] = nil

        do {
            let baseRequest = try makeRequest(range: range)
            let fingerprint = try Self.fingerprint(for: baseRequest)
            let request = baseRequest.applying(fingerprint: fingerprint, forceRefresh: forceRefresh)
            fingerprints[range] = fingerprint

            if !forceRefresh, let cached = cachedEntry(for: range, fingerprint: fingerprint) {
                responses[range] = cached.response
                generatedDates[range] = cached.generatedAt
                selectedReportIds[range] = cached.response.reportId
                errorMessages[range] = nil
                setLoading(false, for: range)
                return
            }

            let result: AIInsightsResponse = try await client.functions.invoke(
                "ai-insights",
                options: FunctionInvokeOptions(body: request)
            )
            let generatedAt = Self.date(from: result.generatedAt) ?? Date()
            let entry = AIInsightsCacheEntry(response: result, generatedAt: generatedAt, fingerprint: fingerprint)
            responses[range] = result
            generatedDates[range] = entry.generatedAt
            selectedReportIds[range] = result.reportId
            if let usage = result.usage {
                usageByRange[range] = usage
            }
            if let history = result.history {
                let reports = AIInsightsLanguagePolicy.reports(history, matching: request.metadata.language)
                histories[range] = reports
                mergeIntoHistoryIndex(reports)
            } else if let reportId = result.reportId, let generatedAt = result.generatedAt {
                mergeIntoHistoryIndex([
                    AIInsightsReport(
                        id: reportId,
                        period: request.metadata.period,
                        language: request.metadata.language,
                        summary: result.summary,
                        insights: result.insights,
                        recommendations: result.recommendations,
                        createdAt: generatedAt
                    )
                ])
            }
            errorMessages[range] = nil
            saveCachedEntry(entry, for: range)
        } catch {
            if let response = Self.errorResponse(from: error), let usage = response.usage {
                usageByRange[range] = usage
            }
            errorMessages[range] = Self.userFacingErrorMessage(from: error)
        }

        setLoading(false, for: range)
    }

    private func makeRequest(range: DashboardTimeRange) throws -> AIInsightsRequest {
        let sales = try fetchSales(range: range)
        let expenses = try fetchExpenses(range: range)
        let inventory = try fetchInventory()

        if sales.isEmpty && expenses.isEmpty && inventory.isEmpty {
            throw NSError(
                domain: "AIInsights",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No dealer data found for AI analysis."]
            )
        }

        return AIInsightsRequest(
            sales: Array(sales.prefix(200)),
            expenses: Array(expenses.prefix(500)),
            inventory: Array(inventory.prefix(300)),
            metadata: makeMetadata(range: range)
        )
    }

    private func makeMetadata(range: DashboardTimeRange) -> AIInsightMetadata {
        let regionSettings = RegionSettingsManager.shared
        return AIInsightMetadata(
            language: AIInsightsLanguagePolicy.normalizedCode(regionSettings.selectedLanguage.rawValue),
            promptVersion: AIInsightsLanguagePolicy.promptVersion,
            currencyCode: regionSettings.selectedRegion.currencyCode,
            region: regionSettings.selectedRegion.rawValue,
            period: range.rawValue,
            organizationId: CloudSyncEnvironment.currentDealerId?.uuidString,
            periodStart: range.startDate.map(Self.dateString),
            periodEnd: range.endDate.map(Self.dateString)
        )
    }

    private func fetchSales(range: DashboardTimeRange) throws -> [AIInsightSalePayload] {
        let request: NSFetchRequest<Sale> = Sale.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Sale.date, ascending: false)]

        var predicates: [NSPredicate] = [NSPredicate(format: "deletedAt == nil")]
        if let startDate = range.startDate {
            predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
        }
        if let endDate = range.endDate {
            predicates.append(NSPredicate(format: "date < %@", endDate as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 200

        return try context.fetch(request).compactMap { sale in
            guard let vehicle = sale.vehicle, vehicle.deletedAt == nil else { return nil }
            let saleDate = sale.date ?? vehicle.saleDate ?? Date()
            return AIInsightSalePayload(
                make: clean(vehicle.make, fallback: "Unknown"),
                model: clean(vehicle.model, fallback: "Vehicle"),
                purchasePrice: vehicle.purchasePrice?.decimalValue ?? 0,
                salePrice: sale.amount?.decimalValue ?? vehicle.salePrice?.decimalValue ?? 0,
                date: Self.dateString(saleDate)
            )
        }
    }

    private func fetchExpenses(range: DashboardTimeRange) throws -> [AIInsightExpensePayload] {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Expense.date, ascending: false)]

        var predicates: [NSPredicate] = [NSPredicate(format: "deletedAt == nil")]
        if let startDate = range.startDate {
            predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
        }
        if let endDate = range.endDate {
            predicates.append(NSPredicate(format: "date < %@", endDate as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 500

        return try context.fetch(request).map { expense in
            AIInsightExpensePayload(
                category: clean(expense.categoryTitle, fallback: "Other"),
                amount: expense.amount?.decimalValue ?? 0,
                date: Self.dateString(expense.date ?? Date())
            )
        }
    }

    private func fetchInventory() throws -> [AIInsightInventoryPayload] {
        let request: NSFetchRequest<Vehicle> = Vehicle.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Vehicle.purchaseDate, ascending: false)]
        request.predicate = NSPredicate(format: "deletedAt == nil AND status != %@", "sold")
        request.fetchLimit = 300

        let calendar = Calendar.current
        return try context.fetch(request).map { vehicle in
            let purchaseDate = vehicle.purchaseDate ?? Date()
            let days = calendar.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 0
            return AIInsightInventoryPayload(
                make: clean(vehicle.make, fallback: "Unknown"),
                model: clean(vehicle.model, fallback: "Vehicle"),
                purchasePrice: vehicle.purchasePrice?.decimalValue ?? 0,
                askingPrice: vehicle.askingPrice?.decimalValue,
                status: clean(vehicle.status, fallback: "owned"),
                purchaseDate: Self.dateString(purchaseDate),
                daysInInventory: max(0, days)
            )
        }
    }

    private func clean(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func cachedEntry(for range: DashboardTimeRange, fingerprint: String) -> AIInsightsCacheEntry? {
        guard let data = userDefaults.data(forKey: cacheKey(for: range)),
              let entry = try? JSONDecoder().decode(AIInsightsCacheEntry.self, from: data),
              entry.fingerprint == fingerprint else {
            return nil
        }
        return entry
    }

    private func saveCachedEntry(_ entry: AIInsightsCacheEntry, for range: DashboardTimeRange) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        userDefaults.set(data, forKey: cacheKey(for: range))
    }

    private func cacheKey(for range: DashboardTimeRange) -> String {
        let dealerId = CloudSyncEnvironment.currentDealerId?.uuidString ?? "local"
        return AIInsightsLanguagePolicy.cacheKey(
            dealerId: dealerId,
            language: RegionSettingsManager.shared.selectedLanguage.rawValue,
            rangeRawValue: range.rawValue
        )
    }

    private static func fingerprint(for request: AIInsightsRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func userFacingErrorMessage(from error: Error) -> String {
        if let response = errorResponse(from: error) {
            if response.code == "AI_INSIGHTS_LIMIT_REACHED" {
                return "ai_insights_limit_reached_error".localizedString
            }
            if response.code == "AI_INSIGHTS_LANGUAGE_MISMATCH" {
                return "please_try_again".localizedString
            }
            let message = response.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return message
            }
        }
        return error.localizedDescription
    }

    private static func errorResponse(from error: Error) -> AIInsightsErrorResponse? {
        if case let FunctionsError.httpError(_, data) = error {
            return try? JSONDecoder().decode(AIInsightsErrorResponse.self, from: data)
        }
        return nil
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = fractionalFormatter.date(from: string) {
            return date
        }
        return plainFormatter.date(from: string)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
