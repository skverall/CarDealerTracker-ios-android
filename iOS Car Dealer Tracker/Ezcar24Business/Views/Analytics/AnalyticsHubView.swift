import SwiftUI
import CoreData

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

    @StateObject private var financeViewModel: DashboardViewModel
    @StateObject private var inventoryViewModel: InventoryAnalyticsViewModel
    @StateObject private var crmViewModel: CRMAnalyticsViewModel

    @State private var selectedRange: DashboardTimeRange = .month
    @Namespace private var namespace

    init() {
        let context = PersistenceController.shared.container.viewContext
        _financeViewModel = StateObject(wrappedValue: DashboardViewModel(context: context, initialRange: .month))
        _inventoryViewModel = StateObject(wrappedValue: InventoryAnalyticsViewModel(context: context))
        _crmViewModel = StateObject(wrappedValue: CRMAnalyticsViewModel(context: context))
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
            VStack(spacing: 24) {
                rangePicker

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
            .padding(.bottom, 100) // Extra padding for tab bar visibility
        }
        .background(ColorTheme.background)
        .navigationTitle("analytics_title".localizedString)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            refreshAll()
        }
        .onChange(of: selectedRange) { _, newValue in
            financeViewModel.fetchFinancialData(range: newValue)
        }
    }

    private func refreshAll() {
        financeViewModel.fetchFinancialData(range: selectedRange)
        inventoryViewModel.refreshData()
        crmViewModel.refresh()
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
        .background(ColorTheme.cardBackground)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(ColorTheme.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var inventoryCard: some View {
        AnalyticsSectionCard(
            title: "inventory_analytics".localizedString,
            subtitle: nil, // Subtitle moved to insight text
            icon: "car.fill",
            accent: ColorTheme.primary
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Insight Header
                HStack(spacing: 16) {
                    InventoryHealthScoreCompact(score: inventoryViewModel.healthScore, size: 52)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(inventoryViewModel.healthStatusTitle)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(ColorTheme.primaryText)
                        
                        Text(inventoryViewModel.healthStatusMessage)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Divider()
                
                // Detailed Metrics
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    MetricLine(
                        title: "Turnover Speed",
                        value: "\(inventoryViewModel.averageDaysInInventory) Days",
                        statusColor: inventoryViewModel.getTurnoverStatus().1.color
                    )
                    
                    MetricLine(
                        title: "Aging Stock (>60d)",
                        value: "\(inventoryViewModel.burningVehicles.count) Units",
                        statusColor: inventoryViewModel.burningVehicles.count > 0 ? ColorTheme.danger : ColorTheme.success
                    )
                    
                    MetricLine(
                        title: "Capital Stuck",
                        value: inventoryViewModel.totalHoldingCost.asCurrencyCompact()
                    )
                    
                    MetricLine(
                        title: "Total Vehicles",
                        value: "\(inventoryViewModel.totalVehicles)"
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
            VStack(spacing: 12) {
                AnalyticsMetricRow(
                    title: "total_revenue".localizedString,
                    value: financeViewModel.periodSalesRevenue.asCurrency(),
                    changePercent: financeViewModel.revenueChangePercent,
                    comparisonLabel: selectedRange.comparisonLabel,
                    isPositiveGood: true
                )

                AnalyticsMetricRow(
                    title: "net_profit".localizedString,
                    value: financeViewModel.periodSalesProfit.asCurrency(),
                    changePercent: financeViewModel.profitChangePercent,
                    comparisonLabel: selectedRange.comparisonLabel,
                    isPositiveGood: true
                )

                AnalyticsMetricRow(
                    title: "total_spend".localizedString,
                    value: financeViewModel.totalExpenses.asCurrency(),
                    changePercent: financeViewModel.periodChangePercent,
                    comparisonLabel: selectedRange.comparisonLabel,
                    isPositiveGood: false
                )
            }
        }
    }

    private var crmCard: some View {
        AnalyticsSectionCard(
            title: "Sales Pipeline", // Renamed for clarity
            subtitle: "Lead conversion performance",
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
                    MetricLine(
                        title: "Total Inquiries",
                        value: "\(crmViewModel.totalLeads)"
                    )
                    
                    MetricLine(
                        title: "Active Opps",
                        value: "\(crmViewModel.activeLeads)"
                    )

                    MetricLine(
                        title: "Conversion",
                        value: String(format: "%.1f%%", crmViewModel.conversionRate),
                        statusColor: crmViewModel.conversionRate > 5.0 ? ColorTheme.success : nil
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ClientStatus.allCases) { status in
                        let count = crmViewModel.stageCounts[status, default: 0]
                        StageChip(title: status.displayName, count: count, color: status.color)
                    }
                }
            }
        }
    }
}

private struct AnalyticsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: accent.opacity(0.25), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(ColorTheme.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(ColorTheme.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ColorTheme.tertiaryText)
            }

            content
        }
        .padding(18)
        .cardStyle()
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
