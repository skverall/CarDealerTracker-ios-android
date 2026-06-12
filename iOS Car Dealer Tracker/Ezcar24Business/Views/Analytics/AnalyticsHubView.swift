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
                aiInsightsViewModel.prepare(range: selectedRange)
            }
        }
        .onChange(of: selectedRange) { _, newValue in
            financeViewModel.fetchFinancialData(range: newValue)
            if subscriptionManager.isProAccessActive {
                aiInsightsViewModel.prepare(range: newValue)
            }
        }
        .onChange(of: subscriptionManager.isProAccessActive) { _, isPro in
            if isPro {
                aiInsightsViewModel.prepare(range: selectedRange)
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
            aiInsightsViewModel.prepare(range: selectedRange)
        }
    }

    private func performAIInsightsAction() {
        guard subscriptionManager.isProAccessActive else {
            showingAIInsightsPaywall = true
            return
        }

        guard isSignedIn else { return }

        let hasResponse = aiInsightsViewModel.response(for: selectedRange) != nil
        Task {
            await aiInsightsViewModel.generate(
                range: selectedRange,
                forceRefresh: hasResponse,
                isProAccessActive: true
            )
        }
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
            conversionRate: canViewCRM ? crmViewModel.conversionRate : nil,
            hasProAccess: subscriptionManager.isProAccessActive,
            action: performAIInsightsAction
        )
    }

    private var aiInsightsCard: some View {
        let hasProAccess = subscriptionManager.isProAccessActive
        let response = hasProAccess ? aiInsightsViewModel.response(for: selectedRange) : nil
        let isLoading = hasProAccess && aiInsightsViewModel.isLoading(for: selectedRange)
        let errorMessage = hasProAccess ? aiInsightsViewModel.errorMessage(for: selectedRange) : nil
        let generatedAt = hasProAccess ? aiInsightsViewModel.generatedAt(for: selectedRange) : nil

        return AIInsightsPremiumCard(
            periodTitle: selectedRange.displayLabel,
            response: response,
            isLoading: isLoading,
            errorMessage: errorMessage,
            generatedAt: generatedAt,
            isSignedIn: isSignedIn,
            hasProAccess: hasProAccess,
            isCheckingAccess: subscriptionManager.isCheckingStatus
        ) {
            performAIInsightsAction()
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
    let hasProAccess: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("analytics_pulse_title".localizedString)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(String(format: "analytics_pulse_subtitle".localizedString, periodTitle))
                        .font(.system(size: 13))
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                AnalyticsPulseStatusBadge(status: status)
            }

            HStack(alignment: .top, spacing: 16) {
                PulseKeyMetric(title: "total_revenue".localizedString, value: revenue)

                Divider()
                    .frame(height: 36)

                PulseKeyMetric(title: "total_spend".localizedString, value: spend)

                Divider()
                    .frame(height: 36)

                PulseKeyMetric(
                    title: "net_profit".localizedString,
                    value: profit,
                    valueColor: profit.hasPrefix("-") ? ColorTheme.danger : nil
                )
            }

            VStack(spacing: 0) {
                PulseDetailRow(
                    title: "inventory_analytics".localizedString,
                    subtitle: inventoryMessage,
                    value: inventoryScore.map(String.init) ?? "—"
                )

                if let agingCount {
                    Divider()

                    PulseDetailRow(
                        title: "analytics_aging_stock".localizedString,
                        value: String(format: "analytics_units_value".localizedString, Int64(agingCount)),
                        valueColor: agingCount > 0 ? ColorTheme.danger : nil
                    )
                }

                if let conversionRate {
                    Divider()

                    PulseDetailRow(
                        title: "analytics_conversion".localizedString,
                        value: String(format: "%.1f%%", conversionRate)
                    )
                }
            }

            Button(action: action) {
                Text(hasProAccess ? "analytics_ask_ai".localizedString : "ai_insights_unlock".localizedString)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(ColorTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.hapticScale)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct AnalyticsPulseStatusBadge: View {
    let status: AnalyticsPulseStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tint)
                .frame(width: 7, height: 7)

            Text(status.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ColorTheme.secondaryText)
        }
        .padding(.top, 5)
    }
}

private struct PulseKeyMetric: View {
    let title: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor ?? ColorTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
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
                    .font(.system(size: 14))
                    .foregroundColor(ColorTheme.primaryText)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(ColorTheme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor ?? ColorTheme.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ColorTheme.cardBackground)
                .overlay(
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
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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

private struct AIInsightsPremiumCard: View {
    let periodTitle: String
    let response: AIInsightsResponse?
    let isLoading: Bool
    let errorMessage: String?
    let generatedAt: Date?
    let isSignedIn: Bool
    let hasProAccess: Bool
    let isCheckingAccess: Bool
    let action: () -> Void

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

            AIInsightsActionButton(
                title: buttonTitle,
                isLoading: isLoading,
                isEnabled: isActionEnabled,
                action: action
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: isLoading)
        .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: response)
    }

    private var buttonTitle: String {
        if isLoading { return "ai_insights_generating".localizedString }
        if isCheckingAccess { return "ai_insights_checking".localizedString }
        if !hasProAccess { return "ai_insights_unlock".localizedString }
        if !isSignedIn { return "ai_insights_sign_in_cta".localizedString }
        if response != nil { return "ai_insights_refresh".localizedString }
        return "ai_insights_generate".localizedString
    }

    private var isActionEnabled: Bool {
        if isLoading || isCheckingAccess { return false }
        if !hasProAccess { return true }
        return isSignedIn
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ai_insights_title".localizedString)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ColorTheme.primaryText)

                Text(String(format: "analytics_period".localizedString, periodTitle))
                    .font(.system(size: 13))
                    .foregroundColor(ColorTheme.secondaryText)
            }

            Spacer(minLength: 12)

            Text(statusTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ColorTheme.secondaryText)
                .lineLimit(1)
        }
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(ColorTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.hapticScale)
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

struct AIInsightsResponse: Codable, Equatable {
    let summary: String
    let insights: [String]
    let recommendations: [String]
}

private struct AIInsightsRequest: Encodable {
    let sales: [AIInsightSalePayload]
    let expenses: [AIInsightExpensePayload]
    let inventory: [AIInsightInventoryPayload]
    let metadata: AIInsightMetadata
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
    let currencyCode: String
    let region: String
    let period: String
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

    private let context: NSManagedObjectContext
    private let client: SupabaseClient
    private let userDefaults: UserDefaults
    private var fingerprints: [DashboardTimeRange: String] = [:]

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
                errorMessages[range] = nil
            } else {
                responses[range] = nil
                generatedDates[range] = nil
                fingerprints[range] = fingerprint
                errorMessages[range] = nil
            }
        } catch {
            responses[range] = nil
            generatedDates[range] = nil
            fingerprints[range] = nil
            errorMessages[range] = nil
        }
    }

    func generate(range: DashboardTimeRange, forceRefresh: Bool = false, isProAccessActive: Bool) async {
        guard isProAccessActive else {
            errorMessages[range] = "ai_insights_pro_required_error".localizedString
            return
        }
        guard !loadingRanges.contains(range) else { return }
        loadingRanges.insert(range)
        errorMessages[range] = nil

        do {
            let request = try makeRequest(range: range)
            let fingerprint = try Self.fingerprint(for: request)
            fingerprints[range] = fingerprint

            if !forceRefresh, let cached = cachedEntry(for: range, fingerprint: fingerprint) {
                responses[range] = cached.response
                generatedDates[range] = cached.generatedAt
                errorMessages[range] = nil
                loadingRanges.remove(range)
                return
            }

            let result: AIInsightsResponse = try await client.functions.invoke(
                "ai-insights",
                options: FunctionInvokeOptions(body: request)
            )
            let entry = AIInsightsCacheEntry(response: result, generatedAt: Date(), fingerprint: fingerprint)
            responses[range] = result
            generatedDates[range] = entry.generatedAt
            errorMessages[range] = nil
            saveCachedEntry(entry, for: range)
        } catch {
            errorMessages[range] = "AI insights failed: \(error.localizedDescription)"
        }

        loadingRanges.remove(range)
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

        let regionSettings = RegionSettingsManager.shared
        let metadata = AIInsightMetadata(
            language: regionSettings.selectedLanguage.rawValue,
            currencyCode: regionSettings.selectedRegion.currencyCode,
            region: regionSettings.selectedRegion.rawValue,
            period: range.rawValue
        )

        return AIInsightsRequest(
            sales: Array(sales.prefix(200)),
            expenses: Array(expenses.prefix(500)),
            inventory: Array(inventory.prefix(300)),
            metadata: metadata
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
        return "ai_insights_cache_v1_\(dealerId)_\(range.rawValue)"
    }

    private static func fingerprint(for request: AIInsightsRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
